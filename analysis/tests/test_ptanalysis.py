import json

import numpy as np
import pandas as pd
import pytest

from ptanalysis import agreement, classification, report, synth
from ptanalysis.thresholds import from_development_set, level, roc, triage

# Shrout & Fleiss (1979), Table 2: 6 targets rated by 4 judges
SF = np.array([[9, 2, 5, 8], [6, 1, 3, 2], [8, 4, 6, 8], [7, 1, 2, 6], [10, 5, 6, 9], [6, 2, 4, 7]], float)


def test_icc_matches_shrout_fleiss():
    r = agreement.icc_a1(SF)
    assert r.icc == pytest.approx(0.29, abs=0.005)  # published ICC(2,1) = .29
    assert r.ci_low < r.icc < r.ci_high


def test_icc_matches_pingouin_if_available():
    pg = pytest.importorskip("pingouin")
    long = pd.DataFrame([(i, j, SF[i, j]) for i in range(6) for j in range(4)], columns=["t", "r", "y"])
    t = pg.intraclass_corr(long, targets="t", raters="r", ratings="y").set_index("Type")
    row = "ICC(A,1)" if "ICC(A,1)" in t.index else "ICC2"  # pingouin >= 0.7 renamed the rows
    ci = "CI95" if "CI95" in t.columns else "CI95%"
    r = agreement.icc_a1(SF)
    assert r.icc == pytest.approx(t.loc[row, "ICC"], abs=1e-6)
    lo, hi = t.loc[row, ci]
    assert r.ci_low == pytest.approx(lo, abs=0.01) and r.ci_high == pytest.approx(hi, abs=0.01)


def test_bland_altman_and_errors():
    ref = np.array([10, 20, 30, 40, 50.0])
    dev = ref + np.array([1, -1, 1, -1, 0.5])
    ba = agreement.bland_altman(dev, ref)
    assert ba.bias == pytest.approx(0.1)
    assert ba.loa_low < 0 < ba.loa_high
    assert agreement.mae(dev, ref) == pytest.approx(0.9)
    assert agreement.rmse(dev, ref) == pytest.approx(np.sqrt((1 + 1 + 1 + 1 + 0.25) / 5))


def test_wilson_interval():
    lo, hi = classification.wilson(8, 10)
    assert lo == pytest.approx(0.490, abs=0.001) and hi == pytest.approx(0.943, abs=0.001)


def test_confusion_and_kappa():
    ref = ["healthy"] * 5 + ["monitor"] * 3 + ["refer"] * 2
    dev = ["healthy"] * 4 + ["monitor"] + ["monitor"] * 2 + ["refer"] + ["refer"] * 2
    cm = classification.confusion(ref, dev)
    assert cm.tolist() == [[4, 1, 0], [0, 2, 1], [0, 0, 2]]
    pc = classification.per_class(cm)
    assert pc["refer"]["sensitivity"] == 1.0
    assert pc["healthy"]["specificity"] == 1.0
    k = classification.weighted_kappa(ref, dev)
    skl = pytest.importorskip("sklearn.metrics")
    assert k == pytest.approx(skl.cohen_kappa_score(ref, dev, weights="linear", labels=classification.LEVELS))
    assert classification.mcc(np.eye(3, dtype=int) * 5) == pytest.approx(1.0)


def test_triage_rule_matches_firmware():
    thr = {"K": [38, 12, 16], "L": [-22, 12, 16], "N": [28, 12, 16], "F": [0, 2.25, 3], "S": [0, 3, 4], "R": [0, 3, 5]}
    assert level(2.99, thr["R"]) == "healthy"
    assert level(3.0, thr["R"]) == "monitor"
    assert level(5.0, thr["R"]) == "refer"
    row = pd.Series({"K": 38, "L": -22, "N": 28, "F": 0, "S": 0, "R": 3.5})
    assert triage(row, thr) == "monitor"
    row["K"] = 60
    assert triage(row, thr) == "refer"


def test_thresholds_from_development_set_format():
    dev = pd.DataFrame({"K": np.r_[np.full(8, 38.0) + np.arange(8), 70], "L": -22.0, "N": 28.0, "F": 0.5, "S": -0.5, "R": 1.0,
                        "pt_level": ["healthy"] * 8 + ["refer"]})
    thr = from_development_set(dev)
    assert thr["provisional"] is False
    assert thr["R"] == [0.0, 3.0, 5.0]
    sd = np.std(np.arange(8), ddof=1)
    assert thr["K"][0] == pytest.approx(41.5)
    assert thr["K"][1] == pytest.approx(round(1.5 * sd, 2))
    assert thr["F"][0] == 0.0 and thr["F"][1] == pytest.approx(0.75)
    json.dumps(thr)  # serialisable for the THR command


def test_roc_cutoff_reaches_sensitivity():
    s = np.r_[np.linspace(0, 1, 50), np.linspace(0.8, 3, 20)]
    y = np.r_[np.zeros(50, bool), np.ones(20, bool)]
    r = roc(s, y)
    assert 0.9 < r["auc"] <= 1.0
    assert ((s >= r["cut"]) & y).sum() / y.sum() >= 0.9


def test_end_to_end_on_synthetic_data(tmp_path):
    summ, ref = synth.make(60, 20)
    sp, rp = tmp_path / "summary.csv", tmp_path / "pt_reference.csv"
    summ.to_csv(sp, index=False)
    ref.to_csv(rp, index=False)
    m = report.evaluate(str(sp), str(rp), str(tmp_path / "out"))
    assert m["n_dev"] == 20 and m["n_val"] == 40
    assert m["agreement"]["K"]["mae"] < 3
    assert m["agreement"]["K"]["icc"] > 0.8
    assert (tmp_path / "out" / "report.md").exists()
    assert (tmp_path / "out" / "bland_altman.png").exists()
    assert m["classification"]["n"] == 40
