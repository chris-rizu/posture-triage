"""Runs the full evaluation and writes report.md, metrics.json and figures."""
from __future__ import annotations

import json
import os

import numpy as np
import pandas as pd

from . import agreement, classification
from .thresholds import INDICATORS, NAMES, from_development_set, save, triage


def load(summary_csv: str, reference_csv: str) -> pd.DataFrame:
    """One row per participant: the first valid assessment joined with the reference."""
    s = pd.read_csv(summary_csv)
    s = s[(s["complete"] == 1) & (s["agree"] == 1)].sort_values("date_time")
    first = s.groupby("participant", as_index=False).first()
    ref = pd.read_csv(reference_csv)
    df = first.merge(ref, on="participant", how="inner")
    if df.empty:
        raise ValueError("no participant appears in both files")
    return df


def retest(summary_csv: str) -> dict[str, np.ndarray]:
    """Participants with two valid sessions: n x 2 arrays per indicator."""
    s = pd.read_csv(summary_csv)
    s = s[(s["complete"] == 1) & (s["agree"] == 1)].sort_values("date_time")
    g = s.groupby("participant")
    pairs = {k: [] for k in INDICATORS}
    for _, rows in g:
        if len(rows) >= 2:
            for k in INDICATORS:
                pairs[k].append([rows[k].iloc[0], rows[k].iloc[1]])
    return {k: np.array(v) for k, v in pairs.items() if len(v) >= 3}


def _fmt(x, d=2):
    return "–" if x is None or (isinstance(x, float) and np.isnan(x)) else f"{x:.{d}f}"


def plots(df: pd.DataFrame, out: str, cm: np.ndarray) -> list[str]:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    files = []
    fig, axes = plt.subplots(2, 3, figsize=(12, 7.5))
    for ax, k in zip(axes.flat, INDICATORS):
        a, b = df[k].astype(float), df[f"pt_{k}"].astype(float)
        ba = agreement.bland_altman(a, b)
        mean = (a + b) / 2
        ax.scatter(mean, a - b, s=18, color="#1668C7", alpha=0.8)
        for y, ls in ((ba.bias, "-"), (ba.loa_low, "--"), (ba.loa_high, "--")):
            ax.axhline(y, color="#1D2A33", ls=ls, lw=1)
        ax.set_title(f"{NAMES[k]} ({k})", fontsize=11)
        ax.set_xlabel("Mean of device and reference (°)")
        ax.set_ylabel("Device − reference (°)")
        ax.text(0.02, 0.96, f"bias {ba.bias:.2f}°\nLoA {ba.loa_low:.2f}° to {ba.loa_high:.2f}°",
                transform=ax.transAxes, va="top", fontsize=8.5)
    fig.tight_layout()
    f = os.path.join(out, "bland_altman.png")
    fig.savefig(f, dpi=160)
    plt.close(fig)
    files.append(f)

    fig, ax = plt.subplots(figsize=(4.6, 4))
    ax.imshow(cm, cmap="Blues")
    for i in range(3):
        for j in range(3):
            ax.text(j, i, str(cm[i, j]), ha="center", va="center", fontsize=13,
                    color="white" if cm[i, j] > cm.max() / 2 else "#1D2A33")
    ax.set_xticks(range(3), classification.LEVELS)
    ax.set_yticks(range(3), classification.LEVELS)
    ax.set_xlabel("Device")
    ax.set_ylabel("Physical therapist")
    fig.tight_layout()
    f = os.path.join(out, "confusion.png")
    fig.savefig(f, dpi=160)
    plt.close(fig)
    files.append(f)
    return files


