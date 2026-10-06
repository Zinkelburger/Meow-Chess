import 'dart:convert';

import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/pairing.dart' show quadGroupSizes;
import '../domain/us_chess.dart' show TimeControl;
import 'drafts.dart';
import 'player_format.dart';
import 'side_panel.dart';
import 'theme.dart';

/// Who a new section takes from the roster.
enum NewSectionPool { ticked, unassigned, everyone, none }

/// The one way to make sections: choose who goes in, how they play, and
/// see every player who will land in each new section before creating it.
/// Ticking rows in the table while this is open updates the list.
class NewSectionPanel extends StatefulWidget {
  const NewSectionPanel({
    required this.controller,
    required this.ticked,
    required this.onCreated,
    required this.onClose,
    super.key,
  });
  final TournamentController controller;

  /// The players ticked in the table right now.
  final Set<String> ticked;
  final ValueChanged<List<String>> onCreated;
  final VoidCallback onClose;

  @override
  State<NewSectionPanel> createState() => _NewSectionPanelState();
}

class _NewSectionPanelState extends State<NewSectionPanel> {
  final name = TextEditingController(),
      rounds = TextEditingController(),
      board = TextEditingController(),
      timeControl = TextEditingController(),
      configuration = TextEditingController();
  late final FormDraft draft;
  Format format = Format.swiss;
  NewSectionPool? pool;
  bool doubleGames = false, sideGames = false, more = false;
  String? error;
  TournamentController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    draft = FormDraft(
      c.workspaceState,
      'draft-new-section',
      {
        'name': name,
        'rounds': rounds,
        'board': board,
        'timeControl': timeControl,
        'configuration': configuration,
      },
      const {
        'name': '',
        'rounds': '',
        'board': '',
        'timeControl': '',
        'configuration': '',
      },
    );
    try {
      final saved = jsonDecode(configuration.text) as Map;
      format = Format.values.byName(saved['format'] as String);
      doubleGames = saved['doubleGames'] == true;
      sideGames = saved['sideGames'] == true;
    } catch (_) {
      // No saved choices: start with a Swiss.
    }
    // Ticked players are the obvious intent; otherwise whoever is left
    // out; otherwise an empty section.
    pool = widget.ticked.isNotEmpty
        ? NewSectionPool.ticked
        : unassigned.isNotEmpty
        ? NewSectionPool.unassigned
        : format == Format.quad
        ? null
        : NewSectionPool.none;
  }

  @override
  void didUpdateWidget(covariant NewSectionPanel old) {
    super.didUpdateWidget(old);
    // Ticking the first row while the panel is open means "these players".
    if (old.ticked.isEmpty && widget.ticked.isNotEmpty) {
      pool = NewSectionPool.ticked;
    } else if (widget.ticked.isEmpty && pool == NewSectionPool.ticked) {
      pool = unassigned.isNotEmpty
          ? NewSectionPool.unassigned
          : format == Format.quad
          ? null
          : NewSectionPool.none;
    }
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    configuration.text = jsonEncode({
      'format': format.name,
      'doubleGames': doubleGames,
      'sideGames': sideGames,
    });
  }

  @override
  void dispose() {
    draft.dispose();
    for (final field in [name, rounds, board, timeControl, configuration]) {
      field.dispose();
    }
    super.dispose();
  }

  Event get e => c.event!;

  /// Whether [id] can be put in a new section now.
  bool movable(String id) {
    final p = e.player(id);
    return !p.withdrawn && (e.sectionOf(id)?.rounds.isEmpty ?? true);
  }

  List<String> get unassigned => [
    for (final p in e.players)
      if (!p.withdrawn && e.sectionOf(p.id) == null) p.id,
  ];

  List<String> get everyone => [
    for (final p in e.players)
      if (movable(p.id)) p.id,
  ];

  List<String> get ticked => [
    for (final p in e.players)
      if (widget.ticked.contains(p.id) && movable(p.id)) p.id,
  ];

  List<String> entrants(NewSectionPool? pool) => switch (pool) {
    NewSectionPool.ticked => ticked,
    NewSectionPool.unassigned => unassigned,
    NewSectionPool.everyone => everyone,
    NewSectionPool.none || null => const [],
  };

  /// The groups this would create: name, format and players in order.
  List<(String, Format, List<Player>)> preview(List<String> ids) {
    final players = [for (final id in ids) e.player(id)];
    if (format != Format.quad) {
      return [(name.text.trim(), format, players)];
    }
    if (players.length < 4) return const [];
    players.sort((a, b) {
      final c = b.rating.compareTo(a.rating);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    final chosen = ids.toSet();
    final taken = {
      for (final s in e.sections)
        if (!s.players.every(chosen.contains) || s.players.isEmpty) s.name,
    };
    final groups = <(String, Format, List<Player>)>[];
    var number = 1, offset = 0;
    for (final size in quadGroupSizes(players.length)) {
      var label = 'Bottom Swiss';
      if (size == 4) {
        while (taken.contains('Quad $number')) {
          number++;
        }
        label = 'Quad $number';
      } else {
        for (var n = 2; taken.contains(label); n++) {
          label = 'Bottom Swiss $n';
        }
      }
      taken.add(label);
      groups.add((
        label,
        size == 4 ? Format.quad : Format.swiss,
        players.skip(offset).take(size).toList(),
      ));
      offset += size;
    }
    return groups;
  }

  void create() {
    final ids = entrants(pool);
    try {
      if (pool == null) {
        throw const TournamentException('Choose who goes in the section.');
      }
      final n = int.tryParse(rounds.text.trim());
      final first = board.text.trim().isEmpty
          ? null
          : int.tryParse(board.text.trim());
      if (format != Format.quad && (n == null || n < 1 || n > 32)) {
        throw const TournamentException(
          'Number of rounds must be between 1 and 32.',
        );
      }
      if (board.text.trim().isNotEmpty && (first == null || first < 1)) {
        throw const TournamentException(
          'The first board number must be 1 or more.',
        );
      }
      final control = timeControl.text.trim();
      if (control.isNotEmpty) TimeControl.parse(control);
      final created = c.createSections(
        ids,
        format: format,
        name: name.text,
        rounds: n ?? 3,
        doubleGames: format == Format.roundRobin && doubleGames,
        sideGames: format != Format.quad && sideGames,
        boardStart: first,
        timeControl: control,
      );
      draft.reset(const {
        'name': '',
        'rounds': '',
        'board': '',
        'timeControl': '',
        'configuration': '',
      });
      widget.onCreated(created);
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    final ids = entrants(pool);
    final quads = format == Format.quad;
    final paired = widget.ticked.length - ticked.length;
    final groups = quads && ids.length < 4 ? null : preview(ids);
    final chosen = ids.toSet();
    final emptied = [
      for (final s in e.sections)
        if (s.players.isNotEmpty && s.players.every(chosen.contains)) s.name,
    ];
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
    Widget field(
      String key,
      TextEditingController controller,
      String label, {
      bool autofocus = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: ValueKey('new-section-$key'),
        controller: controller,
        autofocus: autofocus,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() => error = null),
        onSubmitted: (_) => create(),
      ),
    );
    final count = ids.length;
    final createLabel = quads
        ? groups == null || groups.isEmpty
              ? 'Create quads'
              : 'Create ${groups.length} ${groups.length == 1 ? 'section' : 'sections'}'
        : count == 0
        ? 'Create empty section'
        : 'Create section with $count ${count == 1 ? 'player' : 'players'}';
    return SidePanel(
      key: const ValueKey('new-section-panel'),
      title: 'New section',
      width: 400,
      onClose: widget.onClose,
      footer: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              error!,
              key: const ValueKey('new-section-error'),
              style: TextStyle(color: colors.error),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const ValueKey('create-section'),
              onPressed: pool == null || (quads && (groups?.isEmpty ?? true))
                  ? null
                  : create,
              child: Text(createLabel),
            ),
            OutlinedButton(
              onPressed: widget.onClose,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
      children: [
        DraftStatus(draft: draft),
        Text('Who goes in', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _ChoiceGroup(
          children: [
            _Choice(
              key: const ValueKey('pool-ticked'),
              label: 'Ticked players',
              count: ticked.length,
              detail: widget.ticked.isEmpty
                  ? 'Tick players in the table to choose them'
                  : paired > 0
                  ? '$paired in paired sections stay where they are'
                  : null,
              selected: pool == NewSectionPool.ticked,
              onTap: widget.ticked.isEmpty
                  ? null
                  : () => setState(() => pool = NewSectionPool.ticked),
            ),
            _Choice(
              key: const ValueKey('pool-unassigned'),
              label: 'Everyone not in a section',
              count: unassigned.length,
              selected: pool == NewSectionPool.unassigned,
              onTap: unassigned.isEmpty
                  ? null
                  : () => setState(() => pool = NewSectionPool.unassigned),
            ),
            if (everyone.length > unassigned.length)
              _Choice(
                key: const ValueKey('pool-everyone'),
                label: 'Everyone not yet paired',
                count: everyone.length,
                detail: 'Takes players out of their current sections',
                selected: pool == NewSectionPool.everyone,
                onTap: () => setState(() => pool = NewSectionPool.everyone),
              ),
            if (!quads)
              _Choice(
                key: const ValueKey('pool-none'),
                label: 'No one yet',
                detail: 'Starts empty; add or move players later',
                selected: pool == NewSectionPool.none,
                onTap: () => setState(() => pool = NewSectionPool.none),
              ),
          ],
        ),
        heading('Format'),
        SegmentedButton<Format>(
          key: const ValueKey('new-section-format'),
          expandedInsets: EdgeInsets.zero,
          // Room for "Round robin" on one line in the 360px column.
          style: const ButtonStyle(
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: Format.quad, label: Text('Quads')),
            ButtonSegment(value: Format.swiss, label: Text('Swiss')),
            ButtonSegment(value: Format.roundRobin, label: Text('Round robin')),
          ],
          selected: {format},
          onSelectionChanged: (v) => setState(() {
            format = v.first;
            error = null;
            // Quads need players; fall back to the likeliest group.
            if (format == Format.quad &&
                (pool == null || pool == NewSectionPool.none)) {
              pool = ticked.isNotEmpty
                  ? NewSectionPool.ticked
                  : unassigned.isNotEmpty
                  ? NewSectionPool.unassigned
                  : everyone.isNotEmpty
                  ? NewSectionPool.everyone
                  : null;
            }
          }),
        ),
        const SizedBox(height: 8),
        Text(switch (format) {
          Format.quad =>
            'Groups of four by rating, three rounds each. Five to seven left over play a small Swiss.',
          Format.swiss => 'Players meet others on the same score each round.',
          Format.roundRobin => 'Everyone plays everyone.',
        }, style: muted),
        const SizedBox(height: 16),
        if (!quads) ...[
          field('name', name, 'Section name', autofocus: true),
          field('rounds', rounds, 'Number of rounds'),
          if (format == Format.roundRobin)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SegmentedButton<bool>(
                key: const ValueKey('new-section-double'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('One game each')),
                  ButtonSegment(value: true, label: Text('Two games each')),
                ],
                selected: {doubleGames},
                onSelectionChanged: (v) =>
                    setState(() => doubleGames = v.first),
              ),
            ),
        ],
        DisclosureGroup(
          key: const ValueKey('new-section-more'),
          title: 'More settings',
          open: more,
          onToggle: () => setState(() => more = !more),
          summary: [
            if (!quads && sideGames) 'Side games',
            if (board.text.trim().isNotEmpty) 'Board ${board.text.trim()}',
            if (timeControl.text.trim().isNotEmpty) timeControl.text.trim(),
          ].join(' · '),
          children: [
            const SizedBox(height: 8),
            if (!quads)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    PlainCheckbox(
                      key: const ValueKey('new-section-side-games'),
                      label: 'Side games',
                      value: sideGames,
                      onChanged: (v) => setState(() => sideGames = v ?? false),
                    ),
                    const SizedBox(width: 8),
                    const Text('Side games'),
                  ],
                ),
              ),
            field('board', board, 'First board (blank continues numbering)'),
            field(
              'time-control',
              timeControl,
              'Time control (blank uses event default)',
            ),
          ],
        ),
        heading(
          groups == null
              ? 'Goes in'
              : quads
              ? 'Goes in · ${groups.length} ${groups.length == 1 ? 'section' : 'sections'}'
              : 'Goes in · $count ${count == 1 ? 'player' : 'players'}',
        ),
        if (pool == null)
          Text('Choose who goes in the section', style: muted)
        else if (groups == null)
          Text(
            'Quads need at least four players. Choose more, or pick Swiss.',
            style: TextStyle(color: colors.error),
          )
        else ...[
          for (final (title, _, players) in groups)
            _PreviewGroup(
              title: quads
                  ? title
                  : title.isEmpty
                  ? 'New section'
                  : title,
              players: players,
              sectionOf: (id) => e.sectionOf(id)?.name,
            ),
          const SizedBox(height: 8),
          Text(
            [
              if (pool != NewSectionPool.everyone)
                'Players not listed stay where they are.',
              if (emptied.isNotEmpty)
                '${emptied.join(', ')} will be empty and ${emptied.length == 1 ? 'is' : 'are'} removed.',
            ].join(' '),
            key: const ValueKey('new-section-note'),
            style: muted,
          ),
        ],
      ],
    );
  }
}

