import 'dart:convert';

import '../core/indicators.dart';
import '../core/score.dart';
import '../core/protocol.dart';

/// One completed (or abandoned) assessment. No names are stored: only the
/// participant code (thesis Section 3.6, data privacy).
class SessionRecord {
  SessionRecord({
    required this.id,
    required this.participant,
    required this.started,
    required this.device,
    required this.firmware,
    required this.demo,
    required this.thresholds,
    required this.trials,
    required this.result,
    required this.streamCsv,
  });

  final String id;
  final String participant;
  final DateTime started;
  final String device, firmware;
  final bool demo;
  final Thresholds thresholds;
  final List<Map<String, dynamic>> trials; // the device's "trial" messages
  final Map<String, dynamic>? result; // the device's "result" message
  final String streamCsv; // 5 Hz log

  Risk? get risk => riskFromKey(result?['risk'] as String?);

  /// 0-100 summary score (see core/score.dart); null when the assessment is incomplete.
  int? get score {
    final r = risk;
    if (!valid || r == null) return null;
    return postureScore({for (final i in Ind.values) i: value(i) ?? double.nan}, thresholds, r);
  }

  /// Mean pod angles of the valid standing trials (for drawing the recorded posture).
  ({List<double> s, List<double> f})? get standingPose {
    final ok = trials.where((t) => t['kind'] == 'stand' && t['ok'] == true).toList();
    if (ok.isEmpty) return null;
    List<double> mean(String k) => [
          for (var p = 0; p < 5; p++)
            ok.map((t) => ((t['pods'] as Map?)?[k] as List?)?.elementAtOrNull(p) as num?).whereType<num>().fold<double>(0, (a, b) => a + b) /
                ok.length
        ];
    return (s: mean('s'), f: mean('f'));
  }
  bool get valid => result?['complete'] == true && result?['agree'] == true;

  List? _ind(Ind i) => (result?['ind'] as Map?)?[indKey(i)] as List?;
  double? value(Ind i) => (_ind(i)?.elementAtOrNull(0) as num?)?.toDouble();
  double? range(Ind i) => (_ind(i)?.elementAtOrNull(1) as num?)?.toDouble();
  Risk? level(Ind i) => riskFromKey(_ind(i)?.elementAtOrNull(2) as String?);

  Map<String, dynamic> toJson() => {
        'id': id,
        'participant': participant,
        'started': started.toIso8601String(),
        'device': device,
        'firmware': firmware,
        'demo': demo,
        'thresholds': thresholds.toJson(),
        'trials': trials,
        'result': result,
      };

  factory SessionRecord.fromJson(Map<String, dynamic> j, {String streamCsv = ''}) => SessionRecord(
        id: j['id'] as String,
        participant: j['participant'] as String,
        started: DateTime.parse(j['started'] as String),
        device: j['device'] as String? ?? '',
        firmware: j['firmware'] as String? ?? '',
        demo: j['demo'] == true,
        thresholds: Thresholds.fromJson((j['thresholds'] as Map).cast<String, dynamic>()),
        trials: ((j['trials'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList(),
        result: (j['result'] as Map?)?.cast<String, dynamic>(),
        streamCsv: streamCsv,
      );

  String encode() => const JsonEncoder.withIndent(' ').convert(toJson());

  // ---------------------------------------------------------------- CSV
  static String _n(Object? v) => v == null ? '' : (v is double ? (v.isNaN ? '' : v.toStringAsFixed(2)) : '$v');

  static final summaryHeader = [
    'session_id', 'participant', 'date_time', 'device', 'firmware', 'demo', 'thresholds_provisional',
    'complete', 'agree', 'risk',
    for (final i in Ind.values) ...[indKey(i), '${indKey(i)}_range', '${indKey(i)}_level'],
  ].join(',');

  String summaryRow() => [
        id, participant, started.toIso8601String(), device, firmware, demo ? 1 : 0, thresholds.provisional ? 1 : 0,
        result?['complete'] == true ? 1 : 0, result?['agree'] == true ? 1 : 0, result?['risk'] ?? '',
        for (final i in Ind.values) ...[_n(value(i)), _n(range(i)), level(i)?.name ?? ''],
      ].join(',');

  static final trialsHeader = [
    'session_id', 'participant', 'kind', 'n', 'ok', 'why',
    for (final i in Ind.values) indKey(i),
    for (var p = 1; p <= 5; p++) 's$p',
    for (var p = 1; p <= 5; p++) 'f$p',
    for (var p = 1; p <= 5; p++) 'r$p',
  ].join(',');

  String trialsCsv() {
    final b = StringBuffer('$trialsHeader\n');
    for (final t in trials) {
      final ind = (t['ind'] as Map?) ?? const {};
      final pods = (t['pods'] as Map?) ?? const {};
      List<Object?> col(String k) => (pods[k] as List?) ?? List.filled(5, null);
      b.writeln([
        id, participant, t['kind'], t['n'] ?? '', t['ok'] == true ? 1 : 0, t['why'] ?? '',
        for (final i in Ind.values) _n((ind[indKey(i)] as num?)?.toDouble()),
        ...col('s').map((v) => _n((v as num?)?.toDouble())),
        ...col('f').map((v) => _n((v as num?)?.toDouble())),
        ...col('r').map((v) => _n((v as num?)?.toDouble())),
      ].join(','));
    }
    return b.toString();
  }

  static final streamHeader = [
    't_s', 'phase', 'state',
    for (var p = 1; p <= 5; p++) 's$p',
    for (var p = 1; p <= 5; p++) 'f$p',
    for (var p = 1; p <= 5; p++) 'r$p',
    for (final i in Ind.values) indKey(i),
    'battery_mv', 'flags',
  ].join(',');

  static String streamRow(double t, String phase, Measurement m) => [
        t.toStringAsFixed(2), phase, m.state.name,
        ...m.s.map(_n), ...m.f.map(_n), ...m.r.map(_n),
        for (final i in Ind.values) _n(m.ind[i]),
        m.batteryMv, m.flags,
      ].join(',');
}
