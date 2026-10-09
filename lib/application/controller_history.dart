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
  HistoryGraph get graph => _graph ??= repository.historyGraph();

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
    _move(graph.back!, 'Undo $undoLabel', acceptLosses);
  }

  void redo({bool acceptLosses = false}) {
    _refuseClosed('Redo');
    if (!canRedo) return;
    _move(graph.forward!, 'Redo $redoLabel', acceptLosses);
  }

  void restore(int node, {bool acceptLosses = false}) {
    _refuseClosed('Restore #$node');
    if (node == graph.head) return;
    _move(
      node,
      'Restore #$node · ${graph.nodes[node]?.action ?? ''}',
      acceptLosses,
    );
  }

  void _move(int node, String action, bool acceptLosses) {
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
      event = repository.checkout(
        node,
        expectedRevision: event!.revision,
        action: action,
      );
      _graph = null;
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
