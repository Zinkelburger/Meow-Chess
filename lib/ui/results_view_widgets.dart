part of 'results_view.dart';

/// The widest a pane of boards grows, before text scaling.
const _widestPane = 760.0;
const _board = 40.0, _row = 32.0, _statusLine = 38.0;

double _scoreWidth(BuildContext context) =>
    math.max(36, MediaQuery.textScalerOf(context).scale(32));

/// The board column grows with the text, so its "Board" heading still fits
/// at large text sizes (it vanished at 200%; found by the UI fuzzer).
double _boardWidth(BuildContext context) =>
    math.max(_board, MediaQuery.textScalerOf(context).scale(_board));

/// The boards and the crosstable: side by side in a wide window, with their
/// headings and toolbars sharing rows, and one above the other otherwise.
class _PairingsLayout extends StatelessWidget {
  const _PairingsLayout({
    required this.sectionId,
    required this.controller,
    required this.roundAction,
    required this.onPlayer,
    required this.crosstableHeading,
    required this.stackedScroll,
    required this.boardHeading,
    required this.boardToolbar,
    required this.notices,
    required this.boardTable,
  });
  final String? sectionId;
  final TournamentController controller;
  final Widget? roundAction;
  final void Function(String id, {String? focus}) onPlayer;
  final GlobalKey crosstableHeading;
  final ScrollController stackedScroll;
  final Widget boardHeading, boardToolbar, boardTable;
  final List<Widget> notices;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, layout) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      // A wide gutter with a hairline keeps the two tables distinct.
      const gutter = 40.0;
      final split = layout.maxWidth >= 1040 * scale + gutter;
      // Each pane takes half of a wide window, so long names fit, up to
      // a width a row is still easy to read across.
      final paneWidth = math.min(
        (layout.maxWidth - gutter) / 2,
        _widestPane * scale,
      );
      final divider = SizedBox(
        width: gutter,
        child: Center(
          child: VerticalDivider(
            width: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      );
      final standings = PlayersView(
        key: ValueKey('crosstable-$sectionId'),
        controller: controller,
        sectionId: sectionId,
        standingsOnly: true,
        onPlayer: onPlayer,
        standingsLayout: (heading, toolbar, table) {
          final crossHeading = KeyedSubtree(
            key: crosstableHeading,
            child: heading,
          );
          if (!split) {
            return SingleChildScrollView(
              key: const ValueKey('pairings-stacked'),
              controller: stackedScroll,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: math.min(layout.maxWidth, _widestPane * scale),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      boardHeading,
                      boardToolbar,
                      ...notices,
                      boardTable,
                      const SizedBox(height: 24),
                      crossHeading,
                      toolbar,
                      table,
                    ],
                  ),
                ),
              ),
            );
          }
          Widget sharedRow(Widget left, Widget right) => IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: paneWidth, child: left),
                divider,
                SizedBox(width: paneWidth, child: right),
              ],
            ),
          );
          return Column(
            key: const ValueKey('pairings-split'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: layout.maxHeight * 0.6),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      sharedRow(crossHeading, boardHeading),
                      sharedRow(toolbar, boardToolbar),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: paneWidth, child: table),
                    divider,
                    SizedBox(
                      width: paneWidth,
                      child: notices.isEmpty
                          ? boardTable
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ...notices,
                                Expanded(child: boardTable),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (roundAction != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: roundAction!,
              ),
            ),
          Expanded(child: standings),
        ],
      );
    },
  );
}

