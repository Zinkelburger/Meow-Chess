import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import 'dialogs.dart';
import 'theme.dart';

class BoardRow {
  const BoardRow(this.section, this.round, this.game);
  final Section section;
  final Round round;
  final Game game;
}

class ResultsView extends StatefulWidget {
  const ResultsView({required this.controller, this.sectionId, super.key});
  final TournamentController controller;
  final String? sectionId;
  @override
  State<ResultsView> createState() => _ResultsViewState();
}

class _ResultsViewState extends State<ResultsView> {
  final focus = FocusNode(debugLabel: 'Results commands');
  final scroll = ScrollController();
  final jump = TextEditingController();
  String? active;
  bool missingOnly = false, forfeit = false, correcting = false, busy = false;
  int? selectedRound;
  String roundSignature = '';
  String get preference => 'results-${widget.sectionId ?? 'all'}';
  @override
  void initState() {
    super.initState();
    roundSignature = signature();
    final saved = widget.controller.repository.readPreference(preference);
    if (saved != null) {
      try {
        final j = jsonDecode(saved);
        active = j['active'];
        missingOnly = j['missingOnly'];
        selectedRound = j['round'];
      } catch (_) {}
    }
  }

  String signature() => widget.controller.event!.sections
      .where((s) => widget.sectionId == null || s.id == widget.sectionId)
      .map((s) => '${s.id}:${s.rounds.length}')
      .join('|');

