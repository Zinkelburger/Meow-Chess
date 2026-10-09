import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/us_chess.dart';
import 'side_panel.dart';
import 'select.dart';

/// Side games use explicit opponents, independent of main-section pairings.
class SideGamePanel extends StatefulWidget {
  const SideGamePanel({
    required this.controller,
    required this.onClose,
    required this.onPaired,
    this.sectionId,
    super.key,
  });
  final TournamentController controller;
  final String? sectionId;
  final VoidCallback onClose;
  final ValueChanged<String> onPaired;
  @override
  State<SideGamePanel> createState() => _SideGamePanelState();
}

class _SideGamePanelState extends State<SideGamePanel> {
  String? white, black, error;
  late String? section = widget.sectionId;

  void pair() {
    try {
      if (white == null || black == null) {
        setState(() => error = 'Choose both players.');
        return;
      }
      final id = widget.controller.addSideGame(
        white!,
        black!,
        sectionId: section,
      );
      widget.onPaired(id);
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.controller.event!;
    final people = {for (final p in e.players) p.personId ?? p.id: p};
    final players = people.values.toList()
      ..sort((a, b) => compareNames(a.name, b.name));
    Widget choose(String label, String? value, ValueChanged<String?> change) =>
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: PlainSelect<String?>(
            key: ValueKey('side-game-${label.toLowerCase()}'),
            value: value,
            label: label,
            options: [for (final p in players) SelectOption(p.id, p.name)],
            onChanged: change,
          ),
        );
    return SidePanel(
      title: 'Pair a side game',
      onClose: widget.onClose,
      children: [
        const Text(
          'Choose any two registered players. Each gets a separate entry and score in Side Games. Record a main-game forfeit or result first if either player is still playing there.',
        ),
        choose('White', white, (v) => setState(() => white = v)),
        choose('Black', black, (v) => setState(() => black = v)),
        if (e.sections.where((s) => s.sideGames).length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: PlainSelect<String?>(
              label: 'Side-games section',
              value: section,
              options: [
                for (final s in e.sections.where((s) => s.sideGames))
                  SelectOption(s.id, s.name),
              ],
              onChanged: (v) => setState(() => section = v),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const ValueKey('post-side-game'),
            onPressed: pair,
            child: const Text('Post side game'),
          ),
        ),
      ],
    );
  }
}
