import '../application/member_lookup.dart';
import 'player_actions.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../application/tournament_controller.dart';
import 'rating_refresh.dart';
import '../infrastructure/member_directory.dart';
import '../domain/model.dart';
import '../domain/pairing.dart';
import '../infrastructure/roster_import.dart' show ImportRow;
import 'dialogs.dart';
import 'desktop_window.dart';
import 'event_panel.dart';
import 'history_panel.dart';
import 'panels.dart';
import '../infrastructure/reports.dart' show ReportKind;
import 'side_panel.dart';
import 'theme.dart' show controlHeight;
import 'players_view.dart';
import 'results_view.dart';
import 'reports_view.dart';
import 'workspace_actions.dart';
import 'update_panels.dart';
import 'help_panel.dart';
import 'side_game_panel.dart';
import 'quad_pairings_panel.dart';

enum TaskView { players, results, reports }

class Workspace extends StatefulWidget {
  const Workspace({
    required this.controller,
    required this.path,
    required this.onClose,
    required this.onTheme,
    this.ratingLookup,
    this.rosterLoader,
    super.key,
  });
  final TournamentController controller;
  final String path;
  final VoidCallback onClose, onTheme;
  final MemberLookup? ratingLookup;
  final Future<List<ImportRow>> Function(String)? rosterLoader;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  String? sectionId;
  TaskView view = TaskView.players;
  bool pairing = false;
  bool historyOpen = false;

  /// The Undo or Redo step History was opened to review, if any.
  int? historyReview;

  /// Event details, backups and copies, docked at the right.
  bool eventOpen = false;
  final sectionScroll = ScrollController();
  (Size, double)? sectionViewport;
  final workspaceFocus = FocusNode(debugLabel: 'workspace');
  final sectionKeys = <String, GlobalKey>{};
  final eventPanel = GlobalKey<EventPanelState>();

  /// New sections, section settings, combine and print, docked at the right.
  late final dock = DockController(tournament: c);
  final resultsKeys = <String, GlobalKey<ResultsViewState>>{};
  late final ratingRefresh = RatingRefresh(
    c,
    lookup: widget.ratingLookup ?? fetchMember,
  );
  Timer? clock;
  TournamentController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(refresh);
    ratingRefresh.addListener(refresh);
    c.workspaceState.addListener(refresh);
    dock.addListener(dockChanged);
    final saved = c.workspaceState.read('view');
    if (saved != null) {
      final fields = saved.split('|');
      if (fields.length == 2) {
        sectionId = fields[0].isEmpty ? null : fields[0];
        view =
            TaskView.values.where((v) => v.name == fields[1]).firstOrNull ??
            TaskView.players;
      }
    }
    historyOpen = c.workspaceState.read('historyPanel') == 'open';
    if (historyOpen) dock.claim('history');
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    ratingRefresh
      ..removeListener(refresh)
      ..dispose();
    sectionScroll.dispose();
    workspaceFocus.dispose();
    c.removeListener(refresh);
    c.workspaceState.removeListener(refresh);
    dock
      ..removeListener(dockChanged)
      ..dispose();
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> startRatingRefresh() async {
    dock.close();
    pickSection(null, next: TaskView.players);
    if (ratingRefresh.active) return;
    if (c.event!.players.isEmpty) return;
    final category = await readRatingCategory();
    if (!mounted || ratingRefresh.active) return;
    await ratingRefresh.fetch(ratingCategory: category);
  }

  void go(TaskView next) {
    if (view != next) dock.close();
    setState(() {
      view = next;
    });
    remember();
  }

  void pickSection(String? id, {TaskView? next}) {
    if (id != sectionId || (next != null && next != view)) dock.close();
    setState(() {
      sectionId = id;
      if (next != null) view = next;
    });
    remember();
    revealSection();
  }

