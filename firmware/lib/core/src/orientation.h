// Tilt estimation for one sensor pod: accelerometer angles fused with the gyroscope
// by a complementary filter (thesis Eq. 3.1-3.4).
//
// Pod axes (mount every GY-521 the same way):
//   X  along the spine, pointing toward the head
//   Z  perpendicular to the back, pointing away from the body (chip side out)
//   Y  = Z x X, pointing to the wearer's LEFT
//
// Angles, all in degrees:
//   s  sagittal tilt  = atan2(az, ax). Positive = top of the segment tilted FORWARD.
//   f  frontal tilt   = atan2(ay, ax). Positive = top of the segment tilted to the wearer's RIGHT.
//   r  surface roll   = atan2(ay, az). Used in the forward bend, when the back faces up.
//                       Positive = wearer's LEFT side of the back higher.
//
// Gyro coupling (derived from rigid-body kinematics and checked in test_core):
//   ds/dt = +gy,  df/dt = -gz,  dr/dt = +gx
//
// f and r are only defined when their atan2 arguments are not both near zero:
// f needs the pod roughly upright (|(ax, ay)| >= 0.5 g, i.e. bent less than ~60 deg),
// r needs the back roughly facing up (|(ay, az)| >= 0.5 g, i.e. bent more than ~30 deg).
// Outside those ranges the filter reports NaN, and when the angle becomes defined
// again it restarts from the accelerometer value instead of carrying stale state.
#pragma once
#include <math.h>
#include "core_config.h"

namespace pt {

struct ImuSample {      // one reading in physical units
  float ax, ay, az;     // g
  float gx, gy, gz;     // deg/s
};

struct Tilt {
  float s = 0, f = 0, r = 0;
};

inline float rad2deg(float r) { return r * 57.29577951308232f; }

constexpr float kMinLeverG = 0.5f;

inline bool frontalDefined(const ImuSample& m) { return m.ax * m.ax + m.ay * m.ay >= kMinLeverG * kMinLeverG; }
inline bool rollDefined(const ImuSample& m) { return m.ay * m.ay + m.az * m.az >= kMinLeverG * kMinLeverG; }

inline Tilt accelTilt(const ImuSample& m) {
  Tilt t;
  t.s = rad2deg(atan2f(m.az, m.ax));
  t.f = frontalDefined(m) ? rad2deg(atan2f(m.ay, m.ax)) : NAN;
  t.r = rollDefined(m) ? rad2deg(atan2f(m.ay, m.az)) : NAN;
  return t;
}

class TiltFilter {
 public:
  void setBias(float bx, float by, float bz) { bx_ = bx; by_ = by; bz_ = bz; }
  void reset(const ImuSample& m) { t_ = accelTilt(m); started_ = true; }
  const Tilt& tilt() const { return t_; }
  bool started() const { return started_; }

  // Gyro rate after bias removal (deg/s), used for motion checks.
  float rateMagnitude(const ImuSample& m) const {
    float x = m.gx - bx_, y = m.gy - by_, z = m.gz - bz_;
    return sqrtf(x * x + y * y + z * z);
  }

  void update(const ImuSample& m, float dt = kDt, float alpha = kAlpha) {
    Tilt a = accelTilt(m);
    if (!started_) { t_ = a; started_ = true; return; }
    t_.s = blend(t_.s + (m.gy - by_) * dt, a.s, alpha);
    t_.f = blend(t_.f - (m.gz - bz_) * dt, a.f, alpha);
    t_.r = blend(t_.r + (m.gx - bx_) * dt, a.r, alpha);
  }

 private:
  // Blend while respecting the +-180 deg wrap of atan2.
  static float blend(float gyroAngle, float accAngle, float alpha) {
    if (accAngle != accAngle) return NAN;          // angle undefined in this pose
    if (gyroAngle != gyroAngle) return accAngle;   // just became defined: restart
    float d = accAngle - gyroAngle;
    while (d > 180.f) d -= 360.f;
    while (d < -180.f) d += 360.f;
    float out = gyroAngle + (1.f - alpha) * d;
    while (out > 180.f) out -= 360.f;
    while (out < -180.f) out += 360.f;
    return out;
  }
  Tilt t_;
  bool started_ = false;
  float bx_ = 0, by_ = 0, bz_ = 0;
};

}  // namespace pt
