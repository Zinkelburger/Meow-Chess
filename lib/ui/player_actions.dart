import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import 'panels.dart';
import 'player_format.dart';
import 'side_panel.dart';

enum PlayerOperation { move, withdraw }

/// A swap keeps a quad or round robin at full size. Between two Swiss
/// sections a move does the same job, so swaps are only offered when a
/// fixed-size section is involved and neither side has been paired.
bool swapAllowed(Section a, Section b) =>
    a.id != b.id &&
    a.rounds.isEmpty &&
    b.rounds.isEmpty &&
    (a.format != Format.swiss || b.format != Format.swiss);

/// Players in [s] who could exchange places with a mover.
List<Player> swapCandidates(Event e, Section s) => [
  for (final id in s.players)
    if (!e.player(id).withdrawn) e.player(id),
];

/// Whether a move from [from] to [to] must exchange places with someone,
/// so every quad keeps four players. Round robins may swap but need not.
bool swapNeeded(Event e, Section? from, Section to) {
  if (from == null || !swapAllowed(from, to)) return false;
  final others = swapCandidates(e, to).length;
  if (others == 0) return false;
  if (from.format == Format.quad) return true;
  return to.format == Format.quad && others >= 4;
}

/// Rounds of [p]'s section that are not yet paired, where a bye can still
/// be requested.
List<int> openRounds(Event e, Player p) {
  final s = e.sectionOf(p.id);
  final planned =
      s?.plannedRounds ??
      e.sections.fold<int>(
        0,
        (n, x) => x.plannedRounds > n ? x.plannedRounds : n,
      );
  return [for (var r = (s?.rounds.length ?? 0) + 1; r <= planned; r++) r];
}

/// Opens a row's context menu from the keyboard (Menu key or Shift+F10),
/// anchored under the row, so the menu is not mouse-only.
class ContextMenuKeys extends StatelessWidget {
  const ContextMenuKeys({required this.onMenu, required this.child, super.key});
  final ValueChanged<Offset> onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    void open() {
      final box = context.findRenderObject() as RenderBox?;
      onMenu(
        box == null
            ? Offset.zero
            : box.localToGlobal(Offset(24, box.size.height)),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.contextMenu): open,
        const SingleActivator(LogicalKeyboardKey.f10, shift: true): open,
      },
      child: child,
    );
  }
}

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
  Offset position, {
  ValueChanged<String>? onByes,
}) async {
  final e = c.event!, p = e.player(playerId);
  final byes = onByes != null && !p.withdrawn && openRounds(e, p).isNotEmpty;
  final action = await contextMenu<Object>(context, position, [
    if (byes) const PopupMenuItem(value: 'byes', child: Text('Byes…')),
    const PopupMenuItem(value: PlayerOperation.move, child: Text('Move…')),
    PopupMenuItem(
      value: PlayerOperation.withdraw,
      child: Text(p.withdrawn ? 'Reinstate player…' : 'Withdraw player…'),
    ),
  ]);
  if (!context.mounted) return;
  if (action == 'byes') {
    onByes!(playerId);
  } else if (action is PlayerOperation) {
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
  String? target, swapWith, error;
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
          swapWith = null;
          error = 'The event changed. Review the players and choose again.';
        });
        return;
      }
      switch (widget.operation) {
        case PlayerOperation.move:
          swapWith != null
              ? c.swapPlayers(player!, swapWith!, revision)
              : c.movePlayers([player!], target!, reason: reason.text.trim());
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
    final withdrawing = widget.operation == PlayerOperation.withdraw;
    final label = withdrawing
        ? player != null && e.player(player!).withdrawn
              ? 'Reinstate player'
              : 'Withdraw player'
        : 'Move player';
    final move = player == null || withdrawing
        ? null
        : MoveFields(
            event: e,
            playerId: player!,
            target: target,
            swapWith: swapWith,
            reason: reason,
            onTarget: (v) => setState(() {
              target = v;
              swapWith = null;
              error = null;
            }),
            onSwap: (v) => setState(() => swapWith = v),
            onSubmit: apply,
          );
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
            swapWith = null;
            error = null;
          }),
        ),
        const SizedBox(height: 12),
        if (move != null)
          move
        else if (withdrawing && player != null)
          Text(
            e.player(player!).withdrawn
                ? 'Return ${e.player(player!).name} to active play.'
                : 'Withdraw ${e.player(player!).name} ${withdrawAfter(e, player!) ?? 'from future pairings'}. Existing games are kept.',
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
            onPressed:
                player != null && (withdrawing || (move?.ready ?? false))
                ? apply
                : null,
            child: Text(withdrawing ? label : 'Move'),
          ),
        ),
      ],
    );
  }
}

/// Where a player moves, and in a quad who takes their place. One action,
/// Move, covers both: a quad always keeps four players, so a move in or out
/// of a full quad asks who exchanges places.
class MoveFields extends StatelessWidget {
  const MoveFields({
    required this.event,
    required this.playerId,
    required this.target,
    required this.swapWith,
    required this.reason,
    required this.onTarget,
    required this.onSwap,
    required this.onSubmit,
    super.key,
  });
  final Event event;
  final String playerId;
  final String? target, swapWith;
  final TextEditingController reason;
  final ValueChanged<String?> onTarget, onSwap;
  final VoidCallback onSubmit;

  Section? get from => event.sectionOf(playerId);
  Section? get to => event.sections.where((s) => s.id == target).firstOrNull;
  bool get swapping =>
      from != null && to != null && swapAllowed(from!, to!);
  bool get needed => to != null && swapNeeded(event, from, to!);
  bool get ready => to != null && (!needed || swapWith != null);
  bool get playStarted =>
      (from?.rounds.isNotEmpty ?? false) || (to?.rounds.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final destinations = [
      for (final s in event.sections)
        if (s.id != from?.id) s,
    ];
    if (destinations.isEmpty) {
      return const Text('Create another section to move this player.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(('move-target', playerId, target)),
          initialValue: target,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Move to'),
          items: [
            for (final s in destinations)
              DropdownMenuItem(
                value: s.id,
                child: Text(s.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onTarget,
        ),
        if (swapping) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(('move-swap', playerId, target, swapWith)),
            initialValue: swapWith ?? (needed ? null : ''),
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Swap with'),
            items: [
              if (!needed)
                const DropdownMenuItem(value: '', child: Text('No one')),
              for (final p in swapCandidates(event, to!))
                if (p.id != playerId)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(
                      '${p.name} · ${ratingText(p.rating)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            ],
            onChanged: (v) => onSwap(v == '' ? null : v),
          ),
        ],
        if (to != null && playStarted) ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('move-reason'),
            controller: reason,
            decoration: const InputDecoration(labelText: 'Reason'),
            onSubmitted: (_) => ready ? onSubmit() : null,
          ),
        ],
      ],
    );
  }
}

/// When a withdrawal takes effect, in words: after the latest paired
/// round, or null before play or once every round is paired.
String? withdrawAfter(Event e, String playerId) {
  final s = e.sectionOf(playerId);
  if (s == null || s.rounds.isEmpty || s.rounds.length >= s.plannedRounds) {
    return null;
  }
  return 'after round ${s.rounds.length}';
}