  void revealSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || sectionId == null) return;
      final target = sectionKeys[sectionId]?.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        target,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  void remember() {
    c.workspaceState.write('view', '${sectionId ?? ''}|${view.name}');
  }

  void newSection() {
    try {
      var number = 1;
      final names = c.event!.sections.map((s) => s.name).toSet();
      while (names.contains('Section $number')) {
        number++;
      }
      c.addSection('Section $number', Format.swiss, 3, assignUnassigned: false);
      pickSection(c.event!.sections.last.id, next: TaskView.players);
      sectionSettings();
    } catch (e) {
      showFailure(context, e);
    }
  }

  void refreshRoster() => dock.show(
    'web-roster',
    WebRosterPanel(
      controller: c,
      loader: widget.rosterLoader,
      onClose: dock.close,
      onImported: (refreshRatings) {
        dock.close();
        if (refreshRatings) {
          ratingRefresh.discard();
          startRatingRefresh();
        }
      },
    ),
  );

  void pairSideGame(String id) => dock.show(
    'side-game',
    SideGamePanel(
      controller: c,
      sectionId: id,
      onClose: dock.close,
      onPaired: (id) {
        dock.close();
        pickSection(id, next: TaskView.results);
      },
    ),
  );

  void editQuadPairings() => dock.show(
    'quad-pairings',
    QuadPairingsPanel(
      key: UniqueKey(),
      controller: c,
      sectionId: sectionId,
      onClose: dock.close,
    ),
  );

  void removeSection(String id) {
    try {
      c.removeSection(id);
      if (sectionId == id) pickSection(null);
    } catch (e) {
      showFailure(context, e);
    }
  }

  void addSections() => dock.show(
    'new-sections',
    NewSectionsPanel(
      controller: c,
      onCreated: () {
        dock.close();
        pickSection(null, next: TaskView.players);
      },
      onClose: dock.close,
    ),
  );

  /// Pairs and posts the next round in [sectionId], or in every section
  /// that is ready. Anything worth checking stays on screen until dismissed.
  Future<void> pair() async {
    if (pairing) return;
    setState(() => pairing = true);
    try {
      final batch = await c.propose(onlyReady: true);
      if (!mounted) return;
      if (batch.rounds.isEmpty) {
        throw TournamentException(
          batch.issues.values.join('\n').isEmpty
              ? 'No section is ready for another round.'
              : batch.issues.values.join('\n'),
        );
      }
      final notes = [
        ...batch.issues.entries.map(
          (e) =>
              '${c.event!.sections.firstWhere((s) => s.id == e.key).name}: ${e.value}',
        ),
      ];
      // Post straight away; anything worth checking is fixed afterwards
      // with Edit pairings or Undo post.
      c.post(batch);
      if (!mounted) return;
      setState(() => postNotes = notes);
      if (sectionId == null || batch.rounds.containsKey(sectionId)) {
        go(TaskView.results);
      } else {
        pickSection(null, next: TaskView.results);
      }
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => pairing = false);
    }
  }

  /// Notes from the last post, kept until the TD dismisses them.
  List<String> postNotes = const [];

  WorkspaceActions get actions => WorkspaceActions(context, c);
  void sectionSettings() => dock.show(
    'settings-$sectionId',
    sectionSettingsPanel(c, sectionId!, dock.close),
  );
  void combine() => dock.show(
    'combine-$sectionId',
    CombinePanel(
      key: ValueKey('combine-$sectionId'),
      controller: c,
      sectionId: sectionId!,
      onClose: dock.close,
    ),
  );

  /// Ctrl+L or the Players page: the Lookup panel, toggled.
  void lookup() => dock.id == 'lookup'
      ? dock.close()
      : dock.show(
          'lookup',
          LookupPanel(
            key: const ValueKey('lookup'),
            controller: c,
            onClose: dock.close,
          ),
        );

  void undo() => step(c.graph.back, c.undo);
  void redo() => step(c.graph.forward, c.redo);

  /// A routine step moves at once. One with consequences opens History on
  /// that step, where they are listed beside the button that commits it.
  void step(int? node, void Function({bool acceptLosses}) move) {
    if (node == null) return;
    try {
      if (historyNeedsReview(c, node)) {
        setState(() => historyReview = node);
        dock.claim('history');
        return;
      }
      move();
    } catch (e) {
      showFailure(context, e);
    }
  }

  void toggleHistory() {
    if (historyOpen) {
      dock.close();
    } else {
      dock.claim('history');
    }
  }

  void toggleEvent() {
    if (eventOpen) {
      dock.close();
    } else {
      dock.claim('event');
    }
  }

  void dockChanged() {
    historyOpen = dock.id == 'history';
    if (!historyOpen) historyReview = null;
    eventOpen = dock.id == 'event';
    c.workspaceState.write('historyPanel', historyOpen ? 'open' : 'closed');
    refresh();
    if (dock.id != null) {
      WidgetsBinding.instance.endOfFrame.then((_) {
        if (!mounted || dock.id == null) return;
        FocusManager.instance.applyFocusChangesIfNeeded();
        // Removing an editor can leave focus on the route outside our shortcuts.
        // Keep existing field focus; restore the workspace only when it lost it.
        if (!workspaceFocus.hasFocus) {
          workspaceFocus.requestFocus();
        }
      });
    }
  }

  void printCurrent() {
    if (view == TaskView.results) {
      resultsKeys[sectionId ?? 'all']?.currentState?.printRound();
      return;
    }
    printSheets(
      context,
      c.event!,
      sectionId: sectionId,
      kind: view == TaskView.players ? ReportKind.sections : ReportKind.packet,
    );
  }

  void keyboardHelp() => dock.id == 'keyboard-help'
      ? dock.close()
      : dock.show(
          'keyboard-help',
          SidePanel(
            title: 'Keyboard shortcuts',
            onClose: dock.close,
            children: [
              const Text(
                'Result keys score the focused player and jump to the next missing board.',
              ),
              const SizedBox(height: 16),
              for (final (keys, action) in const [
                ('1 / W', 'This player wins'),
                ('0 / L', 'This player loses'),
                ('D', 'Draw (½ on the sheet)'),
                ('F', 'No-show: this player forfeits'),
                ('X', 'This player wins by forfeit'),
                ('F on both players', 'Double forfeit'),
                ('Delete', 'Clear the result'),
                ('↑ / ↓', 'Previous / next board'),
                ('← / →', 'Other player'),
                ('P / ?', 'Still playing / disputed'),
                ('A', 'Temporary pairing assumption'),
                ('Tab, then Enter', 'Open the focused player'),
                ('Ctrl+L', 'Find a player'),
                ('Ctrl+P', 'Print this view'),
                ('Ctrl+Z', 'Undo'),
                ('Ctrl+Shift+Z / Ctrl+Y', 'Redo'),
                ('Ctrl+H', 'History'),
                ('Esc', 'Close the panel; keep its draft'),
                ('F1', 'This reference'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('$keys — $action'),
                ),
            ],
          ),
        );

  @override
  Widget build(BuildContext context) {
    final e = c.event!, colors = Theme.of(context).colorScheme;
    final section = e.sections.where((s) => s.id == sectionId).firstOrNull;
    final content = switch (view) {
      TaskView.players => PlayersView(
        key: ValueKey('players-${section?.id}'),
        controller: c,
        sectionId: section?.id,
        ratingRefresh: ratingRefresh,
        onRefreshRoster: refreshRoster,
        onRefreshRatings: startRatingRefresh,
        onAddSections: e.sections.any((s) => s.rounds.isNotEmpty)
            ? null
            : addSections,
      ),
      TaskView.results => ResultsView(
        key: resultsKeys.putIfAbsent(
          section?.id ?? 'all',
          () => GlobalKey<ResultsViewState>(),
        ),
        controller: c,
        sectionId: section?.id,
      ),
      TaskView.reports => PlayerDetailsLayout(
        child: ReportsView(
          key: const ValueKey('reports'),
          controller: c,
          onResults: (id) => pickSection(id, next: TaskView.results),
          onBackups: showBackups,
        ),
      ),
    };
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): dock.close,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): lookup,
        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
            printCurrent,
        const SingleActivator(LogicalKeyboardKey.f1): keyboardHelp,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
          if (!editingText) undo();
        },
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): () {
          if (!editingText) redo();
        },
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
          if (!editingText) redo();
        },
        const SingleActivator(LogicalKeyboardKey.keyH, control: true):
            toggleHistory,
      },
      child: Dock(
        controller: dock,
        child: Focus(
          focusNode: workspaceFocus,
          autofocus: true,
          child: Scaffold(
            // Names, IDs, scores and messages can be dragged over and copied.
            body: SelectionArea(
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top bar: event name and pages on the left, tool icons pinned
                    // to the right.
                    WorkspaceToolbar(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final navigation = SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            hitTestBehavior: HitTestBehavior.deferToChild,
                            child: Row(
                              children: [
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth < 1100
                                        ? 160
                                        : 260,
                                  ),
                                  child: Tooltip(
                                    message: 'Event details',
                                    child: TextButton.icon(
                                      key: const ValueKey('event-details'),
                                      onPressed: toggleEvent,
                                      iconAlignment: IconAlignment.end,
                                      icon: Icon(
                                        Icons.edit_outlined,
                                        size: 16,
                                        color: colors.onSurfaceVariant,
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: colors.onSurface,
                                        backgroundColor: eventOpen
                                            ? colors.primary.withValues(
                                                alpha: 0.12,
                                              )
                                            : null,
                                        minimumSize: const Size(0, 32),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                      ),
                                      label: Text(
                                        e.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                          final actions = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _barIcon(
                                Icons.help_outline,
                                'Help articles',
                                () => dock.id == 'help'
                                    ? dock.close()
                                    : dock.show(
                                        'help',
                                        HelpPanel(
                                          controller: c,
                                          onClose: dock.close,
                                        ),
                                      ),
                                selected: dock.id == 'help',
                              ),
                              _barIcon(
                                Icons.keyboard_outlined,
                                'Keyboard shortcuts (F1)',
                                keyboardHelp,
                                selected: dock.id == 'keyboard-help',
                              ),
                              _toolbarDivider(),
                              _barIcon(
                                Icons.arrow_back,
                                c.canUndo
                                    ? 'Undo ${c.undoLabel} (Ctrl+Z)'
                                    : 'Nothing to undo',
                                c.canUndo ? undo : null,
                                key: const ValueKey('undo'),
                              ),
                              _barIcon(
                                Icons.arrow_forward,
                                c.canRedo
                                    ? 'Redo ${c.redoLabel} (Ctrl+Shift+Z)'
                                    : 'Nothing to redo',
                                c.canRedo ? redo : null,
                              ),
                              _barIcon(
                                Icons.history,
                                historyOpen
                                    ? 'Hide history (Ctrl+H)'
                                    : 'History (Ctrl+H)',
                                toggleHistory,
                                selected: historyOpen,
                              ),
                              _toolbarDivider(),
                              _barIcon(
                                dark
                                    ? Icons.light_mode_outlined
                                    : Icons.dark_mode_outlined,
                                dark ? 'Light mode' : 'Dark mode',
                                widget.onTheme,
                              ),
                              _barIcon(
                                Icons.home_outlined,
                                'Close event',
                                widget.onClose,
                              ),
                            ],
                          );
                          if (constraints.maxWidth /
                                  MediaQuery.textScalerOf(context).scale(1) <
                              640) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                navigation,
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: actions,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: navigation),
                              const SizedBox(width: 12),
                              actions,
                            ],
                          );
                        },
                      ),
                    ),
                    if (e.practice) _practiceBanner(context),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: LayoutBuilder(
                        builder: (context, layout) {
                          final pages = Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final (task, label) in [
                                (TaskView.players, 'Players'),
                                (TaskView.results, 'Pairings'),
                                (TaskView.reports, 'Export'),
                              ])
                                _tab(label, view == task, () => go(task)),
                            ],
                          );
                          final action = view != TaskView.results
                              ? const SizedBox.shrink()
                              : _postControl(context, e, section);
                          // One control tall whether or not Create pairings is
                          // offered, so changing section never shifts the page.
                          final reserved = BoxConstraints(
                            minHeight: MediaQuery.textScalerOf(
                              context,
                            ).scale(controlHeight),
                          );
                          if (layout.maxWidth /
                                  MediaQuery.textScalerOf(context).scale(1) <
                              1050) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                pages,
                                ConstrainedBox(
                                  constraints: view == TaskView.results
                                      ? reserved
                                      : const BoxConstraints(),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: action,
                                  ),
                                ),
                              ],
                            );
                          }
                          return ConstrainedBox(
                            constraints: reserved,
                            child: Row(
                              children: [
                                pages,
                                const SizedBox(width: 24),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: action,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    // The rating report always covers every section.
                    if (view != TaskView.reports) _sectionTabs(context),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (c.backupWarning != null)
                                  MaterialBanner(
                                    content: Text(c.backupWarning!),
                                    actions: [
                                      TextButton(
                                        onPressed: c.secondaryBackup,
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                if (postNotes.isNotEmpty) _postNotes(context),
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, layout) => Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        content,
                                        if (dock.panel != null)
                                          Positioned(
                                            top: 0,
                                            bottom: 0,
                                            right: 0,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                top: 16,
                                              ),
                                              child: ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  maxWidth: detailsColumnWidth(
                                                    layout.maxWidth,
                                                  ),
                                                ),
                                                child: dock.panel,
                                              ),
                                            ),
                                          ),
                                        if (eventOpen)
                                          Positioned(
                                            top: 0,
                                            bottom: 0,
                                            right: 0,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                top: 16,
                                              ),
                                              child: ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  maxWidth: detailsColumnWidth(
                                                    layout.maxWidth,
                                                  ),
                                                ),
                                                child: EventPanel(
                                                  key: eventPanel,
                                                  controller: c,
                                                  onClose: toggleEvent,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (historyOpen)
                                          Positioned(
                                            top: 0,
                                            bottom: 0,
                                            right: 0,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                top: 16,
                                              ),
                                              child: ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  maxWidth: detailsColumnWidth(
                                                    layout.maxWidth,
                                                  ),
                                                ),
                                                child: HistoryPanel(
                                                  controller: c,
                                                  review: historyReview,
                                                  onClose: toggleHistory,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    _statusBar(context, e),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbarDivider() => SizedBox(
    height: 20,
    child: VerticalDivider(
      width: 17,
      color: Theme.of(context).colorScheme.outlineVariant,
    ),
  );

  /// A practice copy looks different at a glance, so nobody runs the real
  /// event in it by mistake.
  Widget _practiceBanner(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Amber paper, unlike any other surface in the app; text at 7:1+.
    final background = dark ? const Color(0xff3d2e10) : const Color(0xfff8e4b8);
    final ink = dark ? const Color(0xfff6dfa9) : const Color(0xff4a3000);
    return Container(
      key: const ValueKey('practice-banner'),
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: 18, color: ink),
          const SizedBox(width: 8),
          Text(
            'Practice copy',
            style: TextStyle(fontWeight: FontWeight.w600, color: ink),
          ),
          Flexible(
            child: Text(
              '  ·  Changes here don’t touch a real event.',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink),
            ),
          ),
        ],
      ),
    );
  }

  /// What is safe: when the file was last saved, when it was last backed
  /// up, and the revision. Backups open from here.
  Widget _statusBar(BuildContext context, Event e) {
    final colors = Theme.of(context).colorScheme;
    final head = c.graph.nodes[c.graph.head];
    final backup = c.repository.readPreference('lastBackup')?.split('|');
    final backedUp = backup != null && backup.length > 2
        ? historyTime(backup[2])
        : null;
    final style = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    return Container(
      key: const ValueKey('status-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Icon(Icons.check, size: 14, color: colors.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              head == null
                  ? 'Event saved'
                  : 'Event saved ${historyTime(head.timestamp)}',
              key: const ValueKey('status-saved'),
              style: style,
            ),
            Text('  ·  ', style: style),
            TextButton(
              key: const ValueKey('status-backup'),
              onPressed: showBackups,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 24),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Text(
                e.backupFolder.isEmpty
                    ? 'No backup folder'
                    : c.backupWarning != null
                    ? 'Backup failed'
                    : backedUp == null
                    ? 'Backups on'
                    : 'Backup $backedUp',
              ),
            ),
            Text('  ·  ', style: style),
            Text(
              '${e.players.length} players · ${e.sections.length} sections · ${widget.path}',
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
            if (c.workspaceState.failures.isNotEmpty) ...[
              Text(
                ' · Draft or workspace state not saved',
                style: TextStyle(color: colors.error),
              ),
              TextButton(
                onPressed: c.workspaceState.retry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void showBackups() => dock.id == 'backups'
      ? dock.close()
      : dock.show(
          'backups',
          BackupsPanel(
            key: const ValueKey('backups'),
            controller: c,
            onClose: dock.close,
          ),
        );

  /// The post button, labelled with what it will post. When nothing can
  /// be posted it says why beside it, and once every round is played it
  /// gives way to the event-complete state.
  Widget _postControl(BuildContext context, Event e, Section? section) {
    final colors = Theme.of(context).colorScheme;
    if (section?.sideGames == true) {
      return Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          key: const ValueKey('pair-side-game'),
          onPressed: () => pairSideGame(section!.id),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Pair a side game'),
        ),
      );
    }
    // Completion includes fixed quad schedules even though they need no post
    // button. A finished Swiss must not hide an unfinished quad in this event.
    final overall = postState(c.pairingEvent, null);
    if (!overall.complete && section != null && hasFixedQuadSchedule(section)) {
      return const SizedBox.shrink();
    }
    final needingPairings = e.sections
        .where((s) => !hasFixedQuadSchedule(s))
        .toList();
    if (!overall.complete && needingPairings.isEmpty) {
      return const SizedBox.shrink();
    }
    final state = overall.complete
        ? overall
        : postState(e.copy(sections: needingPairings), null);
    if (state.complete && !overall.complete) return const SizedBox.shrink();
    final muted = TextStyle(color: colors.onSurfaceVariant);
    if (state.complete) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              key: const ValueKey('event-complete'),
              'All rounds played',
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton(
            onPressed: () => go(TaskView.reports),
            child: const Text('Finish & export'),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.why != null &&
            (state.label != null ||
                e.sections.isEmpty ||
                e.sections.every((s) => s.players.isEmpty)))
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                state.why!,
                key: const ValueKey('post-blocked'),
                style: muted,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                textAlign: TextAlign.right,
              ),
            ),
          ),
        if (state.label != null)
          Flexible(
            child: FilledButton.icon(
              key: const ValueKey('pair-next-round'),
              onPressed: pairing || state.label == null ? null : pair,
              icon: const Icon(Icons.arrow_forward, size: 18),
              iconAlignment: IconAlignment.end,
              label: Text(
                pairing ? 'Creating pairings…' : state.label!,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }

  Widget _postNotes(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('post-notes'),
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(
              Icons.info_outline,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final note in postNotes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(note),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => postNotes = const []),
          ),
        ],
      ),
    );
  }

  Widget _sectionTabs(BuildContext context) {
    final viewport = (
      MediaQuery.sizeOf(context),
      MediaQuery.textScalerOf(context).scale(1),
    );
    if (sectionViewport != viewport) {
      sectionViewport = viewport;
      revealSection();
    }
    final e = c.event!, colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('section-tabs'),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          _sectionLink('All sections', null, '${e.players.length} players'),
          Expanded(
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent && sectionScroll.hasClients) {
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (_) {
                      sectionScroll.jumpTo(
                        (sectionScroll.offset +
                                event.scrollDelta.dy +
                                event.scrollDelta.dx)
                            .clamp(0, sectionScroll.position.maxScrollExtent),
                      );
                    },
                  );
                }
              },
              child: Scrollbar(
                controller: sectionScroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: sectionScroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final s in e.sections)
                        _sectionLink(
                          s.name,
                          s.id,
                          s.sideGames
                              ? '${s.players.length} players · Side games'
                              : s.rounds.isEmpty
                              ? '${s.players.length} players'
                              : 'Round ${s.rounds.length} · ${s.rounds.last.complete ? 'Complete' : '${s.rounds.last.games.where((g) => !g.outcome.resolved).length} missing'}',
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            key: const ValueKey('new-section'),
            onPressed: newSection,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Section'),
          ),
          if (e.sections.any(hasFixedQuadSchedule)) ...[
            const SizedBox(width: 8),
            if (MediaQuery.sizeOf(context).width /
                    MediaQuery.textScalerOf(context).scale(1) <
                1100)
              IconButton(
                key: const ValueKey('edit-quad-pairings'),
                tooltip: 'Edit quad pairings',
                onPressed: editQuadPairings,
                icon: const Icon(Icons.edit_outlined, size: 18),
              )
            else
              OutlinedButton.icon(
                key: const ValueKey('edit-quad-pairings'),
                onPressed: editQuadPairings,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit quad pairings'),
              ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLink(String label, String? id, String subtitle) {
    final colors = Theme.of(context).colorScheme;
    final active =
        sectionId == id ||
        (id == null && !c.event!.sections.any((s) => s.id == sectionId));
    final section = c.event!.sections.where((s) => s.id == id).firstOrNull;
    Widget tab() => Container(
      key: sectionKeys.putIfAbsent(id ?? 'all', GlobalKey.new),
      decoration: BoxDecoration(
        color: active ? colors.surface : null,
        border: Border(
          bottom: BorderSide(
            color: active ? colors.onSurface : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            selected: active,
            child: TextButton(
              key: ValueKey('section-chip-${id ?? 'all'}'),
              onPressed: () => pickSection(id),
              style: TextButton.styleFrom(
                foregroundColor: colors.onSurface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: const RoundedRectangleBorder(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return Builder(
      builder: (context) => GestureDetector(
        onSecondaryTapDown: (details) async {
          final action = await contextMenu<String>(
            context,
            details.globalPosition,
            [
              const PopupMenuItem(
                value: 'print',
                child: Text('Print player list'),
              ),
              const PopupMenuItem(
                value: 'preview',
                child: Text('Preview player list…'),
              ),
              if (section != null) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'settings',
                  child: Text('Rename / section settings…'),
                ),
                if (section.sideGames)
                  const PopupMenuItem(
                    value: 'side-game',
                    child: Text('Pair a side game…'),
                  ),
                const PopupMenuItem(
                  value: 'combine',
                  child: Text('Combine sections…'),
                ),
                const PopupMenuItem(
                  value: 'help',
                  child: Text('How these pairings work'),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'delete',
                  enabled: section.rounds.isEmpty,
                  child: Text(
                    section.rounds.isEmpty
                        ? 'Delete section'
                        : 'Delete unavailable after pairings',
                  ),
                ),
              ],
            ],
          );
          if (!mounted || !context.mounted || action == null) return;
          switch (action) {
            case 'print':
              printSheets(
                context,
                c.event!,
                sectionId: id,
                kind: ReportKind.sections,
              );
            case 'preview':
              showPrint(
                context,
                c.event!,
                sectionId: id,
                kind: ReportKind.sections,
              );
            case 'settings':
              pickSection(id);
              sectionSettings();
            case 'side-game':
              pickSection(id);
              pairSideGame(id!);
            case 'combine':
              pickSection(id);
              combine();
            case 'help':
              dock.show(
                'help',
                HelpPanel(
                  controller: c,
                  onClose: dock.close,
                  articleId: section!.format == Format.quad
                      ? 'quads'
                      : section.format == Format.swiss
                      ? 'swiss'
                      : 'round-robin',
                ),
              );
            case 'delete':
              removeSection(id!);
          }
        },
        child: tab(),
      ),
    );
  }

  Widget _tab(String text, bool selected, VoidCallback action) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton(
        onPressed: action,
        style: TextButton.styleFrom(
          backgroundColor: selected ? colors.onSurface : null,
          foregroundColor: selected ? colors.surface : colors.onSurface,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(text),
      ),
    );
  }

  /// Ctrl+Z inside a text field belongs to the field, not event history.
  bool get editingText =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;

  Widget _barIcon(
    IconData icon,
    String tooltip,
    VoidCallback? action, {
    bool selected = false,
    Key? key,
  }) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      key: key,
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: action,
      isSelected: selected,
      style: selected
          ? IconButton.styleFrom(
              backgroundColor: colors.primary.withValues(alpha: 0.12),
            )
          : null,
      color: selected ? colors.primary : colors.onSurfaceVariant,
      disabledColor: colors.onSurface.withValues(alpha: 0.35),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// What the post button would do for [section] (null for every section):
/// its label, why it is held back, or that every round has been played.
({String? label, String? why, bool complete}) postState(
  Event e,
  Section? section,
) {
  final scope = section == null
      ? e.sections.where((s) => !s.sideGames).toList()
      : [section];
  if (scope.isEmpty) {
    return (
      label: null,
      why: 'Create sections on the Players page first.',
      complete: false,
    );
  }
  final active = scope.where((s) => s.players.isNotEmpty).toList();
  if (active.isEmpty) {
    return (
      label: null,
      why: section == null
          ? 'Move players into a section first.'
          : 'Move players into ${section.name} first.',
      complete: false,
    );
  }
  final open = active.where((s) => s.rounds.length < s.plannedRounds).toList();
  int waiting(Section s) => s.rounds
      .expand((r) => r.games)
      .where((g) => !g.outcome.resolved && g.pairingAssumption == null)
      .length;
  if (open.isEmpty) {
    final missing = active
        .expand((s) => s.rounds)
        .expand((r) => r.games)
        .where((g) => !g.outcome.resolved)
        .length;
    if (missing == 0) return (label: null, why: null, complete: true);
    return (
      label: null,
      why:
          'Final pairings created · $missing ${missing == 1 ? 'result' : 'results'} still to enter.',
      complete: false,
    );
  }
  final ready = open.where((s) => waiting(s) == 0).toList();
  final held = open.where((s) => waiting(s) > 0).toList();
  String results(int n) => '$n ${n == 1 ? 'result' : 'results'}';
  String? why;
  if (held.length == 1) {
    final s = held.single;
    why = section != null
        ? 'Enter ${results(waiting(s))} first.'
        : '${s.name} waits for ${results(waiting(s))}.';
  } else if (held.isNotEmpty) {
    final n = held.fold(0, (n, s) => n + waiting(s));
    why = '${held.length} sections wait for ${results(n)}.';
  }
  if (ready.isEmpty) return (label: null, why: why, complete: false);
  final numbers = ready.map((s) => s.rounds.length + 1).toSet();
  final round = numbers.length == 1
      ? 'Create pairings · Round ${numbers.single}'
      : 'Create pairings';
  final label = section == null && (ready.length > 1 || e.sections.length > 1)
      ? '$round · ${ready.length} ${ready.length == 1 ? 'section' : 'sections'}'
      : round;
  return (label: label, why: why, complete: false);
}
