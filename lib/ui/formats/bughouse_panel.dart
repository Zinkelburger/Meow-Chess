import 'package:flutter/material.dart';

import '../../application/failures.dart';
import '../../application/tournament_controller.dart';
import '../../domain/bughouse.dart';
import '../../domain/model.dart';
import '../controller_listener.dart';
import '../format_extensions.dart';
import '../panels.dart';
import '../player_format.dart';
import '../side_panel.dart';
import '../theme.dart';

/// Bughouse adds nothing to the Pairing rules group: partnerships are formed
/// in the Partners panel and the section is always unrated.
final bughouseFormatExtension = FormatExtension(
  format: Format.bughouse,
  fields: (current, {required locked}) => const [],
  values: (section) => const {},
  apply: (section, values) => section.copy(unrated: true),
  summary: (section) =>
      'Unrated · ${section.partners.length} partnership${section.partners.length == 1 ? '' : 's'}',
  problem: (event, section) => section.players.length < 4
      ? 'A bughouse section needs at least four players.'
      : unpartnered(section).isNotEmpty
      ? 'Pair everyone up first'
      : null,
);

/// Docks the Partners panel for [sectionId].
void showBughousePartners(
  BuildContext context,
  TournamentController c, {
  required String sectionId,
}) {
  final dock = Dock.maybeOf(context);
  if (dock == null) return;
  dock.show(
    'bughouse-partners',
    BughousePartnersPanel(
      key: ValueKey(('bughouse-partners', sectionId)),
      controller: c,
      sectionId: sectionId,
      onClose: dock.close,
    ),
  );
}

/// Forms and dissolves the partnerships of a bughouse section before
/// round 1. Every change applies at once as one undoable revision.
class BughousePartnersPanel extends StatefulWidget {
  const BughousePartnersPanel({
    required this.controller,
    required this.sectionId,
    required this.onClose,
    super.key,
  });
  final TournamentController controller;
  final String sectionId;
  final VoidCallback onClose;

  @override
  State<BughousePartnersPanel> createState() => _BughousePartnersPanelState();
}

class _BughousePartnersPanelState extends State<BughousePartnersPanel>
    with ListensToController<BughousePartnersPanel> {
  final picked = <String>[];
  String? error;
  TournamentController get c => widget.controller;
  Section? get section =>
      c.event?.sections.where((s) => s.id == widget.sectionId).firstOrNull;

  @override
  Listenable controllerOf(BughousePartnersPanel widget) => widget.controller;

  void apply(List<List<String>> partners) {
    try {
      c.setPartners(widget.sectionId, partners);
      setState(() {
        picked.clear();
        error = null;
      });
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  void toggle(String id) => setState(() {
    error = null;
    if (!picked.remove(id)) {
      picked.add(id);
      // Only two can be partners; the earliest tick gives way.
      if (picked.length > 2) picked.removeAt(0);
    }
  });

  @override
  Widget build(BuildContext context) {
    final s = section, e = c.event;
    final colors = Theme.of(context).colorScheme;
    if (s == null || e == null) {
      return SidePanel(
        title: 'Partners',
        onClose: widget.onClose,
        children: const [Text('That section no longer exists.')],
      );
    }
    final free = unpartnered(s);
    final locked = s.rounds.isNotEmpty;
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    String who(String id) {
      final p = e.player(id);
      return '${p.name} (${ratingText(p.effectivePairingRating)})';
    }

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
    return SidePanel(
      title: 'Partners',
      onClose: widget.onClose,
      footer: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
        const SizedBox(height: 8),
        if (!locked)
          FilledButton(
            key: const ValueKey('pair-as-partners'),
            onPressed: picked.length == 2
                ? () => apply([
                    ...s.partners,
                    [picked[0], picked[1]],
                  ])
                : null,
            child: const Text('Pair as partners'),
          ),
        TextButton(onPressed: widget.onClose, child: const Text('Done')),
      ],
      children: [
        Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(
          '${s.partners.length} partnership${s.partners.length == 1 ? '' : 's'} · '
          '${free.length} without a partner',
          style: muted,
        ),
        const SizedBox(height: 8),
        Text(
          locked
              ? 'Partnerships are fixed once round 1 is posted.'
              : 'Tick two players, then Pair as partners. A player without a partner sits out with a zero-point bye.',
          style: muted,
        ),
        if (s.partners.isNotEmpty) heading('Partnerships'),
        for (final pair in s.partners)
          Row(
            key: ValueKey(('partnership', pair[0], pair[1])),
            children: [
              Expanded(
                child: Text(
                  pair.map((id) => e.player(id).name).join(' / '),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              if (!locked)
                IconButton(
                  key: ValueKey(('unlink', pair[0], pair[1])),
                  tooltip: 'Unlink',
                  icon: const Icon(Icons.link_off, size: 18),
                  onPressed: () => apply([
                    for (final p in s.partners)
                      if (p != pair) p,
                  ]),
                ),
            ],
          ),
        if (free.isNotEmpty) heading('Without a partner'),
        for (final id in free)
          InkWell(
            key: ValueKey(('partner-pick', id)),
            onTap: locked ? null : () => toggle(id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  PlainCheckbox(
                    label: 'Pick ${e.player(id).name}',
                    value: picked.contains(id),
                    onChanged: locked ? null : (_) => toggle(id),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(who(id), style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
