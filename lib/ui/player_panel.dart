import '../application/member_lookup.dart';
import 'rating_settings.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/membership.dart';
import 'membership_style.dart';
import '../domain/us_chess.dart';
import 'drafts.dart';
import 'theme.dart';
import '../infrastructure/member_directory.dart';
import 'member_identity_lookup.dart';
import '../domain/member_observation.dart';

import 'player_actions.dart';
import 'side_panel.dart';
import 'player_format.dart';
import 'rating_refresh.dart';
import 'rating_review_panel.dart';

class PlayerPanel extends StatefulWidget {
  const PlayerPanel({
    required this.controller,
    required this.onClose,
    this.player,
    this.sectionId,
    this.memberLookup = fetchMember,
    this.identityLookup = fetchMembership,
    this.memberSearch = searchMembers,
    this.focusField,
    this.ratingReview,
    this.onBackToReview,
    super.key,
  });
  final TournamentController controller;
  final String? focusField;

  /// An open USCF rating review. The player stays fully editable; this
  /// player's proposal shows under the Rating field.
  final RatingRefresh? ratingReview;
  final VoidCallback? onBackToReview;

  /// Where a new player goes by default: the section on screen.
  final String? sectionId;

  /// Null to add a new player.
  final Player? player;
  final MemberLookup memberLookup;
  final MemberLookup identityLookup;
  final Future<List<MemberObservation>> Function(String) memberSearch;
  final VoidCallback onClose;
  @override
  State<PlayerPanel> createState() => PlayerPanelState();
}

class PlayerPanelState extends State<PlayerPanel> {
  static const _fields = [
    ('name', 'Full name', 1),
    ('memberId', 'US Chess ID', 1),
    ('rating', 'Rating', 1),
    ('state', 'State (2 letters)', 1),
    ('reportName', 'Name on rating report', 1),
    ('team', 'Team', 1),
    ('notes', 'Notes', 3),
  ];
  final text = {for (final f in _fields) f.$1: TextEditingController()};
  final fieldFocus = {for (final f in _fields) f.$1: FocusNode()};

  /// Collapsible groups below the identity fields. Adding a player keeps
  /// the extras under one "More details" group so a walk-up stays quick.
  static const _groups = [
    'byes',
    'uschess',
    'requests',
    'team',
    'notes',
    'more',
  ];
  final groupFocus = {for (final g in _groups) g: FocusNode()};

  /// Groups open in this panel. A TD's own open/close choice is remembered
  /// across players; otherwise a group opens where it is likely needed.
  final expanded = <String>{};

  String? groupOf(String field) => widget.player == null
      ? switch (field) {
          'state' || 'reportName' || 'team' || 'notes' => 'more',
          _ => null,
        }
      : switch (field) {
          'reportName' => 'uschess',
          'team' => 'team',
          'notes' => 'notes',
          'byes' => 'byes',
          'avoid' => 'requests',
          _ => null,
        };

  String _groupPref(String group) => 'player-panel-group-$group';

  void openGroups() {
    expanded.clear();
    final e = c.event!, p = widget.player;
    final s = p == null ? null : e.sectionOf(p.id);
    bool byDefault(String group) => switch (group) {
      'byes' => s == null || s.format == Format.swiss,
      'uschess' =>
        p != null &&
            MembershipSummary(p, eventDate: e.lastDate).severity !=
                MembershipSeverity.normal,
      _ => false,
    };
    for (final group in _groups) {
      final saved = c.workspaceState.read(_groupPref(group));
      if (saved == null ? byDefault(group) : saved == 'open') {
        expanded.add(group);
      }
    }
    // A restored draft or move shows where it was being edited.
    for (final (key, _, _) in _fields) {
      if (groupOf(key) case final group? when draft.isEdited(key)) {
        expanded.add(group);
      }
    }
    moving = moveTo != null;
    if (groupOf(widget.focusField ?? '') case final group?) {
      expanded.add(group);
    }
  }

  void toggleGroup(String group) {
    final open = !expanded.contains(group);
    setState(() => open ? expanded.add(group) : expanded.remove(group));
    c.workspaceState.write(_groupPref(group), open ? 'open' : 'closed');
  }

