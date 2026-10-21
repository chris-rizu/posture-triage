import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

import 'session_record.dart';
import 'store_memory.dart' if (dart.library.io) 'store_files.dart' as impl;

/// Saved assessments. On the phone they are files in the app's documents
/// folder (`sessions/<id>.json` and `<id>_stream.csv`); in a browser they live in memory.
abstract class RecordStore {
  static RecordStore create() => impl.createStore();

  Future<List<SessionRecord>> list();
  Future<void> save(SessionRecord r);
  Future<void> delete(String id);
  String get location;

  /// One row per session, for the analysis toolkit (analysis/README.md).
  Future<String> summaryCsv() async {
    final rows = await list();
    final b = StringBuffer('${SessionRecord.summaryHeader}\n');
    for (final r in rows.reversed) {
      b.writeln(r.summaryRow());
    }
    return b.toString();
  }

  Future<String> allTrialsCsv() async {
    final rows = await list();
    final b = StringBuffer('${SessionRecord.trialsHeader}\n');
    for (final r in rows.reversed) {
      final t = r.trialsCsv();
      b.write(t.substring(t.indexOf('\n') + 1));
    }
    return b.toString();
  }
}

XFile _csv(String name, String text) =>
    XFile.fromData(utf8.encode(text), name: name, mimeType: 'text/csv');

/// Opens the share sheet with the three CSV files of one session.
/// iPad share sheets need an anchor; the top-right corner, where the share buttons are.
const _origin = Rect.fromLTWH(600, 40, 1, 1);

Future<void> shareSession(SessionRecord r) => SharePlus.instance.share(ShareParams(
      subject: 'Posture assessment ${r.participant} ${r.id}',
      files: [
        _csv('${r.id}_summary.csv', '${SessionRecord.summaryHeader}\n${r.summaryRow()}\n'),
        _csv('${r.id}_trials.csv', r.trialsCsv()),
        _csv('${r.id}_stream.csv', r.streamCsv),
      ],
      sharePositionOrigin: _origin,
      fileNameOverrides: ['${r.id}_summary.csv', '${r.id}_trials.csv', '${r.id}_stream.csv'],
    ));

/// Opens the share sheet with summary.csv and trials.csv for every saved session.
Future<void> shareAll(RecordStore store) async {
  final summary = await store.summaryCsv();
  final trials = await store.allTrialsCsv();
  await SharePlus.instance.share(ShareParams(
    subject: 'Posture assessments (all sessions)',
    files: [_csv('summary.csv', summary), _csv('trials.csv', trials)],
    sharePositionOrigin: _origin,
    fileNameOverrides: ['summary.csv', 'trials.csv'],
  ));
}
