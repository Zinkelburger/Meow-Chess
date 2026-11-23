import 'package:flutter/material.dart';

import '../domain/eligibility.dart';
import '../domain/model.dart';
import '../domain/pairing.dart';
import 'membership_style.dart' show attentionColor;
import 'theme.dart' show controlHeight;

enum TaskView { players, results, reports }

/// The page buttons (Players, Pairings, Export) with the page's main
/// action at the right. Narrow windows put the action under the pages.
class WorkspacePageRow extends StatelessWidget {
  const WorkspacePageRow({
    required this.view,
    required this.onGo,
    required this.action,
    this.reserveAction = true,
    super.key,
  });
  final TaskView view;
  final ValueChanged<TaskView> onGo;

  /// Shown on Pairings only: [PairingControl].
  final Widget action;

  /// Whether some section of the event has something to show in [action]:
  /// its line is then kept on Pairings whichever section is chosen, so
  /// changing section never shifts the page. With nothing to show anywhere
  /// a narrow window keeps no empty line for it.
  final bool reserveAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: LayoutBuilder(
      builder: (context, layout) {
        final colors = Theme.of(context).colorScheme;
        final pages = Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final (task, label) in [
              (TaskView.players, 'Players'),
              (TaskView.results, 'Pairings'),
              (TaskView.reports, 'Export'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: TextButton(
                  onPressed: () => onGo(task),
                  style: TextButton.styleFrom(
                    backgroundColor: view == task ? colors.onSurface : null,
                    foregroundColor: view == task
                        ? colors.surface
                        : colors.onSurface,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(label),
                ),
              ),
          ],
        );
        final shown = view != TaskView.results
            ? const SizedBox.shrink()
            : action;
        // One control tall whether or not Create pairings is offered for
        // the section chosen, so changing section never shifts the page.
        final reserved = BoxConstraints(
          minHeight: MediaQuery.textScalerOf(context).scale(controlHeight),
        );
        if (layout.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
            1050) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pages,
              if (view == TaskView.results && reserveAction)
                ConstrainedBox(
                  key: const ValueKey('page-action-line'),
                  constraints: reserved,
                  child: Align(alignment: Alignment.centerRight, child: shown),
                ),
            ],
          );
        }
        return ConstrainedBox(
          constraints: reserved,
          child: Row(
            children: [
              pages,
              const SizedBox(width: 24),
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: shown),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// What Create pairings would do: its [label], [why] it is held back,
/// whether every round has been played ([complete]), and whether a section
/// in scope still needs its rounds set ([setUp]). [caution] is said with a
/// warning mark beside the button, never instead of it: a section about to
/// be paired for round 1 with too few players ([tooFewPlayers]).
typedef PostState = ({
  String? label,
  String? why,
  bool complete,
  bool setUp,
  String? caution,
});

/// What [PairingControl] shows for one choice of section.
enum PairingOffer {
  /// Nothing: a fixed quad schedule, a ladder, or All sections with nothing
  /// to pair and nothing to explain.
  none,

  /// "Pair a side game" for a side-games section.
  sideGame,

  /// Every round of the event is played: "Finish & export".
  eventComplete,

  /// The chosen section has played all its rounds; others have not.
  sectionComplete,

  /// The Create pairings button, why it is held back, or both.
  pairings,
}

/// What the Pairings page offers for [section] (null for every section), and
/// the [postState] behind a [PairingOffer.pairings] or
/// [PairingOffer.sectionComplete] answer. [pairingEvent] is [event] as the
/// pairer sees it, with any temporary pairing assumptions applied.
({PairingOffer offer, PostState? state}) pairingOffer(
  Event event,
  Event pairingEvent,
  Section? section,
) {
  if (section?.sideGames == true) {
    return (offer: PairingOffer.sideGame, state: null);
  }
  // Completion includes fixed quad schedules even though they need no
  // button. A finished Swiss must not hide an unfinished quad in this event.
  final overall = postState(pairingEvent, null);
  if (overall.complete) return (offer: PairingOffer.eventComplete, state: null);
  if (section != null) {
    if (hasFixedQuadSchedule(section) || section.format == Format.ladder) {
      return (offer: PairingOffer.none, state: null);
    }
    final state = postState(event, section);
    return (
      offer: state.complete
          ? PairingOffer.sectionComplete
          : state.label == null && state.why == null
          ? PairingOffer.none
          : PairingOffer.pairings,
      state: state,
    );
  }
  final needingPairings = event.sections
      .where((s) => !hasFixedQuadSchedule(s))
      .toList();
  if (needingPairings.isEmpty) return (offer: PairingOffer.none, state: null);
  final state = postState(event.copy(sections: needingPairings), null);
  // With every section chosen, why nothing can be paired is said only while
  // no section has players; after that each section's page says it.
  final explained =
      state.why != null &&
      (state.label != null ||
          state.setUp ||
          event.sections.isEmpty ||
          event.sections.every((s) => s.players.isEmpty));
  if (state.complete || (state.label == null && !explained)) {
    return (offer: PairingOffer.none, state: null);
  }
  return (
    offer: PairingOffer.pairings,
    state: (
      label: state.label,
      why: explained ? state.why : null,
      complete: false,
      setUp: state.setUp,
      caution: state.caution,
    ),
  );
}

/// Whether All sections or any one section has something to show in
/// [PairingControl]: the Pairings page keeps a line for it then.
bool offersPairingControl(Event event, Event pairingEvent) => [
  null,
  ...event.sections,
].any((s) => pairingOffer(event, pairingEvent, s).offer != PairingOffer.none);

/// The Create pairings button, labelled with what it will pair: the chosen
/// section's next round, or every ready section's with All sections chosen.
/// When nothing can be paired it says why, and once every round is played
/// it gives way to the event-complete state.
class PairingControl extends StatelessWidget {
  const PairingControl({
    required this.event,
    required this.pairingEvent,
    required this.section,
    required this.pairing,
    required this.onPair,
    required this.onPairSideGame,
    required this.onFinish,
    required this.onSetUp,
    super.key,
  });

  /// The event as shown, and as the pairer sees it (with any temporary
  /// pairing assumptions applied).
  final Event event, pairingEvent;

  /// The section shown, or null for every section.
  final Section? section;

  /// Whether pairings are being created now.
  final bool pairing;
  final VoidCallback onPair, onFinish;

  /// Opens Set up, where a section's rounds are set.
  final VoidCallback onSetUp;
  final ValueChanged<String> onPairSideGame;

  @override
  Widget build(BuildContext context) {
    final section = this.section;
    final colors = Theme.of(context).colorScheme;
    final (:offer, :state) = pairingOffer(event, pairingEvent, section);
    final muted = TextStyle(color: colors.onSurfaceVariant);
    switch (offer) {
      case PairingOffer.none:
        return const SizedBox.shrink();
      case PairingOffer.sideGame:
        return Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const ValueKey('pair-side-game'),
            onPressed: () => onPairSideGame(section!.id),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Pair a side game'),
          ),
        );
      case PairingOffer.eventComplete:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 18, color: colors.onSurface),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                key: const ValueKey('event-complete'),
                'All rounds played',
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 16),
            OutlinedButton(
              onPressed: onFinish,
              child: const Text('Finish & export'),
            ),
          ],
        );
      case PairingOffer.sectionComplete:
        return Text(
          '${section!.name} has played all its rounds',
          key: const ValueKey('section-complete'),
          style: muted,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
          textAlign: TextAlign.right,
        );
      case PairingOffer.pairings:
        final label = state!.label;
        // The caution leads: it is the one to read before pressing.
        final caution = state.caution;
        final note = [?caution, ?state.why].join(' ');
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (note.isNotEmpty)
              Flexible(
                child: Padding(
                  padding: EdgeInsets.only(right: label == null ? 0 : 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (caution != null) ...[
                        Icon(
                          Icons.warning_amber_rounded,
                          key: const ValueKey('post-caution'),
                          size: 18,
                          color: attentionColor(colors),
                          semanticLabel: 'Caution',
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        // Two lines may not hold it all; hovering does.
                        child: Tooltip(
                          message: caution == null ? '' : note,
                          child: Text(
                            note,
                            key: const ValueKey('post-blocked'),
                            style: caution == null
                                ? muted
                                : TextStyle(color: colors.onSurface),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                            // Beside its mark, the words start at it.
                            textAlign: caution == null
                                ? TextAlign.right
                                : TextAlign.left,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Setting the rounds is the next step while nothing can be
            // paired without it; beside Create pairings it is the quieter
            // of the two.
            if (state.setUp)
              Padding(
                padding: EdgeInsets.only(
                  left: note.isEmpty || label != null ? 0 : 12,
                  right: label == null ? 0 : 8,
                ),
                child: label == null
                    ? FilledButton(
                        key: const ValueKey('pair-set-up'),
                        onPressed: onSetUp,
                        child: const Text('Set up sections'),
                      )
                    : OutlinedButton(
                        key: const ValueKey('pair-set-up'),
                        onPressed: onSetUp,
                        child: const Text('Set up sections'),
                      ),
              ),
            if (label != null)
              Flexible(
                // Never squeezed out by the note beside it.
                flex: 2,
                // While pairing, the label stays and an hourglass takes the
                // arrow's place: the button keeps its size, so nothing in
                // the row moves.
                child: FilledButton.icon(
                  key: const ValueKey('pair-next-round'),
                  onPressed: pairing ? null : onPair,
                  icon: pairing
                      ? const Icon(
                          Icons.hourglass_top,
                          key: ValueKey('pairing-progress'),
                          size: 18,
                          semanticLabel: 'Creating pairings',
                        )
                      : const Icon(Icons.arrow_forward, size: 18),
                  iconAlignment: IconAlignment.end,
                  label: section == null
                      ? Text(label, overflow: TextOverflow.ellipsis)
                      : _sectionLabel(label, section),
                ),
              ),
          ],
        );
    }
  }

  /// "Create pairings · Open · Round 2" with a long section name cut short
  /// in the middle of the label, so the round is always in view.
  Widget _sectionLabel(String label, Section section) => LayoutBuilder(
    builder: (context, box) {
      const start = 'Create pairings · ';
      final end = ' · Round ${section.rounds.length + 1}';
      final style = DefaultTextStyle.of(context).style;
      double width(String text) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      // Too narrow even for the words around the name: one line, cut at
      // the end like any other label.
      if (box.maxWidth < width('$start…$end')) {
        return Text(label, softWrap: false, overflow: TextOverflow.ellipsis);
      }
      return Semantics(
        label: label,
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(start, softWrap: false),
            Flexible(
              child: Text(
                section.name,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(end, softWrap: false),
          ],
        ),
      );
    },
  );
}

/// What Create pairings would do for [section] (null for every section):
/// its label, why it is held back, or that every round has been played.
PostState postState(Event e, Section? section) {
  final scope = section == null
      ? e.sections.where((s) => !s.sideGames).toList()
      : [section];
  if (scope.isEmpty) {
    return (
      label: null,
      why: 'Choose New section to put players in a section first.',
      complete: false,
      setUp: false,
      caution: null,
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
      setUp: false,
      caution: null,
    );
  }
  // A section a registration list named waits for its rounds to be set.
  final unset = active.where((s) => s.roundsUnset).toList();
  final setUp = unset.isNotEmpty;
  final unsetWhy = unset.isEmpty
      ? null
      : unset.length == 1
      ? '${unset.single.name} has no rounds set.'
      : '${unset.length} sections have no rounds set.';
  final open = active
      .where((s) => !s.roundsUnset && s.rounds.length < s.plannedRounds)
      .toList();
  if (open.isEmpty && setUp) {
    return (
      label: null,
      why: unsetWhy,
      complete: false,
      setUp: true,
      caution: null,
    );
  }
  int waiting(Section s) => [
    for (final r in s.rounds)
      for (final g in r.games)
        if (!g.outcome.resolved && !pairsWithoutResult(s, r.number, g)) g,
  ].length;
  if (open.isEmpty) {
    final missing = active
        .expand((s) => s.rounds)
        .expand((r) => r.games)
        .where((g) => !g.outcome.resolved)
        .length;
    if (missing == 0) {
      return (
        label: null,
        why: null,
        complete: true,
        setUp: false,
        caution: null,
      );
    }
    return (
      label: null,
      why:
          'Final pairings created · $missing ${missing == 1 ? 'result' : 'results'} still to enter.',
      complete: false,
      setUp: false,
      caution: null,
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
  if (unsetWhy != null) why = [?why, unsetWhy].join(' ');
  if (ready.isEmpty) {
    return (
      label: null,
      why: why,
      complete: false,
      setUp: setUp,
      caution: null,
    );
  }
  // K03: flagged before round 1, never a reason to hold pairings back.
  final outside = ready
      .where((s) => s.rounds.isEmpty)
      .fold(0, (n, s) => n + sectionRangeProblems(e, s).length);
  if (outside > 0) {
    why = [
      ?why,
      '$outside ${outside == 1 ? 'player is' : 'players are'} rated '
          'outside what their section takes.',
    ].join(' ');
  }
  // Likewise said before round 1 and never a reason to hold back: a
  // section with too few players, which Combine or fewer rounds answers.
  final few = [
    for (final s in ready)
      if (s.rounds.isEmpty) ?tooFewPlayers(e, s),
  ];
  final caution = few.isEmpty
      ? null
      : few.length == 1
      ? few.single
      : '${few.length} sections have too few players.';
  final numbers = ready.map((s) => s.rounds.length + 1).toSet();
  if (section != null) {
    return (
      label: 'Create pairings · ${section.name} · Round ${numbers.single}',
      why: why,
      complete: false,
      setUp: setUp,
      caution: caution,
    );
  }
  final round = numbers.length == 1
      ? 'Create pairings · Round ${numbers.single}'
      : 'Create pairings';
  final label = ready.length > 1 || e.sections.length > 1
      ? '$round · ${ready.length} ${ready.length == 1 ? 'section' : 'sections'}'
      : round;
  return (
    label: label,
    why: why,
    complete: false,
    setUp: setUp,
    caution: caution,
  );
}
