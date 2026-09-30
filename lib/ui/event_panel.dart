import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import 'identity_review.dart';
import 'players_view.dart' show SidePanel;
import 'workspace_actions.dart';

/// Event details, backups and copies, docked at the right like a player.
class EventPanel extends StatefulWidget {
  const EventPanel({
    required this.controller,
    required this.onClose,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;
  @override
  State<EventPanel> createState() => EventPanelState();
}

class EventPanelState extends State<EventPanel> {
  static const _fields = [
    ('name', 'Event name', 1),
    ('date', 'Date (YYYY-MM-DD)', 1),
    ('time', 'Time control', 1),
    ('venue', 'Venue or city', 1),
    ('td', 'Chief TD US Chess ID', 1),
    ('affiliate', 'Affiliate ID', 1),
    ('policy', 'Announced conditions', 3),
    ('notes', 'Private TD notes', 4),
  ];
  final text = {for (final f in _fields) f.$1: TextEditingController()};
  String? error;
  TournamentController get c => widget.controller;
  Map<String, String> get values => text.map((k, v) => MapEntry(k, v.text));
  bool get dirty => !mapEquals(values, stored);

  Map<String, String> get stored {
    final e = c.event!;
    return {
      'name': e.name,
      'date': e.date,
      'time': e.timeControl,
      'venue': e.venue,
      'td': e.tdId,
      'affiliate': e.affiliateId,
      'policy': e.policy,
      'notes': e.notes,
    };
  }

  /// Values last shown, to tell outside changes (undo) from typing.
  Map<String, String> shown = const {};

  void load() {
    shown = stored;
    for (final e in text.entries) {
      e.value.text = shown[e.key]!;
    }
    error = null;
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(EventPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow outside changes unless the user is mid-edit.
    if (mapEquals(values, shown) && !mapEquals(shown, stored)) load();
  }

  @override
  void dispose() {
    for (final t in text.values) {
      t.dispose();
    }
    super.dispose();
  }

  /// Saves pending edits. Returns false and shows why if invalid.
  bool commit() {
    if (!dirty) return true;
    final v = values;
    try {
      if (v['name']!.trim().isEmpty) {
        throw const TournamentException('Enter the event name.');
      }
      final date = DateTime.tryParse(v['date']!);
      if (date == null ||
          date.toIso8601String().substring(0, 10) != v['date']) {
        throw const TournamentException('Use a valid YYYY-MM-DD date.');
      }
      c.change(
        'Edit event details',
        c.event!.copy(
          name: v['name']!.trim(),
          date: v['date'],
          timeControl: v['time'],
          venue: v['venue'],
          tdId: v['td'],
          affiliateId: v['affiliate'],
          policy: v['policy'],
          notes: v['notes'],
        ),
      );
      setState(() => shown = stored);
      if (error != null) setState(() => error = null);
      return true;
    } catch (e) {
      setState(() => error = '$e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = c.event!, colors = Theme.of(context).colorScheme;
    final actions = WorkspaceActions(context, c);
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    final backup = c.repository.readPreference('lastBackup');
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
    return SidePanel(
      title: 'Event details',
      onClose: () {
        if (commit()) widget.onClose();
      },
      children: [
        for (final (key, label, lines) in _fields)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: TextField(
              key: ValueKey('event-$key'),
              controller: text[key],
              maxLines: lines,
              decoration: InputDecoration(
                labelText: label,
                hintText: key == 'time' ? 'G/60;d5' : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => commit(),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
        if (dirty)
          Row(
            children: [
              FilledButton(onPressed: commit, child: const Text('Save')),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(load),
                child: const Text('Revert'),
              ),
            ],
          ),
        heading('Backups'),
        Text(
          e.backupFolder.isEmpty
              ? 'No backup folder. Every change is still saved to the event file.'
              : 'Backing up to ${e.backupFolder}${backup == null ? '' : ' · last at revision ${backup.split('|').first} (now ${e.revision})'}',
          style: muted,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: actions.chooseBackupFolder,
              child: Text(
                e.backupFolder.isEmpty
                    ? 'Choose backup folder…'
                    : 'Change folder…',
              ),
            ),
            if (e.backupFolder.isNotEmpty) ...[
              OutlinedButton(
                onPressed: c.secondaryBackup,
                child: const Text('Back up now'),
              ),
              TextButton(
                onPressed: actions.clearBackupFolder,
                child: const Text('Stop backups'),
              ),
            ],
          ],
        ),
        heading('Copies'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: actions.saveCopy,
              child: const Text('Save a copy…'),
            ),
            OutlinedButton(
              onPressed: () => actions.saveCopy(practice: true),
              child: const Text('Practice copy…'),
            ),
          ],
        ),
        heading('US Chess API key'),
        Text('Only needed to look up US Chess IDs online.', style: muted),
        const SizedBox(height: 8),
        const ApiKeyField(),
      ],
    );
  }
}
