import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/event_repository.dart';
import '../application/member_lookup.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../infrastructure/member_directory.dart';
import '../infrastructure/remembered_printing.dart';
import '../infrastructure/reports.dart' show ReportKind;
import '../infrastructure/roster_import.dart' show ImportRow;
import '../infrastructure/sqlite_event_repository.dart';
import 'dialogs.dart';
import 'event_panel.dart';
import 'help_panel.dart';
import 'history_panel.dart';
import 'pairing_review.dart';
import 'panels.dart';
import 'players_view.dart';
import 'quad_pairings_panel.dart';
import 'rating_refresh.dart';
import 'reports_view.dart';
import 'results_view.dart';
import 'rulings_panel.dart';
import 'section_tabs.dart';
import 'selection_keys.dart';
import 'side_game_panel.dart';
import 'side_panel.dart';
import 'update_panels.dart';
import 'workspace_actions.dart';
import 'workspace_pages.dart';
import 'workspace_status.dart';
import 'workspace_toolbar.dart';

export 'workspace_pages.dart' show TaskView, postState;

class Workspace extends StatefulWidget {
  const Workspace({
    required this.controller,
    required this.path,
    required this.onClose,
    required this.onTheme,
    this.onOpenCopy,
    this.ratingLookup,
    this.rosterLoader,
    this.printing,
    super.key,
  });
  final TournamentController controller;
  final String path;
  final VoidCallback onClose, onTheme;

  /// Carries on in a copy just saved, when the event's own file has gone.
  final ValueChanged<String>? onOpenCopy;
  final MemberLookup? ratingLookup;
  final Future<List<ImportRow>> Function(String)? rosterLoader;

  /// The printing service for direct prints; tests pass their own.
  final RememberedPrinting? printing;
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

  /// Whether a draft or workspace setting could not be written. Drafts are
  /// written on every keystroke and scroll, so the workspace listens for
  /// this one fact rather than rebuilding on each write.
  late final stateFailed = ValueNotifier(c.workspaceState.failures.isNotEmpty);

  /// Takes "Sent to …" off the status line a while after the print.
  Timer? printNoticeTimer;
  TournamentController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(eventChanged);
    ratingRefresh.addListener(refresh);
    c.workspaceState.addListener(stateChanged);
    dock.addListener(dockChanged);
    dock.printStatus.addListener(printStatusChanged);
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
    printNoticeTimer?.cancel();
    ratingRefresh
      ..removeListener(refresh)
      ..dispose();
    sectionScroll.dispose();
    workspaceFocus.dispose();
    c.removeListener(eventChanged);
    c.workspaceState.removeListener(stateChanged);
    dock.printStatus.removeListener(printStatusChanged);
    dock
      ..removeListener(dockChanged)
      ..dispose();
    stateFailed.dispose();
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  /// The event changed, or a backup ran or failed.
  void eventChanged() {
    _backupRead = false;
    refresh();
  }

  void stateChanged() =>
      stateFailed.value = c.workspaceState.failures.isNotEmpty;

  void printStatusChanged() {
    printNoticeTimer?.cancel();
    final status = dock.printStatus.value;
    if (status == null || status.sending) return;
    printNoticeTimer = Timer(const Duration(seconds: 10), () {
      if (identical(dock.printStatus.value, status)) dock.reportPrint(null);
    });
  }

  Future<void> startRatingRefresh() async {
    if (!dock.close()) return;
    if (!pickSection(null, next: TaskView.players)) return;
    if (ratingRefresh.active) return;
    if (c.event!.players.isEmpty) return;
    final category = await readRatingCategory();
    if (!mounted || ratingRefresh.active) return;
    await ratingRefresh.fetch(ratingCategory: category);
  }

  /// Shows another page. False, staying put, when the open panel holds an
  /// edit it could not save and so stays open on the problem.
  bool go(TaskView next) {
    if (view != next && !dock.close()) return false;
    setState(() {
      view = next;
    });
    remember();
    return true;
  }

