import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/protocol.dart';
import '../data/record_store.dart';
import '../data/session_record.dart';
import '../device/harness.dart';

enum StepKind { calibrate, stand, bend, result }

enum StepStatus { pending, countdown, running, done, failed }

class AStep {
  AStep(this.kind, [this.n = 0, this.repeat = false]);
  final StepKind kind;
  final int n; // trial number (1-based) for stand/bend
  final bool repeat; // added because trials disagreed
  StepStatus status = StepStatus.pending;
  String? note;

  String get title => switch (kind) {
        StepKind.calibrate => 'Calibrate',
        StepKind.stand => repeat ? 'Standing trial (repeat)' : 'Standing trial $n of 3',
        StepKind.bend => repeat ? 'Forward-bend trial (repeat)' : 'Forward-bend trial $n of 3',
        StepKind.result => 'Result',
      };

  String get instructions => switch (kind) {
        StepKind.calibrate =>
          'Check that all five pods are attached and the belt is snug on the tops of the hip bones. '
              'Ask the participant to stand still in a relaxed posture for 3 seconds.',
        StepKind.stand =>
          'Ask the participant to stand naturally, feet hip-width apart, arms relaxed, looking straight ahead, '
              'and to stay still for 30 seconds. The unit vibrates once when the trial ends.',
        StepKind.bend =>
          'Ask the participant to bend forward slowly from the hips, knees straight, arms hanging and palms together, '
              'and to hold the bend. Recording starts after the countdown and lasts 5 seconds.',
        StepKind.result => 'The harness combines the three trials of each kind and applies the triage rule.',
      };
}

/// Runs the guided assessment protocol (thesis Section 3.4.6):
/// calibrate, three standing trials, three forward-bend trials, result.
class Assessment extends ChangeNotifier {
  Assessment(this.harness, this.store, this.participant, {this.bendCountdown = 4}) {
    _measSub = harness.measurements.listen(_log);
  }

  static const maxRepeats = 3;
  /// Seconds between pressing Start and the BEND command (time to bend forward).
  final int bendCountdown;

  final Harness harness;
  final RecordStore store;
  final String participant;
  final DateTime started = DateTime.now();
  late final String id = '${participant}_${_stamp(started)}';

  final steps = <AStep>[
    AStep(StepKind.calibrate),
    for (var i = 1; i <= 3; i++) AStep(StepKind.stand, i),
    for (var i = 1; i <= 3; i++) AStep(StepKind.bend, i),
    AStep(StepKind.result),
  ];
  int current = 0;
  bool busy = false;
  int countdown = 0;
  int progressSec = 0, progressOf = 0;
  Map<String, dynamic>? result;
  SessionRecord? saved;
  final trials = <Map<String, dynamic>>[];
  int _repeats = 0;
  bool _cancelled = false;
  bool _disposed = false;

  final _stream = StringBuffer('${SessionRecord.streamHeader}\n');
  late StreamSubscription<Measurement> _measSub;
  StreamSubscription? _progSub;

  AStep get step => steps[current];
  bool get finished => saved != null;

  static String _stamp(DateTime t) =>
      '${t.year}${_pad(t.month)}${_pad(t.day)}_${_pad(t.hour)}${_pad(t.minute)}${_pad(t.second)}';
  static String _pad(int v) => v.toString().padLeft(2, '0');

  String _phase(Measurement m) => switch (m.state) {
        DevState.calibrating => 'calibrate',
        DevState.stand => 'stand${step.kind == StepKind.stand ? step.n : ''}',
        DevState.bend => 'bend${step.kind == StepKind.bend ? step.n : ''}',
        _ => 'idle',
      };

