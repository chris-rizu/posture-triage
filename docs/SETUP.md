# Setting up VS Code and Claude Code for this project

These steps take about 30–45 minutes the first time, mostly downloads.

## 1. Install the tools

| Tool | Get it from | Check |
|---|---|---|
| VS Code | code.visualstudio.com | |
| Git | git-scm.com | `git --version` |
| Flutter SDK (stable) | docs.flutter.dev/get-started/install | `flutter doctor` |
| Android Studio (for the Android SDK and an emulator) | developer.android.com/studio | `flutter doctor` shows Android toolchain ✓ |
| Python 3.10 or newer | python.org | `python --version` |
| Node.js 20 or newer (only to rebuild the mascot) | nodejs.org | `node --version` |

In VS Code, open the Extensions panel and install the extensions the project recommends
(VS Code offers them when you open the folder): **PlatformIO IDE**, **Flutter**, **Python** and
**Claude Code**. PlatformIO downloads the ESP32 toolchain the first time you build.

## 2. Open the project

Unzip `posture-triage.zip`, then in VS Code use **File → Open Folder** and pick `posture-triage`.
Claude Code reads `CLAUDE.md` automatically, so it already knows the pins, angle conventions,
protocol and thresholds. Open it from the Claude icon in the sidebar and ask, for example,
"run the firmware tests" or "add a fourth demo profile".

## 3. Run each part

**Firmware tests on the PC (no board needed):**
```
cd firmware
pio test -e native
```

**Flash the ESP32 without sensors (simulated wearer):**
```
pio run -e esp32-sim -t upload
pio device monitor
```
Type `CAL`, then `STAND`, `RESULT` in the serial monitor. The app can also connect to it over Bluetooth.

**Flash the real harness:** `pio run -e esp32 -t upload`. In the serial monitor, `WHO` lists the
five sensors and `RAW` prints raw values for checking the mounting (upright: ax ≈ +1 g on every pod).

**App on an Android phone:** enable Developer options and USB debugging on the phone, plug it in, then
```
cd app
flutter pub get
flutter run
```
Allow "Nearby devices" when Android asks. "Try demo" on the Home tab works without hardware.
To make an installable file: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`.

**Analysis:**
```
cd analysis
python -m venv .venv && .venv\Scripts\activate      (macOS/Linux: source .venv/bin/activate)
pip install -r requirements.txt
pytest
python -m ptanalysis synth --out data
python -m ptanalysis evaluate data/summary.csv data/pt_reference.csv --out out
```

## 4. During the study

1. Development set (20 participants): run assessments; the physical therapist fills in
   `pt_reference.csv` (columns in `analysis/README.md`). In the app: Saved → Export all.
2. `python -m ptanalysis thresholds summary.csv pt_reference.csv --out out/thresholds.json`
3. In the app: Thresholds → paste the JSON → Send to harness. The limits are now frozen.
4. Validation set (40 participants), then `python -m ptanalysis evaluate ... --thresholds out/thresholds.json`.
