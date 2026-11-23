import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/tournament_controller.dart';
import '../domain/event_check.dart';
import '../domain/model.dart';
import '../domain/pairing_quality.dart';
import 'controller_listener.dart';
import 'select.dart';
import 'side_panel.dart';

/// The event checked for the mistakes a director wants to hear about before
/// the next round: what was found, every check that ran (and those that did
/// not apply), and how each Swiss round's pairings came out. It reads the
/// event as it is now and changes nothing.
class CheckPanel extends StatefulWidget {
  const CheckPanel({
    required this.controller,
    required this.onClose,
    this.sectionId,
    this.onOpenSection,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;

  /// The section to check first; null checks the whole event.
  final String? sectionId;

  /// Shows a finding's section in the workspace; [scope] is what the panel
  /// is checking, to come back to.
  final void Function(String sectionId, String? scope)? onOpenSection;

  @override
  State<CheckPanel> createState() => _CheckPanelState();
}

class _CheckPanelState extends State<CheckPanel>
    with ListensToController<CheckPanel> {
  @override
  Listenable controllerOf(CheckPanel widget) => widget.controller;
  late String? sectionId = widget.sectionId;
  bool copied = false;

  @override
  void controllerChanged() => setState(() => copied = false);

  @override
  Widget build(BuildContext context) {
    final e = widget.controller.event!;
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    // Undo can remove the section being checked.
    final scope = e.sections.any((s) => s.id == sectionId) ? sectionId : null;
    final check = checkEvent(e, sectionId: scope);
    final found = check.findings;
    final quality = [
      for (final s in e.sections)
        if (scope == null || s.id == scope) ?pairingQuality(e, s),
    ];
    return SidePanel(
      key: const ValueKey('check-panel'),
      title: 'Check event',
      onClose: widget.onClose,
      footer: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('copy-check'),
            icon: Icon(copied ? Icons.check : Icons.copy, size: 16),
            label: Text(copied ? 'Copied' : 'Copy report'),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: _report(check, quality)),
              );
              if (mounted) setState(() => copied = true);
            },
          ),
        ),
      ],
      children: [
        if (e.sections.length > 1) ...[
          PlainSelect<String?>(
            key: const ValueKey('check-scope'),
            value: scope,
            label: 'Check',
            options: [
              const SelectOption(null, 'The whole event'),
              for (final s in e.sections) SelectOption(s.id, s.name),
            ],
            onChanged: (v) => setState(() {
              sectionId = v;
              copied = false;
            }),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          found.isEmpty ? 'Nothing found.' : _summary(found),
          key: const ValueKey('check-summary'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'This looks at the event as it is now. It changes nothing and '
          'never stops a round from being paired.',
          style: muted,
        ),
        for (final f in found) ...[
          const Divider(height: 24),
          _finding(context, e, f, scope),
        ],
        const Divider(height: 32),
        Text('Checked', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final c in check.checks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Icon(
                    !c.ran
                        ? Icons.remove
                        : c.clear
                        ? Icons.check
                        : Icons.error_outline,
                    size: 16,
                    color: !c.ran
                        ? colors.onSurfaceVariant
                        : c.clear
                        ? colors.primary
                        : colors.error,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.title),
                      Text(c.verdict, style: muted),
                    ],
                  ),
                ),
              ],
            ),
          ),
        for (final q in quality) ...[
          const Divider(height: 32),
          Text(
            'Pairing quality · ${q.name}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            [
              'Counted from the posted rounds and the results before each.',
              if (q.note.isNotEmpty) q.note,
            ].join(' '),
            style: muted,
          ),
          const SizedBox(height: 8),
          _QualityTable(q),
        ],
      ],
    );
  }

  String _summary(List<CheckFinding> found) {
    int of(CheckLevel level) => found.where((f) => f.level == level).length;
    final fix = of(CheckLevel.fix), look = of(CheckLevel.look);
    final note = of(CheckLevel.note);
    return [
      if (fix > 0) '$fix to fix',
      if (look > 0) '$look to look at',
      if (note > 0) '$note ${note == 1 ? 'note' : 'notes'}',
    ].join(', ');
  }

  Widget _finding(
    BuildContext context,
    Event e,
    CheckFinding f,
    String? scope,
  ) {
    final colors = Theme.of(context).colorScheme;
    final open = widget.onOpenSection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          f.level.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: f.level == CheckLevel.note
                ? colors.onSurfaceVariant
                : colors.error,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(f.message),
        if (open != null && f.sectionId.isNotEmpty && f.sectionId != scope)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => open(f.sectionId, scope),
              child: Text(
                'Show ${e.sections.where((s) => s.id == f.sectionId).map((s) => s.name).firstOrNull ?? 'section'}',
              ),
            ),
          ),
      ],
    );
  }
}

/// The text of the Copy report button: the check, then the quality tables.
String _report(EventCheck check, List<SectionQuality> quality) => [
  check.report(),
  for (final q in quality) ...[
    '',
    'Pairing quality: ${q.name}',
    for (final r in [...q.rounds, if (q.rounds.length > 1) q.total]) ...[
      '  ${r.round == 0 ? 'All rounds' : 'Round ${r.round}'}',
      for (final (label, value) in qualityRows(r)) '    $label: $value',
    ],
  ],
].join('\n');

/// A tally as the director reads it: `18 of 20`, or a dash when there was
/// nothing to count.
String tallyText(Tally t) => t.of == 0 ? '–' : '${t.count} of ${t.of}';

/// The figures of one round, labelled, in display order.
List<(String, String)> qualityRows(RoundQuality r) => [
  ('Boards inside one score group', tallyText(r.sameScore)),
  ('Got the color they were due', tallyText(r.colorsDue)),
  ('Third game in a row with one color', tallyText(r.thirdInRow)),
  ('Two colors out of balance', tallyText(r.imbalance)),
  ('Left their score group the same way twice', tallyText(r.repeatFloats)),
  ('Repeat pairings', tallyText(r.rematches)),
  if (r.teammates case final t?) ('Team-mates paired', tallyText(t)),
  if (r.requests.count > 0)
    ('Do-not-pair requests paired', tallyText(r.requests)),
];

class _QualityTable extends StatelessWidget {
  const _QualityTable(this.quality);
  final SectionQuality quality;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rounds = [
      ...quality.rounds,
      if (quality.rounds.length > 1) quality.total,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in rounds) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Text(
              r.round == 0
                  ? 'All rounds · ${r.boards} boards'
                  : 'Round ${r.round} · ${r.boards} ${r.boards == 1 ? 'board' : 'boards'}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          for (final (label, value) in qualityRows(r))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label, style: const TextStyle(fontSize: 13)),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      color: value == '–' ? colors.onSurfaceVariant : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
