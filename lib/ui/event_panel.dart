import '../application/member_lookup.dart';
import '../domain/fide.dart';
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
/// Workspace-state key naming the field or group the event panel should
/// show when it opens next; `tiebreaks` is the Standings group.
const eventPanelFocusKey = 'event-panel-focus';

class EventPanel extends StatefulWidget {
  const EventPanel({
    required this.controller,
    required this.onClose,
    this.initialField,
    this.backLabel,
    this.identityLookup = fetchMembership,
    this.memberSearch = searchMembers,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;
  final String? initialField;

  /// Set when the panel was opened from another one, which Close returns to.
  final String? backLabel;
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
    ('chiefArbiter', 'Chief arbiter', 1),
    ('chiefArbiterId', 'Chief arbiter FIDE ID', 1),
    ('deputy1', 'Deputy arbiter', 1),
    ('deputy1Id', 'Deputy arbiter FIDE ID', 1),
    ('deputy2', 'Second deputy arbiter', 1),
    ('deputy2Id', 'Second deputy FIDE ID', 1),
    ('federation', 'Federation (3 letters)', 1),
  ];

  /// FIDE registration fields, shown under their own heading once a
  /// section is FIDE rated.
  static const _fideFields = {
    'chiefArbiter',
    'chiefArbiterId',
    'deputy1',
    'deputy1Id',
    'deputy2',
    'deputy2Id',
    'federation',
  };
  final text = {for (final f in _fields) f.$1: TextEditingController()};
  String? error;
  late FormDraft draft;
  final fieldFocus = <String, FocusNode>{};
  static const _tiebreaksPref = 'event-panel-group-tiebreaks';

  /// US Chess report fields, left out of an event no section of which is
  /// US Chess rated (a FIDE-only event).
  static const _usChessFields = {'td', 'atd', 'otherTds', 'affiliate'};

  bool get usChessRated =>
      c.event!.sections.isEmpty ||
      c.event!.sections.any((s) => !s.unrated) ||
      c.event!.tdId.isNotEmpty;

  /// The Tie-breaks group: closed unless the TD opened it before or asked
  /// for it (the section panel's link).
  bool tiebreaksOpen = false;

  /// Deputies are optional for FIDE registration: folded unless recorded
  /// or asked for.
  late bool deputiesOpen =
      c.event!.fide.deputies.isNotEmpty || widget.initialField == 'deputies';

  bool get fideSections =>
      hasFideSection(c.event!) || c.event!.fideTiebreaks.isNotEmpty;

  /// Sections ranked under US Chess rules (any that are not FIDE rated).
  bool get usChessSections =>
      c.event!.sections.isEmpty ||
      c.event!.sections.any((s) => !s.fideRated) ||
      c.event!.tiebreaks.isNotEmpty;
  TournamentController get c => widget.controller;
  Map<String, String> get values => text.map((k, v) => MapEntry(k, v.text));
  bool get dirty => !mapEquals(values, stored);

  Map<String, String> get stored {
    final e = c.event!;
    final deputies = e.fide.deputies;
    FideOfficial deputy(int i) =>
        i < deputies.length ? deputies[i] : const FideOfficial();
    return {
      'chiefArbiter': e.fide.chiefArbiter.name,
      'chiefArbiterId': e.fide.chiefArbiter.id,
      'deputy1': deputy(0).name,
      'deputy1Id': deputy(0).id,
      'deputy2': deputy(1).name,
      'deputy2Id': deputy(1).id,
      'federation': e.fide.federation,
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
    // A section panel's "Tie-breaks · Event details" link asks for the
    // Standings group through the workspace state, since the panel opens
    // from the workspace rather than from that link.
    final requested = c.workspaceState.read(eventPanelFocusKey);
    tiebreaksOpen =
        c.workspaceState.read(_tiebreaksPref) == 'open' ||
        widget.initialField == 'tiebreaks' ||
        requested == 'tiebreaks';
    if (requested != null && requested.isNotEmpty) {
      c.workspaceState.write(eventPanelFocusKey, '');
    }
    focusField(
      widget.initialField ??
          (requested != null && requested.isNotEmpty ? requested : 'name'),
    );
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
      for (final key in ['chiefArbiterId', 'deputy1Id', 'deputy2Id']) {
        final id = v[key]!.trim();
        if (id.isNotEmpty && id != stored[key] && !isFideId(id)) {
          throw TournamentException(
            'A FIDE ID is digits only (${_fields.firstWhere((f) => f.$1 == key).$2}).',
          );
        }
      }
      final federation = v['federation']!.trim().toUpperCase();
      if (federation.isNotEmpty && !isFederationCode(federation)) {
        throw const TournamentException(
          'The federation is a three-letter FIDE code, like USA.',
        );
      }
      final fide = FideRegistration(
        federation: federation,
        chiefArbiter: FideOfficial(
          name: v['chiefArbiter']!.trim(),
          id: v['chiefArbiterId']!.trim(),
        ),
        deputies: [
          for (final n in [1, 2])
            if (FideOfficial(
                  name: v['deputy$n']!.trim(),
                  id: v['deputy${n}Id']!.trim(),
                )
                case final d when !d.isEmpty)
              d,
          // The panel edits two deputies; more (from automation) are kept.
          ...c.event!.fide.deputies.skip(2),
        ],
      );
      c.change(
        'Edit event details',
        c.event!.copy(
          fide: fide,
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

  /// A FIDE registration field: saved with the event fields by Save.
  Widget fideField(String key, String label) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 8),
    child: TextField(
      key: ValueKey('event-$key'),
      controller: text[key],
      focusNode: fieldFocus.putIfAbsent(key, () => FocusNode(debugLabel: key)),
      textCapitalization: key == 'federation'
          ? TextCapitalization.characters
          : TextCapitalization.words,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => commit(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    const role = TextStyle(fontWeight: FontWeight.w600);
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
    final showFide =
        hasFideSection(c.event!) ||
        !c.event!.fide.isEmpty ||
        _fideFields.any(draft.isEdited);
    return SidePanel(
      title: 'Event details',
      onClose: widget.onClose,
      backLabel: widget.backLabel,
      children: [
        DraftStatus(draft: draft),
        for (final (key, label, lines) in _fields)
          if (!_fideFields.contains(key) &&
              (usChessRated || !_usChessFields.contains(key))) ...[
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
        // FIDE registration, shown once a section is FIDE rated: short
        // labels under each role so nothing clips at large text.
        if (showFide) ...[
          heading('FIDE'),
          Text('Chief arbiter', style: role),
          fideField('chiefArbiter', 'Name'),
          fideField('chiefArbiterId', 'FIDE ID'),
          fideField('federation', 'Event federation'),
          DisclosureGroup(
            key: const ValueKey('group-deputies'),
            headerKey: const ValueKey('event-group-deputies'),
            title: 'Deputy arbiters',
            open: deputiesOpen,
            onToggle: () => setState(() => deputiesOpen = !deputiesOpen),
            summary: [
              for (final n in ['deputy1', 'deputy2'])
                if (text[n]!.text.trim().isNotEmpty) text[n]!.text.trim(),
            ].join(', ').ifEmpty('None'),
            children: [
              for (final n in [1, 2]) ...[
                Text(n == 1 ? 'First deputy' : 'Second deputy', style: role),
                fideField('deputy$n', 'Name'),
                fideField('deputy${n}Id', 'FIDE ID'),
              ],
            ],
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
        Focus(
          focusNode: fieldFocus.putIfAbsent(
            'tiebreaks',
            () => FocusNode(debugLabel: 'tiebreaks'),
          ),
          child: DisclosureGroup(
            key: const ValueKey('group-tiebreaks'),
            headerKey: const ValueKey('event-group-tiebreaks'),
            title: 'Tie-breaks',
            open: tiebreaksOpen,
            onToggle: () => setState(() {
              tiebreaksOpen = !tiebreaksOpen;
              c.workspaceState.write(
                _tiebreaksPref,
                tiebreaksOpen ? 'open' : 'closed',
              );
            }),
            summary: [
              if (usChessSections)
                c.event!.useTiebreaks
                    ? TiebreakOrderEditor.summary(c.event!, fide: false)
                    : 'Off · ties share a place',
              if (fideSections)
                'FIDE: ${TiebreakOrderEditor.summary(c.event!, fide: true)}',
            ].join(' · '),
            children: [
              if (usChessSections) ...[
                SwitchListTile(
                  key: const ValueKey('event-use-tiebreaks'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    fideSections
                        ? 'Break ties in US Chess sections'
                        : 'Break ties',
                  ),
                  subtitle: Text(
                    c.event!.useTiebreaks
                        ? 'Standings rank tied players by this order.'
                        : 'Tied players share a place.',
                    style: muted,
                  ),
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
                if (c.event!.useTiebreaks)
                  TiebreakOrderEditor(
                    controller: c,
                    onError: (message) => setState(() => error = message),
                  ),
              ],
              if (fideSections) ...[
                Padding(
                  padding: EdgeInsets.only(
                    top: usChessSections ? 20 : 4,
                    bottom: 4,
                  ),
                  child: Text(
                    'FIDE-rated sections',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Always break ties, in this order.',
                    style: muted,
                  ),
                ),
                TiebreakOrderEditor(
                  key: const ValueKey('event-fide-tiebreaks'),
                  controller: c,
                  fide: true,
                  onError: (message) => setState(() => error = message),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
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

/// Rule 34B (US Chess) or C.07 (FIDE): the announced tie-break order,
/// edited in place with undo. The order reads as a short numbered list;
/// methods are added from one select, moved up or down, or removed. An
/// empty list is the default order for each section's format.
class TiebreakOrderEditor extends StatelessWidget {
  const TiebreakOrderEditor({
    required this.controller,
    required this.onError,
    this.fide = false,
    super.key,
  });
  final TournamentController controller;
  final ValueChanged<String> onError;

  /// Edits the FIDE (C.07) order of the FIDE-rated sections instead of the
  /// US Chess rule 34 order.
  final bool fide;

  /// The order a TD sees and edits: the announced list, or the default for
  /// the event's first section format.
  static List<String> shownOrder(Event e, {required bool fide}) {
    final chosen = fide ? e.fideTiebreaks : e.tiebreaks;
    if (chosen.isNotEmpty) return chosen;
    final format =
        e.sections
            .where((s) => !fide || s.fideRated)
            .map(pairingFormat)
            .firstOrNull ??
        Format.swiss;
    return [
      for (final m
          in fide ? defaultFideTiebreaks(format) : defaultTiebreaks(format))
        m.code,
    ];
  }

  /// The closed summary: "Default order" or the methods' short names.
  static String summary(Event e, {required bool fide}) {
    final chosen = fide ? e.fideTiebreaks : e.tiebreaks;
    if (chosen.isEmpty) return fide ? 'Suggested order' : 'US Chess default';
    final names = [for (final c in chosen) tiebreakMethod(c)?.short ?? c];
    return names.length <= 3
        ? names.join(', ')
        : '${names.take(3).join(', ')} +${names.length - 3}';
  }

  void apply(BuildContext context, List<String> next) {
    FocusScope.of(context).unfocus();
    try {
      final e = controller.event!;
      controller.change(
        fide ? 'Change FIDE tie-break order' : 'Change tie-break order',
        fide ? e.copy(fideTiebreaks: next) : e.copy(tiebreaks: next),
      );
    } catch (err) {
      onError(plainMessage(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = controller.event!;
    final custom = (fide ? e.fideTiebreaks : e.tiebreaks).isNotEmpty;
    final order = shownOrder(e, fide: fide);
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    final prefix = 'event-${fide ? 'fide-' : ''}tiebreak';
    final formats = {
      for (final s in e.sections)
        if (!fide || s.fideRated) pairingFormat(s),
    };
    // The variants of a FIDE method (BH, BH/C1, BH/C1/P…); a US Chess
    // method has none.
    List<TiebreakMethod> variants(String code) {
      final m = tiebreakMethod(code);
      if (!fide || m == null || !m.fide) return const [];
      return [
        for (final v in TiebreakMethod.values)
          if (v.fide && v.base == m.base) v,
      ];
    }

    void move(int from, int to) {
      final next = [...order]..insert(to, order[from]);
      next.removeAt(from < to ? from : from + 1);
      apply(context, next);
    }

    Widget icon(IconData glyph, String tip, VoidCallback? onPressed, Key key) =>
        IconButton(
          key: key,
          icon: Icon(glyph, size: 18),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, code) in order.indexed)
          Container(
            key: ValueKey('$prefix-$i'),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '${i + 1}',
                    style: muted.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: variants(code).length > 1
                      // A FIDE method with modifiers (Cut-1, Median-2,
                      // forfeits as played…) picks its variant in place.
                      ? PlainSelect<String>(
                          key: ValueKey('$prefix-$i-variant'),
                          dense: true,
                          value: code,
                          options: [
                            for (final m in variants(code))
                              if (m.code == code || !order.contains(m.code))
                                SelectOption(m.code, '${m.label} · ${m.short}'),
                          ],
                          onChanged: (v) => apply(context, [...order]..[i] = v),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: tiebreakLabel(code)),
                                TextSpan(
                                  text:
                                      '  ${tiebreakMethod(code)?.short ?? ''}',
                                  style: muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                icon(
                  Icons.arrow_upward,
                  'Move ${tiebreakLabel(code)} up',
                  i == 0 ? null : () => move(i, i - 1),
                  ValueKey('$prefix-$i-up'),
                ),
                icon(
                  Icons.arrow_downward,
                  'Move ${tiebreakLabel(code)} down',
                  i == order.length - 1 ? null : () => move(i, i + 2),
                  ValueKey('$prefix-$i-down'),
                ),
                icon(
                  Icons.close,
                  'Remove ${tiebreakLabel(code)}',
                  order.length == 1
                      ? null
                      : () => apply(context, [...order]..removeAt(i)),
                  ValueKey('$prefix-$i-remove'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        PlainSelect<String>(
          key: ValueKey('$prefix-add'),
          label: 'Add a method',
          value: '',
          options: [
            const SelectOption('', 'Choose a method'),
            if (fide)
              // One entry per FIDE method; its row then offers the
              // variants. Adding takes the first variant not yet listed.
              for (final base in {
                for (final m in TiebreakMethod.values)
                  if (m.fide) m.base,
              })
                if (TiebreakMethod.values
                        .where((m) => m.fide && m.base == base)
                        .firstWhere(
                          (m) => !order.contains(m.code),
                          orElse: () => TiebreakMethod.coinFlip,
                        )
                    case final m when m.fide)
                  SelectOption(m.code, '${tiebreakLabel(base)} · $base')
                else
                  for (final m in TiebreakMethod.values)
                    if (!m.fide && !order.contains(m.code))
                      SelectOption(m.code, '${m.label} · ${m.short}'),
          ],
          onChanged: (code) {
            if (code.isNotEmpty) apply(context, [...order, code]);
          },
        ),
        if (custom)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: ValueKey('$prefix-default'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              onPressed: () => apply(context, const []),
              child: Text(
                fide ? 'Use the suggested order' : 'Use the US Chess default',
              ),
            ),
          )
        else if (formats.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Each format keeps its own default until you change the order.',
              style: muted,
            ),
          ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
