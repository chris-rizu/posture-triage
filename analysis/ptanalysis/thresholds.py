"""Thresholds from the development set and the triage rule (thesis Section 3.2.5).

For K, L, N, F and S the reference value mu and SD sigma come from the
development-set participants the physical therapist rated healthy:
    monitor limit = 1.5 sigma, refer limit = 2 sigma   (on |value - mu|)
Trunk rotation R uses fixed limits: monitor 3 deg, refer 5 deg (mu = 0).

The output JSON is what the app's Thresholds screen sends to the harness:
    {"provisional": false, "K": [mu, mon, ref], ..., "R": [0, 3, 5]}
"""
from __future__ import annotations

import json

import numpy as np
import pandas as pd

INDICATORS = ["K", "L", "N", "F", "S", "R"]
NAMES = {
    "K": "Upper-back rounding", "L": "Lower-back curve", "N": "Neck-base tilt",
    "F": "Trunk lean", "S": "Shoulder tilt", "R": "Trunk rotation",
}
# F and S are signed asymmetries; their healthy reference is 0 by definition.
ZERO_MU = {"F", "S"}
R_FIXED = (0.0, 3.0, 5.0)


def from_development_set(dev: pd.DataFrame, level_col: str = "pt_level", k_mon: float = 1.5, k_ref: float = 2.0) -> dict:
    """dev: one row per development-set participant with device indicator means
    (columns K..S) and the physical therapist's level."""
    healthy = dev[dev[level_col].str.lower() == "healthy"]
    if len(healthy) < 5:
        raise ValueError(f"only {len(healthy)} healthy development participants; need at least 5")
    out: dict = {"provisional": False, "n_healthy": int(len(healthy))}
    for k in INDICATORS:
        if k == "R":
            out[k] = list(R_FIXED)
            continue
        v = healthy[k].astype(float).dropna()
        mu = 0.0 if k in ZERO_MU else float(v.mean())
        # for signed asymmetries, sigma is the RMS about zero
        sigma = float(np.sqrt((v ** 2).mean())) if k in ZERO_MU else float(v.std(ddof=1))
        out[k] = [round(mu, 2), round(k_mon * sigma, 2), round(k_ref * sigma, 2)]
    return out


def level(value: float, lim) -> str:
    if value is None or np.isnan(value):
        return ""
    d = abs(value - lim[0])
    return "refer" if d >= lim[2] else ("monitor" if d >= lim[1] else "healthy")


def triage(row: pd.Series, thr: dict) -> str:
    """Same rule as the firmware: the worst level across the six indicators."""
    order = {"healthy": 0, "monitor": 1, "refer": 2}
    worst = "healthy"
    for k in INDICATORS:
        lv = level(float(row[k]), thr[k])
        if lv and order[lv] > order[worst]:
            worst = lv
    return worst


def roc(scores, positive) -> dict:
    """ROC curve, AUC and the lowest cut-off that still reaches sensitivity >= 0.90."""
    s = np.asarray(scores, float)
    y = np.asarray(positive, bool)
    ok = ~np.isnan(s)
    s, y = s[ok], y[ok]
    if y.all() or (~y).all():
        return {"auc": float("nan"), "fpr": [], "tpr": [], "cut": float("nan")}
    cuts = np.unique(s)[::-1]
    tpr = [0.0]
    fpr = [0.0]
    for c in cuts:
        p = s >= c
        tpr.append((p & y).sum() / y.sum())
        fpr.append((p & ~y).sum() / (~y).sum())
    tpr.append(1.0)
    fpr.append(1.0)
    auc = float(np.trapezoid(tpr, fpr)) if hasattr(np, "trapezoid") else float(np.trapz(tpr, fpr))
    cut = float("nan")
    for c in cuts[::-1]:  # from the highest-specificity end
        if ((s >= c) & y).sum() / y.sum() >= 0.90:
            cut = float(c)
            break
    return {"auc": auc, "fpr": fpr, "tpr": tpr, "cut": cut}


def save(thr: dict, path: str) -> None:
    clean = {k: v for k, v in thr.items() if k == "provisional" or k in INDICATORS}
    with open(path, "w") as f:
        json.dump(clean, f, indent=1)
