// Virtual wearer: produces realistic MPU-6050 readings for the five pods so the
// firmware, the app and the analysis can be tested without the hardware.
//
// The simulator is deliberately independent of the angle formulas in
// orientation.h: it builds each pod's orientation as a rotation matrix, then
// reports gravity in the sensor frame (accelerometer) and the body angular
// velocity from successive rotations (gyroscope). If the formulas or their
// signs were wrong, the unit tests would catch it.
//
// World frame: U = up, W = wearer's left, B = backward (out of the back).
// A pod in neutral upright stance has X = U, Y = W, Z = B.
// Pod orientation = Ry(flex) * Rz(-side) * Rx(roll)   (intrinsic)
//   flex  > 0  top of the pod tilted forward  (expected s = flex)
//   side  > 0  top tilted to the wearer's right (expected f = side when upright)
//   roll  > 0  left side up when the back faces up (expected r = roll in the bend)
#pragma once
#include <math.h>
#include <stdint.h>
#include <string.h>
#include "orientation.h"

namespace pt {

struct Mat3 {
  float m[3][3];
  static Mat3 I() { Mat3 r{}; r.m[0][0] = r.m[1][1] = r.m[2][2] = 1; return r; }
  Mat3 operator*(const Mat3& b) const {
    Mat3 r{};
    for (int i = 0; i < 3; ++i)
      for (int j = 0; j < 3; ++j)
        for (int k = 0; k < 3; ++k) r.m[i][j] += m[i][k] * b.m[k][j];
    return r;
  }
  Mat3 T() const {
    Mat3 r{};
    for (int i = 0; i < 3; ++i) for (int j = 0; j < 3; ++j) r.m[i][j] = m[j][i];
    return r;
  }
};
inline float d2r(float d) { return d * 0.017453292519943295f; }
inline Mat3 rotX(float deg) { float c = cosf(d2r(deg)), s = sinf(d2r(deg)); Mat3 r = Mat3::I(); r.m[1][1] = c; r.m[1][2] = -s; r.m[2][1] = s; r.m[2][2] = c; return r; }
inline Mat3 rotY(float deg) { float c = cosf(d2r(deg)), s = sinf(d2r(deg)); Mat3 r = Mat3::I(); r.m[0][0] = c; r.m[0][2] = s; r.m[2][0] = -s; r.m[2][2] = c; return r; }
inline Mat3 rotZ(float deg) { float c = cosf(d2r(deg)), s = sinf(d2r(deg)); Mat3 r = Mat3::I(); r.m[0][0] = c; r.m[0][1] = -s; r.m[1][0] = s; r.m[1][1] = c; return r; }

// Columns of R are the pod axes X, Y, Z written in world coordinates (U, W, B).
// (U, W, B) is right-handed: U x W = B. rotY(+a) turns X toward -B (forward),
// rotZ(-a) turns X toward -W (the wearer's right), rotX(+a) turns Y toward Z.
inline Mat3 poseMatrix(float flex, float side, float roll) {
  return rotY(flex) * rotZ(-side) * rotX(roll);
}

// Small deterministic RNG (xorshift) with a Gaussian helper.
struct Rng {
  uint32_t s;
  explicit Rng(uint32_t seed = 12345u) : s(seed ? seed : 1u) {}
  uint32_t next() { s ^= s << 13; s ^= s >> 17; s ^= s << 5; return s; }
  float uni() { return (next() >> 8) * (1.0f / 16777216.0f); }
  float gauss() {  // Box-Muller
    float u1 = uni(), u2 = uni();
    if (u1 < 1e-7f) u1 = 1e-7f;
    return sqrtf(-2.0f * logf(u1)) * cosf(6.2831853f * u2);
  }
};

// Readings for one pod at orientation R, given the previous orientation (for the gyro).
inline ImuSample sampleFromPose(const Mat3& R, const Mat3& Rprev, float dt) {
  ImuSample m;
  // gravity reaction = +1 g along world up (U = row 0); in sensor frame: R^T * U
  m.ax = R.m[0][0]; m.ay = R.m[0][1]; m.az = R.m[0][2];
  // body angular velocity: dR = Rprev^T * R ~ I + [w]x dt
  Mat3 d = Rprev.T() * R;
  float k = 57.29577951f / (2.0f * dt);
  m.gx = (d.m[2][1] - d.m[1][2]) * k;
  m.gy = (d.m[0][2] - d.m[2][0]) * k;
  m.gz = (d.m[1][0] - d.m[0][1]) * k;
  return m;
}

// Posture profile of a virtual wearer (degrees). These are the "true" indicator values.
struct Profile {
  const char* key;
  float K, L, N, F, S, R;
};
static const Profile kProfiles[] = {
    {"healthy", 38.0f, -22.0f, 28.0f, 0.3f, 0.5f, 1.2f},
    {"rounded", 56.0f, -18.0f, 41.0f, 0.5f, 1.0f, 1.5f},   // kyphotic / forward-head pattern
    {"asymmetric", 40.0f, -24.0f, 29.0f, 2.6f, 3.4f, 4.0f}, // mild asymmetry -> monitor
    {"scoliotic", 42.0f, -26.0f, 30.0f, 3.5f, 4.6f, 7.5f},  // rotation >= 5 deg -> refer
};
constexpr int kNumProfiles = sizeof(kProfiles) / sizeof(kProfiles[0]);

inline const Profile* findProfile(const char* key) {
  for (const auto& p : kProfiles)
    if (strcmp(p.key, key) == 0) return &p;
  return nullptr;
}

enum SimPose : uint8_t { POSE_STAND = 0, POSE_BEND = 1, POSE_SLOUCH = 2 };

class WearerSim {
 public:
  explicit WearerSim(uint32_t seed = 7u) : rng_(seed) {
    setProfile(kProfiles[0]);
    for (int p = 0; p < kNumPods; ++p) {
      bias_[p][0] = 0.8f * rng_.gauss(); bias_[p][1] = 0.8f * rng_.gauss(); bias_[p][2] = 0.8f * rng_.gauss();
    }
    for (int p = 0; p < kNumPods; ++p) prev_[p] = target(p);
  }
  void setProfile(const Profile& p) { prof_ = p; }
  const Profile& profile() const { return prof_; }
  // The pose changes smoothly over transitionSeconds.
  void setPose(SimPose p, float transitionSeconds = 2.0f) {
    pose_ = p; trans_ = transitionSeconds > 0 ? transitionSeconds : 0.01f;
  }
  SimPose pose() const { return pose_; }
  void setNoise(bool on) { noise_ = on; }
  void setFidget(bool on) { fidget_ = on; }   // inject movement (to test motion rejection)
  float time() const { return t_; }

