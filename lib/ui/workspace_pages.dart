import 'package:flutter/material.dart';

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
    super.key,
  });
  final TaskView view;
  final ValueChanged<TaskView> onGo;

  /// Shown on Pairings only: [PostControl].
  final Widget action;

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
        // One control tall whether or not Create pairings is offered, so
        // changing section never shifts the page.
        final reserved = BoxConstraints(
          minHeight: MediaQuery.textScalerOf(context).scale(controlHeight),
        );
        if (layout.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
            1050) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pages,
              ConstrainedBox(
                constraints: view == TaskView.results
                    ? reserved
                    : const BoxConstraints(),
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

/// The post button, labelled with what it will post. When nothing can be
/// posted it says why beside it, and once every round is played it gives
/// way to the event-complete state.
class PostControl extends StatelessWidget {
  const PostControl({
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
    final e = event, section = this.section;
    final colors = Theme.of(context).colorScheme;
    if (section?.sideGames == true) {
      return Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          key: const ValueKey('pair-side-game'),
          onPressed: () => onPairSideGame(section!.id),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Pair a side game'),
        ),
      );
    }
    // Completion includes fixed quad schedules even though they need no post
    // button. A finished Swiss must not hide an unfinished quad in this event.
    final overall = postState(pairingEvent, null);
    if (!overall.complete && section != null && hasFixedQuadSchedule(section)) {
      return const SizedBox.shrink();
    }
    final needingPairings = e.sections
        .where((s) => !hasFixedQuadSchedule(s))
        .toList();
    if (!overall.complete && needingPairings.isEmpty) {
      return const SizedBox.shrink();
    }
    final state = overall.complete
        ? overall
        : postState(e.copy(sections: needingPairings), null);
    if (state.complete && !overall.complete) return const SizedBox.shrink();
    final muted = TextStyle(color: colors.onSurfaceVariant);
    if (state.complete) {
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
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.why != null &&
            (state.label != null ||
                e.sections.isEmpty ||
                e.sections.every((s) => s.players.isEmpty)))
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
        if (state.label != null)
          Flexible(
            child: FilledButton.icon(
              key: const ValueKey('pair-next-round'),
              onPressed: pairing || state.label == null ? null : onPair,
              icon: const Icon(Icons.arrow_forward, size: 18),
              iconAlignment: IconAlignment.end,
              label: Text(
                pairing ? 'Creating pairings…' : state.label!,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }
}

/// What the post button would do for [section] (null for every section):
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
  int waiting(Section s) => s.rounds
      .expand((r) => r.games)
      .where((g) => !g.outcome.resolved && g.pairingAssumption == null)
      .length;
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
  final numbers = ready.map((s) => s.rounds.length + 1).toSet();
  final round = numbers.length == 1
      ? 'Create pairings · Round ${numbers.single}'
      : 'Create pairings';
  final label = section == null && (ready.length > 1 || e.sections.length > 1)
      ? '$round · ${ready.length} ${ready.length == 1 ? 'section' : 'sections'}'
      : round;
  return (label: label, why: why, complete: false);
}
