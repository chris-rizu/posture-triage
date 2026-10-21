# Posture triage

Software for the thesis "A Sensor-Based System for Posture Assessment and Early Back-Health
Risk Triage". A harness with five IMU sensors measures the spine; an ESP32 computes six posture
indicators and a three-level triage (healthy, monitor, refer); a Flutter app guides the protocol,
shows a live anatomical skeleton driven by the sensors, and exports the data for analysis.
The app has four tabs (Home, Progress, Sensors, Settings); Buko, a small 3D spine character,
greets the user and reacts to results.

```
firmware/   ESP32 firmware (PlatformIO). Core logic is plain C++ and unit-tested on the PC.
app/        Flutter app (Android and iOS; the browser build runs the demo).
skeleton/   Live skeleton twin: BodyParts3D anatomy posed from the sensors (three.js).
mascot/     Buko the mascot: Blender model script and three.js viewer.
analysis/   Python statistics for Chapter 3 (agreement, reliability, triage accuracy).
docs/       BLE protocol, setup guide, hardware notes.
CLAUDE.md   Everything Claude Code needs to know about the project.
```

Start with `docs/SETUP.md`. For iPhones, see `docs/IOS.md`. No hardware yet? Flash `esp32-sim` to a bare ESP32, or tap
"Try demo" on the app's Home tab.

| Check | Command | Status at hand-off |
|---|---|---|
| Firmware unit tests | `cd firmware && pio test -e native` | 25 passed |
| Firmware builds | `pio run -e esp32` and `-e esp32-sim` | both build |
| App static analysis | `cd app && flutter analyze` | no issues |
| App tests | `flutter test` | 11 passed |
| Analysis tests | `cd analysis && pytest` | 9 passed |
| Android build | `flutter build apk --release` | builds (debug-signed) |
| iOS build | `.github/workflows/ios.yml` on a GitHub Mac, or Xcode | project ready; not built here (needs macOS) |
