part of 'players_view.dart';

double _columnWidth(BuildContext context, double width) =>
    width * MediaQuery.textScalerOf(context).scale(14) / 14;

/// Names a team for the ticked players, beside the table.
class _TeamPanel extends StatelessWidget {
  const _TeamPanel({
    required this.controller,
    required this.ids,
    required this.onClose,
  });
  final TournamentController controller;
  final List<String> ids;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final e = c.event!;
    final teams = ids.map((id) => e.player(id).team).toSet();
    return FieldsPanel(
      key: ValueKey('team-${ids.join()}'),
      controller: c,
      draftKey: 'draft-team-${(ids.toList()..sort()).join(',')}',
      title: 'Team for ${ids.length} ${ids.length == 1 ? 'player' : 'players'}',
      description: 'Leave blank to remove the team.',
      fields: const [FieldSpec('team', 'Team')],
      values: {'team': teams.length == 1 ? teams.single : ''},
      onClose: onClose,
      onSave: (v) => c.assignTeam(ids, v['team'] ?? ''),
    );
  }
}

/// An event without players: the ways to add them.
class _Welcome extends StatelessWidget {
  const _Welcome({
    required this.onRefreshRoster,
    required this.onImport,
    required this.onPaste,
    required this.onAdd,
  });
  final VoidCallback? onRefreshRoster;
  final VoidCallback onImport, onPaste, onAdd;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add your players',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onRefreshRoster != null)
                OutlinedButton.icon(
                  key: const ValueKey('add-from-url'),
                  onPressed: onRefreshRoster,
                  icon: const Icon(Icons.add_link, size: 18),
                  label: const Text('Add from URL'),
                ),
              OutlinedButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Import file…'),
              ),
              OutlinedButton.icon(
                onPressed: onPaste,
                icon: const Icon(Icons.content_copy, size: 18),
                label: const Text('Paste'),
              ),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add one player'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Bulk actions for the ticked players, in the right-hand column so the
/// table never moves when a box is ticked.
class _SelectionPanel extends StatelessWidget {
  const _SelectionPanel({
    required this.event,
    required this.ids,
    required this.moveTo,
    required this.moveReason,
    required this.swapping,
    required this.canSwap,
    required this.onClear,
    required this.onConfirmMove,
    required this.onCancelMove,
    required this.onMoveTo,
    required this.onNewSection,
    required this.onSwap,
    required this.onAvoid,
    required this.onTeam,
    required this.onStatus,
  });
  final Event event;

  /// The ticked players, in the order they were ticked.
  final List<String> ids;

  /// A move waiting for a reason.
  final String? moveTo;
  final TextEditingController moveReason;

  /// Swapping waits for a second press to confirm.
  final bool swapping;

  /// Two ticked players who can exchange sections.
  final bool canSwap;
  final VoidCallback onClear, onConfirmMove, onCancelMove, onNewSection;
  final ValueChanged<String> onMoveTo;
  final VoidCallback onSwap, onAvoid, onTeam;
  final void Function(StatusAction action, List<String> ids) onStatus;

