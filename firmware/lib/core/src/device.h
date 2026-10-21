// The device logic as a hardware-independent state machine.
//
// main.cpp feeds it one set of five IMU samples every 20 ms (50 Hz), the battery
// voltage, button events and the text commands that arrive over BLE. The Device
// answers through the DeviceIO callbacks (BLE notifications, vibration motor,
// threshold storage). Because nothing here touches the hardware, the whole flow
// is unit-tested on a PC with the virtual wearer (test/test_core).
#pragma once
#include <stdio.h>
#include <string.h>
#include <ArduinoJson.h>
#include "protocol.h"
#include "triage.h"
#include "trials.h"

namespace pt {

class DeviceIO {
 public:
  virtual ~DeviceIO() {}
  virtual void sendJson(const char* json) = 0;                     // Result characteristic
  virtual void sendMeasurement(const uint8_t* data, int len) = 0;  // Measurement characteristic
  virtual void vibrate(int pulses, int onMs) = 0;
  virtual void saveThresholds(const char* json) = 0;               // persist (NVS on the ESP32)
  virtual void onState(DevState s) { (void)s; }                    // LED, simulator pose, ...
  virtual bool simCommand(const char* arg) { (void)arg; return false; }  // "SIM ..." (simulated build only)
};

class Device {
 public:
  static constexpr int kMeasEvery = 10;        // 50 Hz / 10 = 5 Hz stream
  static constexpr int kLowBattTicks = 250;    // 5 s below the limit before shutting down

  explicit Device(DeviceIO& io) : io_(io) { th_ = defaultThresholds(); }

  void begin(bool simulated) {
    simulated_ = simulated;
    setState(ST_IDLE);
  }

  // ------------------------------------------------------------ state
  DevState state() const { return state_; }
  bool calibrated() const { return calibrated_; }
  bool simulated() const { return simulated_; }
  const Thresholds& thresholds() const { return th_; }
  const PodTilts& tilts() const { return tilts_; }
  const TrialSet& trials() const { return set_; }
  uint16_t batteryMv() const { return batMv_; }
  uint8_t sensorMask() const { return sensorMask_; }
  bool lowBatteryShutdown() const { return state_ == ST_LOW_BATTERY; }

  // ------------------------------------------------------------ 50 Hz input
  void tick(const ImuSample m[kNumPods], uint8_t sensorOkMask, uint16_t batteryMv) {
    batMv_ = batteryMv;
    sensorMask_ = sensorOkMask;
    const bool allOk = sensorOkMask == 0x1F;

    float motion = 0;
    for (int p = 0; p < kNumPods; ++p) {
      if (!(sensorOkMask & (1 << p))) continue;
      filt_[p].update(m[p]);
      tilts_.p[p] = filt_[p].tilt();
      float g = filt_[p].rateMagnitude(m[p]);
      if (g > motion) motion = g;
    }
    moving_ = motion > kMoveGyroDps;

    // battery protection (0 mV = not measured, e.g. powered from USB)
    if (batteryMv > 0 && batteryMv < (uint16_t)(kBatteryShutdownV * 1000)) {
      if (++lowBatt_ >= kLowBattTicks && state_ != ST_LOW_BATTERY) {
        setState(ST_LOW_BATTERY);
        sendErr("low_battery");
      }
    } else {
      lowBatt_ = 0;
    }

    switch (state_) {
      case ST_CALIBRATING:
        if (!allOk) { finishCal(false, "sensor", firstMissing()); break; }
        lastRaw_[0] = m[0]; for (int p = 0; p < kNumPods; ++p) lastRaw_[p] = m[p];
        if (cal_.add(m)) {
          int moved = cal_.movingPod();
          finishCal(moved < 0, "moved", moved);
        }
        break;
      case ST_STAND:
      case ST_BEND: {
        if (!allOk) { abortTrial(FAIL_SENSOR); break; }
        bool done = rec_.add(tilts_, motion);
        if (++progTick_ >= (int)kSampleHz && !done) {
          progTick_ = 0;
          char b[96];
          snprintf(b, sizeof b, "{\"t\":\"progress\",\"kind\":\"%s\",\"sec\":%d,\"of\":%d}",
                   state_ == ST_STAND ? "stand" : "bend", (int)(rec_.seconds() + 0.5f), (int)rec_.duration());
          io_.sendJson(b);
        }
        if (done) finishTrial();
        break;
      }
      case ST_MONITOR: {
        if (!allOk) break;
        float v[IND_COUNT];
        liveIndicators(tilts_, v);
        int fired = mon_.add(v, th_);
        if (fired >= 0) {
          io_.vibrate(3, 400);
          char b[80];
          snprintf(b, sizeof b, "{\"t\":\"alert\",\"ind\":\"%s\",\"v\":%.1f}", kIndKey[fired], v[fired]);
          io_.sendJson(b);
        }
        break;
      }
      default:
        break;
    }

    if (++measTick_ >= kMeasEvery) {
      measTick_ = 0;
      sendMeasurement();
    }
  }

