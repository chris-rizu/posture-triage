import 'package:flutter/foundation.dart';

import 'record_store.dart';
import 'session_record.dart';

/// Saved assessments as a listenable list (newest first).
class Records extends ChangeNotifier {
  Records(this.store) {
    reload();
  }
  final RecordStore store;
  List<SessionRecord> items = const [];
  bool loaded = false;

  Future<void> reload() async {
    items = await store.list();
    loaded = true;
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await store.delete(id);
    await reload();
  }

  List<String> get participants {
    final seen = <String>{};
    return [for (final r in items) if (seen.add(r.participant)) r.participant];
  }

  List<SessionRecord> of(String participant) => items.where((r) => r.participant == participant).toList();

  SessionRecord? get latest => items.isEmpty ? null : items.first;
}