def evaluate(summary_csv: str, reference_csv: str, out: str, thresholds_json: str | None = None) -> dict:
    os.makedirs(out, exist_ok=True)
    df = load(summary_csv, reference_csv)
    dev, val = df[df["set"] == "dev"], df[df["set"] == "val"]

    # thresholds: frozen from the development set (or given)
    if thresholds_json:
        thr = json.load(open(thresholds_json))
    else:
        thr = from_development_set(dev)
        save(thr, os.path.join(out, "thresholds.json"))
    val = val.copy()
    val["device_level"] = val.apply(lambda r: triage(r, thr), axis=1)

    metrics: dict = {"n_dev": int(len(dev)), "n_val": int(len(val)), "thresholds": thr, "agreement": {}, "reliability": {}}
    for k in INDICATORS:
        a, b = val[k].astype(float), val[f"pt_{k}"].astype(float)
        ba = agreement.bland_altman(a, b)
        icc = agreement.icc_a1(np.column_stack([a, b]))
        metrics["agreement"][k] = {
            **ba.as_dict(), "mae": agreement.mae(a, b), "rmse": agreement.rmse(a, b),
            "icc": icc.icc, "icc_ci": [icc.ci_low, icc.ci_high],
        }
    for k, arr in retest(summary_csv).items():
        icc = agreement.icc_a1(arr)
        sem, mdc = agreement.sem_mdc(arr)
        metrics["reliability"][k] = {"n": int(len(arr)), "icc": icc.icc, "icc_ci": [icc.ci_low, icc.ci_high], "sem": sem, "mdc95": mdc}
    metrics["classification"] = classification.summary(val["pt_level"], val["device_level"])
    figs = plots(val, out, np.array(metrics["classification"]["confusion"]))

    with open(os.path.join(out, "metrics.json"), "w") as f:
        json.dump(metrics, f, indent=1, default=float)
    with open(os.path.join(out, "report.md"), "w") as f:
        f.write(markdown(metrics, figs))
    return metrics


def markdown(m: dict, figs: list[str]) -> str:
    L = []
    L.append("# Evaluation report\n")
    L.append(f"Development set: {m['n_dev']} participants. Validation set: {m['n_val']} participants.\n")
    L.append("## Thresholds (frozen from the development set)\n")
    L.append("| Indicator | Reference μ (°) | Monitor limit (°) | Refer limit (°) |\n|---|---|---|---|")
    for k in INDICATORS:
        mu, mon, ref = m["thresholds"][k]
        L.append(f"| {NAMES[k]} ({k}) | {mu:.2f} | {mon:.2f} | {ref:.2f} |")
    L.append("\n## Agreement with the reference (validation set)\n")
    L.append("| Indicator | Bias (°) | 95% LoA (°) | MAE (°) | RMSE (°) | ICC(A,1) [95% CI] |\n|---|---|---|---|---|---|")
    for k in INDICATORS:
        a = m["agreement"][k]
        L.append(f"| {k} | {_fmt(a['bias'])} | {_fmt(a['loa_low'])} to {_fmt(a['loa_high'])} | {_fmt(a['mae'])} | "
                 f"{_fmt(a['rmse'])} | {_fmt(a['icc'])} [{_fmt(a['icc_ci'][0])}, {_fmt(a['icc_ci'][1])}] |")
    if m["reliability"]:
        L.append("\n## Test-retest reliability\n")
        L.append("| Indicator | n | ICC(A,1) [95% CI] | SEM (°) | MDC95 (°) |\n|---|---|---|---|---|")
        for k, r in m["reliability"].items():
            L.append(f"| {k} | {r['n']} | {_fmt(r['icc'])} [{_fmt(r['icc_ci'][0])}, {_fmt(r['icc_ci'][1])}] | {_fmt(r['sem'])} | {_fmt(r['mdc95'])} |")
    c = m["classification"]
    L.append("\n## Triage accuracy (validation set)\n")
    L.append("Rows: physical therapist. Columns: device.\n")
    L.append("| | healthy | monitor | refer |\n|---|---|---|---|")
    for name, row in zip(classification.LEVELS, c["confusion"]):
        L.append(f"| **{name}** | " + " | ".join(str(v) for v in row) + " |")
    L.append(f"\nAccuracy {_fmt(c['accuracy'])} [{_fmt(c['accuracy_ci'][0])}, {_fmt(c['accuracy_ci'][1])}]. "
             f"Weighted kappa {_fmt(c['weighted_kappa'])} [{_fmt(c['weighted_kappa_ci'][0])}, {_fmt(c['weighted_kappa_ci'][1])}]. "
             f"MCC {_fmt(c['mcc'])}.\n")
    L.append("| Level | Sensitivity [95% CI] | Specificity [95% CI] | PPV | NPV | F1 |\n|---|---|---|---|---|---|")
    for name, p in c["per_class"].items():
        L.append(f"| {name} | {_fmt(p['sensitivity'])} [{_fmt(p['sensitivity_ci'][0])}, {_fmt(p['sensitivity_ci'][1])}] | "
                 f"{_fmt(p['specificity'])} [{_fmt(p['specificity_ci'][0])}, {_fmt(p['specificity_ci'][1])}] | "
                 f"{_fmt(p['ppv'])} | {_fmt(p['npv'])} | {_fmt(p['f1'])} |")
    L.append("\n## Figures\n")
    for f in figs:
        L.append(f"![{os.path.basename(f)}]({os.path.basename(f)})")
    return "\n".join(L) + "\n"
