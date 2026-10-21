import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/protocol.dart';
import 'device_link.dart';

/// The real harness over Bluetooth Low Energy (flutter_blue_plus).
///
/// flutter_blue_plus is free for educational institutions under its
/// "nonprofit" licence tier, which is what this thesis project uses.
class BleDeviceLink implements DeviceLink {
  BleDeviceLink._(this._dev, this._meas, this._result, this._cmd);

  final BluetoothDevice _dev;
  final BluetoothCharacteristic _meas, _result, _cmd;
  final _measCtl = StreamController<Measurement>.broadcast();
  final _msgCtl = StreamController<Map<String, dynamic>>.broadcast();
  final _done = Completer<void>();
  final _subs = <StreamSubscription>[];

  static Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;
  static Stream<bool> get isScanning => FlutterBluePlus.isScanning;
  static Stream<BluetoothAdapterState> get adapterState => FlutterBluePlus.adapterState;

  static Future<void> startScan() => FlutterBluePlus.startScan(
        withServices: [Guid(PtUuids.service)],
        timeout: const Duration(seconds: 8),
      );

  static Future<void> stopScan() => FlutterBluePlus.stopScan();

  static Future<BleDeviceLink> connect(BluetoothDevice dev) async {
    await dev.connect(license: License.nonprofit, timeout: const Duration(seconds: 15), mtu: 512);
    final services = await dev.discoverServices();
    final svc = services.firstWhere(
      (s) => s.uuid == Guid(PtUuids.service),
      orElse: () => throw StateError('This device is not a posture-triage harness.'),
    );
    BluetoothCharacteristic ch(String u) => svc.characteristics.firstWhere((c) => c.uuid == Guid(u));
    final link = BleDeviceLink._(dev, ch(PtUuids.measurement), ch(PtUuids.result), ch(PtUuids.command));
    await link._start();
    return link;
  }

  Future<void> _start() async {
    _subs.add(_dev.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) _finish();
    }));
    _subs.add(_meas.onValueReceived.listen((v) {
      final m = Measurement.decode(v);
      if (m != null) _measCtl.add(m);
    }));
    _subs.add(_result.onValueReceived.listen(_onJson));
    await _meas.setNotifyValue(true);
    await _result.setNotifyValue(true);
    await send('STATUS');
  }

  void _onJson(List<int> v) {
    try {
      final j = jsonDecode(utf8.decode(v));
      if (j is Map<String, dynamic>) _msgCtl.add(j);
    } catch (_) {
      // a truncated or malformed message: ignore it
    }
  }

  void _finish() {
    if (_done.isCompleted) return;
    for (final s in _subs) {
      s.cancel();
    }
    _done.complete();
  }

  @override
  String get name => _dev.platformName.isEmpty ? PtUuids.deviceName : _dev.platformName;

  @override
  bool get isDemo => false;

  @override
  Stream<Measurement> get measurements => _measCtl.stream;

  @override
  Stream<Map<String, dynamic>> get messages => _msgCtl.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> send(String command) => _cmd.write(utf8.encode(command), withoutResponse: false);

  @override
  Future<void> close() async {
    await _dev.disconnect();
    _finish();
  }
}
