"""Agreement and reliability statistics (thesis Section 3.5).

Bland-Altman bias and limits of agreement, MAE, RMSE, ICC(A,1) with its 95%
confidence interval (McGraw & Wong, two-way random effects, absolute agreement,
single measurement), SEM and MDC95.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict

import numpy as np
from scipy import stats


@dataclass
class BlandAltman:
    n: int
    bias: float          # mean(device - reference)
    sd: float            # SD of the differences
    loa_low: float
    loa_high: float
    bias_ci: tuple[float, float]
    loa_low_ci: tuple[float, float]
    loa_high_ci: tuple[float, float]

    def as_dict(self) -> dict:
        return asdict(self)


def bland_altman(device, reference, alpha: float = 0.05) -> BlandAltman:
    """Bias and 95% limits of agreement with approximate CIs (Bland & Altman, 1999)."""
    d = np.asarray(device, float) - np.asarray(reference, float)
    d = d[~np.isnan(d)]
    n = d.size
    if n < 3:
        raise ValueError("need at least 3 paired values")
    bias = float(d.mean())
    sd = float(d.std(ddof=1))
    z = stats.norm.ppf(1 - alpha / 2)
    t = stats.t.ppf(1 - alpha / 2, n - 1)
    lo, hi = bias - z * sd, bias + z * sd
    se_bias = sd / np.sqrt(n)
    se_loa = sd * np.sqrt(3.0 / n)
    return BlandAltman(
        n=n, bias=bias, sd=sd, loa_low=lo, loa_high=hi,
        bias_ci=(bias - t * se_bias, bias + t * se_bias),
        loa_low_ci=(lo - t * se_loa, lo + t * se_loa),
        loa_high_ci=(hi - t * se_loa, hi + t * se_loa),
    )


def mae(device, reference) -> float:
    d = np.asarray(device, float) - np.asarray(reference, float)
    return float(np.nanmean(np.abs(d)))


def rmse(device, reference) -> float:
    d = np.asarray(device, float) - np.asarray(reference, float)
    return float(np.sqrt(np.nanmean(d ** 2)))


@dataclass
class ICC:
    icc: float
    ci_low: float
    ci_high: float
    n: int
    k: int
    msr: float  # between subjects (rows)
    msc: float  # between raters/methods (columns)
    mse: float  # residual


def icc_a1(data, alpha: float = 0.05) -> ICC:
    """ICC(A,1): two-way random effects, absolute agreement, single measurement.

    data: n subjects x k methods (or raters, or sessions). Rows with NaN are dropped.
    Equals Shrout & Fleiss ICC(2,1) and pingouin's "ICC2".
    """
    x = np.asarray(data, float)
    x = x[~np.isnan(x).any(axis=1)]
    n, k = x.shape
    if n < 3 or k < 2:
        raise ValueError("need at least 3 subjects and 2 methods")
    grand = x.mean()
    ss_r = k * ((x.mean(axis=1) - grand) ** 2).sum()
    ss_c = n * ((x.mean(axis=0) - grand) ** 2).sum()
    ss_t = ((x - grand) ** 2).sum()
    ss_e = ss_t - ss_r - ss_c
    msr = ss_r / (n - 1)
    msc = ss_c / (k - 1)
    mse = ss_e / ((n - 1) * (k - 1))
    icc = (msr - mse) / (msr + (k - 1) * mse + k * (msc - mse) / n)

    # 95% CI, McGraw & Wong (1996), case 2A
    a = k * icc / (n * (1 - icc))
    b = 1 + k * icc * (n - 1) / (n * (1 - icc))
    v = (a * msc + b * mse) ** 2 / ((a * msc) ** 2 / (k - 1) + (b * mse) ** 2 / ((n - 1) * (k - 1)))
    fl = stats.f.ppf(1 - alpha / 2, n - 1, v)
    fu = stats.f.ppf(1 - alpha / 2, v, n - 1)
    lo = n * (msr - fl * mse) / (fl * (k * msc + (k * n - k - n) * mse) + n * msr)
    hi = n * (fu * msr - mse) / (k * msc + (k * n - k - n) * mse + n * fu * msr)
    return ICC(float(icc), float(lo), float(hi), n, k, float(msr), float(msc), float(mse))


def sem_mdc(data) -> tuple[float, float]:
    """Standard error of measurement and minimal detectable change (95%) from
    test-retest data (n subjects x 2 sessions): SEM = SD * sqrt(1 - ICC),
    MDC95 = 1.96 * sqrt(2) * SEM."""
    x = np.asarray(data, float)
    x = x[~np.isnan(x).any(axis=1)]
    icc = icc_a1(x).icc
    sd = float(x.std(ddof=1))
    sem = sd * np.sqrt(max(0.0, 1 - icc))
    return float(sem), float(1.96 * np.sqrt(2) * sem)
