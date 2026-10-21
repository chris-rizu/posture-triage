import 'dart:async';

import '../core/protocol.dart';

/// A connection to the harness: the real one over BLE, or the built-in demo.
abstract class DeviceLink {
  String get name;
  bool get isDemo;

  /// 5 Hz stream of the Measurement characteristic.
  Stream<Measurement> get measurements;

  /// JSON messages from the Result characteristic (each has a "t" field).
  Stream<Map<String, dynamic>> get messages;

  /// Completes when the connection is lost or closed.
  Future<void> get done;

  /// Sends a text command (CAL, STAND, BEND, RESULT, ...).
  Future<void> send(String command);

  Future<void> close();
}
