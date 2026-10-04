import 'package:flutter/material.dart';

import '../application/workspace_state.dart';

/// Stores partial input, including invalid values, without applying it. A saved
/// base keeps untouched fields in sync when another view edits the same record.
class FormDraft {
  FormDraft(this.store, this.key, this.fields, Map<String, String> base)
    : _base = Map.of(base) {
    final saved = store.readMap(key);
    final oldBase = saved['base'] as Map? ?? {};
    final edits = saved['values'] as Map? ?? {};
    for (final entry in fields.entries) {
      final value = edits[entry.key];
      final edited = value is String && value != oldBase[entry.key];
      entry.value.text = edited ? value : base[entry.key] ?? '';
      if (edited && oldBase[entry.key] is String) {
        // Keep the original base so reopening cannot hide a conflicting edit.
        _base[entry.key] = oldBase[entry.key] as String;
      }
      entry.value.addListener(save);
    }
  }
  final WorkspaceState store;
  final String key;
  final Map<String, TextEditingController> fields;
  Map<String, String> _base;
  bool _loading = false;
  Map<String, String> get values => fields.map((k, v) => MapEntry(k, v.text));
  bool isEdited(String field) => fields[field]!.text != _base[field];
  bool get dirty => fields.keys.any(isEdited);

  void save() {
    if (_loading) return;
    if (dirty) {
      store.writeMap(key, {'base': _base, 'values': values});
    } else {
      store.write(key, '');
    }
  }

  /// Refresh untouched fields without losing input in other fields. A field
  /// changed on both sides keeps its original base until the conflict is resolved.
  void reconcile(Map<String, String> current) {
    var changed = false;
    _loading = true;
    for (final entry in current.entries) {
      final field = fields[entry.key];
      if (field == null) continue;
      if (field.text == _base[entry.key] || field.text == entry.value) {
        changed = changed || _base[entry.key] != entry.value;
        _base[entry.key] = entry.value;
        if (field.text != entry.value) field.text = entry.value;
      }
    }
    _loading = false;
    if (changed) save();
  }

  Set<String> conflicts(Map<String, String> current) => {
    for (final entry in current.entries)
      if (fields.containsKey(entry.key) &&
          fields[entry.key]!.text != _base[entry.key] &&
          entry.value != _base[entry.key] &&
          fields[entry.key]!.text != entry.value)
        entry.key,
  };

  void reset(Map<String, String> base) {
    _loading = true;
    _base = Map.of(base);
    for (final entry in fields.entries) {
      entry.value.text = base[entry.key] ?? '';
    }
    _loading = false;
    save();
  }

  void dispose() {
    for (final field in fields.values) {
      field.removeListener(save);
    }
  }
}

class DraftStatus extends StatelessWidget {
  const DraftStatus({required this.draft, super.key});
  final FormDraft draft;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft.store,
    builder: (context, _) {
      final error = draft.store.failures[draft.key];
      if (!draft.dirty && error == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          liveRegion: error != null,
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                error == null
                    ? 'Draft saved · not applied'
                    : 'Draft not saved to disk. $error',
                style: TextStyle(
                  color: error == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.error,
                ),
              ),
              if (error != null)
                TextButton(onPressed: draft.save, child: const Text('Retry')),
            ],
          ),
        ),
      );
    },
  );
}
