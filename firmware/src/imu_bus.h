// Five MPU-6050 sensors behind a TCA9548A multiplexer, read with plain register
// access (no third-party driver). Configuration follows thesis Table 3.1:
// +-2 g, +-250 deg/s, DLPF 21/20 Hz, 50 Hz sample rate.
#pragma once
#include <Arduino.h>
#include <Wire.h>
#include "hw_config.h"
#include "orientation.h"

class ImuBus {
 public:
  void begin() {
    pinMode(PIN_MUX_RST, OUTPUT);
    resetMux();
    Wire.begin(PIN_SDA, PIN_SCL, I2C_HZ);
    Wire.setTimeOut(10);
    for (int p = 0; p < 5; ++p) ok_[p] = initPod(p);
  }

  // Reads all five pods. Returns a bit mask of the pods that answered.
  uint8_t read(pt::ImuSample out[5]) {
    uint8_t mask = 0;
    for (int p = 0; p < 5; ++p) {
      if (ok_[p] && readPod(p, out[p])) { mask |= 1 << p; fails_[p] = 0; continue; }
      out[p] = pt::ImuSample{1, 0, 0, 0, 0, 0};
      if (ok_[p] && ++fails_[p] >= 3) ok_[p] = false;  // three misses in a row: re-initialise
    }
    // try to bring lost sensors back once a second
    if (mask != 0x1F && millis() - lastRetry_ > 1000) {
      lastRetry_ = millis();
      if (mask == 0) resetMux();
      for (int p = 0; p < 5; ++p) if (!ok_[p]) ok_[p] = initPod(p);
    }
    return mask;
  }

  uint8_t whoAmI(int p) { return select(p) ? readReg(0x75) : 0; }
  bool present(int p) const { return ok_[p]; }

 private:
  void resetMux() {
    digitalWrite(PIN_MUX_RST, LOW);
    delayMicroseconds(10);
    digitalWrite(PIN_MUX_RST, HIGH);
    delayMicroseconds(10);
  }

  bool select(int p) {
    Wire.beginTransmission(MUX_ADDR);
    Wire.write(1 << POD_CHANNEL[p]);
    return Wire.endTransmission() == 0;
  }

  bool writeReg(uint8_t reg, uint8_t val) {
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(reg);
    Wire.write(val);
    return Wire.endTransmission() == 0;
  }

  uint8_t readReg(uint8_t reg) {
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(reg);
    if (Wire.endTransmission(false) != 0) return 0;
    if (Wire.requestFrom((int)MPU_ADDR, 1) != 1) return 0;
    return Wire.read();
  }

  bool initPod(int p) {
    if (!select(p)) return false;
    uint8_t who = readReg(0x75);
    // genuine MPU-6050 returns 0x68; common clones return 0x70, 0x72 or 0x98
    if (who == 0x00 || who == 0xFF) return false;
    bool ok = writeReg(0x6B, 0x80);         // PWR_MGMT_1: device reset
    delay(100);
    ok = ok && writeReg(0x6B, 0x01);        // wake, clock = PLL with X gyro
    ok = ok && writeReg(0x1A, 0x04);        // CONFIG: DLPF 21 Hz accel / 20 Hz gyro
    ok = ok && writeReg(0x19, 19);          // SMPLRT_DIV: 1 kHz / (1 + 19) = 50 Hz
    ok = ok && writeReg(0x1B, 0x00);        // GYRO_CONFIG: +-250 deg/s
    ok = ok && writeReg(0x1C, 0x00);        // ACCEL_CONFIG: +-2 g
    fails_[p] = 0;
    return ok;
  }

  bool readPod(int p, pt::ImuSample& s) {
    if (!select(p)) return false;
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(0x3B);                       // ACCEL_XOUT_H .. GYRO_ZOUT_L (14 bytes)
    if (Wire.endTransmission(false) != 0) return false;
    if (Wire.requestFrom((int)MPU_ADDR, 14) != 14) return false;
    int16_t r[7];
    for (int i = 0; i < 7; ++i) r[i] = (int16_t)((Wire.read() << 8) | Wire.read());
    const float acc[3] = {r[0] / 16384.0f, r[1] / 16384.0f, r[2] / 16384.0f};  // g
    const float gyr[3] = {r[4] / 131.0f, r[5] / 131.0f, r[6] / 131.0f};        // deg/s (r[3] = temperature)
    const AxisMap& m = POD_AXES[p];
    s.ax = m.sign[0] * acc[m.axis[0]]; s.ay = m.sign[1] * acc[m.axis[1]]; s.az = m.sign[2] * acc[m.axis[2]];
    s.gx = m.sign[0] * gyr[m.axis[0]]; s.gy = m.sign[1] * gyr[m.axis[1]]; s.gz = m.sign[2] * gyr[m.axis[2]];
    return true;
  }

  bool ok_[5] = {false, false, false, false, false};
  uint8_t fails_[5] = {0, 0, 0, 0, 0};
  uint32_t lastRetry_ = 0;
};
