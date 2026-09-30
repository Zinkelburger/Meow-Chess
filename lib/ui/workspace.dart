import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import 'dialogs.dart';
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
    c.removeListener(refresh);
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void go(TaskView next) {
    setState(() => view = next);
    remember();
  }

  void pickSection(String? id, {TaskView? next}) {
    setState(() {
      sectionId = id;
      if (next != null) view = next;
    });
    remember();
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
  Future<void> editPairing() => actions.editPairing(sectionId!);

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
    final current = section?.rounds.lastOrNull;
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
      TaskView.reports => ReportsView(controller: c, sectionId: section?.id),
    };
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): lookup,
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
            previewPacket(context, e, sectionId: section?.id),
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
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top bar: event name and pages on the left, tool icons pinned
              // to the right.
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  border: Border(
                    bottom: BorderSide(color: colors.outlineVariant),
                  ),
                ),
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 260),
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
                                        ? colors.primary.withValues(alpha: 0.12)
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
                      Icons.person_search_outlined,
                      'Find player (Ctrl+L)',
                      lookup,
                    ),
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
                    _barIcon(Icons.close, 'Close event', widget.onClose),
                  ],
                ),
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
                          Container(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: colors.outlineVariant,
                                ),
                              ),
                            ),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                FilledButton(
                                  onPressed: pairing || e.sections.isEmpty
                                      ? null
                                      : pair,
                                  child: Text(
                                    pairing
                                        ? 'Pairing…'
                                        : section == null
                                        ? 'Pair next round'
                                        : 'Pair next round · ${section.name}',
                                  ),
                                ),
                                if (e.sections.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  _sectionChip('All sections', null),
                                  for (final s in e.sections)
                                    _sectionChip(
                                      '${s.name} (${s.players.length})',
                                      s.id,
                                    ),
                                  if (section != null) ...[
                                    TextButton(
                                      onPressed: sectionSettings,
                                      child: Text('${section.name} settings…'),
                                    ),
                                    TextButton(
                                      onPressed: combine,
                                      child: const Text('Combine…'),
                                    ),
                                  ],
                                  TextButton(
                                    onPressed: addSections,
                                    child: const Text('New sections…'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (view == TaskView.results &&
                              current != null &&
                              (current.startedAt == null || !current.hasPlay))
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (current.startedAt == null)
                                    OutlinedButton(
                                      onPressed: () {
                                        try {
                                          c.startRound(section!.id);
                                        } catch (e) {
                                          showFailure(context, e);
                                        }
                                      },
                                      child: const Text('Start round'),
                                    ),
                                  if (!current.hasPlay)
                                    OutlinedButton(
                                      onPressed: editPairing,
                                      child: const Text('Edit pairings'),
                                    ),
                                  if (current.startedAt != null)
                                    Text(
                                      'Round started at ${DateTime.parse(current.startedAt!).toLocal().toString().substring(11, 16)}',
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
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
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
    );
  }

  Widget _sectionChip(String label, String? id) => ChoiceChip(
    chipAnimationStyle: noChipAnimation,
    key: ValueKey('section-chip-${id ?? 'all'}'),
    label: Text(label),
    showCheckmark: false,
    selected:
        sectionId == id ||
        (id == null && !c.event!.sections.any((s) => s.id == sectionId)),
    onSelected: (_) => pickSection(id),
  );

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
