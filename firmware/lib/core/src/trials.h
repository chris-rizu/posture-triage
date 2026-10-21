// Calibration and trial recording (thesis Section 3.2.5 and 3.4.6).
#pragma once
#include <math.h>
#include "indicators.h"

namespace pt {

// ---------------------------------------------------------------- calibration
// Wearer stands still for kCalSeconds. Mean gyro per axis becomes the bias;
// the calibration is rejected if any pod's gyro standard deviation on any axis
// exceeds kCalMaxGyroStd (the wearer moved).
class Calibrator {
 public:
  void start() {
    n_ = 0;
    for (int p = 0; p < kNumPods; ++p)
      for (int a = 0; a < 3; ++a) sum_[p][a] = sq_[p][a] = 0.0;
  }
  // Returns true when enough samples are in.
  bool add(const ImuSample m[kNumPods]) {
    for (int p = 0; p < kNumPods; ++p) {
      const float g[3] = {m[p].gx, m[p].gy, m[p].gz};
      for (int a = 0; a < 3; ++a) { sum_[p][a] += g[a]; sq_[p][a] += (double)g[a] * g[a]; }
    }
    ++n_;
    return n_ >= samplesNeeded();
  }
  static int samplesNeeded() { return (int)(kCalSeconds * kSampleHz + 0.5f); }
  int count() const { return n_; }
  float bias(int p, int a) const { return n_ ? (float)(sum_[p][a] / n_) : 0.0f; }
  float stdev(int p, int a) const {
    if (n_ < 2) return 0.0f;
    double mean = sum_[p][a] / n_;
    double var = sq_[p][a] / n_ - mean * mean;
    return var > 0 ? (float)sqrt(var) : 0.0f;
  }
  // -1 if still enough, else index of the first pod that moved.
  int movingPod() const {
    for (int p = 0; p < kNumPods; ++p)
      for (int a = 0; a < 3; ++a)
        if (stdev(p, a) > kCalMaxGyroStd) return p;
    return -1;
  }

 private:
  int n_ = 0;
  double sum_[kNumPods][3];
  double sq_[kNumPods][3];
};

// ---------------------------------------------------------------- trials
enum TrialKind : uint8_t { TRIAL_STAND = 0, TRIAL_BEND = 1 };
enum TrialFail : uint8_t { FAIL_NONE = 0, FAIL_MOVED, FAIL_NOT_BENT, FAIL_NOT_UPRIGHT, FAIL_ABORTED, FAIL_SENSOR };
static const char* const kFailKey[] = {"", "moved", "not_bent", "not_upright", "aborted", "sensor"};

constexpr float kBendMinFlexDeg = 45.0f;   // IMU2 must be tilted at least this far in the bend
constexpr float kStandMaxFlexDeg = 40.0f;  // and less than this while standing

struct TrialSummary {
  TrialKind kind;
  bool ok;
  TrialFail why;
  PodTilts mean;       // mean tilt of each pod over the kept window
  float ind[IND_COUNT];  // indicators from that mean (stand: K..S; bend: R)
};

// Records one trial from the filtered pod tilts. Stand: 30 s, mean of 5..25 s.
// Bend: 5 s hold, mean of 1..5 s. Motion above kMoveGyroDps for longer than
// kMoveMaxSeconds (continuous) anywhere inside the kept window invalidates it.
class TrialRecorder {
 public:
  void start(TrialKind k) {
    kind_ = k; n_ = 0; kept_ = 0; moveRun_ = 0; maxMoveRun_ = 0;
    for (int p = 0; p < kNumPods; ++p) acc_[p][0] = acc_[p][1] = acc_[p][2] = 0.0;
  }
  TrialKind kind() const { return kind_; }
  float seconds() const { return n_ / kSampleHz; }
  float duration() const { return kind_ == TRIAL_STAND ? kStandSeconds : kBendSeconds; }

  // motionDps: the largest bias-corrected gyro magnitude across the pods this tick.
  // Returns true when the trial is finished.
  bool add(const PodTilts& t, float motionDps) {
    float s = n_ / kSampleHz;
    float from = kind_ == TRIAL_STAND ? kStandKeepFrom : 1.0f;
    float to = kind_ == TRIAL_STAND ? kStandKeepTo : kBendSeconds;
    if (s >= from && s < to) {
      for (int p = 0; p < kNumPods; ++p) {
        acc_[p][0] += t.p[p].s; acc_[p][1] += t.p[p].f; acc_[p][2] += t.p[p].r;
      }
      ++kept_;
      if (motionDps > kMoveGyroDps) {
        ++moveRun_;
        if (moveRun_ > maxMoveRun_) maxMoveRun_ = moveRun_;
      } else {
        moveRun_ = 0;
      }
    }
    ++n_;
    return s + 1.0f / kSampleHz >= duration() - 1e-4f;
  }

