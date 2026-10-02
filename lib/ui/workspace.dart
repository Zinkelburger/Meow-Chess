import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/tournament_controller.dart';
import '../domain/model.dart';
import 'dialogs.dart';
import 'desktop_window.dart';
import 'event_panel.dart';
import 'history_panel.dart';
import 'panels.dart';
import 'players_view.dart';
import 'results_view.dart';
import 'reports_view.dart';
import 'workspace_actions.dart';

enum TaskView { players, results, reports }

class Workspace extends StatefulWidget {
  const Workspace({
    required this.controller,
    required this.path,
    required this.onClose,
    required this.onTheme,
    super.key,
  });
  final TournamentController controller;
  final String path;
  final VoidCallback onClose, onTheme;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  String? sectionId;
  TaskView view = TaskView.players;
  bool pairing = false;
  bool historyOpen = false;

  /// Event details, backups and copies, docked at the right.
  bool eventOpen = false;
  final sectionSearch = TextEditingController();
  final sectionFocus = FocusNode(debugLabel: 'section-search');
  final sectionKeys = <String, GlobalKey>{};
  final eventPanel = GlobalKey<EventPanelState>();

  /// New sections, section settings, combine and print, docked at the right.
  final dock = DockController();
  Timer? clock;
  TournamentController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(refresh);
    dock.addListener(dockChanged);
    final saved = c.repository.readPreference('view');
    if (saved != null) {
      final fields = saved.split('|');
      if (fields.length == 2) {
        sectionId = fields[0].isEmpty ? null : fields[0];
        view =
            TaskView.values.where((v) => v.name == fields[1]).firstOrNull ??
            TaskView.players;
      }
    }
    historyOpen = c.repository.readPreference('historyPanel') == 'open';
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    sectionSearch.dispose();
    sectionFocus.dispose();
    c.removeListener(refresh);
    dock
      ..removeListener(dockChanged)
      ..dispose();
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void go(TaskView next) {
    setState(() {
      view = next;
      if (next == TaskView.results && sectionId == null) {
        sectionId = c.event!.sections
            .where((s) => s.rounds.isNotEmpty)
            .firstOrNull
            ?.id;
      }
    });
    remember();
  }

