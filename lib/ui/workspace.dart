import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/member_lookup.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../infrastructure/member_directory.dart';
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
import 'side_game_panel.dart';
import 'side_panel.dart';
import 'update_panels.dart';
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

  /// Asks the Players view to open (or close) its New section panel, where
  /// ticked rows choose who goes in.
  bool newSectionRequested = false;

  void newSection() {
    if (view != TaskView.players) go(TaskView.players);
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
      c.removeSection(id);
      if (sectionId == id) pickSection(null);
    } catch (e) {
      showFailure(context, e);
    }
  }

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
      // Post straight away; anything worth checking is fixed afterwards
      // with Edit pairings or Undo post. If the event changed while
      // pairing, post says so.
      c.post(batch);
      if (!mounted) return;
      setState(() => postNotes = postReviewNotes(c.event!, batch));
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
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.escape): _KeyIntent(
          dock.close,
        ),
        command(LogicalKeyboardKey.keyL): _KeyIntent(lookup),
        command(LogicalKeyboardKey.keyP): _KeyIntent(printCurrent),
        const SingleActivator(LogicalKeyboardKey.f1): _KeyIntent(keyboardHelp),
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
                        onClose: widget.onClose,
                      ),
                      if (e.practice) const PracticeBanner(),
                      WorkspacePageRow(
                        view: view,
                        onGo: go,
                        action: PostControl(
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
                                  if (c.repository
                                      case final SqliteEventRepository file
                                      when !file.crashProtected)
                                    MaterialBanner(
                                      key: const ValueKey('crash-unprotected'),
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
                                      onDismiss: () =>
                                          setState(() => postNotes = const []),
                                    ),
                                  Expanded(
                                    child: LayoutBuilder(
                                      builder: (context, layout) {
                                        // Each tool docks in the same column
                                        // at the right, over the page.
                                        Widget docked(Widget panel) =>
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
                                                    maxWidth:
                                                        detailsColumnWidth(
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

  /// A choice from a section tab's right-click menu; [context] is the tab's.
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
        );
      case SectionMenuAction.preview:
        showPrint(
          context,
          c.event!,
          sectionId: id,
          kind: ReportKind.sections,
          dock: dock,
        );
      case SectionMenuAction.settings:
        pickSection(id);
        sectionSettings();
      case SectionMenuAction.sideGame:
        pickSection(id);
        pairSideGame(id!);
      case SectionMenuAction.combine:
        pickSection(id);
        combine();
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
  Widget statusBar(Event e) {
    final head = c.graph.nodes[c.graph.head];
    final backup = c.repository.readPreference('lastBackup')?.split('|');
    final backedUp = backup != null && backup.length > 2
        ? historyTime(backup[2])
        : null;
    return WorkspaceStatusBar(
      savedAt: head == null ? null : historyTime(head.timestamp),
      backup: e.backupFolder.isEmpty
          ? 'No backup folder'
          : c.backupWarning != null
          ? 'Backup failed'
          : backedUp == null
          ? 'Backups on'
          : 'Backup $backedUp',
      summary:
          '${e.players.length} players · ${e.sections.length} sections · ${widget.path}',
      onBackups: showBackups,
      workspaceStateFailed: c.workspaceState.failures.isNotEmpty,
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
