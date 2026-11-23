import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import 'player_actions.dart';
import 'player_format.dart';
import 'player_panel.dart';
import 'side_panel.dart';

/// The notes entrants left on the registration list ("Bye rd 1", "Leaving
/// after round 3"), one after another, each with the bye grid beside it.
/// Nothing is read out of a note: the director gives the bye and says the
/// note is dealt with.
class NotesPanel extends StatefulWidget {
  const NotesPanel({
    required this.controller,
    required this.onClose,
    this.onSetUp,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;

  /// Opens Set up, where a section's rounds are set.
  final VoidCallback? onSetUp;

  @override
  State<NotesPanel> createState() => _NotesPanelState();
}

/// Players whose registration note waits to be dealt with, in roster order.
List<Player> waitingNotes(Event e) => [
  for (final p in e.players)
    if (p.noteWaiting && !p.withdrawn) p,
];

class _NotesPanelState extends State<NotesPanel> {
  TournamentController get c => widget.controller;
  String? error;
  bool showDone = false;

  void attempt(VoidCallback change) {
    try {
      change();
      setState(() => error = null);
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final e = c.event;
      if (e == null) return const SizedBox.shrink();
      final colors = Theme.of(context).colorScheme;
      final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
      final waiting = waitingNotes(e);
      final done = [
        for (final p in e.players)
          if (p.registrationNote.trim().isNotEmpty &&
              !p.noteWaiting &&
              !p.withdrawn)
            p,
      ];
      return SidePanel(
        key: const ValueKey('registration-notes'),
        title: 'Registration notes',
        onClose: widget.onClose,
        footer: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                error!,
                key: const ValueKey('notes-error'),
                style: TextStyle(color: colors.error),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const ValueKey('notes-close'),
              onPressed: widget.onClose,
              child: const Text('Done'),
            ),
          ),
        ],
        children: [
          if (waiting.isEmpty)
            Text(
              done.isEmpty
                  ? 'No entrant left a note.'
                  : 'Every note is dealt with.',
              key: const ValueKey('notes-empty'),
              style: muted,
            ),
          for (final (i, p) in waiting.indexed)
            _note(context, e, p, first: i == 0),
          if (done.isNotEmpty) ...[
            const SizedBox(height: 16),
            DisclosureGroup(
              headerKey: const ValueKey('notes-done-group'),
              title: 'Dealt with',
              summary: '${done.length}',
              open: showDone,
              onToggle: () => setState(() => showDone = !showDone),
              children: [
                for (final p in done)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: p.name),
                                TextSpan(
                                  text: '  ${p.registrationNote}',
                                  style: muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                        TextButton(
                          key: ValueKey('note-reopen-${p.id}'),
                          onPressed: () => attempt(
                            () => c.markNoteHandled(p.id, handled: false),
                          ),
                          child: const Text('Reopen'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      );
    },
  );

  Widget _note(BuildContext context, Event e, Player p, {required bool first}) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    final s = e.sectionOf(p.id);
    final open = openRounds(e, p);
    final unset = s != null && s.roundsUnset;
    return Container(
      key: ValueKey('note-${p.id}'),
      margin: EdgeInsets.only(top: first ? 0 : 16),
      padding: EdgeInsets.only(top: first ? 0 : 16),
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: p.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: [
                    '   ${s?.name ?? 'No section'}',
                    ratingText(p.rating),
                  ].join(' · '),
                  style: muted.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(p.registrationNote, key: ValueKey('note-text-${p.id}')),
          const SizedBox(height: 8),
          if (unset)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${s.name} has no rounds set', style: muted),
                if (widget.onSetUp != null)
                  TextButton(
                    onPressed: widget.onSetUp,
                    child: const Text('Set up'),
                  ),
              ],
            )
          else if (open.isNotEmpty)
            ByeGrid(
              rounds: open,
              byes: p.byes,
              onToggle: (r, points) => attempt(
                () => p.byes[r] == points
                    ? c.cancelBye(p.id, r)
                    : c.reserveBye(p.id, r, points),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: ValueKey('note-done-${p.id}'),
            onPressed: () => attempt(() => c.markNoteHandled(p.id)),
            child: const Text('Dealt with'),
          ),
        ],
      ),
    );
  }
}