/// Use when a game is still going but the next round must be paired: a
/// result assumed for pairing only, docked beside the boards.
class _AssumePanel extends StatelessWidget {
  const _AssumePanel({
    required this.controller,
    required this.gameId,
    required this.onClose,
  });
  final TournamentController controller;
  final String gameId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    // C.04.2 3.1: a FIDE section pairs an unfinished game as a draw.
    final fide = c.event!.sections.any(
      (s) =>
          s.fideRated &&
          s.rounds.any((r) => r.games.any((g) => g.id == gameId)),
    );
    return FieldsPanel(
      key: ValueKey('assume-$gameId'),
      controller: c,
      draftKey: 'draft-assume-$gameId',
      title: 'Assume a result for pairing',
      description: fide
          ? 'Use when a game is still going but the next round must be paired. FIDE pairs it as a draw; it does not count for points or ratings.'
          : 'Use when a game is still going but the next round must be paired. This is not a real result and does not count for points or ratings.',
      fields: [
        FieldSpec(
          'score',
          'Assume',
          options: fide
              ? const {'0.5': 'Draw'}
              : const {'0.5': 'Draw', '1': 'White wins', '0': 'Black wins'},
        ),
        const FieldSpec('reason', 'Reason', required: true),
      ],
      values: const {'score': '0.5'},
      saveLabel: 'Assume for pairing',
      onClose: onClose,
      onSave: (values) {
        final outcome = switch (values['score']) {
          '1' => Outcome.whiteWin,
          '0.5' => Outcome.draw,
          '0' => Outcome.blackWin,
          _ => null,
        };
        if (outcome == null) {
          throw const TournamentException('Choose a result.');
        }
        c.setPairingAssumption(gameId, outcome, values['reason']!.trim());
      },
    );
  }
}

/// Compact round heading beside the crosstable heading.
class _RoundLine extends StatelessWidget {
  const _RoundLine({
    required this.title,
    required this.facts,
    required this.pastStatus,
    required this.partners,
    required this.onPartners,
    required this.roundNumbers,
    required this.selectedRound,
    required this.showAllRounds,
    required this.onPickRound,
    required this.onShowAll,
  });
  final String title;
  final List<String> facts;
  final Widget? pastStatus;

