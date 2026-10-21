"""Triage accuracy against the physical therapist's reference level (thesis Section 3.5).

3x3 confusion matrix (healthy / monitor / refer), per-class sensitivity,
specificity, PPV, NPV and F1 with Wilson 95% CIs, overall accuracy, multiclass
MCC, and linearly weighted Cohen's kappa with a bootstrap 95% CI.
"""
from __future__ import annotations

import numpy as np
from scipy import stats

LEVELS = ["healthy", "monitor", "refer"]


def wilson(k: int, n: int, alpha: float = 0.05) -> tuple[float, float]:
    """Wilson score interval for a proportion k/n."""
    if n == 0:
        return (float("nan"), float("nan"))
    z = stats.norm.ppf(1 - alpha / 2)
    p = k / n
    den = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / den
    half = z * np.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return (float(centre - half), float(centre + half))


def _codes(labels) -> np.ndarray:
    idx = {l: i for i, l in enumerate(LEVELS)}
    out = np.array([idx.get(str(l).strip().lower(), -1) for l in labels])
    if (out < 0).any():
        bad = sorted({str(l) for l, c in zip(labels, out) if c < 0})
        raise ValueError(f"unknown level(s): {bad}; expected {LEVELS}")
    return out


def confusion(reference, device) -> np.ndarray:
    """Rows = reference (physical therapist), columns = device."""
    r, d = _codes(reference), _codes(device)
    m = np.zeros((3, 3), int)
    for a, b in zip(r, d):
        m[a, b] += 1
    return m


def per_class(cm: np.ndarray) -> dict:
    """One-vs-rest metrics for each level."""
    out = {}
    total = cm.sum()
    for i, name in enumerate(LEVELS):
        tp = int(cm[i, i])
        fn = int(cm[i, :].sum() - tp)
        fp = int(cm[:, i].sum() - tp)
        tn = int(total - tp - fn - fp)
        sens = tp / (tp + fn) if tp + fn else float("nan")
        spec = tn / (tn + fp) if tn + fp else float("nan")
        ppv = tp / (tp + fp) if tp + fp else float("nan")
        npv = tn / (tn + fn) if tn + fn else float("nan")
        f1 = 2 * ppv * sens / (ppv + sens) if (ppv + sens) and not np.isnan(ppv + sens) else float("nan")
        out[name] = {
            "tp": tp, "fn": fn, "fp": fp, "tn": tn,
            "sensitivity": sens, "sensitivity_ci": wilson(tp, tp + fn),
            "specificity": spec, "specificity_ci": wilson(tn, tn + fp),
            "ppv": ppv, "ppv_ci": wilson(tp, tp + fp),
            "npv": npv, "npv_ci": wilson(tn, tn + fn),
            "f1": f1,
        }
    return out


def mcc(cm: np.ndarray) -> float:
    """Matthews correlation coefficient for K classes (Gorodkin, 2004)."""
    c = np.trace(cm)
    s = cm.sum()
    p = cm.sum(axis=0)  # predicted
    t = cm.sum(axis=1)  # true
    num = c * s - (p * t).sum()
    den = np.sqrt((s * s - (p * p).sum()) * (s * s - (t * t).sum()))
    return float(num / den) if den else 0.0


def weighted_kappa(reference, device) -> float:
    """Cohen's kappa with linear weights for the ordered levels."""
    cm = confusion(reference, device).astype(float)
    n = cm.sum()
    k = cm.shape[0]
    w = np.array([[abs(i - j) / (k - 1) for j in range(k)] for i in range(k)])
    obs = (w * cm).sum() / n
    exp = (w * np.outer(cm.sum(axis=1), cm.sum(axis=0))).sum() / (n * n)
    return float(1 - obs / exp) if exp else float("nan")


def kappa_ci(reference, device, n_boot: int = 2000, seed: int = 1, alpha: float = 0.05) -> tuple[float, float]:
    """Percentile bootstrap CI for the weighted kappa."""
    r, d = np.asarray(reference), np.asarray(device)
    rng = np.random.default_rng(seed)
    vals = []
    for _ in range(n_boot):
        i = rng.integers(0, len(r), len(r))
        v = weighted_kappa(r[i], d[i])
        if not np.isnan(v):
            vals.append(v)
    lo, hi = np.percentile(vals, [100 * alpha / 2, 100 * (1 - alpha / 2)])
    return float(lo), float(hi)


def summary(reference, device) -> dict:
    cm = confusion(reference, device)
    n = int(cm.sum())
    acc = int(np.trace(cm))
    return {
        "n": n,
        "levels": LEVELS,
        "confusion": cm.tolist(),
        "accuracy": acc / n if n else float("nan"),
        "accuracy_ci": wilson(acc, n),
        "per_class": per_class(cm),
        "mcc": mcc(cm),
        "weighted_kappa": weighted_kappa(reference, device),
        "weighted_kappa_ci": kappa_ci(reference, device),
    }