  // ------------------------------------------------------------ button
  void buttonShort() {  // toggle monitoring
    if (state_ == ST_MONITOR) command("STOP");
    else if (state_ == ST_IDLE) command("MONITOR");
  }
  void buttonLong() {   // calibrate
    if (state_ == ST_IDLE || state_ == ST_MONITOR) command("CAL");
  }

  // ------------------------------------------------------------ commands
  void command(const char* text) {
    ParsedCmd c = parseCommand(text);
    if (state_ == ST_LOW_BATTERY && c.cmd != CMD_STATUS && c.cmd != CMD_PING) { sendErr("low_battery"); return; }
    switch (c.cmd) {
      case CMD_PING: io_.sendJson("{\"t\":\"pong\"}"); break;
      case CMD_STATUS: sendStatus(); break;
      case CMD_CAL:
        if (busy()) { sendErr("busy"); break; }
        cal_.start();
        setState(ST_CALIBRATING);
        break;
      case CMD_STAND:
      case CMD_BEND:
        if (busy()) { sendErr("busy"); break; }
        if (!calibrated_) { sendErr("not_calibrated"); break; }
        rec_.start(c.cmd == CMD_STAND ? TRIAL_STAND : TRIAL_BEND);
        progTick_ = 0;
        setState(c.cmd == CMD_STAND ? ST_STAND : ST_BEND);
        break;
      case CMD_RESULT: sendResult(); break;
      case CMD_CLEAR:
        if (state_ == ST_STAND || state_ == ST_BEND) abortTrial(FAIL_ABORTED);
        set_.clear();
        sendStatus();
        break;
      case CMD_MONITOR:
        if (busy()) { sendErr("busy"); break; }
        if (!calibrated_) { sendErr("not_calibrated"); break; }
        mon_.start();
        setState(ST_MONITOR);
        break;
      case CMD_STOP:
        if (state_ == ST_STAND || state_ == ST_BEND) abortTrial(FAIL_ABORTED);
        else if (state_ == ST_MONITOR || state_ == ST_CALIBRATING) setState(ST_IDLE);
        sendStatus();
        break;
      case CMD_THR:
        if (loadThresholdsJson(c.arg)) {
          char b[400];
          thresholdsJson(b, sizeof b, false);
          io_.saveThresholds(b);
          sendThresholds();
        } else {
          sendErr("bad_thresholds");
        }
        break;
      case CMD_GETTHR: sendThresholds(); break;
      case CMD_SIM:
        if (!simulated_ || !io_.simCommand(c.arg)) sendErr("sim_unavailable");
        else sendStatus();
        break;
      default: sendErr("unknown_command"); break;
    }
  }

  // ------------------------------------------------------------ thresholds JSON
  // Format: {"K":[mu,mon,ref], "L":[...], ..., "provisional":false}. Keys may be omitted.
  bool loadThresholdsJson(const char* json) {
    JsonDocument doc;
    if (deserializeJson(doc, json)) return false;
    if (!doc.is<JsonObject>()) return false;
    Thresholds t = th_;
    bool any = false;
    for (int i = 0; i < IND_COUNT; ++i) {
      JsonArray a = doc[kIndKey[i]];
      if (a.isNull()) continue;
      if (a.size() != 3) return false;
      t.lim[i] = {a[0].as<float>(), a[1].as<float>(), a[2].as<float>()};
      any = true;
    }
    if (!any) return false;
    t.provisional = doc["provisional"] | false;
    if (!validThresholds(t)) return false;
    th_ = t;
    return true;
  }

