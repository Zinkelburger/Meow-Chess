import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/rulings.dart';
import 'controller_listener.dart';
import 'history_panel.dart' show historyTime;
import 'select.dart';
import 'side_panel.dart';

/// Rules 13I, 20K, 18G and 21H–21L: the event's log of rulings, penalties,
/// appeals and adjudications, newest first, with an inline form to add one.
/// Entries apply at once and undo like any change.
class RulingsPanel extends StatefulWidget {
  const RulingsPanel({
    required this.controller,
    required this.onClose,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;

  @override
  State<RulingsPanel> createState() => _RulingsPanelState();
}

class _RulingsPanelState extends State<RulingsPanel>
    with ListensToController<RulingsPanel> {
  TournamentController get c => widget.controller;
  @override
  Listenable controllerOf(RulingsPanel widget) => widget.controller;
  final text = TextEditingController();
  final outcome = TextEditingController();
  final decidedBy = TextEditingController();
  final round = TextEditingController();
  final playerSearch = TextEditingController();
  String kind = 'ruling';
  String? sectionId;
  final players = <String>[];
  String? error;

  @override
  void initState() {
    super.initState();
    decidedBy.text = c.event!.tdId;
  }

  @override
  void dispose() {
    for (final t in [text, outcome, decidedBy, round, playerSearch]) {
      t.dispose();
    }
    super.dispose();
  }

  void log() {
    try {
      final r = round.text.trim();
      final number = r.isEmpty ? 0 : int.tryParse(r);
      if (number == null || number < 0) {
        throw const TournamentException('Enter the round as a number.');
      }
      c.logRuling(
        kind: kind,
        text: text.text,
        round: number,
        section: sectionId ?? '',
        players: players,
        decidedBy: decidedBy.text,
        outcome: outcome.text,
      );
      setState(() {
        error = null;
        text.clear();
        outcome.clear();
        players.clear();
      });
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    final e = c.event!;
    final entries = [...e.rulings]
      ..sort((a, b) => '${b['at']}'.compareTo('${a['at']}'));
    String name(Object? id) =>
        e.players.where((p) => p.id == id).map((p) => p.name).firstOrNull ??
        '$id';
    String sectionName(Object? id) =>
        e.sections.where((s) => s.id == id).map((s) => s.name).firstOrNull ??
        '';
    return SidePanel(
      key: const ValueKey('rulings-panel'),
      title: 'Rulings',
      onClose: widget.onClose,
      children: [
        Text(appealDeadlineNote, style: muted),
        const SizedBox(height: 4),
        Text(usChessAppealNote, style: muted),
        const SizedBox(height: 16),
        PlainSelect<String>(
          key: const ValueKey('ruling-kind'),
          value: kind,
          label: 'Kind',
          options: [
            for (final k in rulingKinds.entries) SelectOption(k.key, k.value),
          ],
          onChanged: (v) => setState(() => kind = v),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              child: TextField(
                key: const ValueKey('ruling-round'),
                controller: round,
                decoration: const InputDecoration(labelText: 'Round'),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PlainSelect<String?>(
                key: const ValueKey('ruling-section'),
                value: sectionId,
                label: 'Section',
                options: [
                  const SelectOption(null, 'Any section'),
                  for (final s in e.sections) SelectOption(s.id, s.name),
                ],
                onChanged: (v) => setState(() => sectionId = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (players.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final id in players)
                InputChip(
                  label: Text(name(id)),
                  onDeleted: () => setState(() => players.remove(id)),
                ),
            ],
          ),
        // Typed, not scrolled: a club event has 100+ names.
        Autocomplete<Player>(
          key: ValueKey('ruling-players-${players.length}'),
          displayStringForOption: (o) => o.name,
          optionsBuilder: (value) {
            final q = value.text.trim().toLowerCase();
            if (q.isEmpty) return const [];
            return e.players.where(
              (o) =>
                  !players.contains(o.id) && o.name.toLowerCase().contains(q),
            );
          },
          onSelected: (o) => setState(() => players.add(o.id)),
          fieldViewBuilder: (context, field, focus, submit) => TextField(
            key: const ValueKey('ruling-player'),
            controller: field,
            focusNode: focus,
            decoration: const InputDecoration(labelText: 'Players involved'),
            onSubmitted: (_) => submit(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('ruling-text'),
          controller: text,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'What was ruled, and why',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('ruling-outcome'),
          controller: outcome,
          decoration: const InputDecoration(
            labelText: 'Outcome (penalty, result, appeal decision)',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('ruling-decided-by'),
          controller: decidedBy,
          decoration: const InputDecoration(
            labelText: 'Decided by (TD ID or name)',
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const ValueKey('log-ruling'),
            onPressed: log,
            child: const Text('Log'),
          ),
        ),
        const SizedBox(height: 16),
        if (entries.isEmpty)
          Text('Nothing logged yet.', style: muted)
        else
          for (final entry in entries) ...[
            const Divider(height: 24),
            Text(
              [
                rulingKinds['${entry['kind']}'] ?? '${entry['kind']}',
                if ((entry['round'] as num? ?? 0) > 0)
                  'round ${entry['round']}',
                if (sectionName(entry['section']).isNotEmpty)
                  sectionName(entry['section']),
                if ('${entry['at'] ?? ''}'.isNotEmpty)
                  historyTime('${entry['at']}'),
              ].join(' · '),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (entry['players'] case final List ids when ids.isNotEmpty)
              Text(ids.map(name).join(', '), style: muted),
            const SizedBox(height: 4),
            SelectableText('${entry['text'] ?? ''}'),
            if ('${entry['outcome'] ?? ''}'.trim().isNotEmpty)
              Text('Outcome: ${entry['outcome']}', style: muted),
            if ('${entry['decidedBy'] ?? ''}'.trim().isNotEmpty)
              Text('Decided by ${entry['decidedBy']}', style: muted),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: ValueKey('remove-ruling-${entry['id']}'),
                onPressed: () {
                  try {
                    c.removeRuling('${entry['id']}');
                  } catch (e) {
                    setState(() => error = plainMessage(e));
                  }
                },
                child: const Text('Remove'),
              ),
            ),
          ],
      ],
    );
  }
}
