import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import 'dialogs.dart';
import 'panels.dart';
import 'player_format.dart';
import 'side_panel.dart';
import 'select.dart';

/// What a player's status button does. Before their section is paired a
/// player is removed from the event; once it is paired they withdraw.
/// Unpairing the section brings Remove back.
enum StatusAction { remove, withdraw, reinstate }

/// Shows a finished change with Undo, where the host has a place for it.
typedef ActionDone = void Function(String title, String message);

/// The status buttons for [ids], in the order they appear: one of Remove
/// or Withdraw, and Reinstate once every one of them is withdrawn.
List<StatusAction> statusActions(Event e, Iterable<String> ids) {
  final all = ids.toList();
  if (all.isEmpty) return const [];
  final withdrawn = all.every((id) => e.player(id).withdrawn);
  return [
    if (all.every((id) => removeBlocker(e, id) == null))
      StatusAction.remove
    else if (!withdrawn)
      StatusAction.withdraw,
    if (withdrawn) StatusAction.reinstate,
  ];
}

String statusLabel(Event e, StatusAction action, List<String> ids) {
  final one = ids.length == 1;
  return switch (action) {
    StatusAction.remove =>
      one ? 'Remove from event' : 'Remove ${ids.length} players',
    StatusAction.withdraw =>
      one
          ? ['Withdraw', ?withdrawAfter(e, ids.single)].join(' ')
          : 'Withdraw ${ids.length} players',
    StatusAction.reinstate =>
      one ? 'Reinstate' : 'Reinstate ${ids.length} players',
  };
}

/// Applies [action] to [ids] as one undoable change and says what happened.
({String title, String message}) applyStatus(
  TournamentController c,
  StatusAction action,
  List<String> ids,
) {
  final e = c.event!, one = ids.length == 1;
  final who = one ? e.player(ids.single).name : '${ids.length} players';
  final sections = {for (final id in ids) ?e.sectionOf(id)?.id};
  switch (action) {
    case StatusAction.remove:
      c.removePlayers(ids);
      return (
        title: one ? 'Player removed' : 'Players removed',
        message: [
          'Removed $who from the event.',
          ?rosterNote(c.event!, sections),
        ].join(' '),
      );
    case StatusAction.withdraw:
      c.setWithdrawn(ids, true);
      return (
        title: one ? 'Player withdrawn' : 'Players withdrawn',
        message: 'Withdrew $who.',
      );
    case StatusAction.reinstate:
      c.setWithdrawn(ids, false);
      return (
        title: one ? 'Player reinstated' : 'Players reinstated',
        message: 'Reinstated $who.',
      );
  }
}

/// Unpaired quads among [sectionIds] that no longer have four players, so
/// the TD reads it beside the change that caused it.
String? rosterNote(Event e, Set<String> sectionIds) {
  final notes = [
    for (final s in e.sections)
      if (sectionIds.contains(s.id) &&
          s.format == Format.quad &&
          s.rounds.isEmpty &&
          s.players.isNotEmpty &&
          s.players.length != 4)
        '${s.name} now has ${s.players.length} '
            '${s.players.length == 1 ? 'player' : 'players'}.',
  ];
  return notes.isEmpty ? null : [...notes, 'A quad needs four.'].join(' ');
}

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

