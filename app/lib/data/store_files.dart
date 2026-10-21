import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'record_store.dart';
import 'session_record.dart';

RecordStore createStore() => FileRecordStore();

class FileRecordStore extends RecordStore {
  Directory? _dir;

  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/sessions');
    await _dir!.create(recursive: true);
    return _dir!;
  }

  @override
  String get location => _dir?.path ?? 'app documents/sessions';

  @override
  Future<List<SessionRecord>> list() async {
    final d = await _folder();
    final out = <SessionRecord>[];
    for (final f in d.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final streamFile = File(f.path.replaceAll(RegExp(r'\.json$'), '_stream.csv'));
        final stream = await streamFile.exists() ? await streamFile.readAsString() : '';
        out.add(SessionRecord.fromJson(j, streamCsv: stream));
      } catch (_) {
        // skip unreadable files
      }
    }
    out.sort((a, b) => b.started.compareTo(a.started));
    return out;
  }

  @override
  Future<void> save(SessionRecord r) async {
    final d = await _folder();
    await File('${d.path}/${r.id}.json').writeAsString(r.encode());
    await File('${d.path}/${r.id}_stream.csv').writeAsString(r.streamCsv);
  }

  @override
  Future<void> delete(String id) async {
    final d = await _folder();
    for (final n in ['$id.json', '${id}_stream.csv']) {
      final f = File('${d.path}/$n');
      if (await f.exists()) await f.delete();
    }
  }
}
