import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/tournament_controller.dart';
import '../domain/history.dart';
import '../domain/model.dart';
import 'dialogs.dart';

/// Moves through history, first confirming when that removes play already
/// recorded. [move] receives whether that removal was accepted.
Future<void> travel(
  BuildContext context,
  TournamentController c,
  int? node,
  void Function(bool acceptLosses) move,
) async {
  if (node == null) return;
  try {
    final lost = c.lossesTo(node);
    if (lost.isNotEmpty &&
        !await confirm(
          context,
          'Go back past recorded play?',
          'This removes play that has already been recorded:\n\n'
              '${lost.map((l) => '•  $l').join('\n')}\n\n'
              'Nothing is deleted for good: the current state stays in History, '
              'so you can go forward to it again.',
          action: 'Go back anyway',
        )) {
      return;
    }
    move(lost.isNotEmpty);
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

const _rowHeight = 32.0, _laneWidth = 14.0, _maxLanes = 8;

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

  /// The row being reviewed; null follows the current state.
  int? selected;
  int? shownHead;

  /// Snapshots never change, so each is decompressed at most once.
  final snapshots = <int, Event>{};
  Event snapshot(int id) => snapshots[id] ??= c.repository.snapshot(id);

  (String, List<String>, List<String>, List<String>)? details;
  String? detailsKey;

  @override
  void dispose() {
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  void select(int? id) {
    setState(() => selected = id);
    focus.requestFocus();
    final index = c.graph.rows.indexWhere((r) => r.node.id == id);
    if (index < 0 || !scroll.hasClients) return;
    final top = index * _rowHeight, view = scroll.position.viewportDimension;
    if (top < scroll.offset) {
      scroll.jumpTo(top);
    } else if (top + _rowHeight > scroll.offset + view) {
      scroll.jumpTo(top + _rowHeight - view);
    }
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
    final rows = c.graph.rows;
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
      case LogicalKeyboardKey.arrowDown when index < rows.length - 1:
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

  /// Title, what the step itself changed, what restoring it would change,
  /// and the recorded play a restore would remove.
  (String, List<String>, List<String>, List<String>) describe(int id) {
    final graph = c.graph, node = graph.nodes[id]!;
    final state = snapshot(id);
    final step = node.parent == null
        ? ['Start of this event’s history']
        : describeChanges(snapshot(node.parent!), state);
    final isHead = id == graph.head;
    return (
      '#$id · ${node.action}',
      step,
      isHead ? const [] : describeChanges(c.event!, state),
      isHead ? const [] : playLost(c.event!, state),
    );
  }

  @override
  Widget build(BuildContext context) {
    final graph = c.graph, colors = Theme.of(context).colorScheme;
    if (graph.head != shownHead) {
      // After a move, review follows the current state again.
      shownHead = graph.head;
      selected = null;
    }
    final current = selected ?? graph.head;
    final wanted = '$current|${c.event?.revision}';
    if (current != null && wanted != detailsKey) {
      try {
        details = describe(current);
      } catch (e) {
        details = ('History could not be read', ['$e'], const [], const []);
      }
      detailsKey = wanted;
    }
    final lanes = math.min(
      _maxLanes,
      graph.rows.fold(
        1,
        (n, r) => math.max(
          n,
          math.max(r.lane + 1, math.max(r.top.length, r.bottom.length)),
        ),
      ),
    );
    final small = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    return Container(
      width: 380,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border(left: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              children: [
                Text('History', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: c.canUndo
                      ? 'Back: undo ${c.undoLabel}'
                      : 'At the start',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: c.canUndo ? back : null,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: c.canRedo
                      ? 'Forward: redo ${c.redoLabel}'
                      : 'Nothing ahead',
                  icon: const Icon(Icons.chevron_right),
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              '← → step back and forward · ↑ ↓ review · Enter restores',
              style: small,
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            flex: 3,
            child: Focus(
              focusNode: focus,
              onKeyEvent: key,
              child: ListView.builder(
                key: const ValueKey('history-graph'),
                controller: scroll,
                itemExtent: _rowHeight,
                itemCount: graph.rows.length,
                itemBuilder: (context, i) {
                  final row = graph.rows[i], id = row.node.id;
                  final isHead = id == graph.head;
                  final style = graph.style(id);
                  return Material(
                    color: id == current
                        ? colors.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    child: InkWell(
                      key: ValueKey('history-$id'),
                      onTap: () => select(id),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 8 + lanes * _laneWidth,
                            height: _rowHeight,
                            child: CustomPaint(
                              painter: _GraphPainter(row, graph, colors),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              row.node.action,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isHead ? FontWeight.w600 : null,
                                color: style == NodeStyle.branch
                                    ? colors.onSurfaceVariant
                                    : colors.onSurface,
                              ),
                            ),
                          ),
                          if (isHead)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                'Now',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onPrimary,
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          Text(historyTime(row.node.timestamp), style: small),
                          const SizedBox(width: 12),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            flex: 2,
            child: current == null || details == null
                ? const SizedBox()
                : _details(context, current, graph, details!),
          ),
        ],
      ),
    );
  }

  Widget _details(
    BuildContext context,
    int id,
    HistoryGraph graph,
    (String, List<String>, List<String>, List<String>) d,
  ) {
    final colors = Theme.of(context).colorScheme;
    final (title, step, restoring, lost) = d;
    final isHead = id == graph.head;
    final node = graph.nodes[id]!;
    final small = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
    Iterable<Widget> lines(List<String> items, {Color? color}) sync* {
      const limit = 12;
      if (items.isEmpty) {
        yield Text('No visible changes', style: small);
      }
      for (final item in items.take(limit)) {
        yield Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text('•  $item', style: TextStyle(fontSize: 13, color: color)),
        );
      }
      if (items.length > limit) {
        yield Text('…and ${items.length - limit} more', style: small);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${historyTime(node.timestamp)}${isHead
                    ? ' · current state'
                    : graph.style(id) == NodeStyle.branch
                    ? ' · on a side branch'
                    : graph.style(id) == NodeStyle.future
                    ? ' · ahead of now'
                    : ''}',
                style: small,
              ),
              heading('THIS STEP'),
              ...lines(step),
              if (!isHead) ...[
                if (lost.isNotEmpty) ...[
                  heading('RECORDED PLAY THAT WOULD BE REMOVED'),
                  ...lines(lost, color: colors.error),
                ],
                heading('RESTORING HERE WOULD CHANGE'),
                ...lines(restoring),
              ],
            ],
          ),
        ),
        // Kept outside the scroll so it never slides out of reach.
        if (!isHead)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('history-restore'),
              onPressed: () => restore(id),
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Restore to this point'),
            ),
          ),
      ],
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
    final cy = size.height / 2;
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
