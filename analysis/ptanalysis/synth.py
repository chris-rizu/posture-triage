"""Synthetic study data, so the whole analysis can be run before data collection.

Writes files in exactly the formats the real study uses:
  summary.csv       one row per assessment, as exported by the app (Saved > Export all)
  pt_reference.csv  the physical therapist's blinded measurements and level (filled in by hand)

The numbers are invented. Never report them as results.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from .thresholds import INDICATORS

HEALTHY = {"K": (38, 6), "L": (-22, 6), "N": (28, 6), "F": (0, 1.2), "S": (0, 1.5), "R": (0, 1.2)}


def participants(n: int = 60, n_dev: int = 20, seed: int = 7) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    rows = []
    for i in range(n):
        cls = rng.choice(["healthy", "monitor", "refer"], p=[0.6, 0.25, 0.15])
        t = {k: rng.normal(*HEALTHY[k]) for k in INDICATORS}
        t["R"] = abs(t["R"])
        if cls != "healthy":
            k = rng.choice(INDICATORS)
            mu, sd = HEALTHY[k]
            shift = rng.uniform(1.6, 1.95) if cls == "monitor" else rng.uniform(2.3, 3.2)
            sign = 1 if k in ("K", "N", "R") else rng.choice([-1, 1])
            if k == "R":
                t["R"] = rng.uniform(3.2, 4.8) if cls == "monitor" else rng.uniform(5.5, 9.0)
            else:
                t[k] = mu + sign * shift * sd
        rows.append({"participant": f"P{i + 1:03d}", "set": "dev" if i < n_dev else "val", "true_level": cls, **t})
    return pd.DataFrame(rows)


def make(n: int = 60, n_dev: int = 20, n_retest: int = 15, seed: int = 7) -> tuple[pd.DataFrame, pd.DataFrame]:
    rng = np.random.default_rng(seed + 1)
    people = participants(n, n_dev, seed)
    ref_rows, sum_rows = [], []
    for _, p in people.iterrows():
        # physical therapist: inclinometer / scoliometer error ~1 deg; clinical level mostly agrees with truth
        pt = {f"pt_{k}": round(p[k] + rng.normal(0, 1.0), 1) for k in INDICATORS}
        lvl = p.true_level if rng.random() > 0.06 else rng.choice(["healthy", "monitor", "refer"])
        ref_rows.append({"participant": p.participant, "set": p.set, **pt, "pt_level": lvl})
        sessions = 2 if len(sum_rows) < 2 * n_retest and rng.random() < 0.5 else 1
        for s in range(sessions):
            dev = {k: p[k] + 0.5 + rng.normal(0, 1.3) for k in INDICATORS}
            dev["R"] = abs(dev["R"])
            row = {
                "session_id": f"{p.participant}_2026110{s + 1}_0900{s}0",
                "participant": p.participant,
                "date_time": f"2026-11-0{s + 1}T09:00:0{s}",
                "device": "SYNTHETIC", "firmware": "synthetic", "demo": 1, "thresholds_provisional": 1,
                "complete": 1, "agree": 1, "risk": "",
            }
            for k in INDICATORS:
                row[k] = round(dev[k], 2)
                row[f"{k}_range"] = round(abs(rng.normal(0, 0.8)), 2)
                row[f"{k}_level"] = ""
            sum_rows.append(row)
    return pd.DataFrame(sum_rows), pd.DataFrame(ref_rows)
