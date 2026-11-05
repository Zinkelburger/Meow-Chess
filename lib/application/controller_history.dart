part of 'tournament_controller_core.dart';

/// Back, Forward and Restore over the event's saved history graph. Every move
/// is one audited checkout, so it advances the revision like any other save.
mixin _ControllerHistory on ChangeNotifier {
  EventRepository get repository;
  Event? get event;
  set event(Event? value);

  /// Whether the event file has been released.
  bool get _closed;

  HistoryGraph? _graph;

  /// The last Undo, Redo or Restore and the version it left, until the next
  /// change: what the status line reports, with the way back.
  ({String verb, int from, int to})? lastMove;

  /// The newest version saved: where Return to latest goes after moving
  /// back. A version left by going back stays in the history, so the newest
  /// one is the work most recently done.
  int? get latestNode => graph.nodes.keys.fold<int?>(
    null,
    (newest, id) => newest == null || id > newest ? id : newest,
  );

  // Saved states never change, so their landmarks are worked out once.
  final _marks = <int, List<RecoveryMark>>{};

  /// Recovery points on the event's line, newest first: before each round
  /// was paired or unpaired, before each import and each move of players.
  /// [limit] stops the walk early, as reading saved states costs time.
  List<RecoveryPoint> recoveryPoints({int? limit}) {
    if (_closed) throw const TournamentException('This event has closed.');
    final out = <RecoveryPoint>[];
    final graph = this.graph;
    Event? child;
    for (int? id = graph.head; id != null; id = graph.nodes[id]?.parent) {
      final node = graph.nodes[id]!, parent = node.parent;
      if (parent == null) break;
      Event? before;
      final marks = _marks[id] ??= recoveryMarks(
        before = repository.snapshot(parent),
        child ?? repository.snapshot(id),
      );
      child = before;
      for (final mark in marks) {
        out.add(RecoveryPoint(parent, id, mark, node.timestamp));
      }
      if (limit != null && out.length >= limit) break;
    }
    return out;
  }

  /// The saved history. History lives in the event file, so once the event
  /// has closed only a graph already read remains; otherwise it refuses
  /// plainly instead of surfacing a database error.
  HistoryGraph get graph {
    if (_graph case final graph?) return graph;
    if (_closed) throw const TournamentException('This event has closed.');
    return _graph = repository.historyGraph();
  }

  /// The step Back would undo, and the one Forward would redo.
  String? get undoLabel =>
      graph.back == null ? null : graph.nodes[graph.head]?.action;
  String? get redoLabel => graph.nodes[graph.forward]?.action;
  bool get canUndo => graph.back != null;
  bool get canRedo => graph.forward != null;

  /// What happened at the board that moving to [node] would take away. The
  /// UI confirms these; nothing is lost for good, because the state being
  /// left stays in the graph.
  List<String> lossesTo(int node) {
    // A read, so it refuses plainly without logging a failed save.
    if (_closed) throw const TournamentException('This event has closed.');
    return playLost(event!, repository.snapshot(node));
  }

  /// History lives in the event file, so a closed event cannot read it.
  void _refuseClosed(String action) {
    if (!_closed) return;
    const error = TournamentException('This event has closed.');
    Diagnostics.record(
      'save event',
      'failed',
      context: {'action': action},
      error: error,
    );
    throw error;
  }

  void undo({bool acceptLosses = false}) {
    _refuseClosed('Undo');
    if (!canUndo) return;
    _move(graph.back!, 'Undo $undoLabel', acceptLosses, 'Undid');
  }

  void redo({bool acceptLosses = false}) {
    _refuseClosed('Redo');
    if (!canRedo) return;
    _move(graph.forward!, 'Redo $redoLabel', acceptLosses, 'Redid');
  }

  void restore(int node, {bool acceptLosses = false}) {
    _refuseClosed('Restore #$node');
    if (node == graph.head) return;
    _move(
      node,
      'Restore #$node · ${graph.nodes[node]?.action ?? ''}',
      acceptLosses,
      'Went to',
    );
  }

  void _move(int node, String action, bool acceptLosses, String verb) {
    final context = <String, Object?>{
      'action': action,
      'eventId': event?.id,
      'revision': event?.revision,
      'node': node,
    };
    Diagnostics.record('save event', 'started', context: context);
    try {
      if (_closed) throw const TournamentException('This event has closed.');
      final target = repository.snapshot(node);
      // History before a copy was marked practice belongs to the original
      // event; restoring it would also restore that event's backup folder.
      if (event!.practice && !target.practice) {
        throw const TournamentException(
          'This practice copy cannot go back to before it was copied.',
        );
      }
      final lost = playLost(event!, target);
      if (lost.isNotEmpty && !acceptLosses) {
        throw TournamentException(
          'Going there removes play already recorded: ${lost.join('; ')}.',
        );
      }
      final from = graph.head!;
      event = repository.checkout(
        node,
        expectedRevision: event!.revision,
        action: action,
      );
      _graph = null;
      lastMove = (verb: verb, from: from, to: node);
      Diagnostics.record(
        'save event',
        'succeeded',
        context: {...context, 'revision': event!.revision},
      );
    } catch (error, stack) {
      Diagnostics.record(
        'save event',
        'failed',
        context: context,
        error: error,
        stack: stack,
      );
      rethrow;
    }
    // Outside the try: the save has succeeded, so a failing listener must not
    // be logged as a failed save.
    notifyListeners();
  }
}
