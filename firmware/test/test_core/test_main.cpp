// Unit tests for the hardware-independent firmware core. Run on the PC:
//   pio test -e native
#include <unity.h>
#include <string>
#include <vector>
#include "device.h"
#include "sim_driver.h"

using namespace pt;

void setUp() {}
void tearDown() {}

// ---------------------------------------------------------------- helpers
static ImuSample still(float flex, float side, float roll) {
  Mat3 R = poseMatrix(flex, side, roll);
  return sampleFromPose(R, R, kDt);
}

// Integrate a smooth ramp of one pose angle with the gyro only (alpha = 1) and
// return the final filter tilt. Starts from the accelerometer angle.
static Tilt gyroOnlyRamp(float f0, float s0, float r0, float f1, float s1, float r1, float seconds) {
  TiltFilter filt;
  int n = (int)(seconds * kSampleHz);
  Mat3 prev = poseMatrix(f0, s0, r0);
  filt.reset(sampleFromPose(prev, prev, kDt));
  for (int i = 1; i <= n; ++i) {
    float u = (float)i / n;
    Mat3 R = poseMatrix(f0 + (f1 - f0) * u, s0 + (s1 - s0) * u, r0 + (r1 - r0) * u);
    filt.update(sampleFromPose(R, prev, kDt), kDt, 1.0f);
    prev = R;
  }
  return filt.tilt();
}

struct RecIO : DeviceIO {
  SimDriver* drv = nullptr;
  std::vector<std::string> json;
  int meas = 0, buzz = 0;
  std::string saved;
  void sendJson(const char* j) override { json.push_back(j); }
  void sendMeasurement(const uint8_t*, int len) override { TEST_ASSERT_EQUAL(kMeasLen, len); ++meas; }
  void vibrate(int pulses, int) override { buzz += pulses; }
  void saveThresholds(const char* j) override { saved = j; }
  void onState(DevState s) override { if (drv) drv->onState(s); }
  bool simCommand(const char* a) override { return drv && drv->command(a); }
  // last message of a given type, parsed
  bool last(const char* type, JsonDocument& doc) const {
    for (auto it = json.rbegin(); it != json.rend(); ++it) {
      JsonDocument d;
      TEST_ASSERT_FALSE_MESSAGE(deserializeJson(d, *it), it->c_str());
      if (std::string(d["t"] | "") == type) { doc = d; return true; }
    }
    return false;
  }
};

struct Rig {
  SimDriver drv;
  RecIO io;
  Device dev;
  explicit Rig(const char* profile = "healthy", uint32_t seed = 7u) : drv(seed), dev(io) {
    io.drv = &drv;
    drv.sim.setProfile(*findProfile(profile));
    dev.begin(true);
  }
  void run(float seconds, uint8_t mask = 0x1F, uint16_t mv = 3900) {
    int n = (int)(seconds * kSampleHz + 0.5f);
    ImuSample m[kNumPods];
    for (int i = 0; i < n; ++i) { drv.sim.step(m); dev.tick(m, mask, mv); }
  }
  // run until the device is idle again (or timeout)
  void runUntilIdle(float maxSeconds = 40) {
    ImuSample m[kNumPods];
    for (int i = 0; i < (int)(maxSeconds * kSampleHz); ++i) {
      drv.sim.step(m); dev.tick(m, 0x1F, 3900);
      if (dev.state() == ST_IDLE) return;
    }
  }
  void cmd(const char* c) { dev.command(c); }
  void assess() {
    run(2);
    cmd("CAL"); runUntilIdle();
    for (int k = 0; k < 3; ++k) { cmd("STAND"); runUntilIdle(); run(1); }
    for (int k = 0; k < 3; ++k) { cmd("BEND"); runUntilIdle(); run(2); }
    cmd("RESULT");
  }
};

// ---------------------------------------------------------------- angle conventions
void test_accel_sagittal_sign() {
  // forward lean of 30 deg -> s = +30, f ~ 0
  Tilt t = accelTilt(still(30, 0, 0));
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 30.0f, t.s);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 0.0f, t.f);
  // backward lean
  TEST_ASSERT_FLOAT_WITHIN(0.01f, -12.0f, accelTilt(still(-12, 0, 0)).s);
}

