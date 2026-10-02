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
      entry.value.text = value is String && value != oldBase[entry.key]
          ? value
          : base[entry.key] ?? '';
      entry.value.addListener(save);
    }
  }
  final WorkspaceState store;
  final String key;
  final Map<String, TextEditingController> fields;
  Map<String, String> _base;
  bool _loading = false;
  Map<String, String> get values => fields.map((k, v) => MapEntry(k, v.text));
  bool get dirty => fields.entries.any((e) => e.value.text != _base[e.key]);

  void save() {
    if (_loading) return;
    if (dirty) {
      store.writeMap(key, {'base': _base, 'values': values});
    } else {
      store.write(key, '');
    }
  }

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