  void _log(Measurement m) {
    if (finished) return;
    final t = DateTime.now().difference(started).inMilliseconds / 1000.0;
    _stream.writeln(SessionRecord.streamRow(t, _phase(m), m));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> begin() => harness.send('CLEAR');

  /// Runs the current step. Returns when it is done or failed.
  Future<void> runStep() async {
    if (busy || finished) return;
    busy = true;
    _cancelled = false;
    step.note = null;
    _notify();
    try {
      switch (step.kind) {
        case StepKind.calibrate:
          await _calibrate();
        case StepKind.stand:
          await _trial('STAND', 'stand', const Duration(seconds: 60));
        case StepKind.bend:
          step.status = StepStatus.countdown;
          for (countdown = bendCountdown; countdown > 0; countdown--) {
            _notify();
            await Future.delayed(const Duration(seconds: 1));
            if (_cancelled) throw _Cancelled();
          }
          await _trial('BEND', 'bend', const Duration(seconds: 30));
        case StepKind.result:
          await _result();
      }
    } on _Cancelled {
      step.status = StepStatus.pending;
      step.note = 'Stopped.';
    } on TimeoutException {
      step.status = StepStatus.failed;
      step.note = 'No answer from the harness. Check the connection and try again.';
    } finally {
      busy = false;
      countdown = 0;
      _progSub?.cancel();
      _notify();
    }
  }

  Future<void> _calibrate() async {
    step.status = StepStatus.running;
    _notify();
    final reply = harness.next('cal', timeout: const Duration(seconds: 20));
    await harness.send('CAL');
    final m = await reply;
    if (m['ok'] == true) {
      _advance();
    } else {
      step.status = StepStatus.failed;
      step.note = m['why'] == 'sensor'
          ? 'IMU${m['pod']} did not respond. Check its cable and connector.'
          : 'Movement detected (IMU${m['pod']}). Ask the participant to stand still and repeat.';
    }
  }

  Future<void> _trial(String cmd, String kind, Duration timeout) async {
    step.status = StepStatus.running;
    progressSec = 0;
    progressOf = kind == 'stand' ? 30 : 5;
    _progSub = harness.messages.where((m) => m['t'] == 'progress').listen((m) {
      progressSec = (m['sec'] as num).toInt();
      progressOf = (m['of'] as num).toInt();
      _notify();
    });
    _notify();
    final reply = harness.next('trial', where: (m) => m['kind'] == kind, timeout: timeout);
    final err = harness.next('err', timeout: timeout);
    await harness.send(cmd);
    final m = await Future.any([reply, err.then((e) => {'t': 'err', ...e})]);
    if (m['t'] == 'err') {
      step.status = StepStatus.failed;
      step.note = errText(m['msg'] as String?);
      return;
    }
    trials.add(m);
    if (m['ok'] == true) {
      progressSec = progressOf;
      _advance();
    } else if (m['why'] == 'aborted') {
      throw _Cancelled();
    } else {
      step.status = StepStatus.failed;
      step.note = trialFailText(m['why'] as String?);
    }
  }

  Future<void> _result() async {
    step.status = StepStatus.running;
    _notify();
    final reply = harness.next('result', timeout: const Duration(seconds: 10));
    await harness.send('RESULT');
    final m = await reply;
    result = m;
    if (m['complete'] == true && m['agree'] == true) {
      step.status = StepStatus.done;
      await _save();
      return;
    }
    final retake = ((m['retake'] as List?) ?? const []).cast<String>();
    if (_repeats >= maxRepeats || retake.isEmpty) {
      step.status = StepStatus.failed;
      step.note = 'The trials still do not agree within 3°. Check that the pods are firmly attached, '
          'then start a new assessment. This session is saved as incomplete.';
      await _save();
      return;
    }
    // insert one repeat trial per kind that disagreed, then ask for the result again
    _repeats++;
    step.status = StepStatus.pending;
    var at = current;
    for (final k in retake) {
      steps.insert(at++, AStep(k == 'stand' ? StepKind.stand : StepKind.bend, 0, true));
    }
    step.note = 'The ${retake.join(' and ')} trials did not agree within 3°. One more trial replaces the oldest.';
  }

  void _advance() {
    step.status = StepStatus.done;
    if (current < steps.length - 1) current++;
  }

  Future<void> _save() async {
    final r = SessionRecord(
      id: id,
      participant: participant,
      started: started,
      device: harness.name,
      firmware: harness.firmware,
      demo: harness.isDemo || harness.simulated,
      thresholds: harness.thresholds,
      trials: List.of(trials),
      result: result,
      streamCsv: _stream.toString(),
    );
    await store.save(r);
    saved = r;
  }

  Future<void> cancel() async {
    _cancelled = true;
    if (step.status == StepStatus.running) await harness.send('STOP');
  }

  @override
  void dispose() {
    _disposed = true;
    _measSub.cancel();
    _progSub?.cancel();
    super.dispose();
  }
}

class _Cancelled implements Exception {}