void test_accel_frontal_sign() {
  // top tilted 5 deg to the wearer's right -> f = +5
  Tilt t = accelTilt(still(0, 5, 0));
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 5.0f, t.f);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 0.0f, t.s);
}

void test_accel_roll_in_bend() {
  // back facing up (flex 90), left side 6 deg higher -> r = +6
  Tilt t = accelTilt(still(90, 0, 6));
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 6.0f, t.r);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 90.0f, t.s);
  // and still right when the bend is not complete
  TEST_ASSERT_FLOAT_WITHIN(0.01f, -4.0f, accelTilt(still(75, 0, -4)).r);
}

void test_gyro_coupling_sagittal() {  // ds/dt = +gy
  Tilt t = gyroOnlyRamp(0, 0, 0, 40, 0, 0, 2.0f);
  TEST_ASSERT_FLOAT_WITHIN(0.3f, 40.0f, t.s);
}

void test_gyro_coupling_frontal() {   // df/dt = -gz
  Tilt t = gyroOnlyRamp(0, 0, 0, 0, 8, 0, 2.0f);
  TEST_ASSERT_FLOAT_WITHIN(0.2f, 8.0f, t.f);
}

void test_gyro_coupling_roll() {      // dr/dt = +gx (in the bend)
  Tilt t = gyroOnlyRamp(90, 0, 0, 90, 0, 7, 2.0f);
  TEST_ASSERT_FLOAT_WITHIN(0.2f, 7.0f, t.r);
}

void test_filter_rejects_gyro_bias_after_calibration() {
  TiltFilter f;
  ImuSample m = still(20, 0, 0);
  m.gy += 1.5f;  // uncorrected bias would drift s by ~1.5 deg/s * tau
  f.setBias(0, 1.5f, 0);
  f.reset(m);
  for (int i = 0; i < 500; ++i) f.update(m);
  TEST_ASSERT_FLOAT_WITHIN(0.05f, 20.0f, f.tilt().s);
}

// ---------------------------------------------------------------- indicators and triage
void test_indicators_from_simulated_stance() {
  WearerSim sim;
  sim.setNoise(false);
  sim.setProfile(*findProfile("rounded"));
  PodTilts t;
  for (int p = 0; p < kNumPods; ++p) {
    float flex, side;
    sim.standAngles(p, flex, side);
    t.p[p] = accelTilt(still(flex, side, 0));
  }
  float v[IND_COUNT];
  standIndicators(t, v);
  const Profile& q = sim.profile();
  TEST_ASSERT_FLOAT_WITHIN(0.05f, q.K, v[IND_K]);
  TEST_ASSERT_FLOAT_WITHIN(0.05f, q.L, v[IND_L]);
  TEST_ASSERT_FLOAT_WITHIN(0.05f, q.N, v[IND_N]);
  TEST_ASSERT_FLOAT_WITHIN(0.05f, q.F, v[IND_F]);
  TEST_ASSERT_FLOAT_WITHIN(0.1f, q.S, v[IND_S]);
}

void test_triage_levels() {
  Thresholds th = defaultThresholds();
  TEST_ASSERT_EQUAL(RISK_HEALTHY, levelOf(2.9f, th.lim[IND_R]));
  TEST_ASSERT_EQUAL(RISK_MONITOR, levelOf(3.0f, th.lim[IND_R]));
  TEST_ASSERT_EQUAL(RISK_MONITOR, levelOf(4.99f, th.lim[IND_R]));
  TEST_ASSERT_EQUAL(RISK_REFER, levelOf(5.0f, th.lim[IND_R]));
  TEST_ASSERT_EQUAL(RISK_REFER, levelOf(-6.0f, th.lim[IND_F]));  // two-sided
  float v[IND_COUNT] = {38, -22, 28, 0, 0, 3.5f};
  Risk lvl[IND_COUNT];
  TEST_ASSERT_EQUAL(RISK_MONITOR, triage(v, th, lvl));
  v[IND_K] = 60;
  TEST_ASSERT_EQUAL(RISK_REFER, triage(v, th, lvl));
}