  @override
  void didUpdateWidget(covariant ResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = signature();
    if (roundSignature.isNotEmpty &&
        next != roundSignature &&
        selectedRound == null) {
      active = null;
      correcting = false;
      forfeit = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (scroll.hasClients) scroll.jumpTo(0);
        remember();
      });
    }
    roundSignature = next;
  }

  @override
  void dispose() {
    focus.dispose();
    scroll.dispose();
    jump.dispose();
    super.dispose();
  }

  List<BoardRow> rows() {
    final result = <BoardRow>[];
    for (final s in widget.controller.event!.sections.where(
      (s) => widget.sectionId == null || s.id == widget.sectionId,
    )) {
      final r = selectedRound == null
          ? s.rounds.lastOrNull
          : s.rounds.where((r) => r.number == selectedRound).firstOrNull;
      if (r != null) {
        for (final g in r.games) {
          result.add(BoardRow(s, r, g));
        }
      }
    }
    result.sort((a, b) {
      final board = a.game.board.compareTo(b.game.board);
      return board != 0 ? board : a.game.leg.compareTo(b.game.leg);
    });
    return result;
  }

  void remember() {
    widget.controller.repository.writePreference(
      preference,
      jsonEncode({
        'active': active,
        'missingOnly': missingOnly,
        'round': selectedRound,
      }),
    );
  }

  void select(String id, {bool edit = false}) {
    setState(() {
      active = id;
      forfeit = false;
      correcting = edit;
    });
    focus.requestFocus();
    try {
      remember();
    } catch (e) {
      showFailure(context, e);
    }
  }

  void advance(
    List<BoardRow> before, {
    bool backwards = false,
    bool includeComplete = false,
  }) {
    final index = before.indexWhere((r) => r.game.id == active);
    final candidates = backwards
        ? before.take(index < 0 ? before.length : index).toList().reversed
        : before.skip(index + 1);
    final next = candidates
        .where((r) => includeComplete || !r.game.outcome.resolved)
        .firstOrNull;
    setState(() {
      active = next?.game.id;
      correcting = false;
      forfeit = false;
    });
    remember();
    if (next != null && scroll.hasClients) {
      final visible = before
          .where((r) => !missingOnly || !r.game.outcome.resolved)
          .toList();
      final i = visible.indexWhere((r) => r.game.id == next.game.id);
      if (i >= 0) {
        scroll.animateTo(
          (i * 68.0).clamp(0, scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    }
  }

  Future<void> enter(Outcome outcome) async {
    if (busy) return;
    final before = rows();
    final row = before.where((r) => r.game.id == active).firstOrNull;
    if (row == null) return;
    if (row.game.outcome.resolved && !correcting) {
      showFailure(
        context,
        'Press F2 or double-click to correct this saved result.',
      );
      return;
    }
    busy = true;
    try {
      var reason = '';
      if (widget.controller.correctionHasDependencies(row.game.id)) {
        final values = await editFields(
          context,
          title: 'Correct round ${row.round.number}',
          description:
              'Later posted pairings and played games will be retained. Standings and new reports will recalculate; review any previously issued report.',
          fields: const [
            FieldSpec('reason', 'Correction reason', required: true),
          ],
        );
        if (values == null) return;
        reason = values['reason']!;
      }
      widget.controller.recordResult(row.game.id, outcome, reason: reason);
      if (!mounted) return;
      advance(before);
      if (outcome == Outcome.whiteForfeit || outcome == Outcome.blackForfeit) {
        final absent = outcome == Outcome.whiteForfeit
            ? row.game.black
            : row.game.white;
        final p = widget.controller.event!.player(absent);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${p.name}: withdraw from future rounds?'),
            action: SnackBarAction(
              label: 'Withdraw',
              onPressed: () {
                try {
                  widget.controller.savePlayer(
                    widget.controller.event!
                        .player(absent)
                        .copy(withdrawn: true),
                  );
                } catch (e) {
                  if (mounted) showFailure(context, e);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      busy = false;
      if (mounted) focus.requestFocus();
    }
  }

  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (busy) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() => forfeit = false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2) {
      setState(() => correcting = true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      advance(
        rows(),
        backwards:
            key == LogicalKeyboardKey.arrowUp ||
            HardwareKeyboard.instance.isShiftPressed,
        includeComplete:
            key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      setState(() => forfeit = true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      setState(() => correcting = true);
      enter(Outcome.unreported);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      menu();
      return KeyEventResult.handled;
    }
    final win = [
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.numpad1,
    ].contains(key);
    final loss = [
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.numpad0,
    ].contains(key);
    final draw = [
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.equal,
    ].contains(key);
    if (win || loss || draw || key == LogicalKeyboardKey.keyX) {
      if (forfeit && draw) {
        showFailure(
          context,
          'Forfeit: use 1 for a White win or 0 for a White loss. Escape cancels.',
        );
        return KeyEventResult.handled;
      }
      enter(
        win
            ? (forfeit ? Outcome.whiteForfeit : Outcome.whiteWin)
            : loss
            ? (forfeit ? Outcome.blackForfeit : Outcome.blackWin)
            : draw
            ? Outcome.draw
            : Outcome.doubleForfeit,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> menu() async {
    final result = await showDialog<Outcome>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('White’s result'),
        children: [
          for (final outcome in Outcome.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, outcome),
              child: Text(
                outcome == Outcome.unreported
                    ? 'Clear to unreported'
                    : outcome.label,
              ),
            ),
        ],
      ),
    );
    if (result != null) {
      setState(() => correcting = true);
      await enter(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.controller.event!,
        all = rows(),
        visible = all
            .where((r) => !missingOnly || !r.game.outcome.resolved)
            .toList();
    final activeRow = all.where((r) => r.game.id == active).firstOrNull;
    final roundNumbers =
        e.sections.expand((s) => s.rounds).map((r) => r.number).toSet().toList()
          ..sort();
    final byes = <String>[];
    for (final s in e.sections.where(
      (s) => widget.sectionId == null || s.id == widget.sectionId,
    )) {
      final r = selectedRound == null
          ? s.rounds.lastOrNull
          : s.rounds.where((r) => r.number == selectedRound).firstOrNull;
      if (r != null) {
        for (final b in r.byes) {
          byes.add(
            '${s.name} · ${e.player(b.player).name}: ${b.reason} (${scoreText(b.points)})',
          );
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                selectedRound == null
                    ? 'Current rounds'
                    : 'Round $selectedRound',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              DropdownButton<int>(
                value: selectedRound ?? 0,
                items: [
                  const DropdownMenuItem(
                    value: 0,
                    child: Text('Current per section'),
                  ),
                  for (final n in roundNumbers)
                    DropdownMenuItem(value: n, child: Text('Round $n')),
                ],
                onChanged: (v) => setState(() {
                  selectedRound = v == 0 ? null : v;
                  active = null;
                  remember();
                }),
              ),
              StatusPill(
                '${all.where((r) => !r.game.outcome.resolved).length} missing',
              ),
              FilterChip(
                label: const Text('Missing only'),
                selected: missingOnly,
                onSelected: (v) => setState(() {
                  missingOnly = v;
                  remember();
                }),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: jump,
                  decoration: const InputDecoration(labelText: 'Jump to board'),
                  onSubmitted: (v) {
                    final row = all
                        .where((r) => r.game.board == int.tryParse(v))
                        .firstOrNull;
                    if (row != null) select(row.game.id);
                  },
                ),
              ),
              TextButton.icon(
                onPressed: active == null ? null : menu,
                icon: const Icon(Icons.more_horiz),
                label: const Text('Outcome'),
              ),
            ],
          ),
        ),
        if (byes.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Text(byes.join('\n')),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Wrap(
            spacing: 24,
            children: [
              Text(
                forfeit
                    ? 'FORFEIT · 1 White wins / 0 White loses · Escape cancels'
                    : '1 Win · 0 Loss · 5 Draw · W/L/D · F+1/F+0 Forfeit · X Double forfeit',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              const Text('Enter skip · F2 correct · M outcomes'),
            ],
          ),
        ),
        Expanded(
          child: all.isEmpty
              ? const EmptyState(
                  icon: Icons.grid_view_outlined,
                  title: 'Ready when the room is',
                  body: 'Post a round from Event to open the results grid.',
                )
              : Focus(
                  focusNode: focus,
                  onKeyEvent: onKey,
                  child: ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final row = visible[index], g = row.game;
                      final selected = g.id == active;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: selected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          child: Listener(
                            onPointerDown: (_) => select(g.id),
                            child: InkWell(
                              canRequestFocus: false,
                              key: ValueKey('game-${g.id}'),
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {},
                              onDoubleTap: () => select(g.id, edit: true),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 48,
                                      child: Text(
                                        '${g.board}${row.section.doubleGames ? '·${g.leg}' : ''}',
                                        style: const TextStyle(
                                          fontFamily: 'SourceCodePro',
                                          fontSize: 18,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            e.player(g.white).name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            '${row.section.name} · Round ${row.round.number} · White',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Semantics(
                                      label:
                                          'Round ${row.round.number}, board ${g.board}, White result, ${e.player(g.white).name} versus ${e.player(g.black).name}: ${g.outcome.label}',
                                      selected: selected,
                                      child: Container(
                                        width: 100,
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: selected
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.primary
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.outlineVariant,
                                            width: selected ? 2 : 1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          g.outcome.label,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontFamily: 'SourceCodePro',
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(
                                      child: Text(e.player(g.black).name),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Text(
            activeRow == null
                ? 'Select a White-result cell to begin. Tab leaves the grid.'
                : 'Round ${activeRow.round.number} · Board ${activeRow.game.board} · ${e.player(activeRow.game.white).name} vs ${e.player(activeRow.game.black).name} · ${correcting ? 'Correcting' : 'Entering'} White’s result',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
