// Posture-triage control unit: ESP32 DOIT DevKit V1 on carrier board Rev B.
//
// Every 20 ms: read the five IMUs (or the virtual wearer in the SIMULATE build),
// pass them to pt::Device, and forward its messages to BLE and the serial port.
// Commands are accepted from BLE and, for bench testing, from the serial monitor
// (type e.g. CAL, STAND, RESULT, or RAW to print raw sensor values).
#include <Arduino.h>
#include <Preferences.h>
#include <esp_sleep.h>
#include "ble_link.h"
#include "device.h"
#include "hw_config.h"
#include "imu_bus.h"
#ifdef PT_SIMULATE
#include "sim_driver.h"
#endif

static BleLink ble;
static Preferences prefs;
#ifdef PT_SIMULATE
static pt::SimDriver simDriver;
#else
static ImuBus imus;
#endif

// ---------------------------------------------------------------- feedback
class Feedback {
 public:
  void begin() {
    pinMode(PIN_MOTOR, OUTPUT); digitalWrite(PIN_MOTOR, LOW);
    pinMode(PIN_LED, OUTPUT); digitalWrite(PIN_LED, LOW);
  }
  void vibrate(int pulses, int onMs) { pulses_ = pulses; onMs_ = onMs; on_ = false; nextToggle_ = millis(); }
  void update(pt::DevState st, bool connected, bool fault) {
    uint32_t now = millis();
    // motor pulse train: on for onMs_, then off for 150 ms
    if (pulses_ > 0 && (int32_t)(now - nextToggle_) >= 0) {
      on_ = !on_;
      digitalWrite(PIN_MOTOR, on_ ? HIGH : LOW);
      if (on_) nextToggle_ = now + onMs_;
      else { nextToggle_ = now + 150; --pulses_; }
    }
    // LED pattern
    bool led;
    uint32_t t = now % 2000;
    if (st == pt::ST_LOW_BATTERY) led = (now / 125) % 2;
    else if (fault) led = t < 900 && (t / 150) % 2 == 0;                          // triple blink
    else if (st == pt::ST_CALIBRATING || st == pt::ST_STAND || st == pt::ST_BEND) led = (now / 250) % 2;
    else if (st == pt::ST_MONITOR) led = t < 100 || (t > 250 && t < 350);           // double blink
    else if (connected) led = true;
    else led = t < 1000;                                                           // advertising
    digitalWrite(PIN_LED, led);
  }
  void off() { digitalWrite(PIN_MOTOR, LOW); digitalWrite(PIN_LED, LOW); pulses_ = 0; }

 private:
  int pulses_ = 0, onMs_ = 0;
  uint32_t nextToggle_ = 0;
  bool on_ = false;
};
static Feedback fb;

// ---------------------------------------------------------------- device IO
class HwIO : public pt::DeviceIO {
 public:
  void sendJson(const char* json) override {
    ble.sendJson(json);
    Serial.println(json);
  }
  void sendMeasurement(const uint8_t* data, int len) override { ble.sendMeasurement(data, len); }
  void vibrate(int pulses, int onMs) override { fb.vibrate(pulses, onMs); }
  void saveThresholds(const char* json) override { prefs.putString("thr", json); }
  void onState(pt::DevState s) override {
#ifdef PT_SIMULATE
    simDriver.onState(s);
#endif
  }
  bool simCommand(const char* arg) override {
#ifdef PT_SIMULATE
    return simDriver.command(arg);
#else
    return false;
#endif
  }
};
static HwIO io;
static pt::Device dev(io);

// ---------------------------------------------------------------- battery
static float batFiltered = 0;
static uint16_t readBatteryMv() {
#ifdef PT_SIMULATE
  return 3950;
#else
  uint32_t sum = 0;
  for (int i = 0; i < 8; ++i) sum += analogReadMilliVolts(PIN_BAT_SENSE);
  float v = sum / 8.0f * BAT_DIVIDER * BAT_TRIM;
  batFiltered = batFiltered == 0 ? v : batFiltered + 0.02f * (v - batFiltered);
  return batFiltered < 2500 ? 0 : (uint16_t)batFiltered;   // < 2.5 V: no battery (USB power)
#endif
}

