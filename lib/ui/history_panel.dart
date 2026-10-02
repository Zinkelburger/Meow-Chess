import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import '../application/tournament_controller.dart';
import '../domain/history.dart';
import '../domain/model.dart';
import 'dialogs.dart';

/// Moves through history at once. When that takes away play already
/// recorded, a notice says what and offers the way back; nothing is lost,
/// because the state being left stays in History. [move] receives whether
/// that removal was accepted.
void travel(
  BuildContext context,
  TournamentController c,
  int? node,
  void Function(bool acceptLosses) move,
) {
  if (node == null) return;
  try {
    final from = c.graph.head;
    final lost = c.lossesTo(node);
    move(lost.isNotEmpty);
    if (lost.isNotEmpty && from != null && context.mounted) {
      showNotice(
        context,
        'Went back past recorded play: ${lost.join('; ')}.',
        action: SnackBarAction(
          label: 'Go forward',
          onPressed: () {
            try {
              c.restore(from, acceptLosses: true);
            } catch (e) {
              if (context.mounted) showFailure(context, e);
            }
          },
        ),
      );
    }
  } catch (e) {
    if (context.mounted) showFailure(context, e);
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

const _rowHeight = 60.0, _laneWidth = 14.0, _maxLanes = 6;

class HistoryPanel extends StatefulWidget {
  const HistoryPanel({
    required this.controller,
    required this.onClose,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;
  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<HistoryPanel> {
  TournamentController get c => widget.controller;
  final focus = FocusNode(debugLabel: 'history');
  final scroll = ScrollController();
  final expandedBranches = <int>{};
  final rowKeys = <int, GlobalKey>{};
  final expandedPreviews = <String>{};
  int? selected;
  int? shownHead;

  // Saved states are immutable. Only visible operations need to be read.
  final snapshots = <int, Event>{};
  final changes = <int, List<String>>{};
  Event snapshot(int id) => snapshots[id] ??= c.repository.snapshot(id);
  List<String> step(int id) => changes.putIfAbsent(id, () {
    final node = c.graph.nodes[id]!;
    if (node.parent == null) return const [];
    try {
      return describeChanges(
        snapshot(node.parent!),
        snapshot(id),
        includePrevious: false,
      );
    } catch (_) {
      return ['Details unavailable'];
    }
  });

  String title(int id) {
    final items = step(id);
    final text = items.length == 1 ? items.single : c.graph.nodes[id]!.action;
    final colon = text.indexOf(': ');
    if (colon < 0 || colon + 2 >= text.length) return text;
    return text.substring(0, colon + 2) +
        text[colon + 2].toUpperCase() +
        text.substring(colon + 3);
  }

  @override
  void dispose() {
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  void select(int? id) {
    setState(() => selected = id);
    focus.requestFocus();
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
      }
    });
  }

  void back() =>
      travel(context, c, c.graph.back, (a) => c.undo(acceptLosses: a));
  void forward() =>
      travel(context, c, c.graph.forward, (a) => c.redo(acceptLosses: a));
  void restore(int id) =>
      travel(context, c, id, (a) => c.restore(id, acceptLosses: a));

  KeyEventResult key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rows = c.graph.folded(expandedBranches).rows;
    final index = rows.indexWhere(
      (r) => r.node.id == (selected ?? c.graph.head),
    );
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        back();
      case LogicalKeyboardKey.arrowRight:
        forward();
      case LogicalKeyboardKey.arrowUp when index > 0:
        select(rows[index - 1].node.id);
      case LogicalKeyboardKey.arrowDown
          when index >= 0 && index < rows.length - 1:
        select(rows[index + 1].node.id);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter
          when selected != null && selected != c.graph.head:
        restore(selected!);
      case LogicalKeyboardKey.escape:
        select(null);
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
    final visible = graph.folded(expandedBranches);
    final lanes = math.min(
      _maxLanes,
      visible.rows.fold(
        1,
        (n, r) => math.max(
          n,
          math.max(r.lane + 1, math.max(r.top.length, r.bottom.length)),
        ),
      ),
    );
    final small = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border(left: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: Row(
              children: [
                Text('History', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: c.canUndo ? 'Undo ${c.undoLabel}' : 'At the start',
                  icon: const Icon(Icons.undo, size: 19),
                  onPressed: c.canUndo ? back : null,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: c.canRedo ? 'Redo ${c.redoLabel}' : 'Nothing ahead',
                  icon: const Icon(Icons.redo, size: 19),
                  onPressed: c.canRedo ? forward : null,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Close history (Ctrl+H)',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.onClose,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Padding(
            key: const ValueKey('history-keys'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Select a step to review it. ← → undo and redo · ↑ ↓ review · Enter restores · Esc closes details',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: Focus(
              focusNode: focus,
              onKeyEvent: key,
              child: ListView.builder(
                key: const ValueKey('history-graph'),
                controller: scroll,
                scrollCacheExtent: const ScrollCacheExtent.pixels(600),
                itemCount: visible.rows.length,
                itemBuilder: (context, i) {
                  final row = visible.rows[i], id = row.node.id;
                  final isHead = id == graph.head;
                  final branch = graph.branches[id];
                  final expanded = expandedBranches.contains(id);
                  final isSelected = selected == id;
                  return Material(
                    color: isSelected
                        ? colors.primary.withValues(alpha: 0.07)
                        : Colors.transparent,
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 8 + lanes * _laneWidth,
                            child: CustomPaint(
                              painter: _GraphPainter(row, graph, colors),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                InkWell(
                                  key: ValueKey('history-$id'),
                                  onTap: () => select(isSelected ? null : id),
                                  child: Container(
                                    key: rowKeys.putIfAbsent(
                                      id,
                                      () => GlobalKey(),
                                    ),
                                    constraints: const BoxConstraints(
                                      minHeight: _rowHeight,
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                      6,
                                      10,
                                      12,
                                      10,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              '#$id',
                                              style: small.copyWith(
                                                fontFamily: 'SourceCodePro',
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (isHead)
                                              Text(
                                                'Current',
                                                style: small.copyWith(
                                                  color: colors.primary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              )
                                            else if (graph.style(id) ==
                                                NodeStyle.future)
                                              Text('Ahead', style: small),
                                            const Spacer(),
                                            Text(
                                              historyTime(row.node.timestamp),
                                              style: small,
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(
                                              isSelected
                                                  ? Icons.expand_less
                                                  : Icons.expand_more,
                                              size: 15,
                                              color: colors.onSurfaceVariant,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          title(id),
                                          maxLines: isSelected ? null : 2,
                                          overflow: isSelected
                                              ? null
                                              : TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            height: 1.35,
                                            fontWeight: FontWeight.w600,
                                            color: colors.onSurface,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (branch != null)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      key: ValueKey('history-branch-$id'),
                                      onPressed: () {
                                        setState(() {
                                          if (expanded) {
                                            expandedBranches.remove(id);
                                            if (branch.contains(selected)) {
                                              selected = id;
                                            }
                                          } else {
                                            expandedBranches.add(id);
                                          }
                                        });
                                        focus.requestFocus();
                                      },
                                      icon: Icon(
                                        expanded
                                            ? Icons.unfold_less
                                            : Icons.account_tree_outlined,
                                        size: 15,
                                      ),
                                      label: Text(
                                        '${expanded ? 'Collapse' : 'Saved'} branch · ${branch.length} ${branch.length == 1 ? 'operation' : 'operations'}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                if (isSelected) _details(context, id, graph),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text('All branches are saved.', style: small),
          ),
        ],
      ),
    );
  }

  Widget _details(BuildContext context, int id, HistoryGraph graph) {
    final colors = Theme.of(context).colorScheme;
    final items = step(id), path = graph.pathTo(id);
    List<String> lost;
    try {
      lost = id == graph.head ? [] : playLost(c.event!, snapshot(id));
    } catch (_) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('This saved state could not be read.'),
      );
    }
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
    Widget operation(int operationId) => Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '#$operationId',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'SourceCodePro',
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              title(operationId),
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
    List<Widget> operations(String verb, List<int> ids) {
      if (ids.isEmpty) return [];
      final key = '$id|${graph.head}|$verb';
      final expanded = expandedPreviews.contains(key);
      return [
        label(
          '$verb ${ids.length} ${ids.length == 1 ? 'operation' : 'operations'}',
        ),
        for (final operationId in expanded ? ids : ids.take(4))
          operation(operationId),
        if (ids.length > 4)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                if (expanded) {
                  expandedPreviews.remove(key);
                } else {
                  expandedPreviews.add(key);
                }
              }),
              child: Text(
                expanded ? 'Show fewer' : 'Show ${ids.length - 4} more',
              ),
            ),
          ),
      ];
    }

    return Padding(
      key: ValueKey('history-details-$id'),
      padding: const EdgeInsets.fromLTRB(6, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.length > 1) ...[
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  item,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
          ],
          if (id == graph.head)
            Text(
              'You are here.',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            )
          else ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const ValueKey('history-restore'),
                onPressed: () => restore(id),
                icon: const Icon(Icons.restore, size: 16),
                label: Text('Restore #$id'),
              ),
            ),
            ...operations('Undo', path.undo),
            ...operations('Apply', path.apply),
            if (lost.isNotEmpty) ...[
              label('Recorded play affected'),
              for (final item in lost)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    item,
                    style: TextStyle(fontSize: 12, color: colors.error),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.row, this.graph, this.colors);
  final GraphRow row;
  final HistoryGraph graph;
  final ColorScheme colors;

  Color color(int child) => switch (graph.style(child)) {
    NodeStyle.past => colors.primary,
    NodeStyle.future => colors.primary.withValues(alpha: 0.4),
    NodeStyle.branch => colors.outline,
  };

  @override
  void paint(Canvas canvas, Size size) {
    double x(int lane) => 12 + math.min(lane, _maxLanes - 1) * _laneWidth;
    const cy = _rowHeight / 2;
    final line = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final lanes = math.max(row.top.length, row.bottom.length);
    for (var i = 0; i < lanes; i++) {
      final top = i < row.top.length ? row.top[i] : null;
      final bottom = i < row.bottom.length ? row.bottom[i] : null;
      if (i == row.lane) {
        if (top != null) {
          canvas.drawLine(
            Offset(x(i), 0),
            Offset(x(i), cy),
            line..color = color(top),
          );
        }
        if (bottom != null) {
          canvas.drawLine(
            Offset(x(i), cy),
            Offset(x(i), size.height),
            line..color = color(bottom),
          );
        }
      } else if (row.merges.contains(i) && top != null) {
        canvas.drawPath(
          Path()
            ..moveTo(x(i), 0)
            ..quadraticBezierTo(x(i), cy, x(row.lane), cy),
          line..color = color(top),
        );
      } else if (top != null) {
        canvas.drawLine(
          Offset(x(i), 0),
          Offset(x(i), size.height),
          line..color = color(top),
        );
      }
    }
    final id = row.node.id, center = Offset(x(row.lane), cy);
    final style = graph.style(id);
    final ring = color(id);
    if (id == graph.head) {
      canvas.drawCircle(
        center,
        7,
        Paint()..color = ring.withValues(alpha: 0.25),
      );
    }
    canvas.drawCircle(
      center,
      id == graph.head ? 5 : 4,
      Paint()
        ..color = style == NodeStyle.past
            ? ring
            : colors.surfaceContainerLowest,
    );
    canvas.drawCircle(
      center,
      id == graph.head ? 5 : 4,
      Paint()
        ..color = ring
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