  void step(ImuSample out[kNumPods], float dt = kDt) {
    t_ += dt;
    float bendGoal = (pose_ == POSE_BEND) ? 1.0f : 0.0f;
    float slouchGoal = (pose_ == POSE_SLOUCH) ? 1.0f : 0.0f;
    bend_ += clampStep(bendGoal - bend_, dt / trans_);
    slouch_ += clampStep(slouchGoal - slouch_, dt / trans_);
    for (int p = 0; p < kNumPods; ++p) {
      Mat3 R = target(p);
      ImuSample m = sampleFromPose(R, prev_[p], dt);
      prev_[p] = R;
      if (noise_) {
        m.ax += 0.004f * rng_.gauss(); m.ay += 0.004f * rng_.gauss(); m.az += 0.004f * rng_.gauss();
        m.gx += 0.05f * rng_.gauss() + bias_[p][0];
        m.gy += 0.05f * rng_.gauss() + bias_[p][1];
        m.gz += 0.05f * rng_.gauss() + bias_[p][2];
      }
      out[p] = m;
    }
  }

  // Expected pod angles in the standing pose (no sway); used by tests.
  void standAngles(int pod, float& flex, float& side) const {
    const Profile& q = prof_;
    float s1 = q.N, s2 = q.N - q.K, s3 = s2 - q.L;
    switch (pod) {
      case 0: flex = s1; side = 0.5f * q.F; break;
      case 1: flex = s2; side = q.F; break;
      case 2: flex = s3; side = 0.6f * q.F; break;
      case 3: flex = s2 + 0.55f * q.K; side = q.S + 0.4f; break;   // scapulae: between C7 and T12
      default: flex = s2 + 0.55f * q.K; side = q.S - 0.4f; break;
    }
  }
  // Expected roll per pod in the bend.
  float bendRoll(int pod) const {
    switch (pod) {
      case 1: return 0.55f * prof_.R;
      case 3: return prof_.R + 0.3f;
      case 4: return prof_.R - 0.3f;
      default: return 0.3f * prof_.R;
    }
  }

 private:
  static float clampStep(float d, float maxStep) { return d > maxStep ? maxStep : (d < -maxStep ? -maxStep : d); }
  static float smooth(float x) { return x * x * (3.0f - 2.0f * x); }

  Mat3 target(int pod) const {
    float flex, side;
    standAngles(pod, flex, side);
    // slouch: the neck base and upper back round forward by 18 deg
    float sl = smooth(slouch_);
    if (pod == 0) flex += 18.0f * sl;
    if (pod >= 3) flex += 10.0f * sl;
    // breathing and sway
    float br = 0.25f * sinf(6.2831853f * 0.25f * t_ + pod);
    float sway = 0.3f * sinf(6.2831853f * 0.07f * t_);
    flex += br + sway;
    side += 0.2f * sinf(6.2831853f * 0.05f * t_);
    // forward bend: hip flexion carries every segment toward ~90 deg, curves flatten
    float b = smooth(bend_);
    float bentFlex = 88.0f + (pod == 0 ? 6.0f : pod == 2 ? -14.0f : 0.0f);
    flex = flex + (bentFlex - flex) * b;
    side = side * (1.0f - b);
    float roll = bendRoll(pod) * b;
    if (fidget_) {
      flex += 6.0f * sinf(6.2831853f * 1.1f * t_);
      side += 4.0f * sinf(6.2831853f * 0.9f * t_ + 1.0f);
    }
    return poseMatrix(flex, side, roll);
  }

  Rng rng_;
  Profile prof_;
  SimPose pose_ = POSE_STAND;
  float trans_ = 2.0f, bend_ = 0.0f, slouch_ = 0.0f, t_ = 0.0f;
  bool noise_ = true, fidget_ = false;
  float bias_[kNumPods][3];
  Mat3 prev_[kNumPods];
};

}  // namespace pt
