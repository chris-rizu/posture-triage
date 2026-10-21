// BLE protocol shared with the firmware (firmware/lib/core/src/protocol.h,
// docs/BLE_PROTOCOL.md).
import 'dart:typed_data';

import 'indicators.dart';

class PtUuids {
  static const service = '7a1e0001-5c3b-4f2a-9d7e-2b8c4a6f1d00';
  static const measurement = '7a1e0002-5c3b-4f2a-9d7e-2b8c4a6f1d00';
  static const result = '7a1e0003-5c3b-4f2a-9d7e-2b8c4a6f1d00';
  static const command = '7a1e0004-5c3b-4f2a-9d7e-2b8c4a6f1d00';
  static const deviceName = 'PostureTriage';
}

enum DevState { idle, calibrating, stand, bend, monitor, error, lowBattery }

DevState devStateFromKey(String? k) => switch (k) {
      'calibrating' => DevState.calibrating,
      'stand' => DevState.stand,
      'bend' => DevState.bend,
      'monitor' => DevState.monitor,
      'error' => DevState.error,
      'low_battery' => DevState.lowBattery,
      _ => DevState.idle,
    };

class MeasFlags {
  static const moving = 1 << 0;
  static const calibrated = 1 << 1;
  static const lowBattery = 1 << 2;
  static const simulated = 1 << 3;
  static const sensorFault = 1 << 4;
}

/// Pod order: 0 IMU1 C7–T1, 1 IMU2 T12–L1, 2 IMU3 L3–L4, 3 IMU4 left scapula, 4 IMU5 right scapula.
const podNames = ['IMU1', 'IMU2', 'IMU3', 'IMU4', 'IMU5'];
const podSites = ['C7–T1 (base of neck)', 'T12–L1 (thoracolumbar)', 'L3–L4 (mid-lumbar)', 'Left scapula', 'Right scapula'];

/// One 5 Hz sample from the Measurement characteristic. Angles in degrees; NaN = undefined.
class Measurement {
  Measurement({
    required this.state,
    required this.seq,
    required this.s,
    required this.f,
    required this.r,
    required this.ind,
    required this.batteryMv,
    required this.flags,
  });

  static const length = 49;

  final DevState state;
  final int seq;
  final List<double> s, f, r; // per pod
  final Map<Ind, double> ind;
  final int batteryMv;
  final int flags;

  bool get moving => flags & MeasFlags.moving != 0;
  bool get calibrated => flags & MeasFlags.calibrated != 0;
  bool get simulated => flags & MeasFlags.simulated != 0;
  bool get sensorFault => flags & MeasFlags.sensorFault != 0;
  bool get lowBattery => flags & MeasFlags.lowBattery != 0;

  static double _c(ByteData d, int o) {
    final v = d.getInt16(o, Endian.little);
    return v == -32768 ? double.nan : v / 100.0;
  }

  static Measurement? decode(List<int> bytes) {
    if (bytes.length < length || bytes[0] != 1) return null;
    final d = ByteData.sublistView(Uint8List.fromList(bytes));
    final st = bytes[1] < DevState.values.length ? DevState.values[bytes[1]] : DevState.error;
    return Measurement(
      state: st,
      seq: d.getUint16(2, Endian.little),
      s: [for (var p = 0; p < 5; p++) _c(d, 4 + 2 * p)],
      f: [for (var p = 0; p < 5; p++) _c(d, 14 + 2 * p)],
      r: [for (var p = 0; p < 5; p++) _c(d, 24 + 2 * p)],
      ind: {for (final i in Ind.values) i: _c(d, 34 + 2 * i.index)},
      batteryMv: d.getUint16(46, Endian.little),
      flags: bytes[48],
    );
  }

  Uint8List encode() {
    final d = ByteData(length);
    void put(int o, double v) =>
        d.setInt16(o, v.isNaN ? -32768 : (v * 100).round().clamp(-32767, 32767), Endian.little);
    d.setUint8(0, 1);
    d.setUint8(1, state.index);
    d.setUint16(2, seq & 0xFFFF, Endian.little);
    for (var p = 0; p < 5; p++) {
      put(4 + 2 * p, s[p]);
      put(14 + 2 * p, f[p]);
      put(24 + 2 * p, r[p]);
    }
    for (final i in Ind.values) {
      put(34 + 2 * i.index, ind[i] ?? double.nan);
    }
    d.setUint16(46, batteryMv, Endian.little);
    d.setUint8(48, flags);
    return d.buffer.asUint8List();
  }
}

/// Battery percentage from a 1-cell Li-ion voltage (rough, linear 3.3–4.15 V).
int batteryPercent(int mv) {
  if (mv <= 0) return -1;
  return (((mv - 3300) / (4150 - 3300)) * 100).round().clamp(0, 100);
}

String trialFailText(String? why) => switch (why) {
      'moved' => 'The participant moved during the trial. Ask them to stay still and repeat.',
      'not_bent' => 'The trunk was not bent far enough. Ask for a full forward bend, arms hanging, and repeat.',
      'not_upright' => 'The participant was not standing upright. Repeat the trial.',
      'sensor' => 'A sensor stopped responding. Check the cables and repeat.',
      'aborted' => 'The trial was stopped.',
      _ => 'The trial was not valid. Repeat it.',
    };

String errText(String? msg) => switch (msg) {
      'not_calibrated' => 'Calibrate the harness first.',
      'busy' => 'The harness is busy. Wait for the current step to finish.',
      'low_battery' => 'The battery is low. Charge the control unit.',
      'bad_thresholds' => 'The thresholds were rejected by the harness.',
      'unknown_command' => 'The harness did not recognise the command.',
      'sim_unavailable' => 'Simulation commands work only with the simulated firmware or demo mode.',
      _ => msg ?? 'Unknown error',
    };
