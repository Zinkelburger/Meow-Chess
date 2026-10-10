import 'dart:convert';

import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/pairing.dart' show planQuads;
import 'drafts.dart';
import 'player_format.dart';
import 'section_panel.dart';
import 'side_panel.dart';
import 'theme.dart';

/// Who a new section takes from the roster.
enum NewSectionPool { ticked, unassigned, everyone, none }

typedef _Group = ({String name, Format format, List<Player> players});

/// The roster sorted by who can go in a new section, read in one pass.
class _Pools {
  _Pools(Event e, Set<String> tickedIds) {
    for (final s in e.sections) {
      for (final id in s.players) {
        sectionOf[id] = s;
      }
    }
    for (final p in e.players) {
      final from = sectionOf[p.id], chosen = tickedIds.contains(p.id);
      if (p.withdrawn) {
        if (chosen) withdrawnTicked++;
      } else if (from != null && from.rounds.isNotEmpty) {
        if (chosen) pairedTicked++;
      } else {
        everyone.add(p);
        if (from == null) unassigned.add(p);
        if (chosen) ticked.add(p);
      }
    }
  }

  final sectionOf = <String, Section>{};
  final ticked = <Player>[], unassigned = <Player>[], everyone = <Player>[];

  /// Ticked players who cannot move: withdrawn, or in a paired section.
  int withdrawnTicked = 0, pairedTicked = 0;

