# Posture triage: project guide for Claude Code

Thesis: "A Sensor-Based System for Posture Assessment and Early Back-Health Risk Triage" by
Joshua Bolambao, Chris Paolo Caral and Cirs Joy Inso (Cebu, Philippines). The methodology is in
Chapter 3; this repository is the software product described there.

## What is in this repository

| Folder | What it is | Build / test |
|---|---|---|
| `firmware/` | ESP32 firmware (PlatformIO, Arduino framework) | `pio test -e native`, `pio run -e esp32`, `pio run -e esp32-sim` |
| `app/` | Flutter app for Android and iOS (the browser build is for demos); iPhone install: `docs/IOS.md` | `flutter analyze`, `flutter test`, `flutter run` |
| `skeleton/` | The live skeleton twin (BodyParts3D anatomy, three.js) — the centre of the app | see `skeleton/README.md` |
| `mascot/` | Buko, the 3D mascot (secondary: greeting and result reactions; to be improved) | `python build_buko.py`, then `cd web && node build.mjs` |
| `analysis/` | Python statistics toolkit for the evaluation | `pytest`, `python -m ptanalysis ...` |
| `docs/` | BLE protocol, setup guide, hardware notes | |

## Ground rules

- **The firmware core is the single source of truth** for angle maths, indicators, the triage rule
  and the protocol: `firmware/lib/core/src/*.h`. It has no Arduino dependency and is unit-tested
  on the PC. `app/lib/core/` and `analysis/ptanalysis/thresholds.py` mirror parts of it. If you
  change a rule, change all three and their tests.
- Keep the simulator independent of the formulas it tests (`simulator.h` builds rotation
  matrices; it must never call `accelTilt`).
- No names of participants anywhere: participant codes only (P001...).
- Thesis references must be real, IEEE style, from 2022–2026, and not on Beall's list.
- In the UI: plain words a participant understands, sentence case, no all-caps labels.

## Hardware (carrier board Rev B)

ESP32 DOIT DevKit V1 + Adafruit TCA9548A + five GY-521 (MPU-6050) pods, MT3608 boost to 5 V.

| Signal | GPIO |
|---|---|
| I²C SDA / SCL | 21 / 22 (400 kHz) |
| TCA9548A RST (active low) | 23 |
| Vibration motor (R3 → Q1) | 25 |
| Status LED (R5) | 26 |
| Button SW2 to GND | 27 |
| Battery sense (VBAT/2) | 34 |

Multiplexer 0x70, every MPU-6050 at 0x68. Pods IMU1..IMU5 are on channels 0..4 (J1..J5;
Jn pin 1 3V3, 2 GND, 3 SCL, 4 SDA).

| Pod | Site | Used for |
|---|---|---|
| IMU1 | C7–T1 | neck-base tilt, upper-back rounding |
| IMU2 | T12–L1 | rounding, lower-back curve, trunk lean, rotation in the bend |
| IMU3 | L3–L4 | lower-back curve |
| IMU4 / IMU5 | left / right scapula | shoulder tilt, rotation in the bend |

## Angle conventions (verified by `firmware/test/test_core`)