  @override
  Widget build(BuildContext context) {
    final e = event, colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    final names = ids.map((id) => e.player(id).name).toList();
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
    return SidePanel(
      key: const ValueKey('selection-panel'),
      title: '${ids.length} ${ids.length == 1 ? 'player' : 'players'} selected',
      onClose: onClear,
      footer: [
        OutlinedButton(
          key: const ValueKey('clear-selection'),
          onPressed: onClear,
          child: const Text('Clear selection'),
        ),
      ],
      children: [
        Text(
          names.length <= 6
              ? names.join(', ')
              : '${names.take(5).join(', ')} and ${names.length - 5} more',
          style: muted,
        ),
        ...[
          heading(e.sections.isEmpty ? 'Put in a section' : 'Move to section'),
          if (moveTo != null) ...[
            Text(
              'Move to ${e.sections.firstWhere((s) => s.id == moveTo).name}?',
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('move-reason'),
              controller: moveReason,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason'),
              onSubmitted: (_) => onConfirmMove(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: onConfirmMove,
                  child: const Text('Move'),
                ),
                TextButton(
                  onPressed: onCancelMove,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ] else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in e.sections)
                  ActionChip(
                    chipAnimationStyle: noChipAnimation,
                    key: ValueKey('move-to-${s.id}'),
                    tooltip:
                        '${s.name} has ${s.players.length} '
                        '${s.players.length == 1 ? 'player' : 'players'}',
                    label: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: s.name),
                          TextSpan(
                            text: '  ${s.players.length}',
                            style: muted.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    onPressed: ids.every(s.players.contains)
                        ? null
                        : () => onMoveTo(s.id),
                  ),
                ActionChip(
                  chipAnimationStyle: noChipAnimation,
                  key: const ValueKey('selection-new-section'),
                  avatar: Icon(Icons.add, size: 18, color: colors.onSurface),
                  label: const Text('New section…'),
                  onPressed: onNewSection,
                ),
              ],
            ),
        ],
        heading('Actions'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (canSwap)
              OutlinedButton(
                onPressed: onSwap,
                child: Text(
                  swapping
                      ? 'Confirm swap: ${e.player(ids.first).name} ↔ ${e.player(ids.last).name}'
                      : 'Swap sections',
                ),
              ),
            if (ids.length == 2)
              OutlinedButton(
                onPressed: onAvoid,
                child: const Text('Do not pair together'),
              ),
            OutlinedButton.icon(
              onPressed: onTeam,
              icon: const Icon(Icons.group_outlined, size: 18),
              label: const Text('Assign team'),
            ),
            for (final action in statusActions(e, ids))
              OutlinedButton(
                key: ValueKey('selection-${action.name}'),
                onPressed: () => onStatus(action, ids),
                child: Text(statusLabel(e, action, ids)),
              ),
          ],
        ),
      ],
    );
  }
}

/// Confirms a finished import or rating update in place, with Undo.
class _DonePanel extends StatelessWidget {
  const _DonePanel({
    required this.title,
    required this.message,
    required this.canUndo,
    required this.onUndo,
    required this.onClose,
  });
  final String title, message;

  /// Nothing has changed since, so Undo takes back exactly this.
  final bool canUndo;
  final VoidCallback onUndo, onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SidePanel(
      key: const ValueKey('done-panel'),
      title: title,
      onClose: onClose,
      footer: [
        Row(
          children: [
            if (canUndo)
              OutlinedButton.icon(
                key: const ValueKey('done-undo'),
                onPressed: onUndo,
                icon: const Icon(Icons.undo),
                label: const Text('Undo'),
              ),
            const Spacer(),
            OutlinedButton(
              key: const ValueKey('done-close'),
              autofocus: true,
              onPressed: onClose,
              child: const Text('Done'),
            ),
          ],
        ),
      ],
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 20,
                color: colors.onSurface,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          canUndo
              ? 'Undo puts everything back as it was.'
              : 'Later changes were made. Undo is in History.',
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// The players page above the table: search, adding players, ratings and
/// the other player tools, then the count and Print.
class _RosterPage extends StatelessWidget {
  const _RosterPage({
    required this.controller,
    required this.search,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.tools,
    required this.onAdd,
    required this.fideOnly,
    required this.onRefreshRatings,
    required this.refreshable,
    required this.title,
    required this.onPrint,
    required this.ranked,
    required this.table,
  });
  final TournamentController controller;
  final TextEditingController search;
  final VoidCallback onSearchChanged, onSearchSubmitted;
  final Widget tools;
  final VoidCallback onAdd;

  /// A FIDE-only view refreshes from FIDE's list.
  final bool fideOnly;
  final VoidCallback? onRefreshRatings;

  /// The workspace can refresh ratings from US Chess.
  final bool refreshable;
  final String title;

  /// Null when there is no section to print.
  final void Function(BuildContext context)? onPrint;
  final bool ranked;
  final Widget table;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, layout) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                layout.maxHeight *
                (MediaQuery.textScalerOf(context).scale(14) > 21 ? 0.3 : 0.4),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final searchBox = SearchField(
                        key: const ValueKey('player-search'),
                        controller: search,
                        width: math.min(
                          220,
                          constraints.maxWidth /
                              MediaQuery.textScalerOf(context).scale(1),
                        ),
                        onChanged: onSearchChanged,
                        onSubmitted: onSearchSubmitted,
                      );
                      final actions = Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: onAdd,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add player'),
                          ),
                          if (fideOnly)
                            OutlinedButton(
                              key: const ValueKey('refresh-fide'),
                              onPressed: () =>
                                  showFideList(context, controller),
                              child: const Text('Update FIDE ratings'),
                            )
                          else if (refreshable)
                            OutlinedButton(
                              key: const ValueKey('refresh-uscf'),
                              onPressed: onRefreshRatings,
                              child: const Text('Refresh from US Chess'),
                            ),
                          tools,
                        ],
                      );
                      return Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [searchBox, actions],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final standingsPane = Column(
                key: const ValueKey('standings-pane'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (onPrint case final printList?)
                          OutlinedButton.icon(
                            key: const ValueKey('print-standings'),
                            onPressed: () => printList(context),
                            icon: const Icon(Icons.print_outlined, size: 18),
                            label: Text(
                              ranked ? 'Print standings' : 'Print player list',
                            ),
                          ),
                      ],
                    ),
                  ),
                  Flexible(child: table),
                ],
              );
              return standingsPane;
            },
          ),
        ),
      ],
    ),
  );
}

