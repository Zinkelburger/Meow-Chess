import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../application/diagnostics.dart';
import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/posted_results.dart';
import '../infrastructure/web_results.dart';
import 'dialogs.dart' show showFailure;
import 'workspace_status.dart' show showUndoNotice;

/// Reads the rounds a club's results page lists now.
typedef PostedResultsLoader = Future<List<PostedRound>> Function(String url);

/// Results players enter on the club's website, entered here as they come
/// in. While on, the results page is read every few seconds; each result
/// it brings in is a step of the event's history like one typed at the
/// board, so Undo takes it back. Nothing is ever sent to the website.
///
/// It belongs to the workspace, not to a page, so results keep arriving
/// while the director is looking at players or reports. Whether it is on,
/// the page's address and what has been taken are kept with the event's
/// workspace settings, so reopening the event carries on.
class LiveResults extends ChangeNotifier {
  LiveResults(
    this.controller, {
    PostedResultsLoader? loader,
    this.hold,
    this.onTaken,
    this.interval = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _loader = loader,
       _now = now ?? DateTime.now {
    final saved = controller.workspaceState.readMap(_key);
    url = saved['url'] as String? ?? '';
    _on = saved['on'] == true && url.isNotEmpty;
    for (final MapEntry(:key, :value)
        in (saved['taken'] as Map? ?? {}).entries) {
      final outcome = Outcome.values.where((o) => o.name == value).firstOrNull;
      if (outcome != null) _taken['$key'] = outcome;
    }
    controller.addListener(_eventChanged);
  }

  static const _key = 'live-results';
  final TournamentController controller;
  final PostedResultsLoader? _loader;
  final DateTime Function() _now;

  /// True while something else is about to change the event (pairings
  /// being made); results wait for the next reading.
  final bool Function()? hold;

  /// Told what a reading entered, to show with Undo.
  final void Function(String message)? onTaken;

  /// How often the page is read while boards wait for results.
  final Duration interval;

  /// The results page's address, kept after stopping to offer it again.
  String url = '';
  bool _on = false;
  bool get on => _on;

  /// Whether the director is choosing the page to read.
  bool settingUp = false;

  /// Whether there is anything to show above the boards.
  bool get shown => _on || settingUp;

  /// When the page was last read successfully, and why the latest reading
  /// failed, if it did.
  DateTime? checkedAt;
  String? failure;

  /// What the latest reading means for the event as it is now.
  PostedReading reading = const PostedReading();

  String get host => Uri.tryParse(url)?.host ?? '';

  final _taken = <String, Outcome>{};
  var _held = <String>{};
  List<PostedRound>? _posted;
  http.Client? _client;
  Timer? _timer;
  Future<void>? _reading;
  bool _slow = false, _disposed = false;
  int _failures = 0, _generation = 0;

  Future<List<PostedRound>> _load(String url) =>
      (_loader ?? WebResults(_client ??= http.Client()).fetch)(url);

  /// The results page already known for this event: the one used before,
  /// or that of the club its entry list came from. Null when neither.
  String? get knownUrl => url.isNotEmpty
      ? url
      : suggestResultsUrl(
          controller.event?.rosterSource['url'] as String? ?? '',
        );

  /// The address to offer when the director is asked for one: the known
  /// one, or the Boylston Chess Foundation's.
  String get suggestedUrl => knownUrl ?? defaultResultsPage;

  /// Whether website results are offered for this event at all: its
  /// players came from a club whose results page can be read, or the
  /// director has taken results from a page before. Any other event has
  /// no button for them.
  bool get available => knownUrl != null;

  /// The toolbar's switch. Off to on starts at once when the page is
  /// known, as for an event imported from the club's entry list, and asks
  /// for the address otherwise.
  void toggle() {
    if (_on) return stop();
    if (settingUp) return openSetup(false);
    if (knownUrl case final known?) {
      try {
        return start(known);
      } on TournamentException {
        // An address this version can no longer read: ask again.
      }
    }
    openSetup(true);
  }

  /// Stops, and asks which page to read instead.
  void changePage() {
    stop();
    openSetup(true);
  }

  /// Carries on after the event is reopened with results still on.
  void resume() {
    if (_on) unawaited(check());
  }

  /// Starts taking results from [address]. Refuses an address that is not
  /// a results page this app can read.
  void start(String address) {
    url = resolveResultsUrl(address).toString();
    _on = true;
    settingUp = false;
    _generation++;
    _failures = 0;
    failure = null;
    checkedAt = null;
    _posted = null;
    reading = const PostedReading();
    _save();
    notifyListeners();
    unawaited(check());
  }

  void stop() {
    _on = false;
    settingUp = false;
    _generation++;
    _timer?.cancel();
    _posted = null;
    failure = null;
    reading = const PostedReading();
    _save();
    notifyListeners();
  }

  void openSetup(bool open) {
    settingUp = open && !_on;
    notifyListeners();
  }

  void _save() => controller.workspaceState.writeMap(_key, {
    'url': url,
    'on': _on,
    'taken': {for (final e in _taken.entries) e.key: e.value.name},
  });

  bool get _waiting => controller.pairingEvent.sections.any(
    (s) => s.rounds.any((r) => !r.complete),
  );

  void _schedule() {
    _timer?.cancel();
    if (!_on || _disposed) return;
    // A page that cannot be reached is tried less often, and so is one
    // with no board waiting, where only a correction could arrive.
    _slow = _failures == 0 && !_waiting;
    final factor = _failures > 0 ? math.min(1 << (_failures - 1), 6) : 1;
    _timer = Timer(interval * (_slow ? 6 : factor), check);
  }

  void _eventChanged() {
    if (_disposed || !_on || controller.closed) return;
    if (_posted case final posted?) {
      // The same reading against the event as it is now, so a board the
      // director has just settled leaves the list at once.
      reading = _compare(posted, held: _held);
      notifyListeners();
    }
    // A round was just posted: look for it now, not in a minute.
    if (_slow && _reading == null && _waiting) _schedule();
  }

  /// Reads the page once and enters what it brings. A reading already
  /// under way is the one returned.
  Future<void> check() =>
      _reading ??= _read().whenComplete(() => _reading = null);

  Future<void> _read() async {
    if (!_on || _disposed || controller.closed) return;
    _timer?.cancel();
    final generation = _generation;
    bool stale() => _disposed || generation != _generation || controller.closed;
    try {
      final List<PostedRound> posted;
      try {
        posted = await _load(url);
      } catch (error, stack) {
        if (stale()) return;
        // Tried again by itself, so only the first failure in a row is
        // logged.
        if (_failures++ == 0) {
          Diagnostics.record(
            'read website results',
            'failed',
            context: {'url': Diagnostics.sourceUrl(url)},
            error: error,
            stack: stack,
          );
        }
        failure =
            '${plainMessage(error)} Trying again; meanwhile enter results '
            'here yourself.';
        return;
      }
      if (stale()) return;
      _posted = posted;
      _failures = 0;
      failure = null;
      checkedAt = _now();
      try {
        if (!(hold?.call() ?? false)) _enter(posted);
      } catch (error, stack) {
        Diagnostics.record(
          'enter website results',
          'failed',
          error: error,
          stack: stack,
        );
        failure =
            'Could not enter the website\'s results. ${plainMessage(error)}';
      }
      reading = _compare(posted, held: _held);
    } finally {
      if (!stale()) {
        _schedule();
        notifyListeners();
      } else if (_on && !_disposed && !controller.closed) {
        // Stopped and started again while this reading was under way: its
        // page is not used, and the new address is read straight away.
        _timer?.cancel();
        _timer = Timer(Duration.zero, check);
      }
    }
  }

  /// What [posted] means for the event as it is now. Rounds a later round
  /// was paired after are not followed: the website changes none of their
  /// results, and any it shows differently are listed for the director.
  PostedReading _compare(
    List<PostedRound> posted, {
    Set<String> held = const {},
  }) {
    final stored = controller.event!;
    return readPostedResults(
      controller.pairingEvent,
      posted,
      taken: _taken,
      held: held,
      settled: settledGames(
        stored,
        dependsOn: stored.transitions.isEmpty
            ? null
            : controller.correctionHasDependencies,
      ),
    );
  }

  void _enter(List<PostedRound> posted) {
    final found = _compare(posted);
    final entered = <String>[];
    _held = {};
    // Each result is its own saved step. If one fails, those already
    // entered are still recorded as taken from the website, so its later
    // corrections are followed and one cleared here is not entered again.
    try {
      if (found.take.isNotEmpty) {
        _held = controller
            .recordPostedResults(
              found.take,
              source: host,
              onEntered: (id) {
                _taken[id] = found.take[id]!;
                entered.add(id);
              },
            )
            .toSet();
      }
      for (final MapEntry(:key, :value) in found.corrections.entries) {
        // Never past a later round, even if one was paired since the page
        // was compared: that change is the director's to enter.
        if (controller.correctionHasDependencies(key)) continue;
        try {
          controller.recordResult(
            key,
            value,
            reason: 'Changed on $host',
            source: host,
          );
          _taken[key] = value;
          entered.add(key);
        } on TournamentException {
          // No longer this app's to follow: listed for the director.
          _taken.remove(key);
        }
      }
    } finally {
      if (entered.isNotEmpty) {
        _save();
        onTaken?.call(_describe(entered));
      }
    }
  }

  /// "Board 4, Winter – Cai: 1–0, from the website." for one result. For
  /// several, the boards, and which of them Undo takes back: each result
  /// is its own step, and the latest is the last one listed.
  String _describe(List<String> ids) {
    final e = controller.event!;
    final games = {for (final g in e.games) g.id: g};
    final many = e.sections.where((s) => s.rounds.isNotEmpty).length > 1;
    String board(String id) {
      final g = games[id]!;
      final section = e.sections.firstWhere(
        (s) => s.rounds.any((r) => r.games.contains(g)),
      );
      return '${many ? '${section.name} ' : ''}board ${g.board}';
    }

    final last = games[ids.last]!;
    if (ids.length == 1) {
      final where = board(ids.single);
      return '${where[0].toUpperCase()}${where.substring(1)}, '
          '${e.player(last.white).name} – ${e.player(last.black).name}: '
          '${last.outcome.label}, from $host.';
    }
    return '${ids.length} results from $host: ${ids.map(board).join(', ')}. '
        'Undo takes back ${board(ids.last)}; the others are in History.';
  }

  /// Enters the website's result for [difference], replacing this event's.
  void use(PostedDifference difference) {
    final website = difference.website;
    if (website == null || difference.byHand) return;
    // Once a later round is paired the website changes nothing here, even
    // if one was paired since the difference was listed.
    if (controller.correctionHasDependencies(difference.gameId)) return;
    controller.recordResult(
      difference.gameId,
      website,
      reason: 'As entered on $host',
    );
    _taken[difference.gameId] = website;
    _save();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _client?.close();
    controller.removeListener(_eventChanged);
    super.dispose();
  }
}

/// On the boards' toolbar, for an event whose results players enter on the
/// club's website: starts taking them, or stops when they are on.
///
/// It is the one tinted button on the toolbar while results are off,
/// because forgetting it means typing in a round the website already has.
/// Once on it settles to the selected surface, and the strip above the
/// boards carries the tint. The label never changes, only the icon and
/// fill, so nothing beside it moves.
class LiveResultsButton extends StatelessWidget {
  const LiveResultsButton(this.live, {this.enabled = true, super.key});
  final LiveResults live;

  /// False greys the button while there are no boards to take results
  /// for; it keeps its place, so the toolbar does not reflow when they
  /// come.
  final bool enabled;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: live,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final on = live.on;
      final picked = on || live.settingUp;
      final site = Uri.tryParse(live.suggestedUrl)?.host ?? 'the club website';
      return Tooltip(
        message: on
            ? 'Stop taking results from ${live.host}'
            : 'Enter results here as players enter them on $site',
        child: OutlinedButton.icon(
          key: const ValueKey('live-results-button'),
          style: OutlinedButton.styleFrom(
            backgroundColor: picked
                ? colors.surfaceContainerHigh
                : colors.secondaryContainer,
            // Ink on the tint, as on every outlined button: the fill is the
            // signal, and the label stays as easy to read.
            foregroundColor: colors.onSurface,
            disabledBackgroundColor: colors.surfaceContainerLowest,
          ),
          icon: Icon(
            !on
                ? Icons.cloud_download_outlined
                : live.failure != null
                ? Icons.cloud_off_outlined
                : Icons.cloud_done_outlined,
            key: ValueKey(
              !on
                  ? 'live-results-off'
                  : live.failure != null
                  ? 'live-results-failing'
                  : 'live-results-on',
            ),
            size: 18,
          ),
          label: const Text('Website results'),
          onPressed: enabled || on ? live.toggle : null,
        ),
      );
    },
  );
}