// ---------------------------------------------------------------- protocol
void test_measurement_roundtrip() {
  Measurement m{};
  m.state = ST_STAND; m.seq = 65000; m.batteryMv = 3870; m.flags = MF_CALIBRATED | MF_SIMULATED;
  for (int p = 0; p < kNumPods; ++p) { m.tilt.p[p].s = 10.25f * p - 3; m.tilt.p[p].f = -1.5f * p; m.tilt.p[p].r = 0.33f * p; }
  for (int i = 0; i < IND_COUNT; ++i) m.ind[i] = -20.0f + 7.1f * i;
  m.ind[IND_R] = NAN;
  uint8_t b[kMeasLen];
  packMeasurement(m, b);
  Measurement u;
  TEST_ASSERT_TRUE(unpackMeasurement(b, kMeasLen, u));
  TEST_ASSERT_EQUAL(ST_STAND, u.state);
  TEST_ASSERT_EQUAL(65000, u.seq);
  TEST_ASSERT_EQUAL(3870, u.batteryMv);
  TEST_ASSERT_EQUAL(MF_CALIBRATED | MF_SIMULATED, u.flags);
  for (int p = 0; p < kNumPods; ++p) {
    TEST_ASSERT_FLOAT_WITHIN(0.006f, m.tilt.p[p].s, u.tilt.p[p].s);
    TEST_ASSERT_FLOAT_WITHIN(0.006f, m.tilt.p[p].f, u.tilt.p[p].f);
    TEST_ASSERT_FLOAT_WITHIN(0.006f, m.tilt.p[p].r, u.tilt.p[p].r);
  }
  TEST_ASSERT_FLOAT_WITHIN(0.006f, m.ind[IND_K], u.ind[IND_K]);
  TEST_ASSERT_TRUE(isnan(u.ind[IND_R]));
  TEST_ASSERT_FALSE(unpackMeasurement(b, kMeasLen - 1, u));
}

void test_command_parser() {
  TEST_ASSERT_EQUAL(CMD_CAL, parseCommand("CAL").cmd);
  TEST_ASSERT_EQUAL(CMD_STAND, parseCommand("  STAND\r\n").cmd);
  TEST_ASSERT_EQUAL(CMD_UNKNOWN, parseCommand("STANDX").cmd);
  TEST_ASSERT_EQUAL(CMD_GETTHR, parseCommand("GETTHR").cmd);
  ParsedCmd c = parseCommand("THR {\"R\":[0,3,5]}");
  TEST_ASSERT_EQUAL(CMD_THR, c.cmd);
  TEST_ASSERT_EQUAL_STRING("{\"R\":[0,3,5]}", c.arg);
}

void test_threshold_json() {
  RecIO io;
  Device d(io);
  TEST_ASSERT_TRUE(d.loadThresholdsJson("{\"K\":[40,10,14],\"provisional\":false}"));
  TEST_ASSERT_FLOAT_WITHIN(1e-4f, 40.0f, d.thresholds().lim[IND_K].mu);
  TEST_ASSERT_FALSE(d.thresholds().provisional);
  TEST_ASSERT_FLOAT_WITHIN(1e-4f, 3.0f, d.thresholds().lim[IND_R].mon);  // untouched
  TEST_ASSERT_FALSE(d.loadThresholdsJson("{\"K\":[40,14,10]}"));  // ref < mon
  TEST_ASSERT_FALSE(d.loadThresholdsJson("{\"K\":[40,10]}"));
  TEST_ASSERT_FALSE(d.loadThresholdsJson("not json"));
  d.command("THR {\"S\":[0,2.5,3.5]}");
  TEST_ASSERT_TRUE(io.saved.find("\"S\":[0.00,2.50,3.50]") != std::string::npos);
  // what is saved loads back
  Device d2(io);
  TEST_ASSERT_TRUE(d2.loadThresholdsJson(io.saved.c_str()));
  TEST_ASSERT_FLOAT_WITHIN(1e-4f, 2.5f, d2.thresholds().lim[IND_S].mon);
}

