import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/us_chess.dart';
import '../infrastructure/reports.dart';
import '../infrastructure/save_location.dart';
import '../infrastructure/dbf_export.dart';
import 'dialogs.dart';
import 'panels.dart';
import 'drafts.dart';
import 'event_panel.dart';
import 'players_view.dart';

Future<void> saveArtifact(String name, Uint8List bytes) async {
  final location = await chooseSaveLocation(suggestedName: name);
  if (location != null) {
    await XFile.fromData(bytes, name: name).saveTo(location.path);
  }
}

class ReportsView extends StatefulWidget {
  const ReportsView({
    required this.controller,
    this.sectionId,
    this.onResults,
    this.onStandings,
    this.onBackups,
    super.key,
  });
  final TournamentController controller;
  final String? sectionId;
  final ValueChanged<String?>? onResults;
  final VoidCallback? onStandings, onBackups;
  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  String? scope;
  final detailsKey = GlobalKey<ReportDetailsState>();
  final scroll = ScrollController();
  TournamentController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    scope = widget.sectionId;
    final saved = controller.workspaceState.readMap(
      'reports-view-${scope ?? "all"}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.jumpTo(
          (saved["scroll"] as num? ?? 0).toDouble().clamp(
            0,
            scroll.position.maxScrollExtent,
          ),
        );
      }
    });
    scroll.addListener(() {
      controller.workspaceState.writeMap('reports-view-${scope ?? "all"}', {
        "scroll": scroll.offset,
      });
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void repair(ReportRepair action) {
    final dock = Dock.maybeOf(context);
    switch (action.destination) {
      case ReportDestination.report:
        detailsKey.currentState?.focusField(action.field ?? 'city');
      case ReportDestination.results:
        widget.onResults?.call(action.id);
      case ReportDestination.event:
        dock?.show(
          ('report-event', action.field),
          ListenableBuilder(
            listenable: controller,
            builder: (_, _) => EventPanel(
              key: ValueKey('report-event-${action.field}'),
              controller: controller,
              initialField: action.field,
              onClose: dock.close,
            ),
          ),
        );
      case ReportDestination.player:
        dock?.show(
          ('report-player', action.id, action.field),
          ListenableBuilder(
            listenable: controller,
            builder: (_, _) {
              final player = controller.event!.players
                  .where((p) => p.id == action.id)
                  .firstOrNull;
              if (player == null) {
                return SidePanel(
                  title: 'Player removed',
                  onClose: dock.close,
                  children: const [
                    Text('This player is no longer in the event.'),
                  ],
                );
              }
              return PlayerPanel(
                key: ValueKey('report-player-${action.id}-${action.field}'),
                controller: controller,
                player: player,
                focusField: action.field,
                onClose: dock.close,
              );
            },
          ),
        );
      case ReportDestination.section:
        if (action.id != null && dock != null) {
          dock.show((
            'report-section',
            action.id,
          ), sectionSettingsPanel(controller, action.id!, dock.close));
        }
    }
  }

  Widget finishChecklist(Event e, int issues) {
    final remaining = e.games.where((g) => !g.outcome.resolved).length;
    final export = controller.repository
        .readPreference('lastExport')
        ?.split('|');
    final exportRevision = export == null ? null : int.tryParse(export.last);
    final backup = controller.repository
        .readPreference('lastBackup')
        ?.split('|');
    final backupRevision = backup == null ? null : int.tryParse(backup.first);
    String revisionState(int? revision, String absent) => revision == null
        ? absent
        : revision == e.revision
        ? 'Current · revision $revision'
        : 'Revision $revision · newer changes are not included';
    return ExpansionTile(
      key: const PageStorageKey('finish-event'),
      initiallyExpanded:
          e.sections.isNotEmpty && e.sections.every((s) => s.finished),
      tilePadding: EdgeInsets.zero,
      title: const Text('Final review & backup'),
      children: [
        for (final (title, detail, action, callback)
            in <(String, String, String, VoidCallback?)>[
              (
                'Results',
                '$remaining unresolved games · ${e.sections.where((s) => s.finished).length} of ${e.sections.length} sections complete',
                'Open results',
                widget.onResults == null ? null : () => widget.onResults!(null),
              ),
              (
                'Standings',
                'Review final ranks and scores',
                'Open standings',
                widget.onStandings,
              ),
              (
                'Tournament checks',
                issues == 0
                    ? 'Ready'
                    : '$issues ${issues == 1 ? 'item needs' : 'items need'} attention',
                '',
                null,
              ),
              (
                'DBF files',
                revisionState(exportRevision, 'Not exported'),
                '',
                null,
              ),
              (
                'Backup',
                controller.backupWarning ??
                    revisionState(backupRevision, 'No backup recorded'),
                'Backups',
                widget.onBackups,
              ),
              (
                'Submission',
                e.submission.isEmpty ? 'Not recorded' : 'Notes recorded',
                '',
                null,
              ),
            ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('$title: $detail'),
                  if (callback != null)
                    TextButton(onPressed: callback, child: Text(action)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> exportRating(BuildContext context) async {
    final event = controller.event!;
    try {
      final folder = await getDirectoryPath(confirmButtonText: 'Save here');
      if (folder == null) return;
      final path = await writeRatingPackage(event, folder);
      if (controller.event?.id == event.id) {
        controller.secondaryBackup();
        controller.repository.writePreference(
          'lastExport',
          '$path|${event.revision}',
        );
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  /// Players in reported sections who have no state yet.
  List<Player> _stateless(Event e) => [
    for (final s in reportedSections(e))
      for (final id in s.players)
        if (e.player(id).state.isEmpty) e.player(id),
  ];

  void _fillStates(Event e) {
    final ids = _stateless(e).map((p) => p.id).toSet();
    try {
      controller.change(
        'Set state ${e.state} for ${ids.length} players',
        e.copy(
          players: [
            for (final p in e.players)
              ids.contains(p.id) ? p.copy(state: e.state) : p,
          ],
        ),
      );
    } catch (error) {
      showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = controller.event!, all = ratingIssues(e);
    final issues = [
          for (final i in all)
            if (i.blocking) i,
        ],
        advice = [
          for (final i in all)
            if (!i.blocking) i,
        ];
    final stateless = _stateless(e);
    if (scope != null && !e.sections.any((s) => s.id == scope)) scope = null;
    return SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Finish & export',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          const Text(
            'Review the tournament, resolve outstanding issues, and generate your final files.',
          ),
          const SizedBox(height: 24),
          Text(
            'Tournament checks',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          const Text('Checks and DBF exports cover all sections.'),
          const SizedBox(height: 12),
          if (issues.isNotEmpty) _warnings(context, issues),
          if (advice.isNotEmpty) _warnings(context, advice, optional: true),
          if (issues.isEmpty)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.fact_check_outlined),
              title: Text('Ready to export. No blocking issues found.'),
            ),
          if (stateless.isNotEmpty && usStates.contains(e.state))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('fill-states'),
                  onPressed: () => _fillStates(e),
                  child: Text(
                    'Use ${e.state} for ${stateless.length} ${stateless.length == 1 ? 'player' : 'players'} without a state',
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'US Chess DBF files',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Generate THEXPORT.DBF, TSEXPORT.DBF, and TDEXPORT.DBF for upload to US Chess.\nNot yet tested with the US Chess upload site.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ReportDetails(key: detailsKey, controller: controller),
          const SizedBox(height: 12),
          _summary(context, e),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: issues.isEmpty ? () => exportRating(context) : null,
                icon: const Icon(Icons.folder_outlined),
                label: const Text('Generate DBF files'),
              ),
              // A disabled button says why beside it.
              if (issues.isNotEmpty)
                Text(
                  'Resolve the ${issues.length == 1 ? 'item' : '${issues.length} items'} above first.',
                  key: const ValueKey('rating-blocked'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (controller.repository.readPreference('lastExport')
              case final saved?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: SelectableText(
                  'DBF files saved to ${saved.substring(0, saved.lastIndexOf('|'))}\n'
                  '${saved.split('|').last == '${e.revision}' ? 'Includes the current event revision.' : 'Newer changes are not included. Save again to update the report.'}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'Final standings & printouts · ${e.sections.where((s) => s.id == scope).firstOrNull?.name ?? 'All sections'}',
            key: const ValueKey('report-scope'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (kind, label, icon) in [
                (ReportKind.sections, 'Pairing sheets', Icons.print_outlined),
                (ReportKind.standings, 'Standings', Icons.leaderboard_outlined),
                (
                  ReportKind.crosstable,
                  'Crosstable',
                  Icons.table_chart_outlined,
                ),
              ])
                OutlinedButton.icon(
                  onPressed: e.sections.isEmpty
                      ? null
                      : () =>
                            showPrint(context, e, sectionId: scope, kind: kind),
                  icon: Icon(icon),
                  label: Text(label),
                ),
              TextButton(
                onPressed: () async {
                  try {
                    await saveArtifact(
                      'standings-r${e.revision}.csv',
                      Uint8List.fromList(
                        utf8.encode(standingsCsv(e, sectionId: scope)),
                      ),
                    );
                  } catch (error) {
                    if (context.mounted) showFailure(context, error);
                  }
                },
                child: const Text('Save CSV'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await saveArtifact(
                      'crosstable-r${e.revision}.txt',
                      Uint8List.fromList(
                        crosstable(
                          e,
                          asciiOnly: true,
                          sectionId: scope,
                        ).codeUnits,
                      ),
                    );
                  } catch (error) {
                    if (context.mounted) showFailure(context, error);
                  }
                },
                child: const Text('Save text crosstable'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          finishChecklist(e, issues.length),
          const SizedBox(height: 24),
          SubmissionNotes(controller: controller),
        ],
      ),
    );
  }

  /// What the report will say about time control and dates, so the TD can
  /// confirm the rating system before creating files.
  Widget _summary(BuildContext context, Event e) {
    final muted = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    String describe(String control) {
      try {
        final tc = TimeControl.parse(control);
        return '${tc.reportText}: ${tc.category?.label ?? 'not ratable'} (${tc.totalMinutes} minutes with delay or increment, rule 5C)';
      } on TournamentException {
        return '$control: not recognized';
      }
    }

    return Column(
      key: const ValueKey('rating-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (e.sections.any((s) => s.timeControl.isNotEmpty))
          for (final section in e.sections)
            Text(
              '${section.name}: ${describe(section.effectiveTimeControl(e))}',
              style: muted,
            )
        else
          Text('Time control ${describe(e.timeControl)}', style: muted),
        Text(
          e.endDate.isEmpty || e.endDate == e.date
              ? 'Played on ${e.date}'
              : 'Played ${e.date} to ${e.endDate}',
          style: muted,
        ),
      ],
    );
  }

  /// Show blocking checks up front; keep optional advice available separately.
  Widget _warnings(
    BuildContext context,
    List<ReportIssue> issues, {
    bool optional = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey(optional ? 'rating-advice' : 'rating-warnings'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ExpansionTile(
        key: PageStorageKey(
          optional ? 'rating-advice-details' : 'rating-preflight-details',
        ),
        initiallyExpanded: !optional,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          Icons.info_outline,
          color: colors.onSurfaceVariant,
          size: 20,
        ),
        title: Text(
          optional
              ? '${issues.length} optional ${issues.length == 1 ? 'check' : 'checks'}'
              : '${issues.length} ${issues.length == 1 ? 'item needs' : 'items need'} attention',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          optional
              ? 'US Chess accepts the report without these.'
              : 'Resolve these before generating DBF files.',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(56, 0, 24, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ${issue.message}'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final action in issue.repairs)
                        TextButton(
                          key: ValueKey(
                            'repair-${action.destination.name}-${action.id}-${action.field}',
                          ),
                          onPressed: () => repair(action),
                          child: Text(action.label),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Where the event was held and its type, saved with the event. Edits save on
/// Enter or Save, like the event panel.
class ReportDetails extends StatefulWidget {
  const ReportDetails({required this.controller, super.key});
  final TournamentController controller;
  @override
  State<ReportDetails> createState() => ReportDetailsState();
}

class ReportDetailsState extends State<ReportDetails> {
  static const _fields = [
    ('city', 'City', 200.0),
    ('state', 'State', 90.0),
    ('zip', 'ZIP code', 130.0),
  ];
  final text = {for (final f in _fields) f.$1: TextEditingController()};
  String? error;
  late FormDraft draft;
  final fieldFocus = <String, FocusNode>{};
  Map<String, String> shown = const {};
  TournamentController get c => widget.controller;
  Map<String, String> get values => text.map((k, v) => MapEntry(k, v.text));
  bool get dirty => !mapEquals(values, stored);
  Map<String, String> get stored {
    final e = c.event!;
    return {'city': e.city, 'state': e.state, 'zip': e.zip};
  }

  void load() {
    shown = stored;
    for (final e in text.entries) {
      e.value.text = shown[e.key]!;
    }
    error = null;
  }

  @override
  void initState() {
    super.initState();
    load();
    draft = FormDraft(c.workspaceState, 'draft-report-details', text, stored);
  }

  @override
  void didUpdateWidget(ReportDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (mapEquals(values, shown) && !mapEquals(shown, stored)) {
      draft.reset(stored);
      load();
    }
  }

  @override
  void dispose() {
    draft.dispose();
    for (final node in fieldFocus.values) {
      node.dispose();
    }
    for (final t in text.values) {
      t.dispose();
    }
    super.dispose();
  }

  bool commit() {
    if (!dirty) return true;
    final v = values;
    try {
      c.change(
        'Edit report details',
        c.event!.copy(
          city: v['city']!.trim(),
          state: v['state']!.trim().toUpperCase(),
          zip: v['zip']!.trim(),
        ),
      );
      draft.reset(stored);
      setState(load);
      return true;
    } catch (e) {
      setState(() => error = plainMessage(e));
      return false;
    }
  }

  void setLevel(String? level) {
    if (level == null || !commit()) return;
    try {
      c.change('Edit event type', c.event!.copy(level: level));
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  void focusField(String field) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = fieldFocus[field];
      node?.requestFocus();
      if (node?.context case final target?) {
        Scrollable.ensureVisible(target, alignment: 0.25);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = c.event!, colors = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('report-details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DraftStatus(draft: draft),
        Text('Report details', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (key, label, width) in _fields)
              SizedBox(
                width: width,
                child: TextField(
                  key: ValueKey('report-$key'),
                  controller: text[key],
                  focusNode: fieldFocus.putIfAbsent(
                    key,
                    () => FocusNode(debugLabel: key),
                  ),
                  textCapitalization: key == 'state'
                      ? TextCapitalization.characters
                      : TextCapitalization.words,
                  decoration: InputDecoration(labelText: label),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => commit(),
                ),
              ),
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<String>(
                key: ValueKey('report-level-${e.level}'),
                focusNode: fieldFocus.putIfAbsent(
                  'level',
                  () => FocusNode(debugLabel: 'event type'),
                ),
                initialValue: sectionLevels.containsKey(e.level)
                    ? e.level
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Event type'),
                items: [
                  for (final MapEntry(:key, :value) in sectionLevels.entries)
                    DropdownMenuItem(
                      value: key,
                      child: Text(value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: setLevel,
              ),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
        if (dirty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                FilledButton(onPressed: commit, child: const Text('Save')),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    draft.reset(stored);
                    setState(load);
                  },
                  child: const Text('Discard draft'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// When the report was uploaded, its reference number and corrections.
/// Typed in place; Save applies it and navigation preserves the draft.
class SubmissionNotes extends StatefulWidget {
  const SubmissionNotes({required this.controller, super.key});
  final TournamentController controller;
  @override
  State<SubmissionNotes> createState() => _SubmissionNotesState();
}

class _SubmissionNotesState extends State<SubmissionNotes> {
  late final text = TextEditingController(
    text: widget.controller.event!.submission,
  );
  late String shown = widget.controller.event!.submission;
  final focus = FocusNode(debugLabel: 'submission notes');
  String? error;
  late FormDraft draft;
  bool get dirty => text.text != widget.controller.event!.submission;

  @override
  void initState() {
    super.initState();
    draft = FormDraft(
      widget.controller.workspaceState,
      'draft-submission',
      {'notes': text},
      {'notes': shown},
    );
  }

  @override
  void didUpdateWidget(SubmissionNotes oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow undo and other outside changes unless mid-edit.
    final stored = widget.controller.event!.submission;
    if (text.text == shown && stored != shown) {
      draft.reset({'notes': stored});
      shown = stored;
    }
  }

  @override
  void dispose() {
    draft.dispose();
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  void save() {
    if (!dirty) return;
    try {
      widget.controller.change(
        'Update submission record',
        widget.controller.event!.copy(submission: text.text),
      );
      draft.reset({'notes': text.text});
      setState(() {
        shown = text.text;
        error = null;
      });
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DraftStatus(draft: draft),
        Text(
          'Submission notes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'When you uploaded the report, its reference number, and any corrections.',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: TextField(
            key: const ValueKey('submission-notes'),
            controller: text,
            focusNode: focus,
            minLines: 3,
            maxLines: 8,
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
        if (dirty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                FilledButton(onPressed: save, child: const Text('Save')),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () =>
                      setState(() => draft.reset({'notes': shown})),
                  child: const Text('Discard draft'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