// ---------------------------------------------------------------- button
static uint32_t btnDown = 0;
static bool btnLongSent = false;
static void pollButton() {
  bool down = digitalRead(PIN_BUTTON) == LOW;
  uint32_t now = millis();
  if (down && btnDown == 0) { btnDown = now; btnLongSent = false; }
  if (down && btnDown && !btnLongSent && now - btnDown >= 2000) { btnLongSent = true; dev.buttonLong(); }
  if (!down && btnDown) {
    uint32_t held = now - btnDown;
    if (!btnLongSent && held >= 40 && held < 1000) dev.buttonShort();
    btnDown = 0;
  }
}

// ---------------------------------------------------------------- serial commands
static bool rawPrint = false;
static void pollSerial() {
  static char line[BleLink::kCmdMax];
  static int n = 0;
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\r') continue;
    if (c != '\n' && n < (int)sizeof line - 1) { line[n++] = c; continue; }
    line[n] = 0; n = 0;
    if (!strcmp(line, "RAW")) { rawPrint = !rawPrint; continue; }
#ifndef PT_SIMULATE
    if (!strcmp(line, "WHO")) {
      for (int p = 0; p < 5; ++p) Serial.printf("IMU%d WHO_AM_I=0x%02X %s\n", p + 1, imus.whoAmI(p), imus.present(p) ? "ok" : "missing");
      continue;
    }
#endif
    if (line[0]) dev.command(line);
  }
}

static void shutdownLowBattery() {
  Serial.println("{\"t\":\"err\",\"msg\":\"shutdown\"}");
  fb.off();
  delay(200);
  esp_sleep_enable_ext0_wakeup((gpio_num_t)PIN_BUTTON, 0);  // press the button to wake
  esp_deep_sleep_start();
}

// ---------------------------------------------------------------- setup / loop
void setup() {
  Serial.begin(115200);
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  analogSetPinAttenuation(PIN_BAT_SENSE, ADC_11db);
  fb.begin();
  prefs.begin("pt", false);
#ifdef PT_SIMULATE
  Serial.println("PostureTriage firmware " PT_FW_VERSION " (SIMULATED sensors)");
#else
  Serial.println("PostureTriage firmware " PT_FW_VERSION);
  imus.begin();
  for (int p = 0; p < 5; ++p) Serial.printf("IMU%d %s\n", p + 1, imus.present(p) ? "found" : "MISSING");
#endif
  String thr = prefs.getString("thr", "");
  if (thr.length() && dev.loadThresholdsJson(thr.c_str())) Serial.println("Thresholds loaded from flash");
  else Serial.println("Using provisional thresholds");
  ble.begin();
  dev.begin(
#ifdef PT_SIMULATE
      true
#else
      false
#endif
  );
}

void loop() {
  static uint32_t next = micros();
  static uint32_t rawTick = 0;
  char cmd[BleLink::kCmdMax];
  while (ble.nextCommand(cmd)) dev.command(cmd);
  pollSerial();
  pollButton();

  if ((int32_t)(micros() - next) >= 0) {
    next += 20000;                                   // 50 Hz
    if ((int32_t)(micros() - next) > 100000) next = micros() + 20000;  // fell behind: resync
    pt::ImuSample m[5];
    uint8_t mask;
#ifdef PT_SIMULATE
    simDriver.sim.step(m);
    mask = 0x1F;
#else
    mask = imus.read(m);
#endif
    dev.tick(m, mask, readBatteryMv());
    if (rawPrint && ++rawTick % 25 == 0) {
      for (int p = 0; p < 5; ++p)
        Serial.printf("IMU%d a=%+.2f %+.2f %+.2f g=%+6.1f %+6.1f %+6.1f | s=%+6.1f f=%+6.1f r=%+6.1f\n", p + 1,
                      m[p].ax, m[p].ay, m[p].az, m[p].gx, m[p].gy, m[p].gz,
                      dev.tilts().p[p].s, dev.tilts().p[p].f, dev.tilts().p[p].r);
    }
    if (dev.lowBatteryShutdown()) shutdownLowBattery();
  }
  fb.update(dev.state(), ble.connected(), dev.sensorMask() != 0x1F);
}
