import 'package:flutter/material.dart';

import '../domain/eligibility.dart';
import '../domain/model.dart';
import '../domain/pairing.dart';
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
({PairingOffer offer, ({String? label, String? why, bool complete})? state})
pairingOffer(Event event, Event pairingEvent, Section? section) {
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
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.why != null)
              Flexible(
                child: Padding(
                  padding: EdgeInsets.only(right: label == null ? 0 : 12),
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
            if (label != null)
              Flexible(
                // Never squeezed out by the note beside it.
                flex: 2,
                child: FilledButton.icon(
                  key: const ValueKey('pair-next-round'),
                  onPressed: pairing ? null : onPair,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  iconAlignment: IconAlignment.end,
                  label: pairing
                      ? const Text(
                          'Creating pairings…',
                          overflow: TextOverflow.ellipsis,
                        )
                      : section == null
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
({String? label, String? why, bool complete}) postState(
  Event e,
  Section? section,
) {
  final scope = section == null
      ? e.sections.where((s) => !s.sideGames).toList()
      : [section];
  if (scope.isEmpty) {
    return (
      label: null,
      why: 'Choose New section to put players in a section first.',
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
    if (missing == 0) return (label: null, why: null, complete: true);
    return (
      label: null,
      why:
          'Final pairings created · $missing ${missing == 1 ? 'result' : 'results'} still to enter.',
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
  // K03: flagged before round 1, never a reason to hold pairings back.
  final outside = ready
      .where((s) => s.rounds.isEmpty)
      .fold(0, (n, s) => n + sectionRangeProblems(e, s).length);
  if (outside > 0) {
    why = [
      ?why,
      '$outside ${outside == 1 ? 'player is' : 'players are'} outside '
          'their section’s rating range.',
    ].join(' ');
  }
  final numbers = ready.map((s) => s.rounds.length + 1).toSet();
  if (section != null) {
    return (
      label: 'Create pairings · ${section.name} · Round ${numbers.single}',
      why: why,
      complete: false,
    );
  }
  final round = numbers.length == 1
      ? 'Create pairings · Round ${numbers.single}'
      : 'Create pairings';
  final label = ready.length > 1 || e.sections.length > 1
      ? '$round · ${ready.length} ${ready.length == 1 ? 'section' : 'sections'}'
      : round;
  return (label: label, why: why, complete: false);
}