  void focusRequestedField() {
    final field = widget.focusField ?? 'name';
    final group = groupOf(field);
    if (group != null && !expanded.contains(group)) {
      setState(() => expanded.add(group));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node =
          fieldFocus[field] ?? (group == null ? null : groupFocus[group]);
      if (node == null) return;
      node.requestFocus();
      if (node.context != null) {
        Scrollable.ensureVisible(node.context!, alignment: 0.2);
      }
    });
  }

  final reason = TextEditingController();
  late FormDraft draft;
  final joinDraft = TextEditingController();
  final moveTarget = TextEditingController();
  String? error;

  /// The move form under the action row is open.
  bool moving = false;

  /// The chosen destination, and in a quad who exchanges places.
  String? moveTo;
  String? swapWith;
  int? moveRevision;
  String? pendingRating;
  Event? lookupSnapshot;

  /// US Chess lookup: in progress, result, or failure message.
  bool looking = false;
  MemberObservation? member;
  String? lookupError;
  int _lookupGeneration = 0;
  String _lastMemberIdText = '';

  void invalidateLookup() {
    _lookupGeneration++;
    looking = false;
    member = null;
    lookupSnapshot = null;
    pendingRating = null;
    lookupError = null;
  }

  void memberIdChanged() {
    final value = text['memberId']!.text;
    if (value == _lastMemberIdText) return;
    _lastMemberIdText = value;
    setState(invalidateLookup);
  }

  bool applyMember(MemberObservation observation, void Function(Player) save) {
    if (member != observation || widget.player == null) return false;
    final player = fresh;
    if (player.memberId != observation.id ||
        text['memberId']!.text.trim() != observation.id) {
      return false;
    }
    return attempt(() => save(player));
  }

  /// The last player added, confirmed under the add form.
  String? added;

  /// The section a new player joins; null leaves them unsectioned.
  late String? joinSection = widget.sectionId;

  TournamentController get c => widget.controller;
  Map<String, String> get values => text.map((k, v) => MapEntry(k, v.text));
  bool get dirty => !mapEquals(values, stored(widget.player));

  static Map<String, String> stored(Player? p) => {
    'name': p?.name ?? '',
    'memberId': p?.memberId ?? '',
    'rating': p == null ? '' : ratingText(p.rating),
    'state': p?.state ?? '',
    'reportName': p?.reportName ?? '',
    'team': p?.team ?? '',
    'notes': p?.notes ?? '',
  };

  void load() {
    final v = stored(widget.player);
    for (final e in text.entries) {
      e.value.text = v[e.key]!;
    }
    error = null;
  }

  @override
  void initState() {
    super.initState();
    load();
    restoreDraft();
    _lastMemberIdText = text['memberId']!.text;
    text['memberId']!.addListener(memberIdChanged);
    openGroups();
    focusRequestedField();
  }

  void restoreDraft() {
    draft = FormDraft(
      c.workspaceState,
      'draft-player-${widget.player?.id ?? 'new'}',
      {
        ...text,
        'join': joinDraft,
        'moveReason': reason,
        'moveTarget': moveTarget,
      },
      {
        ...stored(widget.player),
        'join': widget.sectionId ?? '',
        'moveReason': '',
        'moveTarget': '',
      },
    );
    moveTo = c.event!.sections.any((s) => s.id == moveTarget.text)
        ? moveTarget.text
        : null;
    joinSection = joinDraft.text.isEmpty ? null : joinDraft.text;
    if (!c.event!.sections.any((s) => s.id == joinSection)) joinSection = null;
  }

  void discardDraft() {
    draft.reset({
      ...stored(widget.player),
      'join': widget.sectionId ?? '',
      'moveReason': '',
      'moveTarget': '',
    });
    joinSection = widget.sectionId;
    moveTo = null;
    swapWith = null;
    moving = false;
    setState(() => error = null);
  }

  @override
  void didUpdateWidget(PlayerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.focusField != widget.focusField ||
        old.player?.id != widget.player?.id) {
      focusRequestedField();
    }
    if (old.controller != widget.controller ||
        old.player?.id != widget.player?.id ||
        (old.player?.memberId != widget.player?.memberId &&
            widget.player?.memberId != text['memberId']!.text.trim())) {
      invalidateLookup();
    }
    if (old.player?.id != widget.player?.id) {
      draft.dispose();
      moving = false;
      moveTo = null;
      swapWith = null;
      moveRevision = null;
      reason.clear();
      member = null;
      lookupError = null;
      load();
      restoreDraft();
      openGroups();
    } else {
      draft.reconcile(stored(widget.player));
    }
  }

  @override
  void dispose() {
    draft.dispose();
    for (final node in [...fieldFocus.values, ...groupFocus.values]) {
      node.dispose();
    }
    joinDraft.dispose();
    moveTarget.dispose();
    for (final t in text.values) {
      t.dispose();
    }
    reason.dispose();
    super.dispose();
  }

  Player get fresh => c.event!.player(widget.player!.id);

  /// Runs a change, showing any failure in the panel.
  bool attempt(void Function() change) {
    try {
      change();
      if (error != null) setState(() => error = null);
      return true;
    } catch (e) {
      setState(() => error = plainMessage(e));
      return false;
    }
  }

  /// Saves pending field edits. Returns false and shows why if invalid.
  bool commit() {
    final adding = widget.player == null;
    final current = stored(adding ? null : fresh);
    late Map<String, String> v;
    if (!attempt(() {
      v = draft.prepareSave(
        current,
        labels: {for (final field in _fields) field.$1: field.$2},
      );
    })) {
      return false;
    }
    if (!_fields.any((field) => draft.isEdited(field.$1))) return true;
    ({String? into, String? problem}) joined = (into: null, problem: null);
    final ok = attempt(() {
      final rating = parseRating(v['rating']!);
      if (v['name']!.trim().isEmpty) {
        throw const TournamentException('Enter the player\'s name.');
      }
      if (rating == null) {
        throw const TournamentException('Enter a rating number, or UNR.');
      }
      final state = v['state']!.trim().toUpperCase();
      if (state.isNotEmpty && !isStateCode(state)) {
        throw const TournamentException(
          'Enter the state as two letters, like MA.',
        );
      }
      final saved = (adding ? Player(id: c.newId(), name: '') : fresh).copy(
        name: v['name']!.trim(),
        memberId: v['memberId']!.trim(),
        rating: rating,
        state: state,
        reportName: v['reportName']!.trim(),
        team: v['team']!.trim(),
        notes: v['notes']!,
      );
      c.savePlayer(saved);
      if (adding) joined = joinNew(saved);
      // Show the saved capitals rather than leaving the panel looking unsaved.
      if (!adding) text['state']!.text = state;
      draft.reset({
        ...stored(adding ? null : saved),
        'join': joinSection ?? '',
        'moveReason': reason.text,
        'moveTarget': moveTarget.text,
      });
    });
    // The add form clears for the next player.
    if (ok && adding) {
      setState(() {
        added = joined.into == null
            ? v['name']!.trim()
            : '${v['name']!.trim()} to ${joined.into}';
        load();
        error = joined.problem;
      });
      fieldFocus['name']!.requestFocus();
    }
    return ok;
  }

  /// Puts a walk-up straight into [joinSection]. Returns where they went,
  /// or, when that cannot happen yet, why; the player stays added either way.
  ({String? into, String? problem}) joinNew(Player p) {
    final s = c.event!.sections.where((s) => s.id == joinSection).firstOrNull;
    if (s == null) return (into: null, problem: null);
    try {
      c.movePlayers([p.id], s.id, reason: s.rounds.isEmpty ? '' : 'Late entry');
      return (into: s.name, problem: null);
    } catch (error) {
      return (
        into: null,
        problem:
            'Added ${p.name}, but not to ${s.name} yet. ${plainMessage(error)}',
      );
    }
  }

  void pickSection(String? target) {
    if (target == null || !commit()) return;
    setState(() {
      moving = true;
      moveTo = target;
      moveTarget.text = target;
      moveRevision = c.event!.revision;
      swapWith = null;
    });
  }

  void confirmMove() {
    if (moveRevision != null && moveRevision != c.event!.revision) {
      setState(() {
        error = 'The event changed. Choose the section and review again.';
        moveTo = null;
        swapWith = null;
      });
      return;
    }
    if (attempt(
      () => swapWith != null
          ? c.swapPlayers(
              widget.player!.id,
              swapWith!,
              moveRevision ?? c.event!.revision,
            )
          : c.movePlayers(
              [widget.player!.id],
              moveTo!,
              reason: reason.text.trim(),
            ),
    )) {
      cancelMove();
    }
  }

  void cancelMove() => setState(() {
    moving = false;
    moveTo = null;
    swapWith = null;
    moveTarget.clear();
    reason.clear();
  });

  Future<void> lookup() async {
    if (!commit()) return;
    final controller = c;
    final playerId = fresh.id, memberId = fresh.memberId;
    final eventId = controller.event!.id;
    final generation = ++_lookupGeneration;
    bool current() =>
        mounted &&
        generation == _lookupGeneration &&
        c == controller &&
        c.event?.id == eventId &&
        widget.player?.id == playerId &&
        text['memberId']!.text.trim() == memberId &&
        c.event!.players.any((p) => p.id == playerId && p.memberId == memberId);
    setState(() {
      expanded.add('uschess');
      looking = true;
      lookupSnapshot = c.event!;
      pendingRating = null;
      member = null;
      lookupError = null;
    });
    try {
      final found = await widget.memberLookup(memberId);
      if (!current()) return;
      if (found?.id == memberId) {
        c.recordMembership(eventId, playerId, found!.toJson());
      }
      setState(() {
        member = found?.id == memberId ? found : null;
        if (found == null) lookupError = 'key';
        if (found != null && found.id != memberId) {
          lookupError = 'The returned member does not match the requested ID.';
        }
      });
    } catch (e) {
      if (current()) setState(() => lookupError = plainMessage(e));
    } finally {
      if (current()) setState(() => looking = false);
    }
  }

  Widget field(String key) {
    final (_, label, lines) = _fields.firstWhere((f) => f.$1 == key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: TextField(
            key: ValueKey('panel-$key'),
            controller: text[key],
            focusNode: fieldFocus[key],
            autofocus: key == (widget.focusField ?? 'name'),
            maxLines: lines,
            textCapitalization: key == 'state'
                ? TextCapitalization.characters
                : TextCapitalization.none,
            decoration: InputDecoration(
              labelText: label,
              alignLabelWithHint: lines > 1,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => commit(),
          ),
        ),
        if (key == 'memberId')
          MemberIdentityLookup(
            key: ValueKey('player-identity-${widget.player?.id ?? 'new'}'),
            id: text['memberId']!,
            name: text['name'],
            lookup: (id) => widget.identityLookup(id),
            search: widget.memberSearch,
            onSelected: (member) => setState(() {
              text['memberId']!.text = member.id;
            }),
          ),
      ],
    );
  }

  /// A group's closed summary: the value, or "None".
  String summaryOf(String key) {
    final value = text[key]!.text.trim();
    return value.isEmpty ? 'None' : value.split('\n').first;
  }

  DisclosureGroup group(
    String id,
    String title,
    List<Widget> children, {
    String? summary,
    Color? summaryColor,
  }) => DisclosureGroup(
    key: ValueKey('group-$id'),
    title: title,
    open: expanded.contains(id),
    onToggle: () => toggleGroup(id),
    focusNode: groupFocus[id],
    summary: summary,
    summaryColor: summaryColor,
    children: children,
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    final problem = error == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(error!, style: TextStyle(color: colors.error)),
          );
    void close() => widget.onClose();

    final player = widget.player;
    if (player == null) {
      return SidePanel(
        title: 'Add player',
        onClose: close,
        children: [
          DraftStatus(draft: draft),
          field('name'),
          field('memberId'),
          field('rating'),
          if (c.event!.sections.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: DropdownButtonFormField<String?>(
                key: const ValueKey('panel-join-section'),
                initialValue: joinSection,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Section'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Not in a section yet'),
                  ),
                  for (final s in c.event!.sections)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() {
                  joinSection = v;
                  joinDraft.text = v ?? '';
                }),
              ),
            ),
          group(
            'more',
            'More details',
            [
              field('state'),
              field('reportName'),
              field('team'),
              field('notes'),
            ],
            summary:
                [
                  for (final key in ['state', 'reportName', 'team', 'notes'])
                    if (text[key]!.text.trim().isNotEmpty) key,
                ].isEmpty
                ? 'State, team, notes'
                : 'Filled in',
          ),
          const SizedBox(height: 12),
          ?problem,
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                FilledButton(onPressed: commit, child: const Text('Add')),
                TextButton(
                  onPressed: discardDraft,
                  child: const Text('Discard draft'),
                ),
              ],
            ),
          ),
          if (added != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Added $added. Enter the next player, or close.',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
        ],
      );
    }
    final e = c.event!, p = player, s = e.sectionOf(p.id);
    final membership = MembershipSummary(p, eventDate: e.lastDate);
    final checkedAt = p.membershipEvidence['id'] == p.memberId
        ? DateTime.tryParse('${p.membershipEvidence['retrievedAt']}')
        : null;
    final checked = checkedAt != null && p.memberId.isNotEmpty;
    final open = openRounds(e, p);
    final avoided = [
      for (final other in e.players)
        if (other.id != p.id &&
            (p.avoid.contains(other.id) || other.avoid.contains(p.id)))
          other,
    ];
    final byes = [
      for (final r in open)
        if (p.byes[r] case final points?) 'R$r ${halves(points)}',
    ];
    final move = MoveFields(
      event: e,
      playerId: p.id,
      target: moveTo,
      swapWith: swapWith,
      reason: reason,
      onTarget: pickSection,
      onSwap: (v) => setState(() => swapWith = v),
      onSubmit: confirmMove,
    );
    final fact = TextStyle(fontSize: 13, color: colors.onSurface);
    TableRow factRow(String label, String value, {Color? color}) => TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 16, bottom: 4),
          child: Text(label, style: muted),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(value, style: fact.copyWith(color: color)),
        ),
      ],
    );

    return SidePanel(
      title: p.name,
      onClose: close,
      footer: [
        if (dirty || error != null) ...[
          ?problem,
          if (dirty)
            Wrap(
              spacing: 8,
              children: [
                FilledButton(onPressed: commit, child: const Text('Save')),
                TextButton(
                  onPressed: discardDraft,
                  child: const Text('Discard draft'),
                ),
              ],
            ),
        ],
      ],
      children: [
        DraftStatus(draft: draft),
        // Who this is and the two decisions TDs make about a player mid-event.
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${s?.name ?? 'Not in a section'} · ${ratingText(p.rating)}',
              style: muted,
            ),
            if (p.withdrawn) const StatusPill('Withdrawn'),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const ValueKey('panel-withdraw'),
              onPressed: () => attempt(
                () => c.savePlayer(fresh.copy(withdrawn: !p.withdrawn)),
              ),
              child: Text(
                p.withdrawn
                    ? 'Reinstate'
                    : ['Withdraw', ?withdrawAfter(e, p.id)].join(' '),
              ),
            ),
            if (e.sections.length > (s == null ? 0 : 1))
              OutlinedButton(
                key: const ValueKey('panel-move'),
                onPressed: moving
                    ? cancelMove
                    : () => setState(() => moving = true),
                child: const Text('Move…'),
              ),
          ],
        ),
        if (moving)
          Container(
            key: const ValueKey('panel-move-form'),
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                move,
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      key: const ValueKey('panel-confirm-move'),
                      onPressed: move.ready ? confirmMove : null,
                      child: const Text('Move'),
                    ),
                    TextButton(
                      onPressed: cancelMove,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        field('name'),
        field('memberId'),
        field('rating'),
        if (widget.ratingReview case final review? when review.active)
          PlayerRatingReview(
            draft: review,
            player: p,
            onBack: widget.onBackToReview ?? close,
          ),
        field('state'),
        const SizedBox(height: 8),
        // Withdrawn players take zero-point byes; the pill already says so.
        if (open.isNotEmpty && !p.withdrawn)
          group(
            'byes',
            'Byes',
            [
              ByeGrid(
                rounds: open,
                byes: p.byes,
                onToggle: (r, points) => attempt(
                  () => c.reserveBye(
                    p.id,
                    r,
                    p.byes[r] == points ? -1 : points,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            summary: byes.isEmpty ? 'None' : byes.join(' · '),
          ),
        group(
          'uschess',
          'US Chess',
          [
            Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: FlexColumnWidth(),
              },
              children: [
                factRow(
                  'Expires',
                  checked
                      ? [membership.label, ?membership.warning].join(' · ')
                      : membership.label,
                  color: membership.attention
                      ? membershipColor(colors, membership)
                      : null,
                ),
                if (checked)
                  factRow(
                    'Checked',
                    checkedAt.toIso8601String().substring(0, 10),
                  ),
                if (p.ratingEvidence['supplementDate'] case final date?)
                  factRow('Supplement', '$date')
                else if (p.ratingEvidence.isNotEmpty)
                  factRow(
                    'Registration',
                    '${p.ratingEvidence['registrationRating'] ?? p.rating}',
                  ),
              ],
            ),
            if (p.memberId.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('panel-member-lookup'),
                  onPressed: looking ? null : lookup,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(looking ? 'Checking…' : 'Refresh from US Chess'),
                ),
              ),
              if (lookupError == 'key')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Needs a US Chess API key.', style: muted),
                      const SizedBox(height: 8),
                      ApiKeyField(onSaved: lookup),
                    ],
                  ),
                )
              else if (lookupError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    lookupError!,
                    style: TextStyle(color: colors.error),
                  ),
                ),
              if (member case final m?) ...[
                const SizedBox(height: 12),
                Text(
                  m.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Supplement ${m.supplementDate ?? 'date unavailable'}',
                  style: muted,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (m.state case final st?
                        when isStateCode(st) && st != p.state)
                      ActionChip(
                        chipAnimationStyle: noChipAnimation,
                        label: Text('Use state $st'),
                        onPressed: () => applyMember(
                          m,
                          (player) => c.savePlayer(player.copy(state: st)),
                        ),
                      ),
                    if (m.reportName case final rn?
                        when rn != playerReportName(p))
                      ActionChip(
                        chipAnimationStyle: noChipAnimation,
                        label: Text('Report as $rn'),
                        tooltip:
                            'Use the US Chess spelling on the rating report',
                        onPressed: () => applyMember(
                          m,
                          (player) => c.savePlayer(player.copy(reportName: rn)),
                        ),
                      ),
                    if (m.name.isNotEmpty && m.name != p.name)
                      ActionChip(
                        chipAnimationStyle: noChipAnimation,
                        label: Text('Use name ${m.name}'),
                        onPressed: () => applyMember(
                          m,
                          (player) => c.savePlayer(player.copy(name: m.name)),
                        ),
                      ),
                    for (final r in m.ratings.entries)
                      if (r.value != null)
                        ActionChip(
                          chipAnimationStyle: noChipAnimation,
                          avatar: m.alreadyApplied(p, r.key)
                              ? const Icon(Icons.check, size: 16)
                              : null,
                          label: Text('${r.key} ${r.value}'),
                          tooltip: 'Review this rating for pairings',
                          onPressed:
                              m.alreadyApplied(p, r.key) ||
                                  (s?.rounds.isNotEmpty ?? false)
                              ? null
                              : () => setState(() => pendingRating = r.key),
                        ),
                  ],
                ),
                if (s?.rounds.isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Pairings are posted; the pairing rating stays.',
                      style: muted,
                    ),
                  ),
                if (pendingRating case final category?) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Confirm ${m.name} (${m.id}): ${p.rating} → ${m.ratings[category]} ($category).',
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      final snapshot = lookupSnapshot;
                      if (snapshot == null) return;
                      if (applyMember(
                        m,
                        (player) => c.applyReviewedRatings(
                          snapshot: snapshot,
                          observations: {player.id: m},
                          playerIds: {player.id},
                          category: category,
                        ),
                      )) {
                        setState(() => pendingRating = null);
                      }
                    },
                    child: const Text('Confirm rating change'),
                  ),
                ],
              ],
            ],
            const SizedBox(height: 16),
            field('reportName'),
          ],
          summary: checked ? 'Expires ${membership.label}' : membership.label,
          summaryColor: membershipColor(colors, membership),
        ),
        group(
          'requests',
          'Pairing requests',
          [
            for (final other in avoided)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    label: Text(other.name),
                    onDeleted: () =>
                        attempt(() => c.avoidPair(p.id, other.id, false)),
                    deleteButtonTooltipMessage:
                        'Allow pairing with ${other.name}',
                  ),
                ),
              ),
            // Typed, not scrolled: a club event has 100+ names.
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Autocomplete<Player>(
                key: ValueKey('avoid-${p.id}-${p.avoid.length}'),
                displayStringForOption: (o) => o.name,
                optionsBuilder: (value) {
                  final q = value.text.trim().toLowerCase();
                  if (q.isEmpty) return const [];
                  return e.players.where(
                    (o) =>
                        o.id != p.id &&
                        !p.avoid.contains(o.id) &&
                        o.name.toLowerCase().contains(q),
                  );
                },
                onSelected: (o) =>
                    attempt(() => c.avoidPair(p.id, o.id, true)),
                fieldViewBuilder: (context, text, focus, submit) => TextField(
                  key: const ValueKey('avoid-player'),
                  controller: text,
                  focusNode: focus,
                  decoration: const InputDecoration(
                    labelText: 'Avoid pairing with',
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ),
            ),
            if (avoided.isNotEmpty && s != null && s.format != Format.swiss)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Everyone meets in a ${s.format == Format.quad ? 'quad' : 'round robin'}; move one of them to keep this.',
                  style: TextStyle(fontSize: 13, color: attentionColor(colors)),
                ),
              ),
            const SizedBox(height: 8),
          ],
          summary: avoided.isEmpty
              ? 'None'
              : avoided.length <= 2
              ? 'Avoid ${avoided.map((o) => o.name).join(', ')}'
              : 'Avoid ${avoided.length} players',
        ),
        group('team', 'Team', [field('team')], summary: summaryOf('team')),
        group('notes', 'Notes', [field('notes')], summary: summaryOf('notes')),
      ],
    );
  }
}