  TrialSummary summary() const {
    TrialSummary r;
    r.kind = kind_;
    r.why = FAIL_NONE;
    for (int i = 0; i < IND_COUNT; ++i) r.ind[i] = NAN;
    if (kept_ == 0) { r.ok = false; r.why = FAIL_ABORTED; return r; }
    for (int p = 0; p < kNumPods; ++p) {
      r.mean.p[p].s = (float)(acc_[p][0] / kept_);
      r.mean.p[p].f = (float)(acc_[p][1] / kept_);
      r.mean.p[p].r = (float)(acc_[p][2] / kept_);
    }
    if (kind_ == TRIAL_STAND) standIndicators(r.mean, r.ind);
    else r.ind[IND_R] = bendRotation(r.mean);

    if (maxMoveRun_ / kSampleHz > kMoveMaxSeconds) r.why = FAIL_MOVED;
    else if (kind_ == TRIAL_BEND && r.mean.p[1].s < kBendMinFlexDeg) r.why = FAIL_NOT_BENT;
    else if (kind_ == TRIAL_STAND && fabsf(r.mean.p[1].s) > kStandMaxFlexDeg) r.why = FAIL_NOT_UPRIGHT;
    r.ok = r.why == FAIL_NONE;
    return r;
  }

 private:
  TrialKind kind_ = TRIAL_STAND;
  int n_ = 0, kept_ = 0, moveRun_ = 0, maxMoveRun_ = 0;
  double acc_[kNumPods][3];
};

// ---------------------------------------------------------------- assessment
// Holds the last three valid trials of each kind and combines them.
struct IndicatorResult {
  float value;   // mean of the three trials
  float range;   // max - min across the trials
  bool agree;    // range <= kTrialAgreeDeg
  Risk level;
};

struct Assessment {
  bool complete;          // three valid stand and three valid bend trials
  bool agree;             // every indicator within kTrialAgreeDeg
  int retakeStand, retakeBend;  // 1 if that trial type needs repeating
  IndicatorResult ind[IND_COUNT];
  Risk risk;              // RISK_NONE unless complete && agree
};

class TrialSet {
 public:
  static constexpr int kTrials = 3;
  void clear() { nStand_ = nBend_ = 0; }
  int standCount() const { return nStand_ < kTrials ? nStand_ : kTrials; }
  int bendCount() const { return nBend_ < kTrials ? nBend_ : kTrials; }

  // Keeps the most recent three of each kind (a ring), so repeating a trial
  // after a disagreement replaces the oldest.
  void add(const TrialSummary& t) {
    if (!t.ok) return;
    if (t.kind == TRIAL_STAND) stand_[nStand_++ % kTrials] = t;
    else bend_[nBend_++ % kTrials] = t;
  }

  Assessment assess(const Thresholds& th) const {
    Assessment a;
    a.complete = standCount() == kTrials && bendCount() == kTrials;
    a.agree = true;
    a.retakeStand = a.retakeBend = 0;
    for (int i = 0; i < IND_COUNT; ++i) {
      const TrialSummary* src = isStandIndicator(i) ? stand_ : bend_;
      int n = isStandIndicator(i) ? standCount() : bendCount();
      IndicatorResult& r = a.ind[i];
      if (n == 0) { r.value = NAN; r.range = NAN; r.agree = false; r.level = RISK_NONE; continue; }
      float sum = 0, lo = 1e9f, hi = -1e9f;
      for (int k = 0; k < n; ++k) {
        float v = src[k].ind[i];
        sum += v; if (v < lo) lo = v; if (v > hi) hi = v;
      }
      r.value = sum / n;
      r.range = hi - lo;
      r.agree = r.range <= kTrialAgreeDeg;
      r.level = levelOf(r.value, th.lim[i]);
      if (!r.agree) {
        a.agree = false;
        if (isStandIndicator(i)) a.retakeStand = 1; else a.retakeBend = 1;
      }
    }
    a.risk = RISK_NONE;
    if (a.complete && a.agree) {
      a.risk = RISK_HEALTHY;
      for (int i = 0; i < IND_COUNT; ++i) a.risk = worst(a.risk, a.ind[i].level);
    }
    return a;
  }

 private:
  TrialSummary stand_[kTrials];
  TrialSummary bend_[kTrials];
  int nStand_ = 0, nBend_ = 0;
};

// ---------------------------------------------------------------- monitoring
// Alerts when an indicator stays beyond its monitor limit for kMonitorHoldSeconds,
// then waits kCooldownSeconds before alerting again. Only the standing indicators
// that make sense during daily wear are watched: K, N, F, S.
class PostureMonitor {
 public:
  static constexpr float kCooldownSeconds = 30.0f;
  void start() { for (int i = 0; i < IND_COUNT; ++i) over_[i] = 0; cooldown_ = 0; }
  // Returns the indicator index that triggered an alert this tick, or -1.
  int add(const float v[IND_COUNT], const Thresholds& th) {
    static const int watched[] = {IND_K, IND_N, IND_F, IND_S};
    if (cooldown_ > 0) --cooldown_;
    int fired = -1;
    for (int w : watched) {
      if (levelOf(v[w], th.lim[w]) != RISK_HEALTHY) ++over_[w]; else over_[w] = 0;
      if (fired < 0 && cooldown_ == 0 && over_[w] >= (int)(kMonitorHoldSeconds * kSampleHz)) {
        fired = w;
        cooldown_ = (int)(kCooldownSeconds * kSampleHz);
        for (int i = 0; i < IND_COUNT; ++i) over_[i] = 0;
      }
    }
    return fired;
  }

 private:
  int over_[IND_COUNT];
  int cooldown_ = 0;
};

}  // namespace pt
