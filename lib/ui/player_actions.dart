import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import 'panels.dart';
import 'side_panel.dart';

enum PlayerOperation { move, swap, withdraw }

/// Context menus appear and disappear immediately, at the pointer.
Future<T?> contextMenu<T>(
  BuildContext context,
  Offset position,
  List<PopupMenuEntry<T>> items,
) {
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromSize(
      overlay.globalToLocal(position) & Size.zero,
      overlay.size,
    ),
    popUpAnimationStyle: AnimationStyle.noAnimation,
    items: items,
  );
}

Future<void> showPlayerMenu(
  BuildContext context,
  TournamentController c,
  String playerId,
  Offset position,
) async {
  final p = c.event!.player(playerId);
  final action = await contextMenu<PlayerOperation>(context, position, [
    const PopupMenuItem(
      value: PlayerOperation.move,
      child: Text('Move to section…'),
    ),
    const PopupMenuItem(
      value: PlayerOperation.swap,
      child: Text('Swap with player…'),
    ),
    PopupMenuItem(
      value: PlayerOperation.withdraw,
      child: Text(p.withdrawn ? 'Reinstate player…' : 'Withdraw player…'),
    ),
  ]);
  if (action != null && context.mounted) {
    showPlayerOperation(context, c, action, playerId: playerId);
  }
}

void showPlayerOperation(
  BuildContext context,
  TournamentController c,
  PlayerOperation operation, {
  String? playerId,
  String? sectionId,
}) {
  final dock = Dock.maybeOf(context);
  if (dock == null) return;
  dock.show(
    ('player-operation', operation, playerId, sectionId),
    PlayerOperationPanel(
      key: UniqueKey(),
      controller: c,
      operation: operation,
      playerId: playerId,
      sectionId: sectionId,
      onClose: dock.close,
    ),
  );
}

class PlayerOperationPanel extends StatefulWidget {
  const PlayerOperationPanel({
    required this.controller,
    required this.operation,
    required this.onClose,
    this.playerId,
    this.sectionId,
    super.key,
  });
  final TournamentController controller;
  final PlayerOperation operation;
  final String? playerId, sectionId;
  final VoidCallback onClose;
  @override
  State<PlayerOperationPanel> createState() => _PlayerOperationPanelState();
}

class _PlayerOperationPanelState extends State<PlayerOperationPanel> {
  late String? player = widget.playerId;
  String? target, error;
  late int revision = widget.controller.event!.revision;
  final reason = TextEditingController();

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  void apply() {
    final c = widget.controller;
    try {
      if (revision != c.event!.revision) {
        setState(() {
          revision = c.event!.revision;
          target = null;
          error = 'The event changed. Review the players and choose again.';
        });
        return;
      }
      switch (widget.operation) {
        case PlayerOperation.move:
          c.movePlayers([player!], target!, reason: reason.text.trim());
        case PlayerOperation.swap:
          c.swapPlayers(player!, target!, revision);
        case PlayerOperation.withdraw:
          final p = c.event!.player(player!);
          c.savePlayer(p.copy(withdrawn: !p.withdrawn));
      }
      widget.onClose();
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.controller.event!;
    final players = e.players
        .where(
          (p) =>
              widget.sectionId == null ||
              e.sectionOf(p.id)?.id == widget.sectionId,
        )
        .toList();
    if (!players.any((p) => p.id == player)) player = null;
    final source = player == null ? null : e.sectionOf(player!);
    final withdrawing = widget.operation == PlayerOperation.withdraw;
    final label = switch (widget.operation) {
      PlayerOperation.move => 'Move player',
      PlayerOperation.swap => 'Swap players',
      PlayerOperation.withdraw =>
        player != null && e.player(player!).withdrawn
            ? 'Reinstate player'
            : 'Withdraw player',
    };
    final targets = widget.operation == PlayerOperation.move
        ? {
            for (final s in e.sections)
              if (s.id != source?.id) s.id: s.name,
          }
        : {
            for (final p in e.players)
              if (source != null &&
                  source.rounds.isEmpty &&
                  !p.withdrawn &&
                  e.sectionOf(p.id) != null &&
                  e.sectionOf(p.id)!.id != source.id &&
                  e.sectionOf(p.id)!.rounds.isEmpty)
                p.id: '${p.name} · ${e.sectionOf(p.id)!.name}',
          };
    if (!targets.containsKey(target)) target = null;
    return SidePanel(
      title: label,
      onClose: widget.onClose,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(('operation-player', player)),
          initialValue: player,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Player'),
          items: [
            for (final p in players)
              DropdownMenuItem(
                value: p.id,
                child: Text(p.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() {
            player = v;
            target = null;
            error = null;
          }),
        ),
        const SizedBox(height: 16),
        if (!withdrawing) ...[
          DropdownButtonFormField<String>(
            key: ValueKey(('operation-target', player, target)),
            initialValue: target,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: widget.operation == PlayerOperation.move
                  ? 'Destination section'
                  : 'Swap with',
            ),
            items: [
              for (final entry in targets.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: player == null
                ? null
                : (v) => setState(() {
                    target = v;
                    error = null;
                  }),
          ),
          const SizedBox(height: 12),
          if (player != null && targets.isEmpty)
            Text(
              widget.operation == PlayerOperation.swap
                  ? 'Swaps require players in two sections without pairings.'
                  : 'Create another section before moving this player.',
            ),
          if (widget.operation == PlayerOperation.move &&
              target != null &&
              (source?.rounds.isNotEmpty == true ||
                  e.sections
                      .firstWhere((s) => s.id == target)
                      .rounds
                      .isNotEmpty))
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason for move'),
            ),
          if (target != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                widget.operation == PlayerOperation.swap
                    ? '${e.player(player!).name} and ${e.player(target!).name} will exchange sections.'
                    : '${e.player(player!).name} will move to ${targets[target]}.',
              ),
            ),
        ] else if (player != null)
          Text(
            e.player(player!).withdrawn
                ? 'Return ${e.player(player!).name} to active play.'
                : 'Withdraw ${e.player(player!).name} from future pairings. Existing games are kept.',
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const ValueKey('apply-player-operation'),
            onPressed: player != null && (withdrawing || target != null)
                ? apply
                : null,
            child: Text(label),
          ),
        ),
      ],
    );
  }
}
