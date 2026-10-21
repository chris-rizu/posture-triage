"""Command line:

  python -m ptanalysis synth --out data/                       # invented data in the study formats
  python -m ptanalysis thresholds data/summary.csv data/pt_reference.csv --out out/thresholds.json
  python -m ptanalysis evaluate data/summary.csv data/pt_reference.csv --out out/ [--thresholds out/thresholds.json]
"""
import argparse
import json
import os

from . import report, synth
from .thresholds import from_development_set, save


def main() -> None:
    ap = argparse.ArgumentParser(prog="ptanalysis")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("synth", help="write synthetic summary.csv and pt_reference.csv")
    s.add_argument("--out", default="data")
    s.add_argument("--n", type=int, default=60)
    s.add_argument("--dev", type=int, default=20)
    t = sub.add_parser("thresholds", help="compute thresholds from the development set")
    t.add_argument("summary")
    t.add_argument("reference")
    t.add_argument("--out", default="out/thresholds.json")
    e = sub.add_parser("evaluate", help="agreement, reliability and triage accuracy on the validation set")
    e.add_argument("summary")
    e.add_argument("reference")
    e.add_argument("--out", default="out")
    e.add_argument("--thresholds", help="use these frozen thresholds instead of recomputing")
    a = ap.parse_args()

    if a.cmd == "synth":
        os.makedirs(a.out, exist_ok=True)
        summ, ref = synth.make(a.n, a.dev)
        summ.to_csv(os.path.join(a.out, "summary.csv"), index=False)
        ref.to_csv(os.path.join(a.out, "pt_reference.csv"), index=False)
        print(f"wrote {a.out}/summary.csv ({len(summ)} sessions) and {a.out}/pt_reference.csv ({len(ref)} participants)")
        print("These numbers are invented. Do not report them as results.")
    elif a.cmd == "thresholds":
        df = report.load(a.summary, a.reference)
        thr = from_development_set(df[df["set"] == "dev"])
        os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
        save(thr, a.out)
        print(json.dumps({k: v for k, v in thr.items() if k != "n_healthy"}))
        print(f"from {thr['n_healthy']} healthy development participants -> {a.out}")
        print("Paste this JSON into the app: Thresholds > Load new limits > Send to harness.")
    else:
        m = report.evaluate(a.summary, a.reference, a.out, a.thresholds)
        c = m["classification"]
        print(f"validation n={m['n_val']}: accuracy {c['accuracy']:.2f}, weighted kappa {c['weighted_kappa']:.2f}")
        print(f"report: {a.out}/report.md")


if __name__ == "__main__":
    main()