  void pickSection(String? id, {TaskView? next}) {
    setState(() {
      sectionId = id;
      if (next != null) view = next;
    });
    remember();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = sectionKeys[id ?? 'all']?.currentContext;
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(
          target,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
        Scrollable.ensureVisible(
          target,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      }
    });
  }

  void jumpToSection() {
    // Run after the destination page's initial result focus has settled.
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (!mounted) return;
      sectionFocus.requestFocus();
      sectionSearch.selection = TextSelection(
        baseOffset: 0,
        extentOffset: sectionSearch.text.length,
      );
    });
  }

  void remember() {
    try {
      c.repository.writePreference('view', '${sectionId ?? ''}|${view.name}');
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
      final batch = await c.propose(sectionId: sectionId);
      if (!mounted) return;
      if (batch.rounds.isEmpty) {
        throw TournamentException(
          batch.issues.values.join('\n').isEmpty
              ? 'No section is ready for another round.'
              : batch.issues.values.join('\n'),
        );
      }
      final swiss = batch.rounds.values.any(
        (r) => r.policy == 'score-swiss-pilot-v1',
      );
      // The Swiss caveat is said once per event, not on every post.
      final caveat =
          swiss && c.repository.readPreference('swiss-caveat') == null;
      final notes = [
        ...batch.issues.entries.map(
          (e) =>
              '${c.event!.sections.firstWhere((s) => s.id == e.key).name}: ${e.value}',
        ),
        if (caveat)
          'Swiss pairings come from a test algorithm that is not yet certified. Look them over before players sit down; Edit pairings fixes a board until play starts.',
      ];
      // Post straight away; anything worth checking is fixed afterwards
      // with Edit pairings or Undo post.
      c.post(batch);
      if (caveat) c.repository.writePreference('swiss-caveat', 'shown');
      if (!mounted) return;
      setState(() => postNotes = notes);
      go(TaskView.results);
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

  /// Ctrl+L or the toolbar: the Lookup panel, toggled.
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

  void undo() =>
      travel(context, c, c.graph.back, (a) => c.undo(acceptLosses: a));
  void redo() =>
      travel(context, c, c.graph.forward, (a) => c.redo(acceptLosses: a));

  void toggleHistory() {
    setState(() => historyOpen = !historyOpen);
    try {
      c.repository.writePreference(
        'historyPanel',
        historyOpen ? 'open' : 'closed',
      );
    } catch (e) {
      showFailure(context, e);
    }
  }

  /// One panel at the right at a time, so the page keeps its width.
  void toggleEvent() {
    if (eventOpen && eventPanel.currentState?.commit() == false) return;
    if (!eventOpen) dock.close();
    setState(() => eventOpen = !eventOpen);
  }

  void dockChanged() {
    if (dock.panel != null && eventOpen) {
      if (eventPanel.currentState?.commit() == false) return;
      eventOpen = false;
    }
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final e = c.event!, colors = Theme.of(context).colorScheme;
    final section = e.sections.where((s) => s.id == sectionId).firstOrNull;
    final content = switch (view) {
      TaskView.players => PlayersView(
        key: ValueKey('players-${section?.id}'),
        controller: c,
        sectionId: section?.id,
        onAddSections: e.sections.any((s) => s.rounds.isNotEmpty)
            ? null
            : addSections,
      ),
      TaskView.results => ResultsView(
        key: ValueKey('results-${section?.id}'),
        controller: c,
        sectionId: section?.id,
      ),
      TaskView.reports => ReportsView(
        key: ValueKey('reports-${section?.id}'),
        controller: c,
        sectionId: section?.id,
      ),
    };
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true):
            jumpToSection,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): lookup,
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
            showPrint(
              context,
              e,
              sectionId: view == TaskView.reports ? null : section?.id,
            ),
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
          autofocus: true,
          child: Scaffold(
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top bar: event name and pages on the left, tool icons pinned
                  // to the right.
                  WorkspaceToolbar(
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            hitTestBehavior: HitTestBehavior.deferToChild,
                            child: Row(
                              children: [
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 260,
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
                                const SizedBox(width: 24),
                                for (final (task, label) in [
                                  (TaskView.players, 'Players'),
                                  (TaskView.results, 'Rounds'),
                                  (TaskView.reports, 'Reports'),
                                ])
                                  _tab(label, view == task, () => go(task)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _barIcon(
                          Icons.person_search_outlined,
                          'Find player (Ctrl+L)',
                          lookup,
                          selected: dock.id == 'lookup',
                        ),
                        _undoButton(context),
                        _barIcon(
                          Icons.chevron_right,
                          c.canRedo
                              ? 'Forward: redo ${c.redoLabel} (Ctrl+Shift+Z)'
                              : 'Nothing to redo',
                          c.canRedo ? redo : null,
                        ),
                        _barIcon(
                          Icons.account_tree_outlined,
                          historyOpen
                              ? 'Hide history (Ctrl+H)'
                              : 'History (Ctrl+H)',
                          toggleHistory,
                          selected: historyOpen,
                        ),
                        _barIcon(
                          dark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          dark ? 'Light mode' : 'Dark mode',
                          widget.onTheme,
                        ),
                        SizedBox(
                          height: 24,
                          child: VerticalDivider(
                            width: 17,
                            color: colors.outlineVariant,
                          ),
                        ),
                        _barIcon(
                          Icons.home_outlined,
                          'Close event',
                          widget.onClose,
                        ),
                      ],
                    ),
                  ),
                  if (e.practice) _practiceBanner(context),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionSidebar(context),
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
                              if (view != TaskView.reports)
                                Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    12,
                                    24,
                                    12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: colors.outlineVariant,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          section?.name ?? 'All sections',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Flexible(
                                        flex: 3,
                                        child: _postControl(
                                          context,
                                          e,
                                          section,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (postNotes.isNotEmpty) _postNotes(context),
                              Expanded(child: content),
                            ],
                          ),
                        ),
                        if (dock.panel != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: dock.panel,
                          ),
                        if (eventOpen)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: EventPanel(
                              key: eventPanel,
                              controller: c,
                              onClose: toggleEvent,
                            ),
                          ),
                        if (historyOpen)
                          HistoryPanel(controller: c, onClose: toggleHistory),
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
    );
  }

  /// Back, named: "Undo Result, board 3" in words, not only on hover.
  Widget _undoButton(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (!c.canUndo) {
      return _barIcon(Icons.undo, 'Nothing to undo', null);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Tooltip(
        message: 'Undo ${c.undoLabel} (Ctrl+Z)',
        child: TextButton.icon(
          key: const ValueKey('undo'),
          onPressed: undo,
          icon: const Icon(Icons.undo, size: 18),
          style: TextButton.styleFrom(
            foregroundColor: colors.onSurface,
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          label: Text('Undo ${c.undoLabel}', overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

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
              '  ·  Nothing here changes a real event. Try anything; undo is always there.',
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
      child: Row(
        children: [
          Icon(Icons.check, size: 14, color: colors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            head == null ? 'Saved' : 'Saved ${historyTime(head.timestamp)}',
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
          Text('  ·  Revision ${e.revision}  ·  ', style: style),
          Expanded(
            child: Text(
              '${e.players.length} players · ${e.sections.length} sections · ${widget.path}',
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
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
    final state = postState(e, section);
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
              section == null
                  ? 'All rounds played'
                  : 'All ${section.plannedRounds} rounds played',
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton(
            onPressed: () => go(TaskView.reports),
            child: const Text('Final reports'),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.why != null)
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
        Flexible(
          child: FilledButton.icon(
            key: const ValueKey('pair-next-round'),
            onPressed: pairing || state.label == null ? null : pair,
            icon: const Icon(Icons.arrow_forward, size: 18),
            iconAlignment: IconAlignment.end,
            label: Text(
              pairing ? 'Posting…' : state.label ?? 'Post next round',
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

  Widget _sectionSidebar(BuildContext context) {
    final e = c.event!, colors = Theme.of(context).colorScheme;
    final q = sectionSearch.text.toLowerCase().replaceAll(' ', '');
    String normalized(String name) => name.toLowerCase().replaceAll(' ', '');
    bool exact((int, Section) entry) =>
        normalized(entry.$2.name) == q || 'section${entry.$1 + 1}' == q;
    final matches =
        e.sections.indexed
            .where(
              (entry) =>
                  normalized(entry.$2.name).contains(q) ||
                  'section${entry.$1 + 1}'.contains(q),
            )
            .toList()
          ..sort(
            (a, b) => exact(a) == exact(b)
                ? a.$1.compareTo(b.$1)
                : exact(a)
                ? -1
                : 1,
          );
    return Container(
      key: const ValueKey('section-sidebar'),
      width: 208,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border(right: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sections',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                MenuAnchor(
                  builder: (context, menu, child) => IconButton(
                    tooltip: 'Manage sections',
                    icon: const Icon(Icons.more_horiz, size: 20),
                    onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                  ),
                  menuChildren: [
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.add, size: 18),
                      onPressed: addSections,
                      child: const Text('New sections…'),
                    ),
                    if (e.sections.any((s) => s.id == sectionId)) ...[
                      MenuItemButton(
                        onPressed: sectionSettings,
                        child: const Text('Section settings…'),
                      ),
                      MenuItemButton(
                        onPressed: combine,
                        child: const Text('Combine sections…'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Tooltip(
              message: 'Jump to a section (Ctrl+J)',
              child: TextField(
                key: const ValueKey('section-search'),
                controller: sectionSearch,
                focusNode: sectionFocus,
                decoration: InputDecoration(
                  hintText: 'Jump to section',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  prefixIconConstraints: const BoxConstraints(minWidth: 32),
                  suffixIcon: q.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear section search',
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => setState(sectionSearch.clear),
                        ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (matches.isNotEmpty) {
                    pickSection(matches.first.$2.id);
                    sectionFocus.unfocus();
                    setState(sectionSearch.clear);
                  }
                },
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  if (q.isEmpty)
                    _sectionLink(
                      'All sections',
                      null,
                      '${e.players.length} players',
                    ),
                  for (final (_, s) in matches)
                    _sectionLink(
                      s.name,
                      s.id,
                      s.rounds.isEmpty
                          ? '${s.players.length} players · Not paired'
                          : 'Round ${s.rounds.length} · ${s.rounds.last.complete ? 'Complete' : '${s.rounds.last.games.where((g) => !g.outcome.resolved).length} missing'}',
                    ),
                  if (matches.isEmpty && q.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'No matching sections',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Ctrl+J to jump',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLink(String label, String? id, String subtitle) {
    final colors = Theme.of(context).colorScheme;
    final active =
        sectionId == id ||
        (id == null && !c.event!.sections.any((s) => s.id == sectionId));
    return Padding(
      key: sectionKeys.putIfAbsent(id ?? 'all', GlobalKey.new),
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        selected: active,
        child: Material(
          color: active ? colors.surfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: ListTile(
            key: ValueKey('section-chip-${id ?? 'all'}'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            title: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            onTap: () => pickSection(id),
          ),
        ),
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
  }) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
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
  final scope = section == null ? e.sections : [section];
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
    final missing = active.fold(0, (n, s) => n + waiting(s));
    if (missing == 0) return (label: null, why: null, complete: true);
    return (
      label: null,
      why:
          'Last round posted · $missing ${missing == 1 ? 'result' : 'results'} still to enter.',
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
      ? 'Post round ${numbers.single}'
      : 'Post next rounds';
  final label = section == null && (ready.length > 1 || e.sections.length > 1)
      ? '$round · ${ready.length} ${ready.length == 1 ? 'section' : 'sections'}'
      : round;
  return (label: label, why: why, complete: false);
}
