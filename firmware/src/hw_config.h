// Pin map and sensor mounting for the carrier board Rev B (see docs/HARDWARE.md).
#pragma once
#include <stdint.h>

// ---- I2C bus and multiplexer
constexpr int PIN_SDA = 21;
constexpr int PIN_SCL = 22;
constexpr int PIN_MUX_RST = 23;        // TCA9548A RST, active low
constexpr uint32_t I2C_HZ = 400000;
constexpr uint8_t MUX_ADDR = 0x70;     // A0..A2 = GND
constexpr uint8_t MPU_ADDR = 0x68;     // AD0 = GND on every GY-521

// IMU1..IMU5 are on multiplexer channels 0..4 (connectors J1..J5)
constexpr uint8_t POD_CHANNEL[5] = {0, 1, 2, 3, 4};

// ---- feedback and input
constexpr int PIN_MOTOR = 25;          // R3 -> Q1 base, R4 pull-down
constexpr int PIN_LED = 26;            // status LED via R5
constexpr int PIN_BUTTON = 27;         // SW2 to GND, internal pull-up, C3 debounce
constexpr int PIN_BAT_SENSE = 34;      // R1/R2 divider: VBAT / 2

constexpr float BAT_DIVIDER = 2.0f;    // VBAT = ADC * BAT_DIVIDER * BAT_TRIM
constexpr float BAT_TRIM = 1.00f;      // adjust after measuring VBAT with a multimeter

// ---- sensor mounting
// The firmware expects every pod in this frame:
//   X along the spine toward the head, Z out of the back (chip side out), Y to the wearer's left.
// If a GY-521 is mounted differently, describe here which chip axis gives each pod axis.
// axis: 0 = chip X, 1 = chip Y, 2 = chip Z;  sign: +1 or -1.
// Check with the serial command "RAW": standing upright, every pod should show ax ~ +1 g;
// lying face down, az ~ +1 g; lying on the right side, ay ~ +1 g.
struct AxisMap {
  uint8_t axis[3];
  int8_t sign[3];
};
constexpr AxisMap POD_AXES[5] = {
    {{0, 1, 2}, {+1, +1, +1}},  // IMU1 C7-T1
    {{0, 1, 2}, {+1, +1, +1}},  // IMU2 T12-L1
    {{0, 1, 2}, {+1, +1, +1}},  // IMU3 L3-L4
    {{0, 1, 2}, {+1, +1, +1}},  // IMU4 left scapula
    {{0, 1, 2}, {+1, +1, +1}},  // IMU5 right scapula
};