/// Bye requests as a small table: rounds across, points down (0, ½, 1).
/// A chosen cell fills and shows its points; choosing it again clears it.
class ByeGrid extends StatelessWidget {
  const ByeGrid({
    required this.rounds,
    required this.byes,
    required this.onToggle,
    super.key,
  });
  final List<int> rounds;
  final Map<int, int> byes;

  /// Called with the round and the bye's points in halves.
  final void Function(int round, int points) onToggle;

  /// Rows in reading order; points are stored in halves.
  static const rows = [(0, '0'), (1, '½'), (2, '1')];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context);
    final cell = scale.scale(32);
    final caption = TextStyle(
      fontSize: 12,
      color: colors.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget label(String text, {TextStyle? style}) => SizedBox(
      height: cell,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: style),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        key: const ValueKey('bye-grid'),
        defaultColumnWidth: FixedColumnWidth(cell),
        columnWidths: {0: FixedColumnWidth(scale.scale(64))},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              label('Round', style: caption),
              for (final r in rounds)
                SizedBox(
                  height: scale.scale(24),
                  child: Center(child: Text('$r', style: caption)),
                ),
            ],
          ),
          for (final (points, mark) in rows)
            TableRow(
              key: ValueKey('panel-bye-$points'),
              children: [
                label(
                  '$mark pt',
                  style: const TextStyle(
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                for (final r in rounds)
                  ByeCell(
                    key: ValueKey('bye-$r-$points'),
                    mark: mark,
                    selected: byes[r] == points,
                    label: 'Round $r, $mark-point bye',
                    onPressed: () => onToggle(r, points),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// One cell of the bye grid. Empty until chosen; chosen fills with ink and
/// shows the points. The ring outside the cell shows keyboard focus.
class ByeCell extends StatefulWidget {
  const ByeCell({
    required this.mark,
    required this.selected,
    required this.label,
    required this.onPressed,
    super.key,
  });
  final String mark;
  final bool selected;
  final String label;
  final VoidCallback? onPressed;

  @override
  State<ByeCell> createState() => _ByeCellState();
}

class _ByeCellState extends State<ByeCell> {
  bool focused = false, hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final on = widget.selected;
    final side = MediaQuery.textScalerOf(context).scale(32);
    return Semantics(
      button: true,
      toggled: on,
      label: widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: widget.onPressed != null,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) => setState(() => focused = v),
        onShowHoverHighlight: (v) => setState(() => hovered = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: side,
            height: side,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: focused
                  ? Border.all(color: focusRing(colors), width: focusRingWidth)
                  : null,
            ),
            child: Container(
              width: side - 6,
              height: side - 6,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on
                    ? colors.onSurface
                    : hovered
                    ? colors.surfaceContainerHigh
                    : colors.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: on ? colors.onSurface : colors.outline,
                ),
              ),
              child: on
                  ? Text(
                      widget.mark,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.surface,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
