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
import '../infrastructure/ratings_api.dart';

import 'side_panel.dart';
import 'player_format.dart';

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
    super.key,
  });
  final TournamentController controller;
  final String? focusField;

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
    ('team', 'Team / mixed-doubles name', 1),
    ('notes', 'Private notes', 3),
  ];
  final text = {for (final f in _fields) f.$1: TextEditingController()};
  final fieldFocus = {for (final f in _fields) f.$1: FocusNode()};

  void focusRequestedField() {
    final node = fieldFocus[widget.focusField ?? 'name'];
    if (node == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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

  /// A move waiting for a reason, because play has started.
  String? moveTo;
  String? swapWith;
  int? moveRevision;
  String? pendingRating;
  int? lookupRevision;

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
    pendingRating = null;
    lookupError = null;
  }

  void memberIdChanged() {
    final value = text['memberId']!.text;
    if (value == _lastMemberIdText) return;
    _lastMemberIdText = value;
    setState(invalidateLookup);
  }

  void applyMember(MemberObservation observation, void Function(Player) save) {
    if (member != observation || widget.player == null) return;
    final player = fresh;
    if (player.memberId != observation.id ||
        text['memberId']!.text.trim() != observation.id) {
      return;
    }
    attempt(() => save(player));
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
      moveTo = null;
      swapWith = null;
      moveRevision = null;
      reason.clear();
      member = null;
      lookupError = null;
      load();
      restoreDraft();
    } else {
      draft.reconcile(stored(widget.player));
    }
  }

  @override
  void dispose() {
    draft.dispose();
    for (final node in fieldFocus.values) {
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
    draft.reconcile(current);
    final conflicts = draft.conflicts(current);
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
    if (!_fields.any((field) => draft.isEdited(field.$1))) return true;
    final v = values;
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
      setState(() {
        moveTo = null;
        moveTarget.clear();
        reason.clear();
      });
    }
  }

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
      looking = true;
      lookupRevision = c.event!.revision;
      pendingRating = null;
      member = null;
      lookupError = null;
    });
    try {
      final found = await widget.memberLookup(memberId);
      if (!current()) return;
      if (found?.id == memberId) {
        final unchanged = lookupRevision == c.event!.revision;
        c.recordMembership(eventId, playerId, found!.toJson());
        if (unchanged) lookupRevision = c.event!.revision;
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fields = [
      for (final (key, label, lines) in _fields) ...[
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
              suffixIcon: key == 'memberId' && widget.player != null
                  ? IconButton(
                      tooltip: 'Refresh monthly supplement',
                      onPressed: looking ? null : lookup,
                      icon: const Icon(Icons.refresh, size: 18),
                    )
                  : null,
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
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(error!, style: TextStyle(color: colors.error)),
        ),
    ];
    void close() => widget.onClose();

    final player = widget.player;
    if (player == null) {
      return SidePanel(
        title: 'Add player',
        onClose: close,
        children: [
          DraftStatus(draft: draft),
          ...fields,
          if (c.event!.sections.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
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
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    final membership = MembershipSummary(p, eventDate: e.lastDate);
    final checkedAt = p.membershipEvidence['id'] == p.memberId
        ? DateTime.tryParse('${p.membershipEvidence['retrievedAt']}')
        : null;
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
    // Byes can be requested for rounds not yet paired.
    final planned =
        s?.plannedRounds ??
        e.sections.fold<int>(
          0,
          (n, x) => x.plannedRounds > n ? x.plannedRounds : n,
        );
    final open = [
      for (var r = (s?.rounds.length ?? 0) + 1; r <= planned; r++) r,
    ];
    return SidePanel(
      title: p.name,
      onClose: close,
      children: [
        DraftStatus(draft: draft),
        if (p.withdrawn)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Withdrawn', style: muted),
          ),
        ...fields,
        if (dirty)
          Wrap(
            spacing: 8,
            children: [
              FilledButton(onPressed: commit, child: const Text('Save')),
              const SizedBox(width: 8),
              TextButton(
                onPressed: discardDraft,
                child: const Text('Discard draft'),
              ),
            ],
          ),
        if (p.ratingEvidence.isNotEmpty)
          Text(
            p.ratingEvidence['supplementDate'] != null
                ? 'Monthly supplement: ${p.ratingEvidence['supplementDate']}'
                : 'Registration rating: ${p.ratingEvidence['registrationRating'] ?? p.rating}',
          ),
        heading('US Chess'),
        Text(
          checkedAt != null && p.memberId.isNotEmpty
              ? 'Expires: ${membership.label}'
              : membership.label,
          style: TextStyle(color: membershipColor(colors, membership)),
        ),
        if (checkedAt != null && p.memberId.isNotEmpty)
          Text(
            'Checked: ${checkedAt.toIso8601String().substring(0, 10)}',
            style: muted,
          ),
        if (p.memberId.isEmpty)
          Text('Enter a US Chess ID to look the player up.', style: muted)
        else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: looking ? null : lookup,
              child: Text(looking ? 'Looking up…' : 'Look up ${p.memberId}'),
            ),
          ),
          if (lookupError == 'key')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Looking up IDs needs a US Chess API key.',
                    style: muted,
                  ),
                  const SizedBox(height: 8),
                  ApiKeyField(onSaved: lookup),
                ],
              ),
            )
          else if (lookupError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(lookupError!, style: TextStyle(color: colors.error)),
            ),
          if (member case final m?) ...[
            const SizedBox(height: 12),
            Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              'Monthly supplement: ${m.supplementDate ?? 'date unavailable'}',
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
                if (m.reportName case final rn? when rn != playerReportName(p))
                  ActionChip(
                    chipAnimationStyle: noChipAnimation,
                    label: Text('Report as $rn'),
                    tooltip: 'Use the US Chess spelling on the rating report',
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
              const Text('Pairings are posted. The pairing rating is kept.'),
            if (pendingRating case final category?) ...[
              const SizedBox(height: 12),
              Text(
                'Confirm ${m.name} (${m.id}): ${p.rating} → ${m.ratings[category]} ($category).',
              ),
              FilledButton(
                onPressed: () {
                  if (lookupRevision != c.event!.revision) {
                    setState(
                      () => lookupError =
                          'The event changed. Refresh and review again.',
                    );
                    return;
                  }
                  applyMember(
                    m,
                    (player) => c.savePlayer(
                      player.copy(
                        rating: m.ratings[category],
                        ratingEvidence: {
                          ...player.ratingEvidence,
                          ...m.toJson(),
                          'kind': 'monthly supplement',
                          'category': category,
                        },
                      ),
                    ),
                  );
                  setState(() => pendingRating = null);
                },
                child: const Text('Confirm rating change'),
              ),
            ],
          ],
        ],
        if (open.isNotEmpty) ...[
          heading('Byes'),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Points a requested bye scores in each round not yet paired.',
              style: muted,
            ),
          ),
          for (final r in open)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(width: 72, child: Text('Round $r')),
                  Expanded(
                    child: SegmentedButton<int>(
                      key: ValueKey('panel-bye-$r'),
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        padding: WidgetStatePropertyAll(EdgeInsets.zero),
                      ),
                      segments: const [
                        ButtonSegment(value: -1, label: Text('None')),
                        ButtonSegment(value: 1, label: Text('1/2')),
                        ButtonSegment(value: 0, label: Text('0')),
                        ButtonSegment(value: 2, label: Text('1')),
                      ],
                      selected: {p.byes[r] ?? -1},
                      onSelectionChanged: p.withdrawn
                          ? null
                          : (v) =>
                                attempt(() => c.reserveBye(p.id, r, v.single)),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (e.sections.isNotEmpty) ...[
          heading('Section'),
          DropdownButton<String>(
            key: const ValueKey('panel-section'),
            value: moveTo ?? s?.id,
            hint: const Text('Not in a section'),
            isExpanded: true,
            items: [
              for (final x in e.sections)
                DropdownMenuItem(value: x.id, child: Text(x.name)),
            ],
            onChanged: pickSection,
          ),
          if (moveTo != null) ...[
            const SizedBox(height: 8),
            Text(
              'Move ${p.name} from ${s?.name ?? 'Unassigned'} to ${e.sections.firstWhere((x) => x.id == moveTo).name}. Confirm below. A reason is required after play.',
              style: muted,
            ),
            if (s != null &&
                s.rounds.isEmpty &&
                e.sections
                    .firstWhere((x) => x.id == moveTo)
                    .rounds
                    .isEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: swapWith ?? '',
                key: ValueKey('swap-partner-$moveTo'),
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Move or exchange places',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Move without a swap'),
                  ),
                  for (final id
                      in e.sections.firstWhere((x) => x.id == moveTo).players)
                    if (id != p.id)
                      DropdownMenuItem(
                        value: id,
                        child: Text('Swap with ${e.player(id).name}'),
                      ),
                ],
                onChanged: (value) =>
                    setState(() => swapWith = value == '' ? null : value),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: reason,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason'),
              onSubmitted: (_) => confirmMove(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: confirmMove,
                  child: Text(
                    swapWith == null ? 'Confirm move' : 'Confirm swap',
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() {
                    moveTo = null;
                    moveTarget.clear();
                    reason.clear();
                  }),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ],
        heading('Pairing requests'),
        if (e.sections.any(
          (x) =>
              x.rounds.isEmpty &&
              !x.players.any(
                (id) => (e.player(id).personId ?? id) == (p.personId ?? p.id),
              ),
        )) ...[
          PopupMenuButton<String>(
            key: const ValueKey('add-separate-section-entry'),
            tooltip: 'Add a separate section entry',
            onSelected: (id) => attempt(() {
              c.addSectionEntry(p.id, id);
            }),
            itemBuilder: (_) => [
              for (final x in e.sections.where(
                (x) =>
                    x.rounds.isEmpty &&
                    !x.players.any(
                      (id) =>
                          (e.player(id).personId ?? id) == (p.personId ?? p.id),
                    ),
              ))
                PopupMenuItem(value: x.id, child: Text(x.name)),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Add a separate section entry…'),
            ),
          ),
          Text(
            'For a side game or another ladder section. Starts a separate score and keeps the original entry.',
            style: muted,
          ),
          const SizedBox(height: 12),
        ],
        Text(
          'Do not pair with these players in future rounds. For siblings or other requests; independent of team membership.',
          style: muted,
        ),
        const SizedBox(height: 8),
        for (final other in e.players.where(
          (other) =>
              other.id != p.id &&
              (p.avoid.contains(other.id) || other.avoid.contains(p.id)),
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InputChip(
              label: Text(other.name),
              onDeleted: () =>
                  attempt(() => c.avoidPair(p.id, other.id, false)),
              deleteButtonTooltipMessage: 'Allow pairing with ${other.name}',
            ),
          ),
        // Typed, not scrolled: a club event has 100+ names.
        Autocomplete<Player>(
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
          onSelected: (o) => attempt(() => c.avoidPair(p.id, o.id, true)),
          fieldViewBuilder: (context, text, focus, submit) => TextField(
            key: const ValueKey('avoid-player'),
            controller: text,
            focusNode: focus,
            decoration: const InputDecoration(
              labelText: 'Avoid pairing with',
              prefixIcon: Icon(Icons.person_off_outlined, size: 18),
            ),
            onSubmitted: (_) => submit(),
          ),
        ),
        if (s != null && s.format != Format.swiss)
          Text(
            'In a quad or round robin everyone must meet. Put these players in different sections to honor the request.',
            style: muted,
          ),
        heading('Status'),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => attempt(
              () => c.savePlayer(fresh.copy(withdrawn: !p.withdrawn)),
            ),
            child: Text(p.withdrawn ? 'Reinstate' : 'Withdraw'),
          ),
        ),
      ],
    );
  }
}
