import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import '../application/diagnostics.dart';
import '../application/tournament_controller.dart';
import '../domain/history.dart';
import '../domain/model.dart';
import '../domain/recovery.dart';
import 'dialogs.dart';
import 'panels.dart';
import 'result_correction_panel.dart';
import 'side_panel.dart';
import 'theme.dart';
import 'workspace_toolbar.dart' show shortcutLabel;

/// Whether moving to [node] changes an earlier result while rounds paired
/// after it stay in place. That needs the correction review, not a restore.
bool changesDependentResult(TournamentController c, Event target) {
  final targetGames = {for (final game in target.games) game.id: game};
  return c.event!.games.any(
    (g) =>
        targetGames[g.id] != null &&
        targetGames[g.id]!.outcome != g.outcome &&
        c.correctionHasDependencies(g.id),
  );
}

/// A routine Undo or Redo moves at once. One that removes recorded play or
/// changes an earlier result under later pairings is shown in History first.
bool historyNeedsReview(TournamentController c, int node) =>
    c.lossesTo(node).isNotEmpty ||
    changesDependentResult(c, c.repository.snapshot(node));

/// A history step in the director's words: what changed and where.
/// [read] supplies saved states, so a caller may cache them.
HistoryStep historyStep(
  TournamentController c,
  int id, [
  Event Function(int node)? read,
]) {
  final node = c.graph.nodes[id]!;
  if (node.parent == null) return (title: node.action, context: '');
  final snapshot = read ?? c.repository.snapshot;
  try {
    return summarizeStep(snapshot(node.parent!), snapshot(id));
  } catch (error, stack) {
    Diagnostics.record(
      'read history step',
      'failed',
      context: {'node': id},
      error: error,
      stack: stack,
    );
    return (title: node.action, context: 'Details unavailable');
  }
}

String historyTime(String timestamp) {
  final t = DateTime.parse(timestamp).toLocal(), now = DateTime.now();
  final clock =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  return t.year == now.year && t.month == now.month && t.day == now.day
      ? clock
      : '${t.month}/${t.day} $clock';
}

/// One line in the list: a change on the event's line, a change that was
/// undone and kept aside, or the switch that shows or hides those.
sealed class _Entry {
  const _Entry();
}

class _Change extends _Entry {
  const _Change(this.id, {this.aside = false, this.last = false});
  final int id;

  /// Undone and replaced by later work, kept in its own group.
  final bool aside;

  /// The oldest row of its line, where the rail ends.
  final bool last;
}

class _Aside extends _Entry {
  const _Aside(this.root, this.count, this.open);
  final int root, count;
  final bool open;
}

