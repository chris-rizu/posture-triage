// Shared constants for the posture-triage firmware core (hardware independent).
// Values follow Chapter 3 of the thesis (Table 3.1, Section 3.4.6).
#pragma once
#include <stdint.h>

namespace pt {

constexpr int kNumPods = 5;               // IMU1..IMU5 = multiplexer channels 0..4
constexpr float kSampleHz = 50.0f;        // per-sensor sampling rate
constexpr float kDt = 1.0f / kSampleHz;   // 0.02 s
constexpr float kAlpha = 0.98f;           // complementary filter weight (time constant ~1 s)

// Calibration (Section 3.2.5): stand still for 3 s; reject if any gyro axis std > 0.5 deg/s.
constexpr float kCalSeconds = 3.0f;
constexpr float kCalMaxGyroStd = 0.5f;

// Trials (Section 3.4.6 / Table 3.8)
constexpr float kStandSeconds = 30.0f;    // standing trial length
constexpr float kStandKeepFrom = 5.0f;    // average over the middle 20 s (5 s .. 25 s)
constexpr float kStandKeepTo = 25.0f;
constexpr float kBendSeconds = 5.0f;      // forward-bend hold
constexpr float kMoveGyroDps = 5.0f;      // a trial is invalid if motion above this ...
constexpr float kMoveMaxSeconds = 1.0f;   // ... lasts longer than this
constexpr float kTrialAgreeDeg = 3.0f;    // three trials must agree within 3 deg

// Monitoring mode: alert when an indicator stays beyond the personal limit this long.
constexpr float kMonitorHoldSeconds = 10.0f;

// Battery (Section 3.2.5)
constexpr float kBatteryShutdownV = 3.30f;
constexpr float kBatteryWarnV = 3.45f;

}  // namespace pt