Pod axes: X up the spine (toward the head), Z out of the back (chip side out), Y = Z × X (wearer's left).
If a GY-521 is mounted differently, fix it in `firmware/src/hw_config.h` (`POD_AXES`); it must be a proper rotation.

| Angle | Formula | Positive means | Gyro |
|---|---|---|---|
| θs sagittal | atan2(az, ax) | top tilted forward | dθs/dt = +gy |
| θf frontal | atan2(ay, ax), defined when \|(ax, ay)\| ≥ 0.5 g | top tilted to the wearer's right | dθf/dt = −gz |
| θr roll (forward bend) | atan2(ay, az), defined when \|(ay, az)\| ≥ 0.5 g | left side higher | dθr/dt = +gx |

Complementary filter α = 0.98 at 50 Hz (τ ≈ 1 s). Undefined angles are NaN and restart from the
accelerometer when they become defined again.

## Indicators and triage

| Key | Indicator | Formula | Trial |
|---|---|---|---|
| K | Upper-back rounding | θs1 − θs2 | standing |
| L | Lower-back curve | θs2 − θs3 | standing |
| N | Neck-base tilt | θs1 | standing |
| F | Trunk lean | θf2 | standing |
| S | Shoulder tilt | (θf4 + θf5)/2 | standing |
| R | Trunk rotation | max(\|(θr4 + θr5)/2\|, \|θr2\|) | forward bend |

Each indicator has `[mu, mon, ref]`: healthy if |v − mu| < mon, monitor if < ref, else refer.
The overall result is the worst indicator. mon/ref = 1.5σ / 2σ of the healthy development-set
participants (`python -m ptanalysis thresholds`); R is fixed at 3° / 5°. Until real thresholds are
loaded, the firmware uses provisional ones and every result says so.

Protocol: calibrate (3 s still, gyro SD ≤ 0.5 °/s), three standing trials (30 s, mean of 5–25 s),
three forward-bend trials (5 s, mean of 1–5 s). A trial fails if motion > 5 °/s lasts > 1 s, if the
wearer is not upright (|θs2| > 40°) or not bent (θs2 < 45°). The three trials must agree within 3°,
otherwise the app asks for one more trial. Monitoring vibrates after 10 s outside the monitor limit
(K, N, F, S) with a 30 s cooldown. Shutdown below 3.30 V for 5 s.

## BLE

See `docs/BLE_PROTOCOL.md`. One service, three characteristics: Measurement (notify, 49-byte
binary, 5 Hz), Result (read/notify, JSON messages with a "t" field), Command (write, text).

## Simulation (no hardware yet)

- `pio run -e esp32-sim -t upload`: a bare ESP32 runs the full firmware with a virtual wearer.
  `SIM PROFILE healthy|rounded|asymmetric|scoliotic`, `SIM POSE stand|bend|slouch|auto`,
  `SIM FIDGET on|off`. The serial monitor accepts the same commands as BLE.
- The app's "Try demo" (Home tab, or Settings → Demo) runs a protocol-level demo harness in Dart.
- `python -m ptanalysis synth` writes invented data in the study's file formats.

## Live skeleton twin (the main visual)

`skeleton/` builds an anatomical skeleton from BodyParts3D (CC BY-SA 2.1 JP: keep the credit
shown under it in the app) with one node per vertebra, and `skeleton/web/src/skeleton.js` poses it
every frame from the measurement stream: the measured tilt at C7/T12/L3 is spread along the spine,
the change from the reference posture is applied on top of the real anatomy, numbered pods with
leader lines show each sensor's live angles, and a region turns amber/red only past its limit.
In the app: `lib/twin/live_skeleton.dart` (widget), shown on the Sensors tab, during every
assessment step and on the result screen. Rebuild after changes:
`cd skeleton/web && node build.mjs` → `app/assets/skeleton/skeleton.html`.

## App structure

`lib/ui/shell.dart` holds four tabs in a bottom menu: **Home** (harness status, Buko, Start
assessment, Live monitor / Calibrate or Try demo, recent result, tips), **Progress** (score chart,
history, per-area insights), **Sensors** (live skeleton, pod readings, slouch alerts) and
**Settings** (device, thresholds, data export, demo, credits). Connecting is a bottom sheet
(`connect_sheet.dart`). The assessment is one guided screen (`assessment_screen.dart`) that ends on
`result_screen.dart`. Hidden tabs pause their 3D scenes (`active` → `setPaused`).

Posture score (`lib/core/score.dart`) is a display summary only, never the triage: each indicator
scores 100 at its mean, 75 at the monitor limit, 50 at the refer limit; the mean of the six is
mapped into the band of the triage level (healthy 80–100, monitor 50–79, refer 0–49), so the
score can never contradict the triage result. Keep UI copy short: one-line hints, no paragraphs.

## Mascot

Buko is secondary (greets on Home, reacts on the result screen) and is due for improvement. It is
a small spine character: stacked vertebra blocks with blue discs, a vertebra-shaped head and the
study harness (straps, belt, pod) on its back. A Blender-built, skinned 3D character (`mascot/build_buko.py` → `buko.glb`) rendered by
three.js (`mascot/web/src/buko.js`), bundled into one offline HTML file
(`app/assets/mascot/buko.html`). The app talks to it with `buko.setMode()`, `buko.setLive()` and
`buko.setReduceMotion()`. After changing the model or viewer, rebuild the HTML:
`cd mascot && python build_buko.py && cd web && node build.mjs`.

## Licences to remember

flutter_blue_plus 2.x is free for educational institutions (`License.nonprofit` in `connect()`);
it may send a build-time licence ping with the app name. three.js is MIT. Atkinson Hyperlegible is OFL.
BodyParts3D (skeleton meshes) is CC BY-SA 2.1 Japan: credit required, adaptations share alike.
