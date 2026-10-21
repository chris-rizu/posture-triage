// Three-level triage rule (thesis Section 3.2.5, Table 3.4).
//
// Each indicator has a reference value mu and two limits on the distance |v - mu|:
//   |v - mu| <  mon            -> healthy
//   mon <= |v - mu| < ref      -> monitor
//   |v - mu| >= ref            -> refer
// The overall result is the worst level of the six indicators.
//
// mon/ref are 1.5 sigma / 2 sigma of the healthy development-set participants
// (the analysis toolkit writes them; the app sends them with the THR command).
// R (trunk rotation) uses fixed limits: 3 deg monitor, 5 deg refer.
#pragma once
#include <math.h>
#include "indicators.h"

namespace pt {

enum Risk : uint8_t { RISK_HEALTHY = 0, RISK_MONITOR = 1, RISK_REFER = 2, RISK_NONE = 255 };
static const char* const kRiskKey[3] = {"healthy", "monitor", "refer"};

struct Limit {
  float mu, mon, ref;
};

struct Thresholds {
  Limit lim[IND_COUNT];
  bool provisional;  // true until replaced by values from the development set
};

// PROVISIONAL defaults so the system works before the development set is collected.
// Replace them with the analysis toolkit output (analysis/thresholds.json) via THR.
inline Thresholds defaultThresholds() {
  Thresholds t;
  t.lim[IND_K] = {38.0f, 12.0f, 16.0f};  // sigma ~8 deg
  t.lim[IND_L] = {-22.0f, 12.0f, 16.0f}; // sigma ~8 deg
  t.lim[IND_N] = {28.0f, 12.0f, 16.0f};  // sigma ~8 deg
  t.lim[IND_F] = {0.0f, 2.25f, 3.0f};    // sigma ~1.5 deg
  t.lim[IND_S] = {0.0f, 3.0f, 4.0f};     // sigma ~2 deg
  t.lim[IND_R] = {0.0f, 3.0f, 5.0f};     // fixed (scoliometer-style ATR limits)
  t.provisional = true;
  return t;
}

inline Risk levelOf(float v, const Limit& l) {
  float d = fabsf(v - l.mu);
  if (d >= l.ref) return RISK_REFER;
  if (d >= l.mon) return RISK_MONITOR;
  return RISK_HEALTHY;
}

inline Risk worst(Risk a, Risk b) {
  if (a == RISK_NONE) return b;
  if (b == RISK_NONE) return a;
  return a > b ? a : b;
}

inline Risk triage(const float v[IND_COUNT], const Thresholds& th, Risk lvl[IND_COUNT]) {
  Risk overall = RISK_HEALTHY;
  for (int i = 0; i < IND_COUNT; ++i) {
    lvl[i] = levelOf(v[i], th.lim[i]);
    overall = worst(overall, lvl[i]);
  }
  return overall;
}

// Sanity check for thresholds received over BLE.
inline bool validThresholds(const Thresholds& t) {
  for (int i = 0; i < IND_COUNT; ++i) {
    const Limit& l = t.lim[i];
    if (!(l.mon > 0.0f) || !(l.ref >= l.mon) || l.ref > 90.0f || fabsf(l.mu) > 90.0f) return false;
  }
  return true;
}

}  // namespace pt