  List<Player> of(NewSectionPool? pool) => switch (pool) {
    NewSectionPool.ticked => ticked,
    NewSectionPool.unassigned => unassigned,
    NewSectionPool.everyone => everyone,
    NewSectionPool.none || null => const [],
  };
}

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
  late final Map<String, TextEditingController> text;
  late final FormDraft draft;
  final problems = <String, String>{};
  NewSectionPool? pool;
  String? error;
  TournamentController get c => widget.controller;

  Format get format =>
      Format.values.byName(text['format']?.text ?? Format.swiss.name);
  bool get holland => text['holland']?.text == 'true';

  @override
  void initState() {
    super.initState();
    final base = sectionValues(null);
    text = {for (final key in base.keys) key: TextEditingController()};
    draft = FormDraft(c.workspaceState, 'draft-new-section', text, base);
    for (final key in text.keys) {
      if (draft.isEdited(key)) {
        if (sectionGroupOf(key) case final group?) {
          c.workspaceState.write(sectionGroupPref(group), 'open');
        }
      }
    }
    // Ticked players are the obvious intent; otherwise whoever is left
    // out; otherwise an empty section.
    pool = widget.ticked.isNotEmpty
        ? NewSectionPool.ticked
        : pools.unassigned.isNotEmpty
        ? NewSectionPool.unassigned
        : needsPlayers
        ? null
        : NewSectionPool.none;
  }

  /// Quads and Holland prelims are made from players, never empty.
  bool get needsPlayers => format == Format.quad || holland;

  @override
  void didUpdateWidget(covariant NewSectionPanel old) {
    super.didUpdateWidget(old);
    // Ticking the first row while the panel is open means "these players".
    if (old.ticked.isEmpty && widget.ticked.isNotEmpty) {
      pool = NewSectionPool.ticked;
    } else if (widget.ticked.isEmpty && pool == NewSectionPool.ticked) {
      pool = pools.unassigned.isNotEmpty
          ? NewSectionPool.unassigned
          : needsPlayers
          ? null
          : NewSectionPool.none;
    }
  }

  /// Why [rounds] cannot work for [players] entrants, or null. A round robin
  /// plays everyone once (twice with two games each, in the same round), so
  /// more rounds than its schedule could never be completed.
  String? roundsProblem(int players) {
    final rounds = text['rounds']!.text.trim();
    if (format != Format.roundRobin ||
        holland ||
        rounds.isEmpty ||
        players < 2) {
      return null;
    }
    final n = int.tryParse(rounds);
    final schedule = players.isOdd ? players : players - 1;
    if (n == null || n <= schedule) return null;
    return 'A round robin of $players has $schedule '
        '${schedule == 1 ? 'round' : 'rounds'}. Enter $schedule or fewer.';
  }

  @override
  void dispose() {
    draft.dispose();
    for (final field in text.values) {
      field.dispose();
    }
    super.dispose();
  }

  Event get e => c.event!;

  _Pools get pools => _Pools(e, widget.ticked);

  /// The groups this would create: name, format and players in order.
  /// Sections in [emptied] give up their names.
  List<_Group> preview(List<Player> players, Set<String> emptied) {
    if (holland) {
      final groups = int.tryParse(text['hollandGroups']!.text.trim()) ?? 0;
      if (groups < 1 || players.length < 2 * groups) return const [];
      // Rating order, dealt round-robin style across the groups, as the
      // controller plans them; the exact split is its decision.
      final sorted = [...players]..sort((a, b) => b.rating.compareTo(a.rating));
      return [
        for (var g = 0; g < groups; g++)
          (
            name: 'Prelim ${g + 1}',
            format: Format.roundRobin,
            players: [
              for (var i = g; i < sorted.length; i += groups) sorted[i],
            ],
          ),
      ];
    }
    if (format != Format.quad) {
      return [
        (name: text['name']!.text.trim(), format: format, players: players),
      ];
    }
    if (players.length < 4) return const [];
    return planQuads(
      players,
      taken: [
        for (final s in e.sections)
          if (!emptied.contains(s.id)) s.name,
      ],
    );
  }

  void changed() => setState(() {
    error = null;
    problems.clear();
  });

  void create() {
    final ids = [for (final p in pools.of(pool)) p.id];
    try {
      if (pool == null) {
        throw const TournamentException('Choose who goes in the section.');
      }
      final v = draft.values;
      if (holland) {
        final groups = int.tryParse(v['hollandGroups']!.trim());
        if (groups == null || groups < 1) {
          throw const SectionFieldProblem(
            'hollandGroups',
            'Enter how many preliminary groups to make.',
          );
        }
        final qualifiers = int.tryParse(v['hollandQualifiers']!.trim());
        if (qualifiers == null || qualifiers < 1) {
          throw const SectionFieldProblem(
            'hollandQualifiers',
            'Enter how many qualify from each group.',
          );
        }
        final created = c.makeHolland(
          groups: groups,
          qualifiers: qualifiers,
          unbalanced: v['hollandUnbalanced'] == 'true',
          players: ids,
        );
        draft.reset(sectionValues(null));
        widget.onCreated(created);
        return;
      }
      final n = readSection(v, boardRequired: false);
      if (roundsProblem(ids.length) case final problem?) {
        throw SectionFieldProblem('rounds', problem);
      }
      final created = c.createSections(
        ids,
        format: n.format,
        name: n.name,
        rounds: n.rounds,
        doubleGames: n.doubleGames,
        sideGames: n.format != Format.quad && n.sideGames,
        boardStart: n.board,
        timeControl: n.timeControl,
      );
      // Everything beyond what createSections takes: the announced rules
      // and the format's own fields. Applied as one more step only when
      // something differs from the defaults the sections were born with.
      final made = [
        for (final s in c.event!.sections)
          if (created.contains(s.id)) s,
      ];
      final configured = <String, Section>{};
      for (final s in made) {
        final next = applySectionValues(c.event!, s, {
          ...v,
          'name': s.name,
          'format': s.format.name,
          'rounds': '${s.plannedRounds}',
          'board': '${s.boardStart}',
          'doubleGames': '${s.doubleGames}',
          'sideGames': '${s.sideGames}',
        });
        if (jsonEncode(next.toJson()) != jsonEncode(s.toJson())) {
          configured[s.id] = next;
        }
      }
      if (configured.isNotEmpty) {
        c.change(
          'Set up ${made.length == 1 ? made.single.name : '${made.length} sections'}',
          c.event!.copy(
            sections: [
              for (final s in c.event!.sections) configured[s.id] ?? s,
            ],
          ),
        );
      }
      draft.reset(sectionValues(null));
      widget.onCreated(created);
    } on SectionFieldProblem catch (e) {
      setState(() {
        error = null;
        problems
          ..clear()
          ..[e.field] = e.message;
      });
      revealSectionField(c, 'new-section-', e.field);
    } catch (e) {
      setState(() {
        problems.clear();
        error = plainMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    final pools = this.pools;
    final entrants = pools.of(pool);
    final quads = format == Format.quad && !holland;
    final emptiedIds = sectionsEmptiedBy(e, {for (final p in entrants) p.id});
    final groups = quads && entrants.length < 4
        ? null
        : preview(entrants, emptiedIds);
    final emptied = [
      for (final s in e.sections)
        if (emptiedIds.contains(s.id)) s.name,
    ];
    final cannotMove = [
      if (pools.pairedTicked > 0)
        '${pools.pairedTicked} in paired sections stay where they are',
      if (pools.withdrawnTicked > 0)
        '${pools.withdrawnTicked} withdrawn ${pools.withdrawnTicked == 1 ? 'is' : 'are'} left out',
    ].join(' · ');
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
    final count = entrants.length;
    final createLabel = holland
        ? groups == null || groups.isEmpty
              ? 'Create Holland prelims'
              : 'Create ${groups.length} Holland ${groups.length == 1 ? 'prelim' : 'prelims'}'
        : quads
        ? groups == null || groups.isEmpty
              ? 'Create quads'
              : 'Create ${groups.length} ${groups.length == 1 ? 'section' : 'sections'}'
        : count == 0
        ? 'Create empty section'
        : 'Create section with $count ${count == 1 ? 'player' : 'players'}';
    // Problems beside a field the form shows; the rounds check is live.
    final shown = {
      ...problems,
      if (roundsProblem(count) case final problem?
          when !problems.containsKey('rounds'))
        'rounds': problem,
    };
    return SidePanel(
      key: const ValueKey('new-section-panel'),
      title: 'New section',
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
              onPressed:
                  pool == null || (needsPlayers && (groups?.isEmpty ?? true))
                  ? null
                  : create,
              child: Text(createLabel),
            ),
            TextButton(
              onPressed: () {
                draft.reset(sectionValues(null));
                changed();
              },
              child: const Text('Discard draft'),
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
              count: pools.ticked.length,
              detail: widget.ticked.isEmpty
                  ? 'Tick players in the table to choose them'
                  : cannotMove.isEmpty
                  ? null
                  : cannotMove,
              selected: pool == NewSectionPool.ticked,
              onTap: widget.ticked.isEmpty
                  ? null
                  : () => setState(() => pool = NewSectionPool.ticked),
            ),
            _Choice(
              key: const ValueKey('pool-unassigned'),
              label: 'Everyone not in a section',
              count: pools.unassigned.length,
              selected: pool == NewSectionPool.unassigned,
              onTap: pools.unassigned.isEmpty
                  ? null
                  : () => setState(() => pool = NewSectionPool.unassigned),
            ),
            if (pools.everyone.length > pools.unassigned.length)
              _Choice(
                key: const ValueKey('pool-everyone'),
                label: 'Everyone not yet paired',
                count: pools.everyone.length,
                detail: 'Takes players out of their current sections',
                selected: pool == NewSectionPool.everyone,
                onTap: () => setState(() => pool = NewSectionPool.everyone),
              ),
            if (!needsPlayers)
              _Choice(
                key: const ValueKey('pool-none'),
                label: 'No one yet',
                detail: 'Starts empty; add or move players later',
                selected: pool == NewSectionPool.none,
                onTap: () => setState(() => pool = NewSectionPool.none),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SectionFormFields(
          controller: c,
          current: null,
          text: text,
          keyPrefix: 'new-section-',
          problems: shown,
          playerCount: count,
          nameAutofocus: true,
          allowHolland: true,
          onChanged: () {
            // Quads and prelims need players; fall back to the likeliest group.
            if (needsPlayers && (pool == null || pool == NewSectionPool.none)) {
              pool = pools.ticked.isNotEmpty
                  ? NewSectionPool.ticked
                  : pools.unassigned.isNotEmpty
                  ? NewSectionPool.unassigned
                  : pools.everyone.isNotEmpty
                  ? NewSectionPool.everyone
                  : null;
            }
            changed();
          },
          onSubmit: create,
        ),
        heading(
          groups == null
              ? 'Goes in'
              : quads || holland
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
        else if (holland && groups.isEmpty)
          Text(
            'Enter the number of preliminary groups; each needs at least two players.',
            style: muted,
          )
        else ...[
          for (final (name: title, format: _, :players) in groups)
            _PreviewGroup(
              title: quads || holland
                  ? title
                  : title.isEmpty
                  ? 'New section'
                  : title,
              players: players,
              sectionOf: (id) => pools.sectionOf[id]?.name,
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
