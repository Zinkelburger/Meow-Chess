import '../domain/history.dart';
import '../domain/model.dart';

abstract interface class EventRepository {
  Event? load();
  Event commit(
    Event next, {
    required int expectedRevision,
    required String action,
  });

  /// Moves the event to the saved state of history [node]. The revision still
  /// advances, so proposals made against the previous state stay stale.
  Event checkout(
    int node, {
    required int expectedRevision,
    required String action,
  });
  HistoryGraph historyGraph();
  Event snapshot(int node);
  List<Json> history();
  String? readPreference(String key);
  void writePreference(String key, String value);
  void backup(String destination);
  void close();
}