/// The Player tools menu: other ways to add players, FIDE ratings, and the
/// optional columns.
class _PlayerTools extends StatelessWidget {
  const _PlayerTools({
    required this.controller,
    required this.onRefreshRoster,
    required this.onImport,
    required this.onPaste,
    required this.showRatingPreview,
    required this.onShowRatingPreview,
    required this.showIds,
    required this.onShowIds,
  });
  final TournamentController controller;
  final VoidCallback? onRefreshRoster;
  final VoidCallback onImport, onPaste;
  final bool showRatingPreview, showIds;
  final ValueChanged<bool?> onShowRatingPreview, onShowIds;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    builder: (context, menu, child) => OutlinedButton.icon(
      key: const ValueKey('player-tools'),
      icon: const Icon(Icons.expand_more, size: 18),
      iconAlignment: IconAlignment.end,
      label: const Text('Player tools'),
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
    ),
    menuChildren: [
      if (onRefreshRoster != null)
        MenuItemButton(
          key: const ValueKey('update-event'),
          leadingIcon: const Icon(Icons.sync),
          onPressed: onRefreshRoster,
          child: const Text('Refresh from URL'),
        ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.upload_file_outlined),
        onPressed: onImport,
        child: const Text('Import file…'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.content_copy),
        onPressed: onPaste,
        child: const Text('Paste'),
      ),
      if (hasFideSection(controller.event!))
        MenuItemButton(
          key: const ValueKey('fide-ratings'),
          leadingIcon: const Icon(Icons.public),
          onPressed: () => showFideList(context, controller),
          child: const Text('FIDE ratings…'),
        ),
      const Divider(),
      CheckboxMenuButton(
        key: const ValueKey('show-rating-preview'),
        value: showRatingPreview,
        onChanged: onShowRatingPreview,
        child: const Text('Show rating estimates'),
      ),
      CheckboxMenuButton(
        value: showIds,
        onChanged: onShowIds,
        child: const Text('Show US Chess IDs'),
      ),
    ],
  );
}

/// The crosstable's title, with a Scheveningen's match score beside it.
class _CrosstableHeading extends StatelessWidget {
  const _CrosstableHeading({required this.matchScore});
  final String? matchScore;

  @override
  Widget build(BuildContext context) => PaneHeading(
    child: Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Crosstable',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        if (matchScore case final score?)
          Text(
            key: const ValueKey('match-score'),
            score,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    ),
  );
}

/// Find a player, print, switch to prize standings, and the tie-break
/// order; a key that is not a result says which keys are.
class _CrosstableToolbar extends StatelessWidget {
  const _CrosstableToolbar({
    required this.search,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onPrint,
    required this.ranked,
    required this.prizeSection,
    required this.prizeStandings,
    required this.onPrizeStandings,
    required this.tiebreakColumns,
    required this.invalidKey,
  });
  final TextEditingController search;
  final VoidCallback onSearchChanged, onSearchSubmitted;