  /// Shows another section (null for all), and [next]'s page if given.
  /// False, staying put, when the open panel would not close; see [go].
  bool pickSection(String? id, {TaskView? next}) {
    if ((id != sectionId || (next != null && next != view)) && !dock.close()) {
      return false;
    }
    setState(() {
      sectionId = id;
      if (next != null) view = next;
    });
    remember();
    revealSection();
    return true;
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

  /// Asks the Players view to open (or close) its New section panel, where
  /// ticked rows choose who goes in.
  bool newSectionRequested = false;

  void newSection() {
    if (view != TaskView.players && !go(TaskView.players)) return;
    setState(() => newSectionRequested = true);
  }

  void sectionsCreated(List<String> ids) =>
      pickSection(ids.length == 1 ? ids.single : null, next: TaskView.players);

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
      final name = c.event!.sections.where((s) => s.id == id).firstOrNull?.name;
      c.removeSection(id);
      if (sectionId == id) pickSection(null);
      if (name != null) showUndoNotice(context, c, 'Deleted $name.');
    } catch (e) {
      showFailure(context, e);
    }
  }

  /// Creates the next round's pairings for the section chosen, or for every
  /// section that is ready with All sections chosen. Anything worth
  /// checking stays on screen until dismissed.
  Future<void> pair() async {
    if (pairing) return;
    final only = c.event!.sections.where((s) => s.id == sectionId).firstOrNull;
    setState(() => pairing = true);
    try {
      final batch = await c.propose(sectionId: only?.id, onlyReady: true);
      if (!mounted) return;
      if (batch.rounds.isEmpty) {
        throw TournamentException(
          batch.issues.values.join('\n').isNotEmpty
              ? batch.issues.values.join('\n')
              : only == null
              ? 'No section is ready for another round.'
              : '${only.name} is not ready for another round.',
        );
      }
      // The pairings go up straight away; anything worth checking is fixed
      // afterwards with Edit pairings or Undo. If the event changed while
      // pairing, the controller says so.
      c.post(batch);
      if (!mounted) return;
      setState(() => postNotes = postReviewNotes(c.event!, batch));
      if (sectionId == null || batch.rounds.containsKey(sectionId)) {
        // The section just paired stays chosen.
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

  /// Notes on the pairings just created, kept until the TD dismisses them.
  List<String> postNotes = const [];

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
      // The players' new section is the one to look at next.
      onCombined: (into) {
        dock.close();
        pickSection(into);
      },
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
    final scope = printScope(c.event!, view, sectionId);
    if (view == TaskView.results) {
      // The page shown: the section's, or every section's once Undo has
      // removed the one chosen.
      resultsKeys[scope.sectionId ?? 'all']?.currentState?.printRound();
      return;
    }
    printSheets(
      context,
      c.event!,
      sectionId: scope.sectionId,
      kind: scope.kind,
      dock: dock,
      printing: widget.printing,
    );
  }

  /// Close event, after the open panel has saved what it holds.
  void closeEvent() {
    if (dock.close()) widget.onClose();
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
              for (final (keys, action) in [
                ('1 / W', 'This player wins'),
                ('0 / L', 'This player loses'),
                ('D', 'Draw (½ on the sheet)'),
                ('F', 'No-show: this player forfeits'),
                ('F on both players', 'Double forfeit'),
                ('1 / 0 on a forfeit', 'Who won the forfeit'),
                ('Delete', 'Clear the result'),
                ('↑ / ↓', 'Previous / next board'),
                ('← / →', 'Other player'),
                ('P / ?', 'Still playing / disputed'),
                ('A', 'Temporary pairing assumption'),
                ('Space', "Open a score box's player"),
                ('Tab, then Enter', 'Open the focused player'),
                (shortcutLabel('L'), 'Find a player'),
                (shortcutLabel('P'), 'Print this view'),
                (shortcutLabel('Z'), 'Undo'),
                (
                  macShortcuts
                      ? shortcutLabel('Z', shift: true)
                      : '${shortcutLabel('Z', shift: true)} / ${shortcutLabel('Y')}',
                  'Redo',
                ),
                (historyShortcut, 'History'),
                ('Shift+F10 / Menu key', 'Menu for the focused row or tab'),
                (
                  'Esc',
                  'Close the panel. Section settings and player cards save '
                      'their changes as they close; other forms keep a draft',
                ),
                ('F1', 'Help'),
                (keyboardHelpShortcut, 'This list'),
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
    final e = c.event!;
    final section = e.sections.where((s) => s.id == sectionId).firstOrNull;
    final content = switch (view) {
      TaskView.players => PlayersView(
        key: ValueKey('players-${section?.id}'),
        controller: c,
        sectionId: section?.id,
        ratingRefresh: ratingRefresh,
        onRefreshRoster: refreshRoster,
        onRefreshRatings: startRatingRefresh,
        newSectionRequested: newSectionRequested,
        onNewSectionShown: () => setState(() => newSectionRequested = false),
        onSectionsCreated: sectionsCreated,
      ),
      TaskView.results => ResultsView(
        key: resultsKeys.putIfAbsent(
          section?.id ?? 'all',
          () => GlobalKey<ResultsViewState>(),
        ),
        controller: c,
        sectionId: section?.id,
        onAddPlayers: () => go(TaskView.players),
        onNewSection: newSection,
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
    // The rating report always covers every section.
    final showSections = view != TaskView.reports;
    if (showSections) followSectionViewport(context);
    SingleActivator command(LogicalKeyboardKey key, {bool shift = false}) =>
        SingleActivator(
          key,
          control: !macShortcuts,
          meta: macShortcuts,
          shift: shift,
        );
    return Shortcuts(
      // Its focus node only routes keys; in the semantics tree it was a
      // window-sized control with no name.
      includeSemantics: false,
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.escape): _KeyIntent(
          dock.close,
        ),
        command(LogicalKeyboardKey.keyL): _KeyIntent(lookup),
        command(LogicalKeyboardKey.keyP): _KeyIntent(printCurrent),
        const SingleActivator(LogicalKeyboardKey.f1): _KeyIntent(help),
        const SingleActivator(LogicalKeyboardKey.f1, shift: true): _KeyIntent(
          keyboardHelp,
        ),
        // In a text field these keys belong to the field.
        command(LogicalKeyboardKey.keyZ): _KeyIntent(undo, inText: false),
        command(LogicalKeyboardKey.keyZ, shift: true): _KeyIntent(
          redo,
          inText: false,
        ),
        if (!macShortcuts)
          command(LogicalKeyboardKey.keyY): _KeyIntent(redo, inText: false),
        // ⌘H hides the app on a Mac; ⌘Y is History there, as in browsers.
        command(
          macShortcuts ? LogicalKeyboardKey.keyY : LogicalKeyboardKey.keyH,
        ): _KeyIntent(
          toggleHistory,
          inText: false,
        ),
      },
      child: Actions(
        actions: {_KeyIntent: _KeyAction(() => editingText)},
        child: Dock(
          controller: dock,
          child: Focus(
            focusNode: workspaceFocus,
            autofocus: true,
            child: Scaffold(
              // Names, IDs, scores and messages can be dragged over and copied.
              body: SelectionArea(
                child: TextFieldKeysInSelection(
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        WorkspaceTopBar(
                          eventName: e.name,
                          eventOpen: eventOpen,
                          onToggleEvent: toggleEvent,
                          helpOpen: dock.id == 'help',
                          onHelp: help,
                          rulingsOpen: dock.id == 'rulings',
                          onRulings: rulings,
                          keyboardHelpOpen: dock.id == 'keyboard-help',
                          onKeyboardHelp: keyboardHelp,
                          undoLabel: c.undoLabel,
                          onUndo: c.canUndo ? undo : null,
                          redoLabel: c.redoLabel,
                          onRedo: c.canRedo ? redo : null,
                          historyOpen: historyOpen,
                          onToggleHistory: toggleHistory,
                          onTheme: widget.onTheme,
                          onClose: closeEvent,
                        ),
                        if (e.practice) const PracticeBanner(),
                        WorkspacePageRow(
                          view: view,
                          onGo: go,
                          reserveAction: offersPairingControl(
                            e,
                            c.pairingEvent,
                          ),
                          action: PairingControl(
                            event: e,
                            pairingEvent: c.pairingEvent,
                            section: section,
                            pairing: pairing,
                            onPair: pair,
                            onPairSideGame: pairSideGame,
                            onFinish: () => go(TaskView.reports),
                          ),
                        ),
                        if (showSections)
                          SectionTabs(
                            event: e,
                            sectionId: sectionId,
                            scroll: sectionScroll,
                            tabKey: (id) =>
                                sectionKeys.putIfAbsent(id, GlobalKey.new),
                            onPick: pickSection,
                            onMenu: sectionMenu,
                            onNewSection: newSection,
                            onEditQuadPairings: editQuadPairings,
                          ),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
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
                                    if (c.fileWarning case final warning?)
                                      MaterialBanner(
                                        key: const ValueKey(
                                          'event-file-problem',
                                        ),
                                        content: Text(warning),
                                        actions: [
                                          TextButton(
                                            onPressed: () async {
                                              final copy =
                                                  await WorkspaceActions(
                                                    context,
                                                    c,
                                                  ).saveCopy();
                                              if (copy != null) {
                                                widget.onOpenCopy?.call(copy);
                                              }
                                            },
                                            child: const Text('Save a copy…'),
                                          ),
                                        ],
                                      ),
                                    if (c.repository
                                        case final SqliteEventRepository file
                                        when !file.crashProtected)
                                      MaterialBanner(
                                        key: const ValueKey(
                                          'crash-unprotected',
                                        ),
                                        content: const Text(
                                          'This folder doesn’t let Meow-Chess protect the event file while it saves, so a crash or power cut could damage it. Keep backups on.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: showBackups,
                                            child: const Text('Backups…'),
                                          ),
                                        ],
                                      ),
                                    if (postNotes.isNotEmpty)
                                      PostNotes(
                                        notes: postNotes,
                                        onDismiss: () => setState(
                                          () => postNotes = const [],
                                        ),
                                      ),
                                    Expanded(
                                      child: LayoutBuilder(
                                        builder: (context, layout) {
                                          // Each tool docks in the same column
                                          // at the right, over the page.
                                          Widget docked(
                                            Widget panel,
                                          ) => Positioned(
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
                                                child: panel,
                                              ),
                                            ),
                                          );
                                          return Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              content,
                                              if (dock.panel case final panel?)
                                                docked(panel),
                                              if (eventOpen)
                                                docked(
                                                  EventPanel(
                                                    key: eventPanel,
                                                    controller: c,
                                                    onClose: toggleEvent,
                                                    backLabel: dock.backLabel,
                                                  ),
                                                ),
                                              if (historyOpen)
                                                docked(
                                                  HistoryPanel(
                                                    controller: c,
                                                    review: historyReview,
                                                    onClose: toggleHistory,
                                                  ),
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        statusBar(e),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Keeps the chosen section tab in view when the window or text size
  /// changes.
  void followSectionViewport(BuildContext context) {
    final viewport = (
      MediaQuery.sizeOf(context),
      MediaQuery.textScalerOf(context).scale(1),
    );
    if (sectionViewport != viewport) {
      sectionViewport = viewport;
      revealSection();
    }
  }

  /// A choice from a section tab's menu; [context] is the tab's.
  void sectionMenu(BuildContext context, SectionMenuAction action, String? id) {
    if (!mounted) return;
    final section = c.event!.sections.where((s) => s.id == id).firstOrNull;
    switch (action) {
      case SectionMenuAction.print:
        printSheets(
          context,
          c.event!,
          sectionId: id,
          kind: ReportKind.sections,
          dock: dock,
          printing: widget.printing,
        );
      case SectionMenuAction.preview:
        showPrint(
          context,
          c.event!,
          sectionId: id,
          kind: ReportKind.sections,
          dock: dock,
        );
      case SectionMenuAction.wallChart:
        printSheets(
          context,
          c.event!,
          sectionId: id,
          kind: ReportKind.wallChart,
          dock: dock,
          printing: widget.printing,
        );
      case SectionMenuAction.settings:
        if (pickSection(id)) sectionSettings();
      case SectionMenuAction.sideGame:
        if (pickSection(id)) pairSideGame(id!);
      case SectionMenuAction.combine:
        if (pickSection(id)) combine();
      case SectionMenuAction.help:
        // The section may have gone while its menu was open.
        if (section == null) return;
        dock.show(
          'help',
          HelpPanel(
            controller: c,
            onClose: dock.close,
            articleId: switch (section.format) {
              Format.quad => 'quads',
              Format.swiss => 'swiss',
              _ => 'round-robin',
            },
          ),
        );
      case SectionMenuAction.delete:
        removeSection(id!);
    }
  }

  void help() => dock.id == 'help'
      ? dock.close()
      : dock.show('help', HelpPanel(controller: c, onClose: dock.close));

  void rulings() => dock.id == 'rulings'
      ? dock.close()
      : dock.show('rulings', RulingsPanel(controller: c, onClose: dock.close));

  /// What is safe: when the file was last saved, when it was last backed
  /// up, and the revision. Backups open from here.
  // The status line's account of the last history move, worked out once
  // per move: summaries read saved states.
  // Compared by value: a record has no identity to rely on.
  Object? _movedFor;
  String? _moved;
  // Every save, history move included, advances the revision, so the
  // newest save time is read once per revision, not on every redraw.
  Object? _savedFor;
  String? _saved;
  // The last backup's time is read from the event file once after each
  // change the controller announces: an edit, a history move, or a backup
  // that ran or failed.
  bool _backupRead = false;
  String? _backedUp;

  Widget statusBar(Event e) {
    if (_savedFor != (c, e.revision)) {
      _savedFor = (c, e.revision);
      _saved = c.repository.lastSaved();
    }
    final saved = _saved;
    final move = c.lastMove;
    if (move != _movedFor) {
      _movedFor = move;
      _moved = move == null
          ? null
          : switch (move.verb) {
              'Undid' => 'Undid: ${historyStep(c, move.from).title}',
              'Redid' => 'Redid: ${historyStep(c, move.to).title}',
              _ =>
                'Went to the version from ${historyTime(c.graph.nodes[move.to]!.timestamp)}',
            };
    }
    if (!_backupRead) {
      _backupRead = true;
      final backup = c.repository.readPreference('lastBackup')?.split('|');
      _backedUp = backup != null && backup.length > 2 ? backup[2] : null;
    }
    final backedUp = _backedUp == null ? null : historyTime(_backedUp!);
    // Rebuilt by itself for a print's progress or a failed draft write.
    return ListenableBuilder(
      listenable: Listenable.merge([dock.printStatus, stateFailed]),
      builder: (context, _) => statusLine(e, saved, move, backedUp),
    );
  }

  Widget statusLine(
    Event e,
    String? saved,
    ({String verb, int from, int to})? move,
    String? backedUp,
  ) {
    final printing = dock.printStatus.value;
    return WorkspaceStatusBar(
      printing: printing?.message,
      printingNow: printing?.sending ?? false,
      // A history move saves too, so this is the newest audit, not the
      // time of the version the event is on.
      savedAt: saved == null ? null : historyTime(saved),
      fileProblem: switch (c.fileProblem) {
        null => null,
        EventFileProblem.moved => 'Event file moved or deleted',
        EventFileProblem.unreachable => 'Event file cannot be reached',
      },
      moved: _moved,
      moveBack: switch (move?.verb) {
        'Undid' => 'Redo',
        'Redid' => 'Undo',
        null => null,
        _ => 'Go back',
      },
      onMoveBack: move == null
          ? null
          : switch (move.verb) {
              'Undid' => redo,
              'Redid' => undo,
              _ => () => step(
                move.from,
                ({bool acceptLosses = false}) =>
                    c.restore(move.from, acceptLosses: acceptLosses),
              ),
            },
      // The browser version has no folders; copies are downloads.
      backup: kIsWeb
          ? 'Download a copy'
          : e.backupFolder.isEmpty
          ? 'No backup folder'
          : c.backupWarning != null
          ? 'Backup failed'
          : backedUp == null
          ? 'Backups on'
          : 'Backup $backedUp',
      summary:
          '${e.players.length} players · ${e.sections.length} sections · ${widget.path}',
      onBackups: showBackups,
      workspaceStateFailed: stateFailed.value,
      onRetryWorkspaceState: c.workspaceState.retry,
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

  /// Ctrl+Z inside a text field belongs to the field, not event history.
  bool get editingText =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;
}

/// What Ctrl+P prints on [view]: the section shown, if it still exists,
/// on Players and Pairings; the whole packet for every section on Export.
({ReportKind kind, String? sectionId}) printScope(
  Event e,
  TaskView view,
  String? sectionId,
) {
  final shown = e.sections.where((s) => s.id == sectionId).firstOrNull?.id;
  return switch (view) {
    TaskView.players => (kind: ReportKind.sections, sectionId: shown),
    TaskView.results => (kind: ReportKind.packet, sectionId: shown),
    TaskView.reports => (kind: ReportKind.packet, sectionId: null),
  };
}

/// A workspace shortcut. One that is not [inText] leaves the key to a
/// focused text field, so the field's own undo and editing keys work.
class _KeyIntent extends Intent {
  const _KeyIntent(this.run, {this.inText = true});
  final VoidCallback run;
  final bool inText;
}

class _KeyAction extends Action<_KeyIntent> {
  _KeyAction(this.editingText);
  final bool Function() editingText;

  @override
  bool isEnabled(_KeyIntent intent) => intent.inText || !editingText();

  @override
  Object? invoke(_KeyIntent intent) {
    intent.run();
    return null;
  }
}
