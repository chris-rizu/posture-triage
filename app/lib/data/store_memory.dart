import 'record_store.dart';
import 'session_record.dart';

RecordStore createStore() => MemoryRecordStore();

/// Used in the browser build (demo only): records last until the tab is closed.
class MemoryRecordStore extends RecordStore {
  final _items = <SessionRecord>[];

  @override
  String get location => 'browser memory (cleared when the tab closes)';

  @override
  Future<List<SessionRecord>> list() async =>
      List.of(_items)..sort((a, b) => b.started.compareTo(a.started));

  @override
  Future<void> save(SessionRecord r) async {
    _items.removeWhere((e) => e.id == r.id);
    _items.add(r);
  }

  @override
  Future<void> delete(String id) async => _items.removeWhere((e) => e.id == id);
}
