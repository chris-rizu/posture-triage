// Posture indicators computed from the five pod tilts (thesis Table 3.3, Eq. 3.5-3.10).
//
// Pod index:  0 = IMU1 C7-T1, 1 = IMU2 T12-L1, 2 = IMU3 L3-L4, 3 = IMU4 left scapula,
//             4 = IMU5 right scapula   (multiplexer channels 0..4)
//
// Standing trial:
//   K  upper-back rounding  = s1 - s2
//   L  lower-back curve     = s2 - s3
//   N  neck-base tilt       = s1
//   F  trunk lean           = f2
//   S  shoulder tilt        = (f4 + f5) / 2
// Forward-bend trial (back facing up):
//   R  trunk rotation       = max(|(r4 + r5) / 2|, |r2|)
#pragma once
#include <math.h>
#include "orientation.h"

namespace pt {

enum Ind : uint8_t { IND_K = 0, IND_L, IND_N, IND_F, IND_S, IND_R, IND_COUNT };
static const char* const kIndKey[IND_COUNT] = {"K", "L", "N", "F", "S", "R"};
static const char* const kIndName[IND_COUNT] = {
    "Upper-back rounding", "Lower-back curve", "Neck-base tilt",
    "Trunk lean", "Shoulder tilt", "Trunk rotation"};

// Indicators measured in the standing trial (K, L, N, F, S); R comes from the bend.
inline bool isStandIndicator(int i) { return i != IND_R; }

struct PodTilts {
  Tilt p[kNumPods];
};

inline void standIndicators(const PodTilts& t, float out[IND_COUNT]) {
  out[IND_K] = t.p[0].s - t.p[1].s;
  out[IND_L] = t.p[1].s - t.p[2].s;
  out[IND_N] = t.p[0].s;
  out[IND_F] = t.p[1].f;
  out[IND_S] = 0.5f * (t.p[3].f + t.p[4].f);
}

inline float bendRotation(const PodTilts& t) {
  float scap = fabsf(0.5f * (t.p[3].r + t.p[4].r));
  float tl = fabsf(t.p[1].r);
  return scap > tl ? scap : tl;
}

// All six from a single snapshot (used for the live stream; R is only meaningful
// while the wearer is bent forward).
inline void liveIndicators(const PodTilts& t, float out[IND_COUNT]) {
  standIndicators(t, out);
  out[IND_R] = bendRotation(t);
}

}  // namespace pt