  int thresholdsJson(char* b, size_t n, bool withType) const {
    int k = snprintf(b, n, "{%s\"provisional\":%s", withType ? "\"t\":\"thr\"," : "", th_.provisional ? "true" : "false");
    for (int i = 0; i < IND_COUNT && k < (int)n; ++i)
      k += snprintf(b + k, n - k, ",\"%s\":[%.2f,%.2f,%.2f]", kIndKey[i], th_.lim[i].mu, th_.lim[i].mon, th_.lim[i].ref);
    if (k < (int)n) k += snprintf(b + k, n - k, "}");
    return k;
  }

 private:
  bool busy() const { return state_ == ST_CALIBRATING || state_ == ST_STAND || state_ == ST_BEND; }

  void setState(DevState s) {
    state_ = s;
    io_.onState(s);
    if (s != ST_STAND && s != ST_BEND) sendStatus();
  }

  int firstMissing() const {
    for (int p = 0; p < kNumPods; ++p) if (!(sensorMask_ & (1 << p))) return p;
    return -1;
  }

  void finishCal(bool ok, const char* why, int pod) {
    char b[96];
    if (ok) {
      for (int p = 0; p < kNumPods; ++p) {
        filt_[p].setBias(cal_.bias(p, 0), cal_.bias(p, 1), cal_.bias(p, 2));
        filt_[p].reset(lastRaw_[p]);
        tilts_.p[p] = filt_[p].tilt();
      }
      calibrated_ = true;
      snprintf(b, sizeof b, "{\"t\":\"cal\",\"ok\":true}");
      io_.vibrate(1, 150);
    } else {
      snprintf(b, sizeof b, "{\"t\":\"cal\",\"ok\":false,\"why\":\"%s\",\"pod\":%d}", why, pod + 1);
      io_.vibrate(3, 120);
    }
    io_.sendJson(b);
    setState(ST_IDLE);
  }

  void abortTrial(TrialFail why) {
    char b[96];
    snprintf(b, sizeof b, "{\"t\":\"trial\",\"kind\":\"%s\",\"ok\":false,\"why\":\"%s\"}",
             rec_.kind() == TRIAL_STAND ? "stand" : "bend", kFailKey[why]);
    io_.sendJson(b);
    io_.vibrate(3, 120);
    setState(ST_IDLE);
  }

  static void fmtNum(char* b, size_t n, float v) {
    if (v == v) snprintf(b, n, "%.2f", v); else snprintf(b, n, "null");
  }

  void finishTrial() {
    TrialSummary t = rec_.summary();
    set_.add(t);
    lastTrial_ = t;
    char b[480], num[16];
    const bool stand = t.kind == TRIAL_STAND;
    int k = snprintf(b, sizeof b, "{\"t\":\"trial\",\"kind\":\"%s\",\"ok\":%s,\"why\":\"%s\",\"n\":%d,\"ind\":{",
                     stand ? "stand" : "bend", t.ok ? "true" : "false", kFailKey[t.why],
                     stand ? set_.standCount() : set_.bendCount());
    bool first = true;
    for (int i = 0; i < IND_COUNT; ++i) {
      if (isStandIndicator(i) != stand) continue;
      fmtNum(num, sizeof num, t.ind[i]);
      k += snprintf(b + k, sizeof b - k, "%s\"%s\":%s", first ? "" : ",", kIndKey[i], num);
      first = false;
    }
    // pod means: s and f for the stand, s and r for the bend
    const char* keys[2] = {"s", stand ? "f" : "r"};
    k += snprintf(b + k, sizeof b - k, "},\"pods\":{");
    for (int j = 0; j < 2; ++j) {
      k += snprintf(b + k, sizeof b - k, "%s\"%s\":[", j ? "," : "", keys[j]);
      for (int p = 0; p < kNumPods; ++p) {
        const Tilt& q = t.mean.p[p];
        float v = j == 0 ? q.s : (stand ? q.f : q.r);
        fmtNum(num, sizeof num, v);
        k += snprintf(b + k, sizeof b - k, "%s%s", p ? "," : "", num);
      }
      k += snprintf(b + k, sizeof b - k, "]");
    }
    snprintf(b + k, sizeof b - k, "}}");
    io_.sendJson(b);
    io_.vibrate(t.ok ? 1 : 3, t.ok ? 200 : 120);
    setState(ST_IDLE);
  }