/// A player's row menu. Right-clicking one of several ticked players acts
/// on all of them ([group]); otherwise it acts on [playerId] alone. The host
/// applies status changes through [onStatus] so it can confirm them; without
/// it they apply here, and the row itself shows the change.
Future<void> showPlayerMenu(
  BuildContext context,
  TournamentController c,
  String playerId,
  Offset position, {
  ValueChanged<String>? onByes,
  Set<String> group = const {},
  ValueChanged<String>? onMoveGroup,
  void Function(StatusAction action, List<String> ids)? onStatus,
}) async {
  final e = c.event!, p = e.player(playerId);
  final ids = group.length > 1 && group.contains(playerId)
      ? group.toList()
      : [playerId];
  final many = ids.length > 1;
  final byes =
      !many && onByes != null && !p.withdrawn && openRounds(e, p).isNotEmpty;
  final destinations = [
    for (final s in e.sections)
      if (!ids.every(s.players.contains)) s,
  ];
  final muted = TextStyle(
    fontSize: 13,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );
  final action = await contextMenu<Object>(context, position, [
    if (byes) const PopupMenuItem(value: 'byes', child: Text('Byes…')),
    if (!many)
      const PopupMenuItem(value: 'move', child: Text('Move…'))
    else if (onMoveGroup != null && destinations.isNotEmpty) ...[
      PopupMenuItem(
        enabled: false,
        height: 32,
        child: Text('Move ${ids.length} players to', style: muted),
      ),
      for (final s in destinations)
        PopupMenuItem(
          value: ('move-to', s.id),
          height: 36,
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(s.name),
          ),
        ),
      const PopupMenuDivider(),
    ],
    for (final a in statusActions(e, ids))
      PopupMenuItem(value: a, child: Text(statusLabel(e, a, ids))),
  ]);
  if (!context.mounted) return;
  switch (action) {
    case 'byes':
      onByes!(playerId);
    case 'move':
      showMovePlayer(context, c, playerId: playerId);
    case ('move-to', final String sectionId):
      onMoveGroup!(sectionId);
    case final StatusAction a:
      if (onStatus != null) {
        onStatus(a, ids);
        return;
      }
      try {
        applyStatus(c, a, ids);
      } catch (error) {
        showFailure(context, error);
      }
  }
}

void showMovePlayer(
  BuildContext context,
  TournamentController c, {
  String? playerId,
  String? sectionId,
}) {
  final dock = Dock.maybeOf(context);
  if (dock == null) return;
  dock.show(
    ('move-player', playerId, sectionId),
    MovePlayerPanel(
      key: UniqueKey(),
      controller: c,
      playerId: playerId,
      sectionId: sectionId,
      onClose: dock.close,
    ),
  );
}

class MovePlayerPanel extends StatefulWidget {
  const MovePlayerPanel({
    required this.controller,
    required this.onClose,
    this.playerId,
    this.sectionId,
    super.key,
  });
  final TournamentController controller;
  final String? playerId, sectionId;
  final VoidCallback onClose;
  @override
  State<MovePlayerPanel> createState() => _MovePlayerPanelState();
}

class _MovePlayerPanelState extends State<MovePlayerPanel> {
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
      swapWith != null
          ? c.swapPlayers(player!, swapWith!, revision)
          : c.movePlayers([player!], target!, reason: reason.text.trim());
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
    final move = player == null
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
      title: 'Move player',
      onClose: widget.onClose,
      children: [
        PlainSelect<String?>(
          key: ValueKey(('operation-player', player)),
          value: player,
          label: 'Player',
          options: [for (final p in players) SelectOption(p.id, p.name)],
          onChanged: (v) => setState(() {
            player = v;
            target = null;
            swapWith = null;
            error = null;
          }),
        ),
        const SizedBox(height: 12),
        ?move,
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
            onPressed: move?.ready ?? false ? apply : null,
            child: const Text('Move'),
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
  bool get swapping => from != null && to != null && swapAllowed(from!, to!);
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
        PlainSelect<String?>(
          key: ValueKey(('move-target', playerId, target)),
          value: target,
          label: 'Move to',
          options: [for (final s in destinations) SelectOption(s.id, s.name)],
          onChanged: onTarget,
        ),
        if (swapping) ...[
          const SizedBox(height: 12),
          PlainSelect<String?>(
            key: ValueKey(('move-swap', playerId, target, swapWith)),
            value: swapWith ?? (needed ? null : ''),
            label: 'Swap with',
            options: [
              if (!needed) const SelectOption('', 'No one'),
              for (final p in swapCandidates(event, to!))
                if (p.id != playerId)
                  SelectOption(p.id, '${p.name} · ${ratingText(p.rating)}'),
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
