# Analysis toolkit

Statistics for Chapter 3, Section 3.5: thresholds from the development set, agreement with the
physical therapist's reference, test-retest reliability and triage accuracy.

```
pip install -r requirements.txt
pytest                                   # checks ICC against Shrout & Fleiss (1979), kappa against scikit-learn
python -m ptanalysis synth --out data    # invented data in the real formats (never report it)
python -m ptanalysis thresholds data/summary.csv data/pt_reference.csv --out out/thresholds.json
python -m ptanalysis evaluate data/summary.csv data/pt_reference.csv --out out
```

`evaluate` writes `out/report.md`, `out/metrics.json`, `out/bland_altman.png` and `out/confusion.png`.

## Input files

**summary.csv**: from the app (Saved assessments → share icon). One row per assessment:
`session_id, participant, date_time, device, firmware, demo, thresholds_provisional, complete, agree, risk,
K, K_range, K_level, ... R, R_range, R_level`. The first valid assessment of each participant is
used for agreement and accuracy; the first two give test-retest reliability.

**pt_reference.csv**: typed in by the team from the physical therapist's blinded examination:

| Column | Meaning |
|---|---|
| participant | code, e.g. P001 |
| set | `dev` (threshold setting) or `val` (validation) |
| pt_K, pt_L, pt_N, pt_F, pt_S | inclinometer angles at the same landmarks (°) |
| pt_R | scoliometer angle of trunk rotation (°) |
| pt_level | the therapist's triage: healthy, monitor or refer |

## Methods implemented

- Bland–Altman bias and 95% limits of agreement with CIs (Bland & Altman, 1999); MAE; RMSE.
- ICC(A,1): two-way random effects, absolute agreement, single measurement, with the
  McGraw & Wong (1996) 95% CI. Equals pingouin's ICC2.
- SEM = SD·√(1 − ICC); MDC95 = 1.96·√2·SEM.
- 3×3 confusion matrix; per-level sensitivity, specificity, PPV, NPV (Wilson 95% CIs) and F1;
  accuracy; multiclass MCC; linearly weighted kappa with a bootstrap 95% CI.
- Thresholds: μ + 1.5σ (monitor) and μ + 2σ (refer) from healthy development-set participants;
  trunk rotation fixed at 3° / 5°.
