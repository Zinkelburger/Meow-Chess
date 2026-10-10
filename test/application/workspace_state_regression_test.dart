import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/workspace_state.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

class CountingPreferences extends SqliteEventRepository {
  CountingPreferences() : super(':memory:');
  int writes = 0;
  @override
  void writePreference(String key, String value) {
    writes++;
    super.writePreference(key, value);
  }
}

void main() {
  test('drafts saved after the event closes do not touch its database', () {
    final repository = CountingPreferences();
    final store = WorkspaceState(repository);
    expect(store.write('view', 'players'), isTrue);
    expect(repository.writes, 1);
    // A view disposing after its event closed still saves its state.
    store.dispose();
    repository.close();
    expect(store.write('view', 'results'), isTrue);
    expect(store.failures, isEmpty);
    expect(repository.writes, 1);
  });

  test('a draft saved after the event closes is the one read back', () {
    final repository = CountingPreferences();
    final store = WorkspaceState(repository);
    store.write('view', 'players');
    store.dispose();
    repository.close();
    store.write('view', 'results');
    expect(store.read('view'), 'results');
    expect(repository.writes, 1);
  });
}