/// Above the boards: the page to take results from while it is being
/// chosen, then what is being followed, when it was last read, and every
/// board where the website and the event disagree.
class LiveResultsStrip extends StatelessWidget {
  const LiveResultsStrip({
    required this.live,
    required this.controller,
    super.key,
  });
  final LiveResults live;
  final TournamentController controller;

  void _use(BuildContext context, PostedDifference difference) {
    try {
      live.use(difference);
      showUndoNotice(
        context,
        controller,
        'Board ${difference.board}, ${difference.white} – '
        '${difference.black}: ${difference.website!.label}, as on the '
        'website.',
      );
    } catch (e) {
      showFailure(context, e);
    }
  }

  static String _clock(DateTime t) =>
      [t.hour, t.minute, t.second].map((n) => '$n'.padLeft(2, '0')).join(':');

  static String _list(List<String> items) => items.length < 2
      ? items.join()
      : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: live,
    builder: (context, _) {
      if (!live.on && !live.settingUp) return const SizedBox.shrink();
      final colors = Theme.of(context).colorScheme;
      // Even-width digits: the read time ticks over without nudging the
      // buttons after it.
      final style = TextStyle(
        color: colors.onSecondaryContainer,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      final r = live.reading;
      final nameSection =
          controller.event!.sections.where((s) => s.rounds.isNotEmpty).length >
          1;
      return Container(
        key: const ValueKey('live-results'),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        // Many disagreements scroll inside the strip, so the boards
        // below always keep most of the pane.
        constraints: const BoxConstraints(maxHeight: 240),
        child: SingleChildScrollView(
          child: !live.on
              ? _LiveResultsSetup(live: live, style: style)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Beside the first line of the status, however far
                    // it wraps.
                    Padding(
                      padding: const EdgeInsets.only(top: 1, right: 8),
                      child: Icon(
                        live.failure == null
                            ? Icons.cloud_sync_outlined
                            : Icons.cloud_off_outlined,
                        size: 18,
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [
                              'Entering results from ${live.host} as '
                                  'players report them there.',
                              if (r.following.isNotEmpty)
                                'Following ${_list(r.following)}.',
                              if (live.checkedAt case final at?)
                                'Read at ${_clock(at)}.'
                              else if (live.failure == null)
                                'Reading the page…',
                            ].join(' '),
                            key: const ValueKey('live-results-status'),
                            style: style,
                          ),
                          if (live.failure case final failure?)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 2,
                                      right: 6,
                                    ),
                                    child: Icon(
                                      Icons.error_outline,
                                      size: 16,
                                      color: colors.error,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      failure,
                                      key: const ValueKey(
                                        'live-results-failure',
                                      ),
                                      style: style,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          for (final problem in r.problems)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(problem, style: style),
                            ),
                          for (final d in r.differences)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    d.describe(nameSection: nameSection),
                                    style: style,
                                  ),
                                  if (d.website case final website?
                                      when !d.byHand)
                                    OutlinedButton(
                                      key: ValueKey((
                                        'live-results-use',
                                        d.gameId,
                                      )),
                                      onPressed: () => _use(context, d),
                                      child: Text('Use ${website.label}'),
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                key: const ValueKey('live-results-stop'),
                                onPressed: live.stop,
                                child: const Text('Stop'),
                              ),
                              OutlinedButton(
                                key: const ValueKey('live-results-change'),
                                onPressed: live.changePage,
                                child: const Text('Change page'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      );
    },
  );
}

/// The choice of results page, shown until results are on.
class _LiveResultsSetup extends StatefulWidget {
  const _LiveResultsSetup({required this.live, required this.style});
  final LiveResults live;
  final TextStyle style;

  @override
  State<_LiveResultsSetup> createState() => _LiveResultsSetupState();
}

class _LiveResultsSetupState extends State<_LiveResultsSetup> {
  late final address = TextEditingController(text: widget.live.suggestedUrl);
  String? error;

  @override
  void dispose() {
    address.dispose();
    super.dispose();
  }

  void start() {
    try {
      widget.live.start(address.text);
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Results players report on the club website are entered here, each '
        'a step Undo takes back; any it cannot settle are listed for you to '
        'enter. For another club, paste its results page. Nothing is sent '
        'to the website.',
        style: widget.style,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            // Narrower in a narrow pane or at a large text size.
            constraints: const BoxConstraints(maxWidth: 360),
            child: TextField(
              key: const ValueKey('live-results-url'),
              controller: address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onSubmitted: (_) => start(),
              decoration: const InputDecoration(
                labelText: 'Results page',
                isDense: true,
              ),
            ),
          ),
          FilledButton(
            key: const ValueKey('live-results-start'),
            onPressed: start,
            child: const Text('Take results'),
          ),
          TextButton(
            onPressed: () => widget.live.openSetup(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
      if (error case final error?) ...[
        const SizedBox(height: 4),
        Text(
          error,
          key: const ValueKey('live-results-error'),
          style: widget.style,
        ),
      ],
    ],
  );
}