  /// A bughouse section still to form its partnerships, before round 1.
  final Section? partners;
  final ValueChanged<Section> onPartners;
  final List<int> roundNumbers;
  final int? selectedRound;
  final bool showAllRounds;
  final ValueChanged<int> onPickRound;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tabular = const [FontFeature.tabularFigures()];
    // Every piece of the heading is one control tall, so when the chips wrap
    // the title still sits on the same line as the Crosstable title beside it.
    final band = BoxConstraints(
      minHeight: MediaQuery.textScalerOf(context).scale(controlHeight),
    );
    Widget line(Widget child) => ConstrainedBox(
      constraints: band,
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        heightFactor: 1,
        child: child,
      ),
    );
    return PaneHeading(
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          line(
            Semantics(
              header: true,
              child: Text.rich(
                key: const ValueKey('round-line'),
                TextSpan(
                  children: [
                    TextSpan(
                      text: title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    TextSpan(
                      text: '   ${facts.join('  ·  ')}',
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.onSurfaceVariant,
                        fontFeatures: tabular,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (pastStatus case final status?) line(status),
          if (partners case final s?)
            line(
              TextButton(
                key: const ValueKey('bughouse-partners'),
                onPressed: () => onPartners(s),
                child: const Text('Partners'),
              ),
            ),
          // The round chips share the title's line, so a section with them
          // is no taller than one without.
          if (roundNumbers.length > 1)
            Semantics(
              label: 'Show round',
              container: true,
              child: Wrap(
                key: const ValueKey('round-selector'),
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final n in roundNumbers)
                    ChoiceChip(
                      label: Text('$n'),
                      showCheckmark: false,
                      selected:
                          !showAllRounds &&
                          (selectedRound ?? roundNumbers.last) == n,
                      onSelected: (_) => onPickRound(n),
                    ),
                  ChoiceChip(
                    key: const ValueKey('all-rounds'),
                    label: const Text('All'),
                    showCheckmark: false,
                    selected: showAllRounds,
                    onSelected: (_) => onShowAll(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Find boards, filter missing results, edit pairings, and print.
class _BoardToolbar extends StatelessWidget {
  const _BoardToolbar({
    required this.controller,
    required this.search,
    required this.searchable,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.prelim,
    required this.viewingPast,
    required this.correcting,
    required this.onCorrect,
    required this.onDoneCorrecting,
    required this.onEditPairings,
    required this.repair,
    required this.onRepair,
    required this.missingOnly,
    required this.onMissingOnly,
    required this.printTooltip,
    required this.onPrint,
  });
  final TournamentController controller;
  final TextEditingController search;
  final bool searchable;
  final VoidCallback onSearchChanged, onSearchSubmitted;
  final Section? prelim;
  final bool viewingPast, correcting;
  final VoidCallback onCorrect, onDoneCorrecting;

  /// Null hides Edit pairings.
  final VoidCallback? onEditPairings;
  final ({Section section, Round round, List<int> boards})? repair;
  final VoidCallback? onRepair;
  final bool missingOnly;
  final ValueChanged<bool>? onMissingOnly;
  final String printTooltip;
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SearchField(
          key: const ValueKey('board-search'),
          controller: search,
          enabled: searchable,
          onChanged: onSearchChanged,
          onSubmitted: onSearchSubmitted,
        ),
        if (prelim case final prelim?) HollandFinalsAction(controller, prelim),
        if (viewingPast && correcting)
          OutlinedButton(
            key: const ValueKey('done-correcting'),
            onPressed: onDoneCorrecting,
            child: const Text('Done correcting'),
          )
        else if (viewingPast)
          OutlinedButton(
            key: const ValueKey('correct-round'),
            onPressed: onCorrect,
            child: const Text('Correct a result'),
          )
        else if (onEditPairings case final edit?)
          TextButton(
            key: const ValueKey('edit-pairings'),
            onPressed: edit,
            child: const Text('Edit pairings'),
          ),
        // Stays in place, greyed, once every board has started, so the
        // toolbar does not reflow under the last result being typed.
        if (repair case final repair?)
          Tooltip(
            message: repair.boards.isEmpty
                ? 'Every board has a result or has started'
                : 'Pair the boards that have not started again, as after a withdrawal',
            child: TextButton(
              key: const ValueKey('repair-unstarted'),
              onPressed: repair.boards.isEmpty ? null : onRepair,
              child: const Text('Re-pair unstarted boards'),
            ),
          ),
        FilterChip(
          chipAnimationStyle: noChipAnimation,
          label: const Text('Missing only'),
          selected: missingOnly,
          onSelected: onMissingOnly,
        ),
        IconButton(
          key: const ValueKey('print-round'),
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          padding: EdgeInsets.zero,
          tooltip: printTooltip,
          onPressed: onPrint,
          icon: const Icon(Icons.print_outlined, size: 18),
        ),
      ],
    ),
  );
}

/// Where focus rests after the last missing result, so the next key
/// cannot overwrite a board. Announced as it appears. It sits in the
/// status line under the boards, which is always there, so nothing moves
/// when the last result goes in.
class _AllEntered extends StatelessWidget {
  const _AllEntered({
    required this.doneNode,
    required this.every,
    required this.onFocusChange,
  });
  final FocusNode doneNode;

  /// Every board has a result, not only those listed.
  final bool every;
  final VoidCallback onFocusChange;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Focus(
      focusNode: doneNode,
      onFocusChange: (_) => onFocusChange(),
      child: Semantics(
        liveRegion: true,
        child: Container(
          key: const ValueKey('all-results-entered'),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(
              color: doneNode.hasFocus ? focusRing(colors) : Colors.transparent,
              width: focusRingWidth,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 16,
                color: colors.onSurface,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  every ? 'All results entered' : 'All matching boards entered',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// In place of the boards when none are listed. With Missing only on,
/// the last result empties the sheet, so this message is then where
/// focus rests. A search that finds nothing says so; without a search or
/// the filter it never reads as one.
class _NoBoards extends StatelessWidget {
  const _NoBoards({
    required this.searched,
    required this.missingOnly,
    required this.allEntered,
    required this.doneNode,
    required this.onFocusChange,
  });
  final bool searched, missingOnly, allEntered;
  final FocusNode doneNode;
  final VoidCallback onFocusChange;

  @override
  Widget build(BuildContext context) {
    if (missingOnly && (!searched || allEntered)) {
      final colors = Theme.of(context).colorScheme;
      return Focus(
        focusNode: doneNode,
        onFocusChange: (_) => onFocusChange(),
        child: Semantics(
          liveRegion: true,
          child: Container(
            key: const ValueKey('all-results-entered'),
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: doneNode.hasFocus
                    ? focusRing(colors)
                    : Colors.transparent,
                width: focusRingWidth,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: EmptyState(
              icon: Icons.check_circle_outline,
              title: searched
                  ? 'All matching boards entered'
                  : 'All results entered',
              body: searched
                  ? 'Clear the search or turn off Missing only to see the other boards.'
                  : 'Turn off Missing only to review them.',
            ),
          ),
        ),
      );
    }
    return searched
        ? const EmptyState(
            icon: Icons.search_off,
            title: 'No matching boards',
            body: 'Try another name or board number.',
          )
        : const EmptyState(
            icon: Icons.grid_view_outlined,
            title: 'No boards in this round',
            body: 'Nobody is paired against an opponent in this round.',
          );
  }
}

/// Before there is anything to pair: what to do next, with the way
/// there when the workspace gave one.
class _NothingToPair extends StatelessWidget {
  const _NothingToPair({
    required this.noPlayers,
    required this.noSections,
    required this.action,
  });
  final bool noPlayers, noSections;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) => EmptyState(
    key: const ValueKey('nothing-to-pair'),
    icon: noPlayers ? Icons.group_add_outlined : Icons.table_rows_outlined,
    title: noPlayers ? 'No players yet' : 'No section yet',
    body: noPlayers
        ? noSections
              ? 'Add players on the Players page, then create a section to pair them.'
              : 'Add players on the Players page to pair them here.'
        : 'Create a section to pair these players.',
    action: action == null
        ? null
        : OutlinedButton(
            key: ValueKey(
              noPlayers ? 'empty-add-players' : 'empty-new-section',
            ),
            onPressed: action,
            child: Text(noPlayers ? 'Add players' : 'New section'),
          ),
  );
}

/// A withdrawn player still sitting at a board that has not started:
/// said above the boards, with the way to pair those boards again.
class _WithdrawnNotice extends StatelessWidget {
  const _WithdrawnNotice({required this.gone, required this.onRepair});

  /// Each withdrawn player's name and board.
  final List<(String, int)> gone;

  /// Null while re-pairing is already open.
  final VoidCallback? onRepair;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('repair-notice'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(
            Icons.person_off_outlined,
            size: 18,
            color: colors.onSecondaryContainer,
          ),
          Text(
            gone.length == 1
                ? '${gone.single.$1} withdrew but is still on board ${gone.single.$2}.'
                : '${gone.length} withdrawn players are still on boards that have not started.',
            style: TextStyle(color: colors.onSecondaryContainer),
          ),
          OutlinedButton(
            key: const ValueKey('repair-notice-action'),
            onPressed: onRepair,
            child: const Text('Re-pair unstarted boards'),
          ),
        ],
      ),
    );
  }
}

/// Under the boards: whose result the focused box enters, and the keys.
/// A key that is not a result makes the legend say so.
class _Legend extends StatelessWidget {
  const _Legend({
    required this.line,
    required this.entered,
    required this.invalidKey,
    required this.forfeitRefused,
    required this.drawHint,
    required this.forfeitHint,
  });

  /// The focused box's board and whose result it enters.
  final String? line;

  /// The completion status, once every board was entered.
  final Widget? entered;
  final bool invalidKey, forfeitRefused, drawHint;

  /// The forfeit keys, when the focused board is an open forfeit.
  final String? forfeitHint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('result-legend'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The status line is always there, two lines tall, so the sheet
          // keeps its height as the cursor comes and goes and when the
          // last result is entered. A long context line wraps onto the
          // second line rather than losing whose result is being entered.
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.textScalerOf(context).scale(_statusLine),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              heightFactor: 1,
              child:
                  entered ??
                  (line == null
                      ? const SizedBox.shrink()
                      : Text(
                          line!,
                          key: const ValueKey('entry-context'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        )),
            ),
          ),
          Semantics(
            liveRegion: invalidKey,
            child: Text(
              invalidKey && forfeitRefused
                  ? 'A forfeit is only won or lost. 1 or 0 picks who won it · Delete clears it to enter a played game'
                  : invalidKey && drawHint
                  ? '$drawKeyHint · $resultKeyHint'
                  : invalidKey
                  ? 'Not a result key. $resultKeyHint · $moreResultKeys'
                  : forfeitHint != null
                  ? '$forfeitHint · $gridKeyHint'
                  : '$resultKeyHint · $gridKeyHint',
              key: const ValueKey('result-key-legend'),
              style: TextStyle(
                fontSize: 12,
                color: invalidKey ? colors.onSurface : colors.onSurfaceVariant,
                fontWeight: invalidKey ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while an earlier round is on screen, so nobody enters this
/// round's results there by mistake. Typing into a locked box says how.
class _PastStatus extends StatelessWidget {
  const _PastStatus({
    required this.correcting,
    required this.nudged,
    required this.what,
  });
  final bool correcting, nudged;

  /// What is read-only, in words.
  final String what;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = correcting ? colors.error : colors.onSurfaceVariant;
    return Row(
      key: const ValueKey('past-round-banner'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          correcting ? Icons.edit_outlined : Icons.lock_outline,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            correcting
                ? 'Correcting · review each change before saving'
                : nudged
                ? '$what · choose Correct a result to change it'
                : what,
            style: TextStyle(
              fontSize: 14,
              color: nudged && !correcting ? colors.onSurface : color,
              fontWeight: nudged && !correcting ? FontWeight.w600 : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// Editing pairings: how to swap two players, and the way out.
class _SwapBanner extends StatelessWidget {
  const _SwapBanner({required this.picked, required this.onDone});

  /// The name of the player picked first, if one is.
  final String? picked;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('swap-banner'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.swap_horiz, size: 18, color: colors.onSecondaryContainer),
          const SizedBox(width: 8),
          Text(
            picked == null
                ? 'Click two players to swap them. Two on one board swap colours.'
                : 'Swap $picked with… click another player, or click $picked again to cancel.',
            style: TextStyle(color: colors.onSecondaryContainer),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onDone, child: const Text('Done editing')),
        ],
      ),
    );
  }
}

/// A quad round that posting would refuse is not shown; say why.
class _ScheduleIssue extends StatelessWidget {
  const _ScheduleIssue({required this.sectionId, required this.text});
  final String sectionId, text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey(('quad-schedule-issue', sectionId)),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: colors.onErrorContainer)),
    );
  }
}

/// The ruled sheet the boards sit on, with a column header that stays put
/// while the boards scroll under it.
class _BoardFrame extends StatelessWidget {
  const _BoardFrame({required this.scroll, required this.items, this.footer});
  final ScrollController scroll;
  final List<WidgetBuilder> items;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // The sheet built in full, for the layouts that are not lazy.
    List<Widget> whole(BuildContext context) => [
      const _BoardColumns(),
      for (final item in items) item(context),
      ?footer,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep player names and inline actions readable at enlarged text sizes.
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final width = constraints.maxWidth.clamp(
          520 * scale,
          _widestPane * scale,
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLowest,
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: !constraints.hasBoundedHeight
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: whole(context),
                      )
                    : constraints.maxHeight <
                          MediaQuery.textScalerOf(context).scale(150)
                    ? SingleChildScrollView(
                        controller: scroll,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: whole(context),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _BoardColumns(),
                          // Lazy: a round of hundreds of boards builds only
                          // those on screen, so entering a result stays quick.
                          // Shrink-wrapped so a short round's sheet ends at
                          // its last board; it still lays out only what shows.
                          Flexible(
                            child: ListView.builder(
                              controller: scroll,
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: items.length,
                              itemBuilder: (context, i) => items[i](context),
                            ),
                          ),
                          ?footer,
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Before round 1: the board sheet with nothing filled in, one row per
/// board the section will need, so nothing moves when pairings arrive.
class _BlankSheet extends StatelessWidget {
  const _BlankSheet({
    required this.event,
    required this.sections,
    required this.everySection,
    required this.scroll,
  });
  final Event event;
  final List<Section> sections;
  final bool everySection;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: colors.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget box() => Container(
      width: _scoreWidth(context),
      height: 24,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
    );
    Widget row(String label, {bool bye = false}) => Container(
      constraints: const BoxConstraints(minHeight: _row),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _boardWidth(context),
            child: Text(label, style: muted),
          ),
          if (bye) SizedBox(width: _scoreWidth(context)) else box(),
          const Spacer(),
          if (!bye) box(),
        ],
      ),
    );
    final items = <Widget>[];
    for (final s in sections) {
      final entrants = s.players
          .where((id) => !event.player(id).withdrawn)
          .length;
      if (everySection) {
        items.add(
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.outlineVariant),
                bottom: BorderSide(color: colors.outlineVariant),
              ),
            ),
            child: Text(
              s.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }
      for (var board = 1; board <= entrants ~/ 2; board++) {
        items.add(row('$board'));
      }
      if (entrants.isOdd) items.add(row('Bye', bye: true));
    }
    return KeyedSubtree(
      key: const ValueKey('blank-board-sheet'),
      child: Semantics(
        label: 'Boards appear here when pairings are created.',
        child: _BoardFrame(
          scroll: scroll,
          items: [for (final item in items) (_) => item],
        ),
      ),
    );
  }
}

class _BoardColumns extends StatelessWidget {
  const _BoardColumns();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('board-column-header'),
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
        child: Row(
          children: [
            SizedBox(width: _boardWidth(context), child: const Text('Board')),
            SizedBox(
              width: _scoreWidth(context),
              child: Text('Score', textAlign: TextAlign.center),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('White')),
            SizedBox(width: 12),
            Expanded(child: Text('Black', textAlign: TextAlign.right)),
            SizedBox(width: 12),
            SizedBox(
              width: _scoreWidth(context),
              child: Text('Score', textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section name above its boards when every section is on screen.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.section,
    required this.round,
    required this.allRounds,
  });
  final Section section;
  final Round round;

  /// Every round of the section is on screen, so the heading names it.
  final bool allRounds;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('board-round-heading-${section.id}-${round.number}'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant),
          bottom: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Text(
        allRounds ? '${section.name} · Round ${round.number}' : section.name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ScoreGroup extends StatelessWidget {
  const _ScoreGroup({required this.points});
  final int points;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surfaceContainerLow.withValues(alpha: 0.5),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Text(
        pointsText(points),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A bye, listed after the boards.
class _ByeRow extends StatelessWidget {
  const _ByeRow({
    required this.bye,
    required this.player,
    required this.round,
    required this.every,
    required this.onShowPlayer,
  });
  final ByeAward bye;
  final Player player;
  final int round;

  /// Every round is on screen, so the keys name the round too.
  final bool every;
  final void Function(String id, {String? focus}) onShowPlayer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final p = player, b = bye;
    return Container(
      key: ValueKey(every ? 'bye-${p.id}-$round' : 'bye-${p.id}'),
      constraints: const BoxConstraints(minHeight: _row),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _boardWidth(context),
            child: Text(
              'Bye',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            width: _scoreWidth(context),
            child: Text(
              halves(b.points),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    // The grid is one Tab stop; names are not.
                    child: ExcludeFocusTraversal(
                      child: InkWell(
                        key: ValueKey(
                          every
                              ? 'bye-player-${p.id}-$round'
                              : 'bye-player-${p.id}',
                        ),
                        onTap: () => onShowPlayer(p.id),
                        child: Text(
                          p.name,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                  // The points are in the score column; a pairing bye needs
                  // no further words.
                  if (!b.allocated)
                    TextSpan(
                      text: '   ${b.reason.toLowerCase()}',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One board: its number, a score box either side, and the two players.
class _GameRow extends StatelessWidget {
  const _GameRow({
    required this.controller,
    required this.row,
    required this.before,
    required this.locked,
    required this.past,
    required this.swapping,
    required this.swapPick,
    required this.entryBox,
    required this.whiteBox,
    required this.blackBox,
    required this.onTap,
    required this.onShowPlayer,
    required this.onPickSwap,
    required this.onWithdraw,
  });
  final TournamentController controller;
  final BoardRow row;

  /// Each player's score before the round, when the boards are grouped.
  final Map<String, int>? before;

  /// Read-only: an earlier round, while not correcting.
  final bool locked;

  /// An earlier round, correcting or not.
  final bool past;
  final bool swapping;
  final String? swapPick;
  final String? entryBox;
  final Widget whiteBox, blackBox;
  final VoidCallback onTap;
  final void Function(String id, {String? focus}) onShowPlayer;
  final ValueChanged<String> onPickSwap;
  final ValueChanged<String> onWithdraw;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final e = c.event!, colors = Theme.of(context).colorScheme;
    final g = row.game;
    final white = e.player(g.white), black = e.player(g.black);
    Widget name(Player p, {required bool right}) {
      final score = before?[p.id];
      final label = Text.rich(
        TextSpan(
          children: [
            if (score != null && right)
              TextSpan(
                text: '(${halves(score)})  ',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            // A bughouse side is both partners: "Chen / Patel".
            TextSpan(
              text: switch (p.id == g.white ? g.whitePartner : g.blackPartner) {
                '' => p.name,
                final partner => '${p.name} / ${e.player(partner).name}',
              },
            ),
            if (score != null && !right)
              TextSpan(
                text: '  (${halves(score)})',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        style: const TextStyle(fontSize: 14),
        textAlign: right ? TextAlign.right : TextAlign.left,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
      if (swapping) {
        final picked = swapPick == p.id;
        return Semantics(
          selected: picked,
          button: true,
          child: InkWell(
            key: ValueKey('round-player-${g.id}-${p.id}'),
            onTap: () => onPickSwap(p.id),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: picked ? colors.primary.withValues(alpha: 0.12) : null,
                border: Border.all(
                  color: picked ? colors.primary : colors.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: label,
            ),
          ),
        );
      }
      void menu(Offset at) => showPlayerMenu(
        context,
        c,
        p.id,
        at,
        onByes: (id) => onShowPlayer(id, focus: 'byes'),
      );
      // The grid is one Tab stop, so names are not: Space on a score box
      // opens that player's details, Shift+F10 their menu.
      final playerLink = ExcludeFocusTraversal(
        child: Tooltip(
          message: '${p.name} · Double-click for player details',
          child: ContextMenuKeys(
            onMenu: menu,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): () =>
                    onShowPlayer(p.id),
                const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
                    onShowPlayer(p.id),
              },
              child: Semantics(
                button: true,
                hint: 'Opens player details',
                child: InkWell(
                  key: ValueKey('round-player-${g.id}-${p.id}'),
                  onSecondaryTapDown: (details) => menu(details.globalPosition),
                  onDoubleTap: () => onShowPlayer(p.id),
                  child: label,
                ),
              ),
            ),
          ),
        ),
      );
      final forfeited =
          g.outcome == Outcome.doubleForfeit ||
          (p.id == g.white && g.outcome == Outcome.blackForfeit) ||
          (p.id == g.black && g.outcome == Outcome.whiteForfeit);
      if (!forfeited || past) return playerLink;
      return Column(
        crossAxisAlignment: right
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          playerLink,
          if (p.withdrawn)
            Text(
              'Withdrawn',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            )
          else
            // Reached with Tab only from this board's score boxes.
            ExcludeFocusTraversal(
              excluding: !{
                boxKey(g.id, true),
                boxKey(g.id, false),
              }.contains(entryBox),
              child: TextButton(
                key: ValueKey('withdraw-${g.id}-${p.id}'),
                onPressed: () => onWithdraw(p.id),
                // The same words as the player menu and the player card.
                child: Text(statusLabel(e, StatusAction.withdraw, [p.id])),
              ),
            ),
        ],
      );
    }

    return GestureDetector(
      key: ValueKey('game-${g.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: _row),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Semantics(
          label:
              'Round ${row.round.number}, board ${g.board}, ${white.name} versus ${black.name}: ${g.outcome.label}${locked ? ', read-only' : ''}',
          child: Row(
            children: [
              SizedBox(
                width: _boardWidth(context),
                child: Text(
                  '${g.board}${row.section.doubleGames ? '·${g.leg}' : ''}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              whiteBox,
              const SizedBox(width: 12),
              Expanded(child: name(white, right: false)),
              const SizedBox(width: 12),
              Expanded(child: name(black, right: true)),
              const SizedBox(width: 12),
              blackBox,
            ],
          ),
        ),
      ),
    );
  }
}

/// One player's score box: the mark for their result, and the focus that
/// takes result keys.
class _ScoreBox extends StatelessWidget {
  const _ScoreBox({
    required this.controller,
    required this.row,
    required this.white,
    required this.node,
    required this.locked,
    required this.entry,
    required this.onKey,
    required this.onFocusChange,
    required this.onTap,
    required this.onShowPlayer,
  });
  final TournamentController controller;
  final BoardRow row;
  final bool white;
  final FocusNode node;
  final bool locked;

  /// The one box Tab enters the grid at.
  final bool entry;
  final KeyEventResult Function(KeyEvent event) onKey;
  final VoidCallback onFocusChange, onTap;
  final void Function(String id, {String? focus}) onShowPlayer;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = Theme.of(context).colorScheme, g = row.game;
    final lock = locked;
    node.skipTraversal = !entry;
    final owner = c.event!.player(white ? g.white : g.black);
    final assumed = !g.outcome.resolved && g.pairingAssumption != null;
    // Unfinished, disputed and assumed results each look different from an
    // empty box, so none of them reads as "not reported yet".
    final (mark, caption) = switch (g.outcome) {
      // A game still going may carry an assumption for pairing.
      Outcome.unfinished when assumed => (
        '(${scoreMark(g.pairingAssumption!, white: white)})',
        'playing',
      ),
      Outcome.unfinished => ('', 'playing'),
      Outcome.disputed => ('?', 'disputed'),
      _ when assumed => (
        '(${scoreMark(g.pairingAssumption!, white: white)})',
        'assumed',
      ),
      _ => (scoreMark(g.outcome, white: white), null),
    };
    final odd = g.outcome == Outcome.disputed;
    final spoken = switch (g.outcome) {
      Outcome.unreported when assumed =>
        'assumed ${mark.replaceAll(RegExp('[()]'), '')} for pairing only',
      Outcome.unreported => 'no result',
      Outcome.unfinished when assumed =>
        'still playing, assumed ${mark.replaceAll(RegExp('[()]'), '')} for pairing only',
      Outcome.unfinished => 'still playing',
      Outcome.disputed => 'disputed',
      Outcome.doubleForfeit => 'double forfeit',
      _ when !g.outcome.played => mark == 'X' ? 'won by forfeit' : 'forfeited',
      _ => mark,
    };
    return ContextMenuKeys(
      onMenu: (at) => showPlayerMenu(
        context,
        c,
        owner.id,
        at,
        onByes: (id) => onShowPlayer(id, focus: 'byes'),
      ),
      child: Focus(
        focusNode: node,
        onKeyEvent: (_, event) => onKey(event),
        onFocusChange: (has) => onFocusChange(),
        child: Semantics(
          label: '${owner.name}\'s score: $spoken${lock ? ', read-only' : ''}',
          child: Tooltip(
            message: assumed
                ? 'Assumed for pairing only: ${g.pairingReason}'
                : odd
                ? g.outcome.label
                : '',
            child: MouseRegion(
              cursor: lock ? SystemMouseCursors.basic : SystemMouseCursors.text,
              child: GestureDetector(
                key: ValueKey('score-${g.id}-${white ? 'w' : 'b'}'),
                onTap: onTap,
                child: Container(
                  width: _scoreWidth(context),
                  constraints: const BoxConstraints(minHeight: 24),
                  padding: EdgeInsets.symmetric(
                    vertical: caption == null ? 3 : 2,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: lock ? colors.surfaceContainerLow : colors.surface,
                    border: node.hasFocus
                        ? Border.all(color: colors.primary, width: 2)
                        : Border.all(color: colors.outline),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        mark,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1,
                          color: odd
                              ? colors.error
                              : assumed
                              ? colors.onSurfaceVariant
                              : colors.onSurface,
                        ),
                      ),
                      if (caption != null)
                        Text(
                          caption,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.1,
                            color: odd ? colors.error : colors.onSurfaceVariant,
                          ),
                        ),
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
}