class HistoryPanel extends StatefulWidget {
  const HistoryPanel({
    required this.controller,
    required this.onClose,
    this.review,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;

  /// A step Undo or Redo stopped at so its consequences can be read first.
  final int? review;
  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<HistoryPanel> {
  TournamentController get c => widget.controller;
  final focus = FocusNode(debugLabel: 'history');
  final scroll = ScrollController();
  final openAsides = <int>{};
  final rowKeys = <int, GlobalKey>{};
  final expandedLists = <String>{};
  var allPoints = false, pointsOpen = false;
  int? selected;
  int? shownHead;

  // Saved states are immutable. Only visible operations need to be read.
  // Summaries are small and kept; whole events are only cached for the most
  // recently read [_snapshotLimit] states, least recently used dropped first.
  static const _snapshotLimit = 32;
  final snapshots = <int, Event>{};
  final summaries = <int, HistoryStep>{};
  final unreadable = <int>{};
  Event snapshot(int id) {
    final event = snapshots.remove(id) ?? c.repository.snapshot(id);
    snapshots[id] = event;
    if (snapshots.length > _snapshotLimit) {
      snapshots.remove(snapshots.keys.first);
    }
    return event;
  }

  HistoryStep summary(int id) =>
      summaries.putIfAbsent(id, () => historyStep(c, id, snapshot));

  @override
  void initState() {
    super.initState();
    shownHead = c.graph.head;
    if (widget.review != null) select(widget.review);
  }

  @override
  void didUpdateWidget(HistoryPanel old) {
    super.didUpdateWidget(old);
    if (widget.review != null && widget.review != old.review) {
      select(widget.review);
    }
  }

  @override
  void dispose() {
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  void select(int? id) {
    // A change kept aside opens its group so the selection is visible.
    final graph = c.graph;
    if (id != null && graph.style(id) == NodeStyle.branch) {
      for (final entry in graph.branches.entries) {
        if (entry.value.contains(id)) openAsides.add(entry.key);
      }
    }
    setState(() => selected = id);
    focus.requestFocus();
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => reveal(id));
  }

  /// Scrolls [id]'s row into view. The list builds rows lazily, so a row far
  /// down may not exist yet: jump toward where it should be and look again
  /// on the next frame, a few times, as row heights become known.
  void reveal(int id, [int tries = 4]) {
    if (!mounted || selected != id) return;
    final rowContext = rowKeys[id]?.currentContext;
    if (rowContext != null) {
      Scrollable.ensureVisible(
        rowContext,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
      Scrollable.ensureVisible(
        rowContext,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      return;
    }
    if (tries == 0 || !scroll.hasClients) return;
    final list = entries(c.graph);
    final index = list.indexWhere((e) => e is _Change && e.id == id);
    if (index < 0) return;
    final position = scroll.position;
    // Average height of what has been laid out so far; the header is row 0.
    final average = position.extentTotal / (list.length + 2);
    position.jumpTo(
      ((index + 1) * average).clamp(0.0, position.maxScrollExtent),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => reveal(id, tries - 1));
  }

  /// The event's line newest first, with each group of undone changes just
  /// above the change they branched from.
  List<_Entry> entries(HistoryGraph graph) {
    final line =
        graph.nodes.keys
            .where((id) => graph.style(id) != NodeStyle.branch)
            .toList()
          ..sort((a, b) => b - a);
    final asides = <int, List<int>>{};
    for (final root in graph.branches.keys) {
      (asides[graph.nodes[root]!.parent!] ??= []).add(root);
    }
    return [
      for (final id in line) ...[
        for (final root in asides[id] ?? <int>[]) ...[
          _Aside(root, graph.branches[root]!.length, openAsides.contains(root)),
          if (openAsides.contains(root))
            for (final (i, aside)
                in (graph.branches[root]!.toList()..sort((a, b) => b - a))
                    .indexed)
              _Change(
                aside,
                aside: true,
                last: i == graph.branches[root]!.length - 1,
              ),
        ],
        _Change(id, last: id == line.last),
      ],
    ];
  }

  void moveTo(int id) {
    final graph = c.graph;
    try {
      if (id == graph.back) {
        c.undo(acceptLosses: true);
      } else if (id == graph.forward) {
        c.redo(acceptLosses: true);
      } else {
        c.restore(id, acceptLosses: true);
      }
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  KeyEventResult key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rows = [
      for (final e in entries(c.graph))
        if (e is _Change) e.id,
    ];
    final index = rows.indexOf(selected ?? c.graph.head ?? -1);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp when index > 0:
        select(rows[index - 1]);
      case LogicalKeyboardKey.arrowDown
          when index >= 0 && index < rows.length - 1:
        select(rows[index + 1]);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter
          when selected != null && selected != c.graph.head:
        moveTo(selected!);
      case LogicalKeyboardKey.escape:
        if (selected != null) {
          select(null);
        } else {
          widget.onClose();
        }
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final graph = c.graph, colors = Theme.of(context).colorScheme;
    if (graph.head != shownHead) {
      shownHead = graph.head;
      selected = null;
    }
    final list = entries(graph);
    final muted = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    // Many changes land in the same minute; the time shows where it changes.
    String? lastTime;
    final times = <int, String?>{};
    for (final e in list) {
      if (e is! _Change) continue;
      final t = historyTime(graph.nodes[e.id]!.timestamp);
      times[e.id] = t == lastTime ? null : t;
      lastTime = t;
    }
    return SidePanel(
      title: 'History',
      onClose: widget.onClose,
      scrolls: false,
      children: [
        Focus(
          focusNode: focus,
          onKeyEvent: key,
          child: ListView.builder(
            key: const ValueKey('history-graph'),
            controller: scroll,
            scrollCacheExtent: const ScrollCacheExtent.pixels(600),
            // The explanation follows the changes, so large text never
            // pushes the newest change out of view.
            itemCount: list.length + 2,
            // Not selectable: the header changes on its own as recovery
            // points are found, and a selectable child that changes while
            // the workspace's selection is being updated trips Flutter's
            // selection container (the UI fuzzer found the exception).
            itemBuilder: (context, i) => i == 0
                ? SelectionContainer.disabled(child: _header(context, graph))
                : --i == list.length
                ? Padding(
                    key: const ValueKey('history-keys'),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Text(
                      'Choosing a change only shows it. The event moves when you press its button.\n'
                      '↑ ↓ choose · Enter go to the chosen version · ${shortcutLabel('Z')} undo',
                      style: muted.copyWith(height: 1.5),
                    ),
                  )
                : switch (list[i]) {
                    final _Aside a => _asideToggle(context, a),
                    final _Change e => _row(
                      context,
                      e,
                      graph,
                      times[e.id],
                      above: i > 0,
                    ),
                  },
          ),
        ),
      ],
    );
  }

  /// Above the changes: the way back to the newest version when the event
  /// is on an earlier one, and the recovery points: named states such as
  /// "Before round 3 pairings". Choosing a point selects its row, so going
  /// there shows the same details and warnings as any other change.
  Widget _header(BuildContext context, HistoryGraph graph) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    final latest = c.latestNode;
    List<RecoveryPoint> points;
    var complete = true;
    try {
      // A few milliseconds of saved states per frame: on a long history the
      // points fill in over the next frames instead of freezing the window.
      final found = c.recoveryPointsWithin(
        limit: allPoints ? null : 6,
        reads: 24,
        within: const Duration(milliseconds: 8),
      );
      points = found.points;
      complete = found.complete;
    } on TournamentException {
      // The event has closed: nothing to list.
      points = const [];
    } catch (error, stack) {
      // A damaged file is logged, not hidden behind an empty list.
      Diagnostics.record(
        'recovery points',
        'failed',
        error: error,
        stack: stack,
      );
      points = const [];
    }
    if (!complete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    final shown = allPoints ? points : points.take(5).toList();
    return Padding(
      key: const ValueKey('history-header'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (latest != null && latest != graph.head) ...[
            Container(
              key: const ValueKey('history-earlier'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The event is on an earlier version',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The newest, from ${historyTime(graph.nodes[latest]!.timestamp)}, is kept: '
                    '${summary(latest).title}',
                    style: muted.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('history-return'),
                    icon: const Icon(Icons.update),
                    label: const Text('Return to latest'),
                    // Returning is reviewed like any other move when it
                    // would remove play or change a result later rounds
                    // were paired on: the row opens with its warning.
                    onPressed: () => historyNeedsReview(c, latest)
                        ? select(latest)
                        : moveTo(latest),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // One line until asked for, so the newest changes stay in view
          // at any text size.
          if (shown.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('history-points'),
                onPressed: () => setState(() => pointsOpen = !pointsOpen),
                icon: Icon(
                  pointsOpen ? Icons.expand_less : Icons.flag_outlined,
                ),
                label: Text(
                  'Recovery points (${points.length > 5 && !allPoints
                      ? '5+'
                      : complete
                      ? points.length
                      : '${points.length}+'})',
                ),
              ),
            ),
          if (shown.isNotEmpty && pointsOpen) ...[
            for (final p in shown)
              InkWell(
                key: ValueKey('history-point-${p.node}-${p.mark.title}'),
                onTap: () => select(p.node),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: p.mark.title,
                            children: [
                              if (p.mark.detail.isNotEmpty)
                                TextSpan(
                                  text: ' · ${p.mark.detail}',
                                  style: muted,
                                ),
                            ],
                          ),
                        ),
                      ),
                      Text(historyTime(p.timestamp), style: muted),
                    ],
                  ),
                ),
              ),
            if (points.length > 5)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('history-all-points'),
                  onPressed: () => setState(() => allPoints = !allPoints),
                  child: Text(
                    allPoints ? 'Show fewer' : 'Show all recovery points',
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Divider(color: colors.outlineVariant),
          ],
        ],
      ),
    );
  }

