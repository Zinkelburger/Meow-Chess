import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/workspace_state.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/drafts.dart';

class FailingPreferences extends SqliteEventRepository {
  FailingPreferences() : super(':memory:');
  bool fail = false;
  @override
  void writePreference(String key, String value) {
    if (fail) throw StateError('Disk full');
    super.writePreference(key, value);
  }
}

void main() {
  test(
    'failed draft writes remain recoverable in memory and retry to disk',
    () {
      final repository = FailingPreferences();
      final store = WorkspaceState(repository);
      final field = TextEditingController();
      final draft = FormDraft(store, 'draft', {'name': field}, {'name': ''});
      repository.fail = true;
      field.text = 'Unfinished name';
      expect(store.failures['draft'], contains('Disk full'));
      expect(repository.readPreference('draft'), isNull);
      draft.dispose();
      field.dispose();
      final restored = TextEditingController();
      final next = FormDraft(store, 'draft', {'name': restored}, {'name': ''});
      expect(restored.text, 'Unfinished name');
      repository.fail = false;
      store.retry();
      expect(store.failures, isEmpty);
      expect(repository.readPreference('draft'), contains('Unfinished name'));
      next.dispose();
      restored.dispose();
      store.dispose();
      repository.close();
    },
  );

  test('restoring a draft keeps untouched fields from the current record', () {
    final repository = FailingPreferences();
    final store = WorkspaceState(repository);
    store.writeMap('draft', {
      'base': {'name': 'Original', 'state': ''},
      'values': {'name': 'Typed name', 'state': ''},
    });
    final name = TextEditingController(), state = TextEditingController();
    final draft = FormDraft(
      store,
      'draft',
      {'name': name, 'state': state},
      {'name': 'Original', 'state': 'MA'},
    );
    expect(name.text, 'Typed name');
    expect(state.text, 'MA');
    expect(draft.dirty, true);
    draft.dispose();
    name.dispose();
    state.dispose();
    store.dispose();
    repository.close();
  });
}
