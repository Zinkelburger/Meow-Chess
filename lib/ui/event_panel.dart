import 'dart:math' as math;

import '../application/member_lookup.dart';
import '../domain/fixed_schedule.dart';
import '../domain/tiebreaks.dart';
import 'rating_settings.dart';
import 'select.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/us_chess.dart';
import '../domain/member_observation.dart';
import 'history_panel.dart' show historyTime;
import '../infrastructure/member_directory.dart';
import 'member_identity_lookup.dart';
import 'side_panel.dart';
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
  final MemberLookup identityLookup;
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
    ('notes', 'Notes', 4),
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
    try {
      final v = draft.prepareSave(
        stored,
        labels: {for (final field in _fields) field.$1: field.$2},
      );
      if (!draft.dirty) return true;
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
      // Checked like a section's time control, and only when changed.
      final time = v['time']!.trim();
      if (time.isNotEmpty && time != c.event!.timeControl.trim()) {
        TimeControl.parse(time);
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
          timeControl: time,
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
          // Rule 5E2: an unstated delay means the recommended minimum.
          if (key == 'time' && delayHint(text[key]!.text) != null)
            Padding(
              key: const ValueKey('event-time-hint'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(delayHint(text[key]!.text)!, style: muted),
            ),
          if (key == 'td' || key == 'atd')
            MemberIdentityLookup(
              key: ValueKey('event-identity-$key'),
              id: text[key]!,
              lookup: (id) => widget.identityLookup(id),
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
        TiebreakOrderEditor(
          controller: c,
          onError: (message) => setState(() => error = message),
        ),
        heading('Reporting'),
        // Chapter 10: online events are rated under the online categories
        // and are never dual-rated; the rating preflight says so.
        SwitchListTile(
          key: const ValueKey('event-online'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Online event'),
          subtitle: Text(
            'Rated under the online categories; never dual-rated (Chapter 10).',
            style: muted,
          ),
          value: c.event!.online,
          onChanged: (value) {
            FocusScope.of(context).unfocus();
            try {
              c.change(
                value ? 'Mark as online event' : 'Mark as over-the-board event',
                c.event!.copy(online: value),
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

/// Rule 34B: the posted tie-break order, edited in place with undo. Each
/// slot is a select; "US Chess default" in any slot clears the list back to
/// the rule 34E order for a Swiss and the 34F order for a round robin.
class TiebreakOrderEditor extends StatefulWidget {
  const TiebreakOrderEditor({
    required this.controller,
    required this.onError,
    super.key,
  });
  final TournamentController controller;
  final ValueChanged<String> onError;

  /// Rule 34B asks for at least two posted methods; four is the default
  /// list's length and as deep as the editor goes.
  static const slots = 4;

  @override
  State<TiebreakOrderEditor> createState() => _TiebreakOrderEditorState();
}

class _TiebreakOrderEditorState extends State<TiebreakOrderEditor> {
  static const _default = '', _remove = 'remove', _add = 'add';

  void apply(List<String> next) {
    FocusScope.of(context).unfocus();
    try {
      widget.controller.change(
        'Change tie-break order',
        widget.controller.event!.copy(tiebreaks: next),
      );
      setState(() {});
    } catch (e) {
      widget.onError(plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.controller.event!;
    final chosen = e.tiebreaks;
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    final shown = chosen.isEmpty
        ? 1
        : math.min(chosen.length + 1, TiebreakOrderEditor.slots);
    final formats = {
      for (final s in e.sections) pairingFormat(s),
      if (e.sections.isEmpty) Format.swiss,
    };
    String formatName(Format f) => switch (f) {
      Format.swiss => 'Swiss',
      Format.roundRobin => 'Round robin',
      Format.quad => 'Quad',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            'Order (rule 34B). Posted on the standings sheet before round 1.',
            style: muted,
          ),
        ),
        for (var i = 0; i < shown; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PlainSelect<String>(
              key: ValueKey('event-tiebreak-$i'),
              label: 'Tie-break ${i + 1}',
              hint: 'Add a method',
              value: i < chosen.length
                  ? chosen[i]
                  : chosen.isEmpty
                  ? _default
                  : _add,
              options: [
                const SelectOption(_default, 'US Chess default'),
                if (i < chosen.length)
                  const SelectOption(_remove, 'Remove from the order'),
                for (final m in TiebreakMethod.values)
                  if (!chosen.contains(m.code) ||
                      (i < chosen.length && chosen[i] == m.code))
                    SelectOption(m.code, '${m.label} (${m.rule})'),
              ],
              onChanged: (value) {
                if (value == _default) return apply(const []);
                final next = [...chosen];
                if (value == _remove) {
                  next.removeAt(i);
                } else if (i < next.length) {
                  next[i] = value;
                } else {
                  next.add(value);
                }
                apply(next);
              },
            ),
          ),
        if (chosen.isEmpty)
          for (final f in formats)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${formatName(f)} default: ${defaultTiebreaks(f).map((m) => '${m.label} (${m.rule})').join(', ')}.',
                style: muted,
              ),
            ),
      ],
    );
  }
}
