// BLE protocol shared by the firmware and the app (see docs/BLE_PROTOCOL.md).
//
// One GATT service, three characteristics (thesis Section 3.2.6.4):
//   Measurement  notify, 5 Hz, packed binary (below)
//   Result       read + notify, UTF-8 JSON messages with a "t" (type) field
//   Command      write, UTF-8 text command
#pragma once
#include <stdint.h>
#include <string.h>
#include <math.h>
#include "indicators.h"

namespace pt {

#define PT_SERVICE_UUID     "7a1e0001-5c3b-4f2a-9d7e-2b8c4a6f1d00"
#define PT_MEASUREMENT_UUID "7a1e0002-5c3b-4f2a-9d7e-2b8c4a6f1d00"
#define PT_RESULT_UUID      "7a1e0003-5c3b-4f2a-9d7e-2b8c4a6f1d00"
#define PT_COMMAND_UUID     "7a1e0004-5c3b-4f2a-9d7e-2b8c4a6f1d00"
#define PT_DEVICE_NAME      "PostureTriage"
#define PT_FW_VERSION       "1.0.0"

enum DevState : uint8_t {
  ST_IDLE = 0, ST_CALIBRATING = 1, ST_STAND = 2, ST_BEND = 3, ST_MONITOR = 4, ST_ERROR = 5, ST_LOW_BATTERY = 6
};
static const char* const kStateKey[] = {"idle", "calibrating", "stand", "bend", "monitor", "error", "low_battery"};

enum MeasFlag : uint8_t {
  MF_MOVING = 1 << 0, MF_CALIBRATED = 1 << 1, MF_LOW_BATTERY = 1 << 2, MF_SIMULATED = 1 << 3, MF_SENSOR_FAULT = 1 << 4
};

// Measurement packet, version 1, little-endian, 49 bytes:
//   0  u8   version (=1)
//   1  u8   state (DevState)
//   2  u16  sequence number
//   4  i16  s[5]   sagittal tilt per pod, centi-degrees
//  14  i16  f[5]   frontal tilt per pod, centi-degrees
//  24  i16  r[5]   surface roll per pod, centi-degrees
//  34  i16  ind[6] K, L, N, F, S, R (live), centi-degrees
//  46  u16  battery, millivolts
//  48  u8   flags (MeasFlag)
// Needs an ATT MTU of at least 52; the app requests 247.
constexpr int kMeasLen = 49;

struct Measurement {
  uint8_t state;
  uint16_t seq;
  PodTilts tilt;
  float ind[IND_COUNT];
  uint16_t batteryMv;
  uint8_t flags;
};

inline int16_t toCenti(float deg) {
  if (!(deg == deg)) return INT16_MIN;  // NaN -> sentinel
  float c = roundf(deg * 100.0f);
  if (c > 32767.f) c = 32767.f;
  if (c < -32767.f) c = -32767.f;
  return (int16_t)c;
}
inline float fromCenti(int16_t c) { return c == INT16_MIN ? NAN : c / 100.0f; }

inline void put16(uint8_t* b, int o, uint16_t v) { b[o] = v & 0xFF; b[o + 1] = v >> 8; }
inline uint16_t get16(const uint8_t* b, int o) { return (uint16_t)(b[o] | (b[o + 1] << 8)); }

inline void packMeasurement(const Measurement& m, uint8_t out[kMeasLen]) {
  out[0] = 1;
  out[1] = m.state;
  put16(out, 2, m.seq);
  for (int p = 0; p < kNumPods; ++p) {
    put16(out, 4 + 2 * p, (uint16_t)toCenti(m.tilt.p[p].s));
    put16(out, 14 + 2 * p, (uint16_t)toCenti(m.tilt.p[p].f));
    put16(out, 24 + 2 * p, (uint16_t)toCenti(m.tilt.p[p].r));
  }
  for (int i = 0; i < IND_COUNT; ++i) put16(out, 34 + 2 * i, (uint16_t)toCenti(m.ind[i]));
  put16(out, 46, m.batteryMv);
  out[48] = m.flags;
}

inline bool unpackMeasurement(const uint8_t* b, int len, Measurement& m) {
  if (len < kMeasLen || b[0] != 1) return false;
  m.state = b[1];
  m.seq = get16(b, 2);
  for (int p = 0; p < kNumPods; ++p) {
    m.tilt.p[p].s = fromCenti((int16_t)get16(b, 4 + 2 * p));
    m.tilt.p[p].f = fromCenti((int16_t)get16(b, 14 + 2 * p));
    m.tilt.p[p].r = fromCenti((int16_t)get16(b, 24 + 2 * p));
  }
  for (int i = 0; i < IND_COUNT; ++i) m.ind[i] = fromCenti((int16_t)get16(b, 34 + 2 * i));
  m.batteryMv = get16(b, 46);
  m.flags = b[48];
  return true;
}

// ---------------------------------------------------------------- commands
enum Cmd : uint8_t {
  CMD_UNKNOWN = 0, CMD_PING, CMD_STATUS, CMD_CAL, CMD_STAND, CMD_BEND, CMD_RESULT, CMD_CLEAR,
  CMD_MONITOR, CMD_STOP, CMD_THR, CMD_GETTHR, CMD_SIM
};

struct ParsedCmd {
  Cmd cmd;
  const char* arg;  // points into the input buffer (rest of the line after the keyword), "" if none
};

inline ParsedCmd parseCommand(const char* s) {
  static const struct { const char* kw; Cmd c; } table[] = {
      {"PING", CMD_PING}, {"STATUS", CMD_STATUS}, {"CAL", CMD_CAL}, {"STAND", CMD_STAND},
      {"BEND", CMD_BEND}, {"RESULT", CMD_RESULT}, {"CLEAR", CMD_CLEAR}, {"MONITOR", CMD_MONITOR},
      {"STOP", CMD_STOP}, {"THR", CMD_THR}, {"GETTHR", CMD_GETTHR}, {"SIM", CMD_SIM}};
  while (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n') ++s;
  for (const auto& e : table) {
    size_t n = strlen(e.kw);
    if (strncmp(s, e.kw, n) == 0 && (s[n] == 0 || s[n] == ' ' || s[n] == '\r' || s[n] == '\n')) {
      const char* a = s + n;
      while (*a == ' ') ++a;
      return {e.c, a};
    }
  }
  return {CMD_UNKNOWN, s};
}

}  // namespace pt