// ---------------------------------------------------------------- full device flow
static void checkProfile(const char* profile, const char* expectRisk) {
  Rig r(profile);
  r.assess();
  JsonDocument res;
  TEST_ASSERT_TRUE(r.io.last("result", res));
  TEST_ASSERT_TRUE_MESSAGE(res["complete"].as<bool>(), profile);
  TEST_ASSERT_TRUE_MESSAGE(res["agree"].as<bool>(), profile);
  TEST_ASSERT_EQUAL_STRING_MESSAGE(expectRisk, res["risk"] | "?", profile);
  // measured indicators are close to the virtual wearer's true values
  const Profile& q = *findProfile(profile);
  const float truth[IND_COUNT] = {q.K, q.L, q.N, q.F, q.S, q.R};
  for (int i = 0; i < IND_COUNT; ++i) {
    float v = res["ind"][kIndKey[i]][0].as<float>();
    char msg[64];
    snprintf(msg, sizeof msg, "%s %s measured %.2f true %.2f", profile, kIndKey[i], v, truth[i]);
    TEST_ASSERT_FLOAT_WITHIN_MESSAGE(1.0f, truth[i], v, msg);
  }
  // every message fits a 512-byte MTU and is valid JSON
  for (auto& j : r.io.json) {
    TEST_ASSERT_TRUE_MESSAGE(j.size() < 500, j.c_str());
    JsonDocument d;
    TEST_ASSERT_FALSE_MESSAGE(deserializeJson(d, j), j.c_str());
  }
  TEST_ASSERT_TRUE(r.io.meas > 100);
}

void test_flow_healthy() { checkProfile("healthy", "healthy"); }
void test_flow_asymmetric() { checkProfile("asymmetric", "monitor"); }
void test_flow_scoliotic() { checkProfile("scoliotic", "refer"); }
void test_flow_rounded() { checkProfile("rounded", "refer"); }

void test_trial_requires_calibration() {
  Rig r;
  r.cmd("STAND");
  JsonDocument e;
  TEST_ASSERT_TRUE(r.io.last("err", e));
  TEST_ASSERT_EQUAL_STRING("not_calibrated", e["msg"]);
  TEST_ASSERT_EQUAL(ST_IDLE, r.dev.state());
}

void test_calibration_rejects_movement() {
  Rig r;
  r.drv.sim.setFidget(true);
  r.cmd("CAL"); r.runUntilIdle();
  JsonDocument c;
  TEST_ASSERT_TRUE(r.io.last("cal", c));
  TEST_ASSERT_FALSE(c["ok"].as<bool>());
  TEST_ASSERT_EQUAL_STRING("moved", c["why"]);
  TEST_ASSERT_FALSE(r.dev.calibrated());
}

void test_trial_rejects_movement() {
  Rig r;
  r.run(1);
  r.cmd("CAL"); r.runUntilIdle();
  r.drv.sim.setFidget(true);
  r.cmd("STAND"); r.runUntilIdle();
  JsonDocument t;
  TEST_ASSERT_TRUE(r.io.last("trial", t));
  TEST_ASSERT_FALSE(t["ok"].as<bool>());
  TEST_ASSERT_EQUAL_STRING("moved", t["why"]);
  TEST_ASSERT_EQUAL(0, r.dev.trials().standCount());
}

void test_bend_rejected_when_not_bent() {
  Rig r;
  r.run(1);
  r.cmd("CAL"); r.runUntilIdle();
  r.cmd("SIM POSE STAND");   // manual pose: the wearer does not bend
  r.cmd("BEND"); r.runUntilIdle();
  JsonDocument t;
  TEST_ASSERT_TRUE(r.io.last("trial", t));
  TEST_ASSERT_EQUAL_STRING("not_bent", t["why"]);
}

void test_disagreeing_trials_ask_for_retake() {
  Rig r("healthy");
  r.run(1);
  r.cmd("CAL"); r.runUntilIdle();
  r.cmd("STAND"); r.runUntilIdle();
  r.cmd("STAND"); r.runUntilIdle();
  r.cmd("SIM PROFILE rounded");   // posture changes between trials
  r.run(3);
  r.cmd("STAND"); r.runUntilIdle();
  for (int k = 0; k < 3; ++k) { r.cmd("BEND"); r.runUntilIdle(); r.run(2); }
  r.cmd("RESULT");
  JsonDocument res;
  TEST_ASSERT_TRUE(r.io.last("result", res));
  TEST_ASSERT_FALSE(res["agree"].as<bool>());
  TEST_ASSERT_TRUE(res["risk"].isNull());
  TEST_ASSERT_EQUAL_STRING("stand", res["retake"][0]);
}

