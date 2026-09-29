import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import 'dialogs.dart';
import 'overview.dart';
import 'players_view.dart';
import 'results_view.dart';
import 'standings_view.dart';
import 'reports_view.dart';
import 'theme.dart';
import 'identity_review.dart';
import 'workspace_actions.dart';

enum TaskView { overview, players, checkIn, results, standings, reports }

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
  TaskView view = TaskView.overview;
  bool pairing = false;
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
            TaskView.overview;
      }
    }
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

  void go(TaskView next, {String? section, bool retain = false}) {
    setState(() {
      view = next;
      if (!retain) sectionId = section;
    });
    try {
      c.repository.writePreference('view', '${sectionId ?? ''}|${view.name}');
    } catch (e) {
      showFailure(context, e);
    }
  }

  Future<void> makeQuads() async {
    try {
      final revision = c.event!.revision, groups = c.quadPreview();
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review the room'),
          content: SizedBox(
            width: 620,
            height: 420,
            child: ListView(
              children: [
                const Text(
                  'Rating order; equal ratings use name, then stable ID. Unchecked and withdrawn players are excluded. Final-round quad colors are shown when posted and may be reversed before play.',
                ),
                const SizedBox(height: 16),
                for (final s in groups)
                  ListTile(
                    title: Text(
                      '${s.name} · ${s.players.length} players · ${s.format.name}',
                    ),
                    subtitle: Text(
                      s.players
                          .map(
                            (id) =>
                                '${c.event!.player(id).name} (${c.event!.player(id).rating})',
                          )
                          .join('\n'),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create sections'),
            ),
          ],
        ),
      );
      if (yes == true) {
        c.applyQuads(groups, revision);
        go(TaskView.overview);
      }
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  Future<void> post() async {
    if (pairing) return;
    setState(() => pairing = true);
    try {
      final batch = await c.propose(sectionId: sectionId);
      if (!mounted) return;
      if (batch.rounds.isEmpty) {
        throw TournamentException(
          batch.issues.values.join('\n').isEmpty
              ? 'Create a section with available players, or review finished sections.'
              : batch.issues.values.join('\n'),
        );
      }
      final warnings = [
        ...batch.issues.entries.map(
          (e) =>
              '${c.event!.sections.firstWhere((s) => s.id == e.key).name}: ${e.value}',
        ),
        if (batch.rounds.values.any((r) => r.policy == 'score-swiss-pilot-v1'))
          'Swiss uses the displayed score-group pilot policy. It has not passed US Chess rule-conformance qualification. Review its pairings before use.',
      ];
      if (warnings.isNotEmpty) {
        final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Review ready pairings'),
            content: SizedBox(
              width: 650,
              height: 430,
              child: ListView(
                children: [
                  for (final warning in warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(warning),
                    ),
                  for (final entry in batch.rounds.entries) ...[
                    Text(
                      c.event!.sections
                          .firstWhere((s) => s.id == entry.key)
                          .name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final bye in entry.value.byes)
                      Text(
                        '${c.event!.player(bye.player).name}: ${bye.reason}',
                      ),
                    for (final game in entry.value.games)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '${game.board}. ${c.event!.player(game.white).name} — ${c.event!.player(game.black).name}',
                        ),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Post ${batch.rounds.length} ready sections'),
              ),
            ],
          ),
        );
        if (yes != true) return;
      }
      c.post(batch);
      if (mounted) go(TaskView.results, retain: true);
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => pairing = false);
    }
  }

  WorkspaceActions get actions => WorkspaceActions(context, c);
  Future<void> settings() => actions.settings();
  Future<void> newSection() => actions.newSection();
  Future<void> sectionSettings() => actions.sectionSettings(sectionId!);
  Future<void> combine() => actions.combine(sectionId!);
  Future<void> lookup() => actions.lookup();
  Future<void> history() => actions.history();
  Future<void> saveCopy({bool practice = false}) =>
      actions.saveCopy(practice: practice);
  Future<void> editPairing() => actions.editPairing(sectionId!);

  void undo() {
    try {
      c.undo();
    } catch (e) {
      showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = c.event!;
    final section = e.sections.where((s) => s.id == sectionId).firstOrNull;
    final current = section?.rounds.lastOrNull;
    final content = switch (view) {
      TaskView.overview => EventOverview(
        controller: c,
        onPlayers: () => go(TaskView.players),
        onCheckIn: () => go(TaskView.checkIn),
        onQuads: makeQuads,
        onPost: post,
        onResults: () => go(TaskView.results),
        onReports: () => go(TaskView.reports),
        onSection: (s) => go(TaskView.results, section: s),
        onSettings: settings,
      ),
      TaskView.players || TaskView.checkIn => PlayersView(
        key: ValueKey('$sectionId-$view'),
        controller: c,
        sectionId: sectionId,
        checkIn: view == TaskView.checkIn,
      ),
      TaskView.results => ResultsView(
        key: ValueKey('results-$sectionId'),
        controller: c,
        sectionId: sectionId,
      ),
      TaskView.standings => StandingsView(
        key: ValueKey('standings-$sectionId'),
        controller: c,
        sectionId: sectionId,
      ),
      TaskView.reports => ReportsView(controller: c, sectionId: sectionId),
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): lookup,
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
            go(TaskView.checkIn),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
            previewPacket(context, e, sectionId: sectionId),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
          if (FocusManager.instance.primaryFocus?.context
                  ?.findAncestorWidgetOfExactType<EditableText>() ==
              null) {
            undo();
          }
        },
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.pets,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'meow',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Tooltip(
                        message: widget.path,
                        child: Text(e.name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    StatusPill(
                      e.practice ? 'Practice copy' : 'Saved · r${e.revision}',
                      good: true,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Player lookup (Ctrl+L)',
                      onPressed: lookup,
                      icon: const Icon(Icons.search),
                    ),
                    IconButton(
                      tooltip: c.undoLabel == null
                          ? 'Nothing to undo'
                          : 'Undo ${c.undoLabel} (Ctrl+Z)',
                      onPressed: c.undoLabel == null ? null : undo,
                      icon: const Icon(Icons.undo),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Event menu',
                      onSelected: (v) {
                        switch (v) {
                          case 'settings':
                            settings();
                          case 'api':
                            configureApi(context);
                          case 'history':
                            history();
                          case 'copy':
                            saveCopy();
                          case 'practice':
                            saveCopy(practice: true);
                          case 'backup':
                            c.secondaryBackup();
                          case 'theme':
                            widget.onTheme();
                          case 'close':
                            widget.onClose();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'settings',
                          child: Text('Event settings'),
                        ),
                        PopupMenuItem(
                          value: 'api',
                          child: Text('US Chess data source'),
                        ),
                        PopupMenuItem(value: 'history', child: Text('History')),
                        PopupMenuItem(
                          value: 'copy',
                          child: Text('Save independent copy'),
                        ),
                        PopupMenuItem(
                          value: 'practice',
                          child: Text('Make practice copy'),
                        ),
                        PopupMenuItem(
                          value: 'backup',
                          child: Text('Back up now'),
                        ),
                        PopupMenuItem(
                          value: 'theme',
                          child: Text('Toggle light / dark'),
                        ),
                        PopupMenuItem(
                          value: 'close',
                          child: Text('Close event'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _tab(
                          'Event',
                          sectionId == null,
                          () => go(TaskView.overview),
                        ),
                        for (final s in e.sections.where(
                          (s) => s.players.isNotEmpty,
                        ))
                          _tab(
                            s.name,
                            sectionId == s.id,
                            () => go(
                              s.rounds.isEmpty
                                  ? TaskView.players
                                  : TaskView.results,
                              section: s.id,
                            ),
                          ),
                        IconButton(
                          tooltip: 'Create section',
                          onPressed: newSection,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (view != TaskView.overview)
                Container(
                  width: double.infinity,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final (task, label) in [
                        (TaskView.players, 'Players'),
                        (TaskView.checkIn, 'Check-in'),
                        (TaskView.results, 'Rounds'),
                        (TaskView.standings, 'Standings'),
                        (TaskView.reports, 'Reports'),
                      ])
                        TextButton(
                          onPressed: () => go(task, retain: true),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontWeight: view == task
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: view == task
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (section != null) ...[
                        TextButton(
                          onPressed: sectionSettings,
                          child: const Text('Section settings'),
                        ),
                        TextButton(
                          onPressed: combine,
                          child: const Text('Combine with…'),
                        ),
                        if (current != null && !current.hasPlay)
                          TextButton(
                            onPressed: editPairing,
                            child: const Text('Edit pairings'),
                          ),
                        if (current != null && current.startedAt == null)
                          TextButton(
                            onPressed: () {
                              try {
                                c.startRound(section.id);
                              } catch (e) {
                                showFailure(context, e);
                              }
                            },
                            child: const Text('Start round'),
                          ),
                        if (current?.startedAt != null)
                          Text(
                            'Started ${DateTime.parse(current!.startedAt!).toLocal().toString().substring(11, 16)}',
                          ),
                      ],
                      FilledButton.tonal(
                        onPressed: pairing ? null : post,
                        child: Text(pairing ? 'Pairing…' : 'Post next round'),
                      ),
                    ],
                  ),
                ),
              Expanded(child: content),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 14),
                    const SizedBox(width: 8),
                    const Text(
                      'Local event · works offline',
                      style: TextStyle(fontSize: 12),
                    ),
                    const Spacer(),
                    Text(
                      '${e.players.length} entries · ${e.sections.where((s) => s.players.isNotEmpty).length} sections',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(String text, bool selected, VoidCallback action) => Padding(
    padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
    child: TextButton(
      style: TextButton.styleFrom(
        backgroundColor: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
        foregroundColor: selected
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : null,
      ),
      onPressed: action,
      child: Text(text),
    ),
  );
}