/// One new section in the preview: its name and size, then each player.
class _PreviewGroup extends StatelessWidget {
  const _PreviewGroup({
    required this.title,
    required this.players,
    required this.sectionOf,
  });
  final String title;
  final List<Player> players;
  final String? Function(String id) sectionOf;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    const figures = [FontFeature.tabularFigures()];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: colors.surfaceContainerLow,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${players.length} ${players.length == 1 ? 'player' : 'players'}',
                  style: muted.copyWith(fontFeatures: figures),
                ),
              ],
            ),
          ),
          if (players.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Empty', style: muted),
            ),
          for (final p in players)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  ),
                  if (sectionOf(p.id) case final from?) ...[
                    Text('from $from', style: muted),
                    const SizedBox(width: 12),
                  ],
                  SizedBox(
                    width: 44,
                    child: Text(
                      ratingText(p.rating),
                      textAlign: TextAlign.right,
                      style: muted.copyWith(fontFeatures: figures),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ChoiceGroup extends StatelessWidget {
  const _ChoiceGroup({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Who goes in',
      container: true,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: colors.outline),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, color: colors.outlineVariant),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatefulWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.detail,
    super.key,
  });
  final String label;
  final String? detail;
  final int? count;
  final bool selected;

  /// Null when the choice is unavailable; [detail] says why.
  final VoidCallback? onTap;

  @override
  State<_Choice> createState() => _ChoiceState();
}

class _ChoiceState extends State<_Choice> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = widget.onTap != null;
    final ink = enabled
        ? colors.onSurface
        : colors.onSurface.withValues(alpha: 0.5);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: widget.selected,
      enabled: enabled,
      button: true,
      label: [
        widget.label,
        if (widget.count != null) '${widget.count} players',
        ?widget.detail,
      ].join(', '),
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Material(
        color: widget.selected
            ? colors.surfaceContainerHigh
            : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (v) => setState(() => focused = v),
          child: Container(
            constraints: const BoxConstraints(minHeight: controlHeight + 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: focused
                ? BoxDecoration(
                    border: Border.all(
                      color: focusRing(colors),
                      width: focusRingWidth,
                    ),
                  )
                : null,
            child: Row(
              children: [
                Icon(
                  widget.selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: widget.selected ? colors.onSurface : colors.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: ink,
                          fontWeight: widget.selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (widget.detail != null)
                        Text(
                          widget.detail!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.count != null)
                  Text(
                    '${widget.count}',
                    style: TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
