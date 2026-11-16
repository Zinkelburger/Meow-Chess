import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/history.dart';

HistoryNode node(int id, int? parent, {int visit = 0}) => HistoryNode(
  id: id,
  parent: parent,
  action: 'step $id',
  timestamp: '2026-10-09T12:00:00Z',
  lastVisit: visit,
);

void main() {
  test('forward follows the most recently visited branch', () {
    final nodes = [
      node(1, null, visit: 1),
      node(2, 1, visit: 2),
      node(3, 1, visit: 5),
      node(4, 3, visit: 6),
    ];
    final graph = HistoryGraph(nodes, 1);
    expect(graph.future, [3, 4]);
    expect(graph.style(2), NodeStyle.branch);
    final path = graph.pathTo(2);
    expect(path.undo, isEmpty);
    expect(path.apply, [2]);
  });

  test('equal visits pick the same child whatever the input order', () {
    final nodes = [node(1, null), node(2, 1), node(3, 1)];
    expect(HistoryGraph(nodes, 1).forward, 2);
    expect(HistoryGraph(nodes.reversed, 1).forward, 2);
  });
}