void test_sensor_fault_aborts_trial() {
  Rig r;
  r.run(1);
  r.cmd("CAL"); r.runUntilIdle();
  r.cmd("STAND");
  r.run(2);
  r.run(0.1f, 0x1F & ~(1 << 2));  // IMU3 stops answering
  JsonDocument t;
  TEST_ASSERT_TRUE(r.io.last("trial", t));
  TEST_ASSERT_EQUAL_STRING("sensor", t["why"]);
  TEST_ASSERT_EQUAL(ST_IDLE, r.dev.state());
}

void test_monitor_alerts_on_sustained_slouch() {
  Rig r;
  r.run(1);
  r.cmd("CAL"); r.runUntilIdle();
  r.cmd("MONITOR");
  TEST_ASSERT_EQUAL(ST_MONITOR, r.dev.state());
  r.run(15);
  JsonDocument a;
  TEST_ASSERT_FALSE(r.io.last("alert", a));   // good posture: no alert
  r.cmd("SIM POSE SLOUCH");
  r.run(14);                                  // 2 s transition + 10 s hold
  TEST_ASSERT_TRUE(r.io.last("alert", a));
  std::string which = a["ind"] | "";
  TEST_ASSERT_TRUE_MESSAGE(which == "K" || which == "N", which.c_str());  // rounding / neck tilt
  r.cmd("STOP");
  TEST_ASSERT_EQUAL(ST_IDLE, r.dev.state());
}

void test_low_battery_shutdown() {
  Rig r;
  r.run(6, 0x1F, 3250);
  TEST_ASSERT_TRUE(r.dev.lowBatteryShutdown());
  r.cmd("CAL");
  JsonDocument e;
  TEST_ASSERT_TRUE(r.io.last("err", e));
  TEST_ASSERT_EQUAL_STRING("low_battery", e["msg"]);
}

void test_button() {
  Rig r;
  r.run(1);
  r.dev.buttonLong();
  TEST_ASSERT_EQUAL(ST_CALIBRATING, r.dev.state());
  r.runUntilIdle();
  r.dev.buttonShort();
  TEST_ASSERT_EQUAL(ST_MONITOR, r.dev.state());
  r.dev.buttonShort();
  TEST_ASSERT_EQUAL(ST_IDLE, r.dev.state());
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_accel_sagittal_sign);
  RUN_TEST(test_accel_frontal_sign);
  RUN_TEST(test_accel_roll_in_bend);
  RUN_TEST(test_gyro_coupling_sagittal);
  RUN_TEST(test_gyro_coupling_frontal);
  RUN_TEST(test_gyro_coupling_roll);
  RUN_TEST(test_filter_rejects_gyro_bias_after_calibration);
  RUN_TEST(test_indicators_from_simulated_stance);
  RUN_TEST(test_triage_levels);
  RUN_TEST(test_measurement_roundtrip);
  RUN_TEST(test_command_parser);
  RUN_TEST(test_threshold_json);
  RUN_TEST(test_flow_healthy);
  RUN_TEST(test_flow_asymmetric);
  RUN_TEST(test_flow_scoliotic);
  RUN_TEST(test_flow_rounded);
  RUN_TEST(test_trial_requires_calibration);
  RUN_TEST(test_calibration_rejects_movement);
  RUN_TEST(test_trial_rejects_movement);
  RUN_TEST(test_bend_rejected_when_not_bent);
  RUN_TEST(test_disagreeing_trials_ask_for_retake);
  RUN_TEST(test_sensor_fault_aborts_trial);
  RUN_TEST(test_monitor_alerts_on_sustained_slouch);
  RUN_TEST(test_low_battery_shutdown);
  RUN_TEST(test_button);
  return UNITY_END();
}