  Widget _asideToggle(BuildContext context, _Aside a) {
    final colors = Theme.of(context).colorScheme;
    final noun = a.count == 1 ? 'change' : 'changes';
    // When the group's work was done tells it apart from other groups.
    final times = [
      for (final id in c.graph.branches[a.root]!) c.graph.nodes[id]!.timestamp,
    ]..sort();
    final first = historyTime(times.first), last = historyTime(times.last);
    final span = first == last ? first : '$first–$last';
    return CustomPaint(
      painter: _Rail(colors: colors, kind: _RailKind.toggle, open: a.open),
      child: Padding(
        padding: const EdgeInsets.only(left: _asideIndent - 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ValueKey('history-branch-${a.root}'),
            onPressed: () {
              setState(() {
                if (a.open) {
                  openAsides.remove(a.root);
                  if (c.graph.branches[a.root]!.contains(selected)) {
                    selected = null;
                  }
                } else {
                  openAsides.add(a.root);
                }
              });
              focus.requestFocus();
            },
            icon: Icon(a.open ? Icons.expand_less : Icons.expand_more),
            label: Text(
              a.open
                  ? 'Hide ${a.count} undone $noun'
                  : '${a.count} undone $noun, kept · $span',
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    _Change e,
    HistoryGraph graph,
    String? time, {
    required bool above,
  }) {
    final id = e.id, colors = Theme.of(context).colorScheme;
    final isHead = id == graph.head, isSelected = selected == id;
    final style = graph.style(id);
    final step = summary(id);
    final muted = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    final scale = MediaQuery.textScalerOf(context);
    // The dot sits on the first line of the title at any text size.
    final dotY = _rowPadding + scale.scale(14) * 1.4 / 2;
    final state = isHead
        ? 'Now'
        : style == NodeStyle.past
        ? null
        : 'Undone';
    return Material(
      color: isSelected ? colors.surfaceContainerHigh : Colors.transparent,
      child: CustomPaint(
        painter: _Rail(
          colors: colors,
          kind: e.aside
              ? _RailKind.aside
              : isHead
              ? _RailKind.head
              : style == NodeStyle.past
              ? _RailKind.past
              : _RailKind.ahead,
          above: above,
          below: !e.last,
          dotY: dotY,
          aside: e.aside,
        ),
        child: Padding(
          padding: EdgeInsets.only(left: e.aside ? _asideIndent : _indent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                selected: isSelected,
                label: [
                  step.title,
                  if (step.context.isNotEmpty) step.context,
                  ?state,
                  historyTime(graph.nodes[id]!.timestamp),
                ].join(', '),
                excludeSemantics: true,
                child: InkWell(
                  key: ValueKey('history-$id'),
                  onTap: () => select(isSelected ? null : id),
                  child: Container(
                    key: rowKeys.putIfAbsent(id, () => GlobalKey()),
                    padding: const EdgeInsets.fromLTRB(
                      0,
                      _rowPadding,
                      16,
                      _rowPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                step.title,
                                maxLines: isSelected ? null : 2,
                                overflow: isSelected
                                    ? null
                                    : TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  fontWeight: isHead || isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: style == NodeStyle.past
                                      ? colors.onSurface
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (time != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 12,
                                  top: 2,
                                ),
                                child: Text(
                                  time,
                                  style: muted.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (step.context.isNotEmpty || state != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (state != null) StatusPill(state),
                                if (step.context.isNotEmpty)
                                  Text(step.context, style: muted),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isSelected) _details(context, id, graph),
            ],
          ),
        ),
      ),
    );
  }

  Widget _details(BuildContext context, int id, HistoryGraph graph) {
    final colors = Theme.of(context).colorScheme;
    final path = graph.pathTo(id);
    final parent = graph.nodes[id]!.parent;
    final small = TextStyle(fontSize: 13, height: 1.4, color: colors.onSurface);
    final muted = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    List<String> items;
    ({String gameId, Outcome outcome})? fix;
    List<String> lost;
    bool dependent;
    try {
      items = parent == null
          ? []
          : describeChanges(snapshot(parent), snapshot(id));
      fix = parent == null
          ? null
          : reversibleResult(snapshot(parent), snapshot(id), c.event!);
      lost = id == graph.head ? [] : playLost(c.event!, snapshot(id));
      dependent = id != graph.head && changesDependentResult(c, snapshot(id));
    } catch (error, stack) {
      // This runs during build, so report each saved state only once.
      if (unreadable.add(id)) {
        Diagnostics.record(
          'read saved state',
          'failed',
          context: {'node': id},
          error: error,
          stack: stack,
        );
      }
      return const Padding(
        padding: EdgeInsets.only(bottom: 12, right: 16),
        child: Text('This saved state could not be read.'),
      );
    }
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
    List<Widget> changes(String what, List<int> ids) {
      if (ids.isEmpty) return [];
      final key = '$id|${graph.head}|$what';
      final open = expandedLists.contains(key);
      return [
        heading(
          '$what ${ids.length} ${ids.length == 1 ? 'change' : 'changes'}',
        ),
        for (final other in open ? ids : ids.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(summary(other).title, style: small),
          ),
        if (ids.length > 4)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                if (!expandedLists.remove(key)) expandedLists.add(key);
              }),
              child: Text(open ? 'Show fewer' : 'Show ${ids.length - 4} more'),
            ),
          ),
      ];
    }

    final style = graph.style(id);
    final moveLabel = switch (style) {
      NodeStyle.past => 'Go back to here',
      NodeStyle.future => 'Redo up to here',
      NodeStyle.branch => 'Switch to this version',
    };
    final move = fix == null
        ? FilledButton.icon(
            key: const ValueKey('history-restore'),
            onPressed: () => moveTo(id),
            icon: const Icon(Icons.restore),
            label: Text(moveLabel),
          )
        : OutlinedButton.icon(
            key: const ValueKey('history-restore'),
            onPressed: () => moveTo(id),
            icon: const Icon(Icons.restore),
            label: Text(moveLabel),
          );
    return Padding(
      key: ValueKey('history-details-$id'),
      padding: const EdgeInsets.fromLTRB(0, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            // A one-line step already reads in full in its title.
            if (items.length > 1 ||
                item.toLowerCase() != summary(id).title.toLowerCase())
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(item, style: small),
              ),
          if (id == graph.head)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('The event is here now.', style: muted),
            )
          else ...[
            heading('At this point'),
            for (final line in stateSummary(snapshot(id)))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(line, style: small),
              ),
            ...changes('Undoes', path.undo),
            ...changes('Brings back', path.apply),
            if (lost.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Warning(
                title: 'Removes recorded play',
                lines: lost,
                note: 'Printed or shared copies stay as they are.',
              ),
            ],
            if (dependent && fix == null) ...[
              const SizedBox(height: 16),
              _Warning(
                title:
                    'An earlier result changes while later rounds stay paired',
                lines: const [],
                note:
                    'To choose what happens to those rounds, use Correct a result in Pairings instead.',
              ),
            ],
            const SizedBox(height: 16),
            if (fix != null) ...[
              FilledButton.icon(
                key: const ValueKey('history-undo-result'),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Fix this result'),
                onPressed: () {
                  final dock = Dock.maybeOf(context);
                  openResultCorrection(
                    context,
                    c,
                    fix!.gameId,
                    outcome: fix.outcome,
                    onDone: () => dock?.claim('history'),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Text(
                  'Changes only this game. Everything after it stays.',
                  style: muted,
                ),
              ),
            ],
            move,
            if (path.undo.length + path.apply.length > 1 || fix != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Moves the whole event to this point. Nothing is deleted; you can come back.',
                  style: muted,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Consequences worth reading before acting, marked by an icon and a title
/// rather than by colour.
class _Warning extends StatelessWidget {
  const _Warning({required this.title, required this.lines, this.note});
  final String title;
  final List<String> lines;
  final String? note;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: colors.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: colors.onErrorContainer,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  for (final line in lines) Text(line),
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(note!),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _rowPadding = 12.0;
const _spineX = 16.0, _asideX = 32.0;
const _indent = 32.0, _asideIndent = 48.0;

enum _RailKind { past, head, ahead, aside, toggle }

/// One straight rail for the event's line; undone changes hang beside it on
/// a second rail that rejoins where they branched off.
class _Rail extends CustomPainter {
  _Rail({
    required this.colors,
    required this.kind,
    this.above = true,
    this.below = true,
    this.dotY = 0,
    this.aside = false,
    this.open = false,
  });
  final ColorScheme colors;
  final _RailKind kind;
  final bool above, below, aside, open;
  final double dotY;

  @override
  void paint(Canvas canvas, Size size) {
    // Undone changes ahead of the event draw lighter than its past.
    final newer = Paint()
      ..strokeWidth = 2
      ..color = kind == _RailKind.past ? colors.outline : colors.outlineVariant;
    final older = Paint()
      ..strokeWidth = 2
      ..color = kind == _RailKind.ahead
          ? colors.outlineVariant
          : colors.outline;
    final side = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..color = colors.outlineVariant;
    final spine = Paint()
      ..strokeWidth = 2
      ..color = colors.outline;
    switch (kind) {
      case _RailKind.toggle:
        canvas.drawLine(
          const Offset(_spineX, 0),
          Offset(_spineX, size.height),
          spine,
        );
        if (!open) {
          canvas.drawPath(
            Path()
              ..moveTo(_asideX, size.height / 2)
              ..quadraticBezierTo(_asideX, size.height, _spineX, size.height),
            side,
          );
        } else {
          canvas.drawLine(
            Offset(_asideX, size.height / 2),
            Offset(_asideX, size.height),
            side,
          );
        }
        return;
      case _RailKind.aside:
        canvas.drawLine(
          const Offset(_spineX, 0),
          Offset(_spineX, size.height),
          spine,
        );
        canvas.drawLine(const Offset(_asideX, 0), Offset(_asideX, dotY), side);
        if (below) {
          canvas.drawLine(
            Offset(_asideX, dotY),
            Offset(_asideX, size.height),
            side,
          );
        } else {
          canvas.drawPath(
            Path()
              ..moveTo(_asideX, dotY)
              ..quadraticBezierTo(_asideX, size.height, _spineX, size.height),
            side,
          );
        }
        _hollow(canvas, const Offset(_asideX, 0).translate(0, dotY));
        return;
      case _RailKind.past || _RailKind.head || _RailKind.ahead:
        if (above) {
          canvas.drawLine(
            const Offset(_spineX, 0),
            Offset(_spineX, dotY),
            newer,
          );
        }
        if (below) {
          canvas.drawLine(
            Offset(_spineX, dotY),
            Offset(_spineX, size.height),
            older,
          );
        }
        final center = Offset(_spineX, dotY);
        if (kind == _RailKind.head) {
          canvas.drawCircle(center, 7, Paint()..color = colors.onSurface);
          canvas.drawCircle(
            center,
            3,
            Paint()..color = colors.surfaceContainerLowest,
          );
        } else if (kind == _RailKind.past) {
          canvas.drawCircle(center, 4.5, Paint()..color = colors.outline);
        } else {
          _hollow(canvas, center);
        }
    }
  }

  void _hollow(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center,
      4.5,
      Paint()..color = colors.surfaceContainerLowest,
    );
    canvas.drawCircle(
      center,
      4.5,
      Paint()
        ..color = colors.outline
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_Rail old) =>
      old.colors != colors ||
      old.kind != kind ||
      old.above != above ||
      old.below != below ||
      old.dotY != dotY ||
      old.open != open;
}
