import 'package:flutter/material.dart';

import '../../application/tournament_controller_core.dart';
import '../../domain/holland.dart';
import '../../domain/model.dart';
import '../dialogs.dart' show showFailure;

/// Rule 30H: the one next step for a Holland preliminary, shown with the
/// section's heading actions. The button creates the final from every
/// prelim of the group once they have all finished; until then the muted
/// line says how many are done. No dialog: the final appears as a section
/// and the action is undoable like any other.
class HollandFinalsAction extends StatelessWidget {
  const HollandFinalsAction(this.controller, this.section, {super.key});
  final TournamentControllerCore controller;
  final Section section;

  @override
  Widget build(BuildContext context) {
    final event = controller.event;
    if (event == null || !isHollandPrelim(section)) {
      return const SizedBox.shrink();
    }
    final group = hollandGroup(section);
    final (:finished, :total) = hollandProgress(event, group);
    final existing = hollandFinalOf(event, group);
    final problem = hollandFinalProblem(event, group);
    final status = existing != null
        ? '${existing.name} created'
        : '$finished of $total prelims finished';
    final muted = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton(
          key: const ValueKey('holland-final'),
          onPressed: problem == null
              ? () {
                  try {
                    controller.makeHollandFinal(group);
                  } catch (error) {
                    showFailure(context, error);
                  }
                }
              : null,
          child: Text('Create the final from $total prelims'),
        ),
        Text(key: const ValueKey('holland-status'), status, style: muted),
      ],
    );
  }
}
