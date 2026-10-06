import '../application/member_lookup.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../application/member_lookup_batch.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/us_chess.dart';
import '../infrastructure/dbf_export.dart';
import 'dialogs.dart';
import 'panels.dart';
import 'drafts.dart';
import 'event_panel.dart';
import 'player_panel.dart';
import 'side_panel.dart';
import '../infrastructure/member_directory.dart';
import 'select.dart';

class ReportsView extends StatefulWidget {
  const ReportsView({
    required this.controller,
    this.onResults,
    this.onBackups,
    this.memberLookup = fetchMembership,
    super.key,
  });
  final TournamentController controller;
  final ValueChanged<String?>? onResults;
  final VoidCallback? onBackups;
  final MemberLookup memberLookup;
  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  final detailsKey = GlobalKey<ReportDetailsState>();
  final scroll = ScrollController();
  bool fetchingStates = false, showAdvice = false;
  String? stateNotice;
  TournamentController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    final saved = controller.workspaceState.readMap('reports-view');
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
      controller.workspaceState.writeMap('reports-view', {
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

  Future<void> _fetchStates() async {
    final c = controller, event = controller.event!;
    final players = _stateless(event);
    final lookups = players.where((p) => p.memberId.isNotEmpty).length;
    // One batch produces one audited membership save, including partial success.
    final found = <String, Json>{};
    final failures = <String>[];
    bool current() => mounted && controller == c && c.event?.id == event.id;
    setState(() {
      fetchingStates = true;
      stateNotice = null;
    });
    try {
      await const MemberLookupBatch().run(
        players,
        lookup: (id) => widget.memberLookup(id),
        isCurrent: current,
        onFound: (player, member) {
          found[player.id] = member.toJson();
          setState(
            () => stateNotice = 'Looked up ${found.length} of $lookups…',
          );
        },
        onFailure: (player, error, _) =>
            failures.add('${player.name}: ${plainMessage(error)}'),
      );
      var filled = 0;
      if (current()) {
        final before = _stateless(c.event!).map((p) => p.id).toSet();
        c.recordMemberships(event.id, found);
        filled = before
            .where((id) => c.event!.player(id).state.isNotEmpty)
            .length;
      }
      if (!mounted) return;
      final remaining = current() ? _stateless(c.event!).length : 0;
      stateNotice = current()
          ? 'Saved $filled missing ${filled == 1 ? 'state' : 'states'}. '
                '${remaining == 0 ? 'All player states are filled.' : '$remaining still missing; add a USCF ID, retry the lookup, or enter the state manually.'}'
                '${failures.isEmpty ? '' : '\n${failures.join('\n')}'}'
          : 'Event changed. Fetch again for the current roster.';
    } catch (error) {
      if (mounted) stateNotice = plainMessage(error);
    } finally {
      if (mounted) setState(() => fetchingStates = false);
    }
  }

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
    return SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, e, issues),
              if (issues.isNotEmpty || advice.isNotEmpty) ...[
                const SizedBox(height: 20),
                _checks(context, e, issues, advice),
              ],
              const SizedBox(height: 32),
              ReportDetails(
                key: detailsKey,
                controller: controller,
                onEditEvent: () => repair(
                  const ReportRepair(
                    'Edit event details',
                    ReportDestination.event,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              _sections(context, e),
              const SizedBox(height: 32),
              _afterUpload(context, e),
            ],
          ),
        ),
      ),
    );
  }

  /// What the page is for, whether it can happen yet, and the one action.
  Widget _header(BuildContext context, Event e, List<ReportIssue> issues) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant);
    final count = reportedSections(e).length;
    final saved = controller.repository.readPreference('lastExport');
    return Column(
      key: const ValueKey('rating-report'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'US Chess rating report',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    issues.isEmpty
                        ? 'Ready to generate · ${count == 1 ? '1 section' : '$count sections'}'
                        : '${issues.length} ${issues.length == 1 ? 'problem' : 'problems'} to fix before generating',
                    key: ValueKey(
                      issues.isEmpty ? 'rating-ready' : 'rating-blocked',
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Creates THEXPORT, TSEXPORT and TDEXPORT.DBF. Not yet tested with the US Chess upload site.',
                    style: muted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            FilledButton.icon(
              key: const ValueKey('generate-dbf'),
              onPressed: issues.isEmpty ? () => exportRating(context) : null,
              icon: const Icon(Icons.folder_outlined, size: 18),
              label: const Text('Generate DBF files'),
            ),
          ],
        ),
        if (saved != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: SelectableText(
                'DBF files saved to ${saved.substring(0, saved.lastIndexOf('|'))}\n'
                '${saved.split('|').last == '${e.revision}' ? 'Includes the current event revision.' : 'Newer changes are not included. Save again to update the report.'}',
                style: muted,
              ),
            ),
          ),
      ],
    );
  }

  /// Every problem beside the place that fixes it. Optional advice folds
  /// below so it never competes with what blocks the report.
  Widget _checks(
    BuildContext context,
    Event e,
    List<ReportIssue> issues,
    List<ReportIssue> advice,
  ) {
    final colors = Theme.of(context).colorScheme;
    final fix = MediaQuery.textScalerOf(context).scale(200);
    final stateless = _stateless(e);
    return _Sheet(
      key: const ValueKey('rating-checks'),
      children: [
        _ColumnHeader([
          const Expanded(child: Text('Problem')),
          const SizedBox(width: 12),
          SizedBox(
            width: fix,
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text('Fix'),
            ),
          ),
        ]),
        for (final issue in issues) _issueRow(issue, fix),
        if (advice.isNotEmpty) ...[
          Semantics(
            button: true,
            expanded: showAdvice,
            child: InkWell(
              key: const PageStorageKey('rating-advice-details'),
              onTap: () => setState(() => showAdvice = !showAdvice),
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow.withValues(alpha: 0.5),
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                child: Row(
                  children: [
                    Icon(
                      showAdvice ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Optional · ${advice.length}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'US Chess accepts the report without these.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showAdvice) ...[
            for (final issue in advice) _issueRow(issue, fix),
            if (stateless.isNotEmpty)
              _Ruled(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (stateless.any((p) => p.memberId.isNotEmpty))
                          OutlinedButton.icon(
                            key: const ValueKey('fetch-states'),
                            onPressed: fetchingStates ? null : _fetchStates,
                            icon: const Icon(
                              Icons.cloud_download_outlined,
                              size: 18,
                            ),
                            label: Text(
                              fetchingStates
                                  ? 'Fetching states…'
                                  : 'Fetch missing states from US Chess',
                            ),
                          ),
                        if (usStates.contains(e.state))
                          OutlinedButton(
                            key: const ValueKey('fill-states'),
                            onPressed: fetchingStates
                                ? null
                                : () => _fillStates(e),
                            child: Text(
                              'Use ${e.state} for ${stateless.length} ${stateless.length == 1 ? 'player' : 'players'} without a state',
                            ),
                          ),
                      ],
                    ),
                    if (stateNotice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Semantics(
                          liveRegion: true,
                          child: SelectableText(stateNotice!),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ],
    );
  }

  /// One or two fixes sit in the Fix column; a fix per player wraps under
  /// the problem so long player lists stay readable.
  Widget _issueRow(ReportIssue issue, double fixWidth) {
    final actions = [
      for (final action in issue.repairs)
        TextButton(
          key: ValueKey(
            'repair-${action.destination.name}-${action.id}-${action.field}',
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          onPressed: () => repair(action),
          child: Text(action.label),
        ),
    ];
    final inline = actions.length <= 2;
    return _Ruled(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(issue.message),
                ),
                if (!inline) Wrap(children: actions),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: fixWidth,
            child: inline
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: actions,
                  )
                : null,
          ),
        ],
      ),
    );
  }

  /// The sections the files will contain, and how US Chess will rate each.
  Widget _sections(BuildContext context, Event e) {
    final colors = Theme.of(context).colorScheme;
    final sections = reportedSections(e);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    const tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
    Widget cells(List<Widget> c) => Row(children: c);
    List<Widget> columns(
      Widget name,
      Widget players,
      Widget rounds,
      Widget control,
      Widget rated,
    ) => [
      Expanded(child: name),
      SizedBox(width: 72 * scale, child: players),
      SizedBox(width: 72 * scale, child: rounds),
      const SizedBox(width: 16),
      SizedBox(width: 150 * scale, child: control),
      SizedBox(width: 190 * scale, child: rated),
    ];
    return Column(
      key: const ValueKey('rating-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sections in the report',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: constraints.maxWidth < 640 * scale
                  ? 640 * scale
                  : constraints.maxWidth,
              child: _Sheet(
                children: [
                  _ColumnHeader(
                    columns(
                      const Text('Section'),
                      const Text('Players', textAlign: TextAlign.right),
                      const Text('Rounds', textAlign: TextAlign.right),
                      const Text('Time control'),
                      const Text('Rated as'),
                    ),
                  ),
                  if (sections.isEmpty)
                    _Ruled(
                      child: Text(
                        'No sections with players yet.',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                  for (final s in sections)
                    _Ruled(
                      child: cells(() {
                        final control = s.effectiveTimeControl(e);
                        String shown = control.isEmpty ? 'None' : control;
                        String rated;
                        bool ratable = true;
                        try {
                          final tc = TimeControl.parse(control);
                          shown = tc.reportText;
                          ratable = tc.category != null;
                          rated = ratable
                              ? '${tc.category!.label} · ${tc.totalMinutes} min'
                              : 'Not ratable';
                        } on TournamentException {
                          ratable = false;
                          rated = 'Not recognized';
                        }
                        return columns(
                          Text(
                            s.name,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '${s.players.toSet().length}',
                            textAlign: TextAlign.right,
                            style: tabular,
                          ),
                          Text(
                            '${reportedRounds(s)}',
                            textAlign: TextAlign.right,
                            style: tabular,
                          ),
                          Text(shown, style: tabular),
                          Text(
                            rated,
                            style: ratable
                                ? null
                                : TextStyle(
                                    color: colors.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                          ),
                        );
                      }()),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Keeping the event safe, and recording the upload once it is done.
  Widget _afterUpload(BuildContext context, Event e) {
    final colors = Theme.of(context).colorScheme;
    final backup = controller.repository
        .readPreference('lastBackup')
        ?.split('|');
    final revision = backup == null ? null : int.tryParse(backup.first);
    final state =
        controller.backupWarning ??
        (revision == null
            ? 'No backup recorded'
            : revision == e.revision
            ? 'Up to date'
            : 'Older · newer changes are not included');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Backup & submission',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Backup: $state',
              key: const ValueKey('backup-state'),
              style: controller.backupWarning == null
                  ? null
                  : TextStyle(color: colors.error),
            ),
            if (widget.onBackups != null)
              OutlinedButton(
                onPressed: widget.onBackups,
                child: const Text('Backups'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SubmissionNotes(controller: controller),
      ],
    );
  }
}

/// A white ruled sheet, like the Players and Pairings tables.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// The shelf column header shared by every table in the app.
class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader(this.cells);
  final List<Widget> cells;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: DefaultTextStyle.merge(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
        child: Row(children: cells),
      ),
    );
  }
}

/// A table row with the half-strength hairline rule above it.
class _Ruled extends StatelessWidget {
  const _Ruled({required this.child, this.first = false});
  final Widget child;
  final bool first;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      alignment: Alignment.centerLeft,
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
      child: child,
    );
  }
}

/// A label and its value in a two-column table.
class _Pair extends StatelessWidget {
  const _Pair(this.label, this.value);
  final String label;
  final Widget value;
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Row(
      children: [
        SizedBox(
          width: 120 * scale,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: value),
      ],
    );
  }
}

/// Where the event was held and its type, saved with the event. Edits save on
/// Enter or Save, like the event panel.
class ReportDetails extends StatefulWidget {
  const ReportDetails({required this.controller, this.onEditEvent, super.key});
  final TournamentController controller;
  final VoidCallback? onEditEvent;
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
  TournamentController get c => widget.controller;
  bool get dirty => draft.dirty;
  Map<String, String> get stored {
    final e = c.event!;
    return {'city': e.city, 'state': e.state, 'zip': e.zip};
  }

  void load() {
    final shown = stored;
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
    draft.reconcile(stored);
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
    try {
      final v = draft.prepareSave(
        stored,
        labels: {for (final field in _fields) field.$1: field.$2},
      );
      if (!draft.dirty) return true;
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
  @override
  Widget build(BuildContext context) {
    final e = c.event!, colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant);
    Widget id(String value) => value.isEmpty
        ? Text('Not entered', style: muted)
        : Text(value, style: const TextStyle(fontFamily: 'SourceCodePro'));
    return Column(
      key: const ValueKey('report-details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DraftStatus(draft: draft),
        Row(
          children: [
            Expanded(
              child: Text(
                'Report details',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (widget.onEditEvent != null)
              TextButton(
                key: const ValueKey('report-edit-event'),
                onPressed: widget.onEditEvent,
                child: const Text('Edit event details'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        _Sheet(
          children: [
            _Ruled(first: true, child: _Pair('Event', Text(e.name))),
            _Ruled(
              child: _Pair(
                'Dates',
                Text(
                  e.endDate.isEmpty || e.endDate == e.date
                      ? e.date
                      : '${e.date} to ${e.endDate}',
                ),
              ),
            ),
            _Ruled(child: _Pair('Chief TD', id(e.tdId))),
            if (e.assistantTdId.isNotEmpty)
              _Ruled(child: _Pair('Assistant TD', id(e.assistantTdId))),
            _Ruled(child: _Pair('Affiliate', id(e.affiliateId))),
            _Ruled(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _Pair(
                  'Site',
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
                    ],
                  ),
                ),
              ),
            ),
            _Ruled(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _Pair(
                  'Event type',
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      label: 'Event type',
                      child: SizedBox(
                        width: 300,
                        child: PlainSelect<String?>(
                          key: ValueKey('report-level-${e.level}'),
                          focusNode: fieldFocus.putIfAbsent(
                            'level',
                            () => FocusNode(debugLabel: 'event type'),
                          ),
                          value: sectionLevels.containsKey(e.level)
                              ? e.level
                              : null,
                          options: [
                            for (final MapEntry(:key, :value)
                                in sectionLevels.entries)
                              SelectOption(key, value),
                          ],
                          onChanged: setLevel,
                        ),
                      ),
                    ),
                  ),
                ),
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
  final focus = FocusNode(debugLabel: 'submission notes');
  String? error;
  late FormDraft draft;
  bool get dirty => draft.dirty;
  Map<String, String> get stored => {
    'notes': widget.controller.event!.submission,
  };

  @override
  void initState() {
    super.initState();
    draft = FormDraft(widget.controller.workspaceState, 'draft-submission', {
      'notes': text,
    }, stored);
  }

  @override
  void didUpdateWidget(SubmissionNotes oldWidget) {
    super.didUpdateWidget(oldWidget);
    draft.reconcile(stored);
  }

  @override
  void dispose() {
    draft.dispose();
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  void save() {
    try {
      final values = draft.prepareSave(
        stored,
        labels: {'notes': 'Submission notes'},
      );
      if (!draft.dirty) return;
      widget.controller.change(
        'Update submission record',
        widget.controller.event!.copy(submission: values['notes']),
      );
      draft.reset(stored);
      setState(() => error = null);
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DraftStatus(draft: draft),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: TextField(
            key: const ValueKey('submission-notes'),
            controller: text,
            focusNode: focus,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Submission notes',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'When you uploaded the report, its reference number, and any corrections.',
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
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
                TextButton(
                  onPressed: () => setState(() {
                    draft.reset(stored);
                    error = null;
                  }),
                  child: const Text('Discard draft'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
