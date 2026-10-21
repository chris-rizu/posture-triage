import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/indicators.dart';
import '../core/protocol.dart';
import 'device_link.dart';

/// App-wide state of the connected harness. Screens listen to it.
class Harness extends ChangeNotifier {
  DeviceLink? _link;
  StreamSubscription? _mSub, _jSub;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();

  Measurement? latest;
  Map<String, dynamic> status = const {};
  Thresholds thresholds = Thresholds.defaults();
  String? lastError;
  DateTime? lastMeasurementAt;
  int packets = 0; // measurement packets received on this connection
  final _arrivals = ListQueue<DateTime>();

  /// Measurement packets per second over the last two seconds (5.0 when healthy).
  double get packetRate {
    final now = DateTime.now();
    while (_arrivals.isNotEmpty && now.difference(_arrivals.first).inMilliseconds > 2000) {
      _arrivals.removeFirst();
    }
    return _arrivals.length / 2.0;
  }

  /// True while packets keep arriving (none missing for more than a second).
  bool get streaming =>
      lastMeasurementAt != null && DateTime.now().difference(lastMeasurementAt!).inMilliseconds < 1000;

  DeviceLink? get link => _link;
  bool get connected => _link != null;
  bool get isDemo => _link?.isDemo ?? false;
  String get name => _link?.name ?? '';

  /// Every JSON message from the harness (after Harness has processed it).
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  /// Live measurements (5 Hz).
  Stream<Measurement> get measurements => _link?.measurements ?? const Stream.empty();

  DevState get state => latest?.state ?? devStateFromKey(status['state'] as String?);
  bool get calibrated => status['cal'] == true || (latest?.calibrated ?? false);
  bool get simulated => status['sim'] == true || (latest?.simulated ?? false);
  int get batteryMv => latest?.batteryMv ?? ((status['bat'] as num? ?? 0) * 1000).round();
  List<int> get sensors => (status['sensors'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const [1, 1, 1, 1, 1];
  String get firmware => status['fw']?.toString() ?? '';

  Future<void> attach(DeviceLink link) async {
    await detach();
    _link = link;
    _mSub = link.measurements.listen((m) {
      latest = m;
      lastMeasurementAt = DateTime.now();
      packets++;
      _arrivals.addLast(lastMeasurementAt!);
      notifyListeners();
    });
    _jSub = link.messages.listen(_onMessage);
    link.done.then((_) {
      if (identical(_link, link)) {
        _clear();
        lastError = 'The harness disconnected.';
        notifyListeners();
      }
    });
    notifyListeners();
    await send('STATUS');
    await send('GETTHR');
  }

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'status':
        status = m;
      case 'thr':
        thresholds = Thresholds.fromJson(m);
      case 'err':
        lastError = errText(m['msg'] as String?);
    }
    _messages.add(m);
    notifyListeners();
  }

  Future<void> send(String cmd) async {
    final l = _link;
    if (l == null) return;
    try {
      await l.send(cmd);
    } catch (e) {
      lastError = 'Could not send $cmd: $e';
      notifyListeners();
    }
  }

  Future<void> sendThresholds(Thresholds t) => send('THR ${jsonEncode(t.toJson())}');

  void clearError() {
    lastError = null;
    notifyListeners();
  }

  void _clear() {
    _mSub?.cancel();
    _jSub?.cancel();
    _link = null;
    latest = null;
    status = const {};
    packets = 0;
    _arrivals.clear();
    lastMeasurementAt = null;
  }

  Future<void> detach() async {
    final l = _link;
    _clear();
    if (l != null) await l.close();
    notifyListeners();
  }

  /// Waits for the next message of type [t] (optionally matching [where]).
  Future<Map<String, dynamic>> next(String t, {bool Function(Map<String, dynamic>)? where, Duration? timeout}) {
    final f = messages.firstWhere((m) => m['t'] == t && (where == null || where(m)));
    return timeout == null ? f : f.timeout(timeout);
  }
}
