import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/us_chess.dart';
import '../infrastructure/ratings_api.dart';
import 'history_panel.dart' show historyTime;
import 'identity_review.dart';
import 'member_identity_lookup.dart';
import 'players_view.dart' show SidePanel;
import 'drafts.dart';
import 'workspace_actions.dart';

/// Event details, docked at the right like a player.
class EventPanel extends StatefulWidget {
  const EventPanel({
    required this.controller,
    required this.onClose,
    this.initialField,
    this.identityLookup = fetchMembership,
    this.memberSearch = searchMembers,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;
  final String? initialField;
  final Future<MemberObservation?> Function(TournamentController, String)
  identityLookup;
  final Future<List<MemberObservation>> Function(String) memberSearch;
  @override
  State<EventPanel> createState() => EventPanelState();
}

class EventPanelState extends State<EventPanel> {
  static const _fields = [
    ('name', 'Event name', 1),
    ('date', 'Date (YYYY-MM-DD)', 1),
    ('endDate', 'Last day (optional)', 1),
    ('time', 'Time control', 1),
    ('venue', 'Venue or city', 1),
    ('td', 'Chief TD US Chess ID', 1),
    ('atd', 'Assistant chief TD US Chess ID', 1),
    ('otherTds', 'Other TDs\' US Chess IDs, comma separated', 1),
    ('affiliate', 'Affiliate ID', 1),
    ('policy', 'Announced conditions', 3),
    ('notes', 'Private TD notes', 4),
  ];
  final text = {for (final f in _fields) f.$1: TextEditingController()};
  String? error;
  late FormDraft draft;
  final fieldFocus = <String, FocusNode>{};
  TournamentController get c => widget.controller;
  Map<String, String> get values => text.map((k, v) => MapEntry(k, v.text));
  bool get dirty => !mapEquals(values, stored);

  Map<String, String> get stored {
    final e = c.event!;
    return {
      'name': e.name,
      'date': e.date,
      'endDate': e.endDate,
      'time': e.timeControl,
      'venue': e.venue,
      'td': e.tdId,
      'atd': e.assistantTdId,
      'otherTds': e.otherTdIds,
      'affiliate': e.affiliateId,
      'policy': e.policy,
      'notes': e.notes,
    };
  }

  void load() {
    final shown = stored;
    for (final e in text.entries) {
      e.value.text = shown[e.key]!;
    }
    error = null;
  }

  @override
  void initState() {
    super.initState();
    load();
    draft = FormDraft(c.workspaceState, 'draft-event', text, stored);
    focusField(widget.initialField ?? 'name');
  }

  @override
  void didUpdateWidget(EventPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    draft.reconcile(stored);
  }

  @override
  void dispose() {
    draft.dispose();
    for (final node in fieldFocus.values) {
      node.dispose();
    }
    for (final t in text.values) {
      t.dispose();
    }
    super.dispose();
  }

  /// Saves pending edits. Returns false and shows why if invalid.
  bool commit() {
    draft.reconcile(stored);
    final conflicts = draft.conflicts(stored);
    if (conflicts.isNotEmpty) {
      final names = _fields
          .where((field) => conflicts.contains(field.$1))
          .map((field) => field.$2)
          .join(', ');
      setState(
        () => error =
            '$names changed elsewhere. Discard this draft to load the saved values, then re-enter your changes.',
      );
      return false;
    }
    if (!draft.dirty) return true;
    final v = values;
    try {
      if (v['name']!.trim().isEmpty) {
        throw const TournamentException('Enter the event name.');
      }
      if (!isEventDate(v['date']!)) {
        throw const TournamentException('Use a valid YYYY-MM-DD date.');
      }
      final end = v['endDate']!.trim();
      if (end.isNotEmpty &&
          (!isEventDate(end) || end.compareTo(v['date']!) < 0)) {
        throw const TournamentException(
          'The last day must be a YYYY-MM-DD date on or after the first.',
        );
      }
      // Only fields being changed are checked, so an older event with an
      // unusual value can still be edited.
      final td = v['td']!.trim(),
          affiliate = v['affiliate']!.trim().toUpperCase();
      if (td != c.event!.tdId && td.isNotEmpty && !isMemberId(td)) {
        throw const TournamentException(
          'The chief TD\'s US Chess ID has eight digits.',
        );
      }
      final atd = v['atd']!.trim(),
          others = otherTdList(v['otherTds']!).join(', ');
      if (atd != c.event!.assistantTdId && atd.isNotEmpty && !isMemberId(atd)) {
        throw const TournamentException(
          'The assistant chief TD\'s US Chess ID has eight digits.',
        );
      }
      if (others != c.event!.otherTdIds) {
        if (otherTdProblem(others) case final problem?) {
          throw TournamentException(problem);
        }
      }
      if (affiliate != c.event!.affiliateId &&
          affiliate.isNotEmpty &&
          !isAffiliateId(affiliate)) {
        throw const TournamentException(
          'Affiliate IDs are the letter A and seven digits, like A6012345.',
        );
      }
      c.change(
        'Edit event details',
        c.event!.copy(
          name: v['name']!.trim(),
          date: v['date'],
          endDate: end,
          timeControl: v['time'],
          venue: v['venue'],
          tdId: td,
          assistantTdId: atd,
          otherTdIds: others,
          affiliateId: affiliate,
          policy: v['policy'],
          notes: v['notes'],
        ),
      );
      // Reload so normalized values (such as a capitalized affiliate ID)
      // show as saved.
      draft.reset(stored);
      setState(load);
      return true;
    } catch (e) {
      setState(() => error = plainMessage(e));
      return false;
    }
  }

  void focusField(String field) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = fieldFocus[field];
      node?.requestFocus();
      if (node?.context case final target?) {
        Scrollable.ensureVisible(target, alignment: 0.25);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
    return SidePanel(
      title: 'Event details',
      onClose: widget.onClose,
      children: [
        DraftStatus(draft: draft),
        for (final (key, label, lines) in _fields) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: TextField(
              key: ValueKey('event-$key'),
              controller: text[key],
              focusNode: fieldFocus.putIfAbsent(
                key,
                () => FocusNode(debugLabel: key),
              ),
              maxLines: lines,
              decoration: InputDecoration(
                labelText: label,
                hintText: key == 'endDate'
                    ? 'YYYY-MM-DD'
                    : key == 'td' || key == 'atd'
                    ? 'ID or name to search'
                    : null,
                alignLabelWithHint: lines > 1,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => commit(),
            ),
          ),
          if (key == 'td' || key == 'atd')
            MemberIdentityLookup(
              key: ValueKey('event-identity-$key'),
              id: text[key]!,
              lookup: (id) => widget.identityLookup(c, id),
              search: widget.memberSearch,
              onSelected: (member) => setState(() {
                text[key]!.text = member.id;
              }),
            ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
        if (dirty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: commit, child: const Text('Save')),
              TextButton(
                onPressed: () {
                  draft.reset(stored);
                  setState(load);
                },
                child: const Text('Discard draft'),
              ),
            ],
          ),
        heading('Standings'),
        SwitchListTile(
          key: const ValueKey('event-use-tiebreaks'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Tie-breaks'),
          value: c.event!.useTiebreaks,
          onChanged: (value) {
            FocusScope.of(context).unfocus();
            try {
              c.change(
                'Change standings ranking',
                c.event!.copy(useTiebreaks: value),
              );
              setState(() {});
            } catch (e) {
              setState(() => error = plainMessage(e));
            }
          },
        ),
        heading('Data sources'),
        const RatingSettings(),
        const SizedBox(height: 24),
        Text(
          'US Chess API key (optional). Without a key, try the public service. Public access may change.',
          style: muted,
        ),
        const SizedBox(height: 8),
        const ApiKeyField(),
      ],
    );
  }
}

/// Backups and copies of the event file, opened from the status bar.
class BackupsPanel extends StatefulWidget {
  const BackupsPanel({
    required this.controller,
    required this.onClose,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;

  @override
  State<BackupsPanel> createState() => _BackupsPanelState();
}

class _BackupsPanelState extends State<BackupsPanel> {
  String? savedCopy;
  bool savingCopy = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        e = c.event!,
        colors = Theme.of(context).colorScheme;
    final actions = WorkspaceActions(context, c);
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    final last = c.repository.readPreference('lastBackup')?.split('|');
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
    return SidePanel(
      title: 'Backups',
      onClose: widget.onClose,
      children: [
        Text(
          'Changes save as you work. A backup folder gets a full copy after each posted round; a USB stick is ideal.',
          style: muted,
        ),
        if (c.backupWarning != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              c.backupWarning!,
              style: TextStyle(color: colors.error),
            ),
          ),
        heading('Backup folder'),
        Text(
          e.backupFolder.isEmpty
              ? 'None chosen.'
              : [
                  e.backupFolder,
                  if (last != null && last.length > 2)
                    'Last copy ${historyTime(last[2])}, revision ${last.first} (now ${e.revision})'
                  else if (last != null)
                    'Last copy at revision ${last.first} (now ${e.revision})',
                ].join('\n'),
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
                e.backupFolder.isEmpty ? 'Choose folder…' : 'Change folder…',
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
        if (savedCopy != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              liveRegion: true,
              child: SelectableText('Copy saved to $savedCopy', style: muted),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: savingCopy
                  ? null
                  : () async {
                      setState(() => savingCopy = true);
                      final path = await actions.saveCopy();
                      if (!mounted) return;
                      setState(() {
                        savingCopy = false;
                        if (path != null) savedCopy = path;
                      });
                    },
              child: Text(savingCopy ? 'Saving copy…' : 'Save copy…'),
            ),
          ],
        ),
      ],
    );
  }
}