  /// Null when there is no section to print.
  final VoidCallback? onPrint;
  final bool ranked, prizeSection, prizeStandings;
  final ValueChanged<bool> onPrizeStandings;
  final List<TiebreakMethod> tiebreakColumns;
  final bool invalidKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SearchField(
            key: const ValueKey('player-search'),
            controller: search,
            onChanged: onSearchChanged,
            onSubmitted: onSearchSubmitted,
          ),
          if (onPrint != null)
            IconButton(
              key: const ValueKey('print-standings'),
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              tooltip: ranked ? 'Print standings' : 'Print player list',
              onPressed: onPrint,
              icon: const Icon(Icons.print_outlined, size: 18),
            ),
          if (prizeSection)
            FilterChip(
              key: const ValueKey('prize-standings'),
              chipAnimationStyle: noChipAnimation,
              label: const Text('Prize standings'),
              selected: prizeStandings,
              onSelected: onPrizeStandings,
            ),
          if (tiebreakColumns.isNotEmpty)
            Text(
              key: const ValueKey('standings-tiebreak-order'),
              'Tie-breaks: ${tiebreakColumns.map((m) => m.label).join(', ')}',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          if (invalidKey)
            Semantics(
              liveRegion: true,
              child: Text(
                key: const ValueKey('standing-key-hint'),
                'Not a result key. $resultKeyHint · $moreResultKeys',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The rows on a ruled sheet under their column header, scrolling inside
/// the pane when it has a height to fill.
class _RosterTable extends StatelessWidget {
  const _RosterTable({
    required this.items,
    required this.width,
    required this.scroll,
    required this.standingsOnly,
    required this.searched,
    required this.columns,
  });
  final List<Widget> items;

  /// The table's width before text scaling.
  final double width;
  final ScrollController scroll;
  final bool standingsOnly;

  /// Something is typed in the search box.
  final bool searched;
  final Widget columns;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      // Only a search can come up empty; with nothing typed there is simply
      // nobody to list yet.
      return searched
          ? const EmptyState(
              icon: Icons.search_off,
              title: 'No matches',
              body: 'Try a different name or US Chess ID.',
            )
          : Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  'No players yet.',
                  key: const ValueKey('no-players'),
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            );
    }
    return Padding(
      padding: standingsOnly
          ? const EdgeInsets.fromLTRB(12, 4, 12, 12)
          : const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final minimum = width * scale;
          // As wide as the boards pane beside it grows (760 less padding).
          final available = constraints.maxWidth.clamp(0.0, 736 * scale);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              // Match the boards in Pairings; keep the roster compact.
              width: standingsOnly && available > minimum ? available : minimum,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLowest,
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    columns,
                    if (!constraints.hasBoundedHeight)
                      ...items
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          controller: scroll,
                          children: items,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The column headings, matching the cells each row shows.
class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.columns, required this.draft});
  final ShownColumns columns;

  /// The open rating review, whose columns show when [columns] has them.
  final RatingRefresh? draft;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget cell(double width, String text, {bool center = false}) => SizedBox(
      width: _columnWidth(context, width),
      child: Text(
        text,
        textAlign: center ? TextAlign.center : null,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    return Container(
      key: const ValueKey('player-column-header'),
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
        child: Row(
          children: [
            if (columns.checkbox)
              SizedBox(width: _columnWidth(context, RosterColumns.check)),
            // Once play starts the rows are in standings order: Rank is the
            // place, # stays the pairing number.
            if (columns.scores) cell(RosterColumns.rank, 'Rank'),
            cell(RosterColumns.number, '#'),
            const Expanded(child: Text('Name')),
            if (columns.ids) cell(RosterColumns.id, 'US Chess ID'),
            if (columns.rating)
              cell(RosterColumns.rating, draft == null ? 'Rating' : 'Entered'),
            if (columns.fide) ...[
              cell(RosterColumns.id, 'FIDE ID'),
              cell(RosterColumns.rating, 'FIDE'),
            ],
            if (draft case final draft? when columns.review) ...[
              cell(RosterColumns.proposal, proposedHeading(draft)),
              cell(RosterColumns.uscfName, 'US Chess name'),
            ],
            if (columns.ratingPreview)
              cell(RosterColumns.preview, 'Est. regular (Δ)'),
            if (columns.membership)
              cell(RosterColumns.membership, 'US Chess expires'),
            if (columns.note) cell(RosterColumns.note, 'Registration note'),
            for (var r = 1; r <= columns.rounds; r++)
              cell(RosterColumns.round, 'R$r', center: true),
            if (columns.scores) cell(RosterColumns.points, 'Pts', center: true),
            for (final m in columns.tiebreaks)
              Tooltip(
                message: '${m.label} (${m.rule})',
                child: cell(RosterColumns.tiebreak, m.short, center: true),
              ),
          ],
        ),
      ),
    );
  }
}

/// A section's name over its players, with a box that ticks them all.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.section,
    required this.players,
    required this.picked,
    required this.checkbox,
    required this.standingsOnly,
    required this.onTick,
  });

  /// Null for the players not in a section.
  final Section? section;
  final List<Player> players;

  /// How many of [players] are ticked.
  final int picked;
  final bool checkbox, standingsOnly;
  final void Function(Iterable<String> ids, bool value) onTick;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final s = section;
    final ids = players.map((p) => p.id).toSet();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant),
          bottom: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          if (checkbox)
            SizedBox(
              width: _columnWidth(context, RosterColumns.check),
              child: Align(
                alignment: Alignment.centerLeft,
                child: PlainCheckbox(
                  label:
                      'Select all visible players in ${s?.name ?? 'unassigned players'}',
                  tristate: true,
                  value: ids.isEmpty || picked == 0
                      ? false
                      : picked == ids.length
                      ? true
                      : null,
                  onChanged: ids.isEmpty
                      ? null
                      : (_) => onTick(ids, picked != ids.length),
                ),
              ),
            ),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: s?.name ?? 'Not in a section',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (!standingsOnly)
                    TextSpan(
                      text:
                          '   ${['${s?.players.length ?? players.length} players', if (standingsOnly && s != null) pairingFormat(s) == s.format ? formatName(s.format) : 'Quad · will pair as a small Swiss', if (standingsOnly && s != null) boardRange(s), if (standingsOnly && s != null && s.rounds.isNotEmpty) 'round ${s.rounds.length} of ${s.plannedRounds}'].join(' · ')}',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A section with nobody listed in it.
class _EmptyGroup extends StatelessWidget {
  const _EmptyGroup({required this.standingsOnly});
  final bool standingsOnly;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
    child: Text(
      standingsOnly
          ? 'No players yet.'
          : 'No players. Tick players below and move them here.',
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// One player's row: tick box, place, number, name and the columns the
/// table shows.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.event,
    required this.player,
    required this.section,
    required this.number,
    required this.rank,
    required this.standing,
    required this.ticked,
    required this.open,
    required this.standingsOnly,
    required this.columns,
    required this.draft,
    required this.roundCells,
    required this.onMenu,
    required this.onRemove,
    required this.onOpen,
    required this.onTick,
  });

  /// The event players and FIDE categories are looked up in.
  final Event event;
  final Player player;
  final Section? section;
  final String number, rank;
  final Standing? standing;
  final bool ticked;

  /// The player's card is open.
  final bool open;
  final bool standingsOnly;

  /// The columns shown, the same for the header and every row.
  final ShownColumns columns;

  /// The open rating review, whose columns show when [columns] has them.
  final RatingRefresh? draft;
  final List<Widget> roundCells;
  final ValueChanged<Offset> onMenu;
  final VoidCallback onRemove, onOpen;
  final ValueChanged<bool> onTick;

  @override
  Widget build(BuildContext context) {
    final p = player, s = section;
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant);
    Widget cell(double width, String text, [TextStyle? style]) => SizedBox(
      width: _columnWidth(context, width),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
    // The name cell, explained when the player is outside the section's
    // rating range.
    Widget rangeTooltip(Widget child) {
      final problem = standingsOnly || s == null
          ? null
          : ratingRangeProblem(p, s);
      if (problem == null) return child;
      return Tooltip(
        message: '$problem Open the player to move them or allow them in.',
        child: child,
      );
    }

    return ContextMenuKeys(
      onMenu: onMenu,
      child: CallbackShortcuts(
        bindings: {
          if (!standingsOnly) ...{
            const SingleActivator(LogicalKeyboardKey.delete): onRemove,
            // The Mac Delete key sends Backspace.
            const SingleActivator(LogicalKeyboardKey.backspace): onRemove,
          },
        },
        child: InkWell(
          key: ValueKey('player-${p.id}'),
          // The crosstable is one Tab stop, at a score cell; Space there
          // opens the player, and the search box finds anyone by name.
          canRequestFocus: !standingsOnly,
          onSecondaryTapDown: (details) => onMenu(details.globalPosition),
          onTap: onOpen,
          child: Container(
            constraints: standingsOnly
                ? const BoxConstraints(minHeight: 32)
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: open
                  ? colors.primary.withValues(alpha: 0.1)
                  : ticked
                  ? colors.surfaceContainerHigh
                  : null,
              border: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (columns.checkbox)
                      SizedBox(
                        width: _columnWidth(context, RosterColumns.check),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: PlainCheckbox(
                            label: 'Select ${p.name}',
                            value: ticked,
                            onChanged: (v) => onTick(v == true),
                          ),
                        ),
                      ),
                    if (columns.scores)
                      KeyedSubtree(
                        key: ValueKey('rank-${p.id}'),
                        child: cell(RosterColumns.rank, rank),
                      ),
                    KeyedSubtree(
                      key: ValueKey('number-${p.id}'),
                      child: cell(RosterColumns.number, number, muted),
                    ),
                    Expanded(
                      child: rangeTooltip(
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: p.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: p.withdrawn
                                      ? colors.onSurfaceVariant
                                      : null,
                                  decoration: p.withdrawn
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              if (p.team.isNotEmpty)
                                TextSpan(
                                  text: '  · ${p.team}',
                                  style: muted.copyWith(fontSize: 12),
                                ),
                              if (p.withdrawn)
                                TextSpan(
                                  text: '  withdrawn',
                                  style: muted.copyWith(fontSize: 12),
                                ),
                              if (!standingsOnly &&
                                  s != null &&
                                  ratingRangeProblem(p, s) != null) ...[
                                const TextSpan(text: '  '),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Icon(
                                    Icons.error_outline,
                                    size: 16,
                                    color: attentionColor(colors),
                                  ),
                                ),
                                TextSpan(
                                  text: ' outside the rating range',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: attentionColor(colors),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (columns.ids)
                      cell(
                        RosterColumns.id,
                        p.memberId.isEmpty ? '—' : p.memberId,
                        muted.copyWith(fontFamily: 'SourceCodePro'),
                      ),
                    if (columns.rating)
                      cell(
                        RosterColumns.rating,
                        ratingText(p.rating),
                        const TextStyle(fontFamily: 'SourceCodePro'),
                      ),
                    if (columns.fide) ...[
                      cell(
                        RosterColumns.id,
                        p.fideId.isEmpty ? '—' : p.fideId,
                        muted.copyWith(fontFamily: 'SourceCodePro'),
                      ),
                      () {
                        // The rating the player's section uses.
                        final rating = fideRating(
                          p,
                          s == null ? null : sectionFideCategory(event, s),
                        );
                        return cell(
                          RosterColumns.rating,
                          rating == 0 ? 'UNR' : '$rating',
                          const TextStyle(fontFamily: 'SourceCodePro'),
                        );
                      }(),
                    ],
                    if (draft case final draft? when columns.review) ...[
                      _ProposedRating(player: p, draft: draft),
                      _UscfName(player: p, draft: draft),
                    ],
                    if (columns.ratingPreview)
                      _RatingPreview(event: event, player: p, section: s),
                    if (columns.membership)
                      SizedBox(
                        width: _columnWidth(context, RosterColumns.membership),
                        child: MembershipCell(
                          player: p,
                          eventDate: event.lastDate,
                        ),
                      ),
                    if (columns.note)
                      Tooltip(
                        message: p.registrationNote,
                        child: cell(
                          RosterColumns.note,
                          p.registrationNote.isEmpty ? '—' : p.registrationNote,
                          muted,
                        ),
                      ),
                    ...roundCells,
                    if (columns.scores) ...[
                      SizedBox(
                        width: _columnWidth(context, RosterColumns.points),
                        child: Text(
                          standing == null ? '' : halves(standing!.points),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      for (final m in columns.tiebreaks)
                        cell(
                          RosterColumns.tiebreak,
                          standing?.tiebreak(m)?.text ?? '',
                          muted,
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A round's cell in a player's row: their score boxes, or a mark with a
/// tooltip (a bye, or not paired yet), or nothing past the planned rounds.
class _RoundCell extends StatelessWidget {
  const _RoundCell({
    required this.boxKey,
    required this.mark,
    required this.tip,
    required this.boxes,
  });

  /// Past the section's planned rounds: an empty column.
  const _RoundCell.blank()
    : boxKey = null,
      mark = null,
      tip = '',
      boxes = const [];

  /// Kept on the cell itself, where tests and the fuzzer find it.
  final Key? boxKey;

  /// Null for a blank cell.
  final String? mark;
  final String tip;
  final List<Widget> boxes;

  @override
  Widget build(BuildContext context) {
    final mark = this.mark;
    if (mark == null) {
      return SizedBox(width: _columnWidth(context, RosterColumns.round));
    }
    return SizedBox(
      key: boxKey,
      width: _columnWidth(context, RosterColumns.round),
      child: boxes.isEmpty
          ? Tooltip(
              message: tip,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  mark,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : Row(children: [for (final box in boxes) Expanded(child: box)]),
    );
  }
}

/// One game's score box in the crosstable, which takes result keys.
class _CellBox extends StatelessWidget {
  const _CellBox({
    required this.game,
    required this.player,
    required this.round,
    required this.node,
    required this.focused,
    required this.entry,
    required this.label,
    required this.tip,
    required this.onKey,
    required this.onFocusChange,
    required this.onTap,
  });
  final Game game;
  final Player player;
  final int round;
  final FocusNode node;
  final bool focused;

  /// The one cell Tab enters the crosstable at.
  final bool entry;
  final String label, tip;
  final KeyEventResult Function(KeyEvent event) onKey;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final g = game, p = player;
    node.skipTraversal = !entry;
    return Focus(
      focusNode: node,
      onKeyEvent: (_, event) => onKey(event),
      onFocusChange: onFocusChange,
      child: Semantics(
        label: label,
        child: Tooltip(
          message: tip,
          child: GestureDetector(
            key: ValueKey('standing-score-${g.id}-${p.id}'),
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(
                  color: focused ? colors.primary : colors.outlineVariant,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                scoreMark(g.outcome, white: g.white == p.id).isEmpty
                    ? '—'
                    : scoreMark(g.outcome, white: g.white == p.id),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The US Chess rating and its change, ticked to include it in the update.
class _ProposedRating extends StatelessWidget {
  const _ProposedRating({required this.player, required this.draft});
  final Player player;
  final RatingRefresh draft;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final problem = draft.problem(p);
    final proposed = draft.proposed(p);
    final highlight = problem == null && draft.largeChange(p);
    final colors = Theme.of(context).colorScheme;
    final m = draft.observations[p.id];
    // Numbers wherever US Chess gave an answer: unrated reads UNR, an
    // unchanged rating ±0. Other problems keep their reason.
    final unrated = draft.unratedAtUscf(p);
    final numbers =
        proposed != null &&
        proposed > 0 &&
        (problem == null || draft.upToDate(p));
    final shown = unrated
        ? 'UNR'
        : numbers
        ? '$proposed'
        : null;
    final change = unrated
        // The entered rating stays; US Chess never replaces it with UNR.
        ? (p.rating == 0 ? '±0' : 'keep ${p.rating}')
        : numbers
        ? ratingChange(draft, p)
        : null;
    return Tooltip(
      message: [
        ?problem,
        if (highlight)
          p.rating == 0
              ? 'Highlighted: first rating. Entered as unrated (UNR).'
              : 'Highlighted: large rating change, more than 50 points.',
        if (m != null) 'Supplement ${m.supplementDate ?? 'date unavailable'}',
      ].join('\n'),
      child: Container(
        key: ValueKey('rating-proposal-${p.id}'),
        width: _columnWidth(context, RosterColumns.proposal) - 12,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        color: highlight ? colors.tertiary.withValues(alpha: 0.16) : null,
        child: Row(
          children: [
            PlainCheckbox(
              key: ValueKey('approve-rating-${p.id}'),
              label: 'Apply US Chess rating for ${p.name}',
              value: problem == null && draft.selected.contains(p.id),
              onChanged: draft.busy || problem != null
                  ? null
                  : (value) => draft.select(p, value == true),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                draft.missingId(p)
                    ? TextSpan(
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(
                              Icons.error_outline,
                              size: 16,
                              color: attentionColor(colors),
                            ),
                          ),
                          TextSpan(
                            text: ' No US Chess ID',
                            style: TextStyle(
                              color: attentionColor(colors),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : shown == null
                    ? TextSpan(
                        // The first sentence fits; the tooltip has the rest.
                        text: problem?.split('. ').first ?? '—',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      )
                    : TextSpan(
                        children: [
                          TextSpan(
                            text: shown,
                            style: TextStyle(
                              fontFamily: 'SourceCodePro',
                              fontWeight: highlight
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: problem == null
                                  ? null
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                          if (change != null)
                            TextSpan(
                              text: '  $change',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: highlight
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: highlight
                                    ? colors.onSurface
                                    : colors.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                        ],
                      ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The name US Chess has for the ID, flagged when it looks like somebody
/// else, so a mistyped ID is caught before its rating is used.
class _UscfName extends StatelessWidget {
  const _UscfName({required this.player, required this.draft});
  final Player player;
  final RatingRefresh draft;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final colors = Theme.of(context).colorScheme;
    final m = draft.observations[p.id];
    final mismatch = draft.nameMismatch(p);
    final width = _columnWidth(context, RosterColumns.uscfName);
    if (m == null || m.name.trim().isEmpty) {
      return SizedBox(
        width: width,
        child: Text('—', style: TextStyle(color: colors.onSurfaceVariant)),
      );
    }
    if (!mismatch) {
      return SizedBox(
        key: ValueKey('uscf-name-${p.id}'),
        width: width,
        child: Text(
          m.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      );
    }
    final attention = attentionColor(colors);
    return Tooltip(
      message:
          'Entered as ${p.name}. US Chess has ${m.name} for ${p.memberId}. '
          'Check the ID before updating this rating.',
      child: Semantics(
        label: 'US Chess name ${m.name} differs from the entered name',
        excludeSemantics: true,
        child: SizedBox(
          key: ValueKey('uscf-name-${p.id}'),
          width: width,
          child: Row(
            children: [
              Icon(Icons.error_outline, size: 16, color: attention),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: attention,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An estimate of the player's regular rating after this event.
class _RatingPreview extends StatelessWidget {
  const _RatingPreview({
    required this.event,
    required this.player,
    required this.section,
  });
  final Event event;
  final Player player;
  final Section? section;

  @override
  Widget build(BuildContext context) {
    final preview = previewRating(event, section, player);
    final change = preview.change;
    return SizedBox(
      width: _columnWidth(context, RosterColumns.preview),
      child: Tooltip(
        message:
            preview.reason ??
            'Approximate regular rating from ${preview.games} completed played games, using starting opponent ratings.',
        child: Text(
          preview.rating == null
              ? '—'
              : '≈${preview.rating} (${change! > 0 ? '+' : ''}$change)',
          key: ValueKey('rating-preview-${player.id}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'SourceCodePro'),
        ),
      ),
    );
  }
}