  void sendResult() {
    Assessment a = set_.assess(th_);
    char b[480], num[16], rng[16];
    int k = snprintf(b, sizeof b,
                     "{\"t\":\"result\",\"complete\":%s,\"agree\":%s,\"risk\":%s%s%s,\"stand\":%d,\"bend\":%d,"
                     "\"retake\":[%s%s%s],\"provisional\":%s,\"ind\":{",
                     a.complete ? "true" : "false", a.agree ? "true" : "false",
                     a.risk == RISK_NONE ? "" : "\"", a.risk == RISK_NONE ? "null" : kRiskKey[a.risk],
                     a.risk == RISK_NONE ? "" : "\"", set_.standCount(), set_.bendCount(),
                     a.retakeStand ? "\"stand\"" : "", a.retakeStand && a.retakeBend ? "," : "",
                     a.retakeBend ? "\"bend\"" : "", th_.provisional ? "true" : "false");
    for (int i = 0; i < IND_COUNT; ++i) {
      const IndicatorResult& r = a.ind[i];
      fmtNum(num, sizeof num, r.value);
      fmtNum(rng, sizeof rng, r.range);
      char lvl[16];
      if (r.level == RISK_NONE) snprintf(lvl, sizeof lvl, "null"); else snprintf(lvl, sizeof lvl, "\"%s\"", kRiskKey[r.level]);
      k += snprintf(b + k, sizeof b - k, "%s\"%s\":[%s,%s,%s]", i ? "," : "", kIndKey[i], num, rng, lvl);
    }
    snprintf(b + k, sizeof b - k, "}}");
    io_.sendJson(b);
  }

  void sendStatus() {
    char b[256];
    snprintf(b, sizeof b,
             "{\"t\":\"status\",\"state\":\"%s\",\"cal\":%s,\"bat\":%.2f,\"sim\":%s,\"fw\":\"%s\","
             "\"stand\":%d,\"bend\":%d,\"provisional\":%s,\"sensors\":[%d,%d,%d,%d,%d]}",
             kStateKey[state_], calibrated_ ? "true" : "false", batMv_ / 1000.0f, simulated_ ? "true" : "false",
             PT_FW_VERSION, set_.standCount(), set_.bendCount(), th_.provisional ? "true" : "false",
             (sensorMask_ >> 0) & 1, (sensorMask_ >> 1) & 1, (sensorMask_ >> 2) & 1, (sensorMask_ >> 3) & 1,
             (sensorMask_ >> 4) & 1);
    io_.sendJson(b);
  }

  void sendThresholds() {
    char b[400];
    thresholdsJson(b, sizeof b, true);
    io_.sendJson(b);
  }

  void sendErr(const char* msg) {
    char b[96];
    snprintf(b, sizeof b, "{\"t\":\"err\",\"msg\":\"%s\"}", msg);
    io_.sendJson(b);
  }

  void sendMeasurement() {
    Measurement m;
    m.state = state_;
    m.seq = seq_++;
    m.tilt = tilts_;
    liveIndicators(tilts_, m.ind);
    m.batteryMv = batMv_;
    m.flags = (moving_ ? MF_MOVING : 0) | (calibrated_ ? MF_CALIBRATED : 0) |
              (batMv_ > 0 && batMv_ < (uint16_t)(kBatteryWarnV * 1000) ? MF_LOW_BATTERY : 0) |
              (simulated_ ? MF_SIMULATED : 0) | (sensorMask_ != 0x1F ? MF_SENSOR_FAULT : 0);
    uint8_t buf[kMeasLen];
    packMeasurement(m, buf);
    io_.sendMeasurement(buf, kMeasLen);
  }

  DeviceIO& io_;
  DevState state_ = ST_IDLE;
  Thresholds th_;
  TiltFilter filt_[kNumPods];
  PodTilts tilts_;
  ImuSample lastRaw_[kNumPods];
  Calibrator cal_;
  TrialRecorder rec_;
  TrialSet set_;
  TrialSummary lastTrial_;
  PostureMonitor mon_;
  bool calibrated_ = false, simulated_ = false, moving_ = false;
  uint8_t sensorMask_ = 0x1F;
  uint16_t batMv_ = 0, seq_ = 0;
  int measTick_ = 0, progTick_ = 0, lowBatt_ = 0;
};

}  // namespace pt
