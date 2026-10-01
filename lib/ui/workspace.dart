import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/tournament_controller.dart';
import '../domain/model.dart';
import 'dialogs.dart';
import 'desktop_window.dart';
import 'event_panel.dart';
import 'history_panel.dart';
import 'players_view.dart';
import 'results_view.dart';
import 'reports_view.dart';
import 'theme.dart';
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
  Timer? clock;
  TournamentController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(refresh);
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
    if (view == TaskView.reports) go(TaskView.results);
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

  Future<void> addSections() async {
    if (await actions.addSections() && mounted) {
      pickSection(null, next: TaskView.players);
    }
  }

  Future<void> pair() async {
    if (pairing) return;
    setState(() => pairing = true);
    try {
      final batch = await c.propose(sectionId: sectionId);
      if (!mounted) return;
      if (batch.rounds.isEmpty) {
        throw TournamentException(
          batch.issues.values.join('\n').isEmpty
              ? 'Nothing to pair. Create a section with players first.'
              : batch.issues.values.join('\n'),
        );
      }
      final warnings = [
        ...batch.issues.entries.map(
          (e) =>
              '${c.event!.sections.firstWhere((s) => s.id == e.key).name}: ${e.value}',
        ),
        if (batch.rounds.values.any((r) => r.policy == 'score-swiss-pilot-v1'))
          'Swiss pairings come from a test algorithm that is not yet certified. Look them over; open a section to use Edit pairings.',
      ];
      // Pair straight away; anything worth checking is fixed afterwards
      // with Edit pairings or undone.
      c.post(batch);
      if (!mounted) return;
      go(TaskView.results);
      if (warnings.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(warnings.join('\n')),
            duration: const Duration(seconds: 12),
            showCloseIcon: true,
            action: SnackBarAction(label: 'Undo', onPressed: undo),
          ),
          snackBarAnimationStyle: AnimationStyle.noAnimation,
        );
      }
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => pairing = false);
    }
  }

  WorkspaceActions get actions => WorkspaceActions(context, c);
  Future<void> sectionSettings() => actions.sectionSettings(sectionId!);
  Future<void> combine() => actions.combine(sectionId!);
  Future<void> lookup() => actions.lookup();

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

  void toggleEvent() {
    if (eventOpen && eventPanel.currentState?.commit() == false) return;
    setState(() => eventOpen = !eventOpen);
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
      TaskView.reports => ReportsView(controller: c),
    };
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true):
            jumpToSection,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): lookup,
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
            previewPacket(
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
                                  message: 'Event details, backups and copies',
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
                              if (e.practice) ...[
                                const SizedBox(width: 10),
                                const StatusPill('Practice copy'),
                              ],
                              const SizedBox(width: 20),
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
                        Icons.chevron_left,
                        c.canUndo
                            ? 'Back: undo ${c.undoLabel} (Ctrl+Z)'
                            : 'Nothing to undo',
                        c.canUndo ? undo : null,
                      ),
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
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (view != TaskView.reports) _sectionSidebar(context),
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
                                  children: [
                                    Expanded(
                                      child: Text(
                                        section?.name ?? 'All sections',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 20),
                                    Tooltip(
                                      message: section == null
                                          ? 'Pair the next round in all sections'
                                          : 'Pair the next round in ${section.name}',
                                      child: FilledButton.icon(
                                        key: const ValueKey('pair-next-round'),
                                        onPressed: pairing || e.sections.isEmpty
                                            ? null
                                            : pair,
                                        icon: const Icon(
                                          Icons.arrow_forward,
                                          size: 18,
                                        ),
                                        iconAlignment: IconAlignment.end,
                                        label: Text(
                                          pairing
                                              ? 'Pairing…'
                                              : 'Pair next round',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Expanded(child: content),
                          ],
                        ),
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                    child: Text(
                      '${e.players.length} players · ${e.sections.length} sections · ${widget.path}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
              vertical: 2,
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
      padding: const EdgeInsets.only(right: 2),
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
