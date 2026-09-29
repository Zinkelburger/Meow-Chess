import '../domain/model.dart';

abstract interface class EventRepository {
  Event? load();
  Event commit(
    Event next, {
    required int expectedRevision,
    required String action,
  });
  Event? undo();
  String? get undoLabel;
  List<Json> history();
  String? readPreference(String key);
  void writePreference(String key, String value);
  void backup(String destination);
  void close();
}
