import 'dart:convert';

import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/pairing.dart';
import 'panels.dart';
import 'side_panel.dart';

void showQuadPairingsEditor(
  BuildContext context,
  TournamentController c, {
  String? sectionId,
}) {
  final dock = Dock.maybeOf(context);
  if (dock == null) return;
  dock.show(
    'quad-pairings',
    QuadPairingsPanel(
      key: UniqueKey(),
      controller: c,
      sectionId: sectionId,
      onClose: dock.close,
    ),
  );
}

class QuadPairingsPanel extends StatefulWidget {
  const QuadPairingsPanel({
    required this.controller,
    required this.onClose,
    this.sectionId,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;
  final String? sectionId;

  @override
  State<QuadPairingsPanel> createState() => _QuadPairingsPanelState();
}

class _QuadPairingsPanelState extends State<QuadPairingsPanel> {
  late String sectionId;
  late int revision;
  late List<List<String>> pairings;
  String? error;
  late String baseline;
  late String roster;
  TournamentController get c => widget.controller;
  List<Section> get quads =>
      c.event!.sections.where(hasFixedQuadSchedule).toList();

  @override
  void initState() {
    super.initState();
    load(
      quads.where((s) => s.id == widget.sectionId).firstOrNull ?? quads.first,
    );
    c.addListener(sync);
  }

  @override
  void dispose() {
    c.removeListener(sync);
    super.dispose();
  }

  /// Posted rounds as posted; the rest from the saved schedule, whether or not
  /// everyone is available for them yet.
  List<List<String>> schedule(Section s) => [
    for (final (index, pairs) in sectionSchedule(s).indexed)
      if (s.rounds.where((r) => r.number == index + 1).firstOrNull
          case final posted?)
        [
          for (final g in posted.games.where((g) => g.leg == 1)) ...[
            g.white,
            g.black,
          ],
        ]
      else
        [
          for (final (white, black) in pairs) ...[white!, black!],
        ],
  ];

  String rosterKey(Section s) =>
      jsonEncode([s.players, s.boardStart, s.doubleGames]);

  void sync() {
    if (!mounted) return;
    final s = quads.where((s) => s.id == sectionId).firstOrNull;
    setState(() {
      if (s == null) return;
      final current = schedule(s);
      if (jsonEncode(current) != baseline || rosterKey(s) != roster) {
        if (jsonEncode(pairings) == baseline) load(s);
        return;
      }
      revision = c.event!.revision;
      // Results can lock a round while the editor is open. Keep other drafts.
      for (var r = 0; r < current.length; r++) {
        if (locked(s, r)) pairings[r] = [...current[r]];
      }
    });
  }

  void load(Section s) {
    sectionId = s.id;
    revision = c.event!.revision;
    error = null;
    pairings = schedule(s);
    baseline = jsonEncode(pairings);
    roster = rosterKey(s);
  }

  bool locked(Section s, int index) => s.rounds.any(
    (r) =>
        r.number == index + 1 &&
        (r.hasPlay || r.games.any((g) => g.pairingAssumption != null)),
  );

  void swap(int round, int slot, String id) {
    setState(() {
      final row = pairings[round], other = pairings[round].indexOf(id);
      row[other] = row[slot];
      row[slot] = id;
      error = null;
    });
  }

  void save() {
    try {
      c.editQuadPairings(sectionId, pairings, revision);
      widget.onClose();
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = quads.where((s) => s.id == sectionId).firstOrNull;
    final stale = revision != c.event!.revision;
    final valid = pairings.every((r) => r.length == 4);
    return SidePanel(
      title: 'Edit quad pairings',
      onClose: widget.onClose,
      footer: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey('save-quad-pairings'),
          onPressed: stale || s == null || !valid ? null : save,
          child: const Text('Save pairings'),
        ),
        TextButton(onPressed: widget.onClose, child: const Text('Cancel')),
      ],
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(('quad-editor-section', sectionId)),
          initialValue: s?.id,
          decoration: const InputDecoration(labelText: 'Quad'),
          isExpanded: true,
          items: [
            for (final q in quads)
              DropdownMenuItem(value: q.id, child: Text(q.name)),
          ],
          onChanged: (id) {
            if (id != null) {
              setState(() => load(quads.firstWhere((q) => q.id == id)));
            }
          },
        ),
        if (stale || s == null) ...[
          const SizedBox(height: 12),
          const Text('Pairings changed elsewhere. Reload to continue.'),
          if (s != null)
            TextButton(
              onPressed: () => setState(() => load(s)),
              child: const Text('Reload quad'),
            ),
        ] else if (!valid) ...[
          const SizedBox(height: 12),
          const Text(
            'This quad has a custom round that cannot be edited here.',
          ),
        ] else ...[
          for (var r = 0; r < 3; r++) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              'Round ${r + 1}${locked(s, r) ? ' · Locked' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (locked(s, r))
              Text(
                s.rounds[r].startedAt != null
                    ? 'Round started'
                    : s.rounds[r].games.any((g) => g.pairingAssumption != null)
                    ? 'Pairing assumption recorded'
                    : 'Clear results to edit',
              ),
            for (var b = 0; b < 2; b++) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Text(
                    'Board ${s.rounds.where((round) => round.number == r + 1).firstOrNull?.games.where((g) => g.leg == 1).elementAt(b).board ?? s.boardStart + b}',
                  ),
                  IconButton(
                    key: ValueKey('quad-flip-$r-$b'),
                    onPressed: locked(s, r)
                        ? null
                        : () => swap(r, b * 2, pairings[r][b * 2 + 1]),
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    tooltip: 'Flip colors',
                  ),
                ],
              ),
              Row(
                children: [
                  for (var color = 0; color < 2; color++) ...[
                    if (color == 1) const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey((
                          'quad-seat',
                          r,
                          b * 2 + color,
                          pairings[r][b * 2 + color],
                        )),
                        initialValue: pairings[r][b * 2 + color],
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: color == 0 ? 'White' : 'Black',
                        ),
                        items: [
                          for (final id in s.players)
                            DropdownMenuItem(
                              value: id,
                              child: Text(
                                c.event!.player(id).name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: locked(s, r)
                            ? null
                            : (id) {
                                if (id != null) swap(r, b * 2 + color, id);
                              },
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ],
      ],
    );
  }
}
