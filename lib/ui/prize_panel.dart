import 'dart:async';

import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/prizes.dart';
import '../infrastructure/reports.dart' show ReportKind;
import 'panels.dart' show showPrint;
import 'controller_listener.dart';
import 'select.dart';
import 'side_panel.dart';

/// Rules 32–33: the announced prize table of one section, edited in place.
/// Every change applies at once as its own undoable step.
class PrizeTablePanel extends StatelessWidget {
  const PrizeTablePanel({
    required this.controller,
    required this.sectionId,
    required this.onClose,
    super.key,
  });
  final TournamentController controller;
  final String sectionId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final s = controller.event?.sections
          .where((s) => s.id == sectionId)
          .firstOrNull;
      return SidePanel(
        key: ValueKey('prizes-$sectionId'),
        title: s == null ? 'Section removed' : '${s.name} prizes',
        onClose: onClose,
        children: [
          PrizeTableEditor(controller: controller, sectionId: sectionId),
        ],
      );
    },
  );
}

/// The prize table itself: fund, terms and one row per prize, with the
/// summary and the prize report at the end. Lives in the section panel's
/// Prizes group and in [PrizeTablePanel].
class PrizeTableEditor extends StatefulWidget {
  const PrizeTableEditor({
    required this.controller,
    required this.sectionId,
    super.key,
  });
  final TournamentController controller;
  final String sectionId;
  @override
  State<PrizeTableEditor> createState() => _PrizeTableEditorState();
}

class _PrizeTableEditorState extends State<PrizeTableEditor>
    with ListensToController<PrizeTableEditor> {
  String? error;

  @override
  Listenable controllerOf(PrizeTableEditor widget) => widget.controller;

  Section? get section => widget.controller.event?.sections
      .where((s) => s.id == widget.sectionId)
      .firstOrNull;

  void apply(PrizeTable Function(PrizeTable) edit) {
    final c = widget.controller, s = section;
    if (s == null) return;
    try {
      final next = edit(PrizeTable.fromJson(s.prizes));
      c.change(
        'Edit prizes for ${s.name}',
        c.event!.copy(
          sections: [
            for (final x in c.event!.sections)
              x.id == s.id ? x.copy(prizes: next.toJson()) : x,
          ],
        ),
      );
      if (error != null && mounted) setState(() => error = null);
    } catch (e) {
      if (mounted) setState(() => error = plainMessage(e));
    }
  }

  void editPrize(String id, Prize Function(Prize) edit) => apply(
    (t) => t.copy(list: [for (final p in t.list) p.id == id ? edit(p) : p]),
  );

  void addPrize() {
    final s = section;
    if (s == null) return;
    final table = PrizeTable.fromJson(s.prizes);
    final places = table.list.where((p) => p.kind == PrizeKind.place).length;
    apply(
      (t) => t.copy(
        list: [
          ...t.list,
          Prize(id: widget.controller.newId(), place: places + 1),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = section, colors = Theme.of(context).colorScheme;
    if (s == null) return const Text('This section no longer exists.');
    final table = PrizeTable.fromJson(s.prizes);
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'The prizes as announced. Tied cash prizes pool and split; '
          'trophies follow the standings order. Changes apply at once.',
          style: muted,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _CommitField(
                key: const ValueKey('prize-based-on'),
                label: 'Based on entries',
                hint: '0 = guaranteed',
                value: table.basedOn == 0 ? '' : '${table.basedOn}',
                onCommit: (v) =>
                    apply((t) => t.copy(basedOn: _whole(v, 'Based on'))),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CommitField(
                key: const ValueKey('prize-fund'),
                label: 'Announced fund \$',
                value: _money(table.fundCents),
                onCommit: (v) => apply(
                  (t) => t.copy(fundCents: _cents(v, 'Announced fund')),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _CommitField(
          key: const ValueKey('prize-unrated-cap'),
          label: 'Most an unrated player may win \$',
          hint: 'blank = no limit',
          value: _money(table.unratedCapCents),
          onCommit: (v) =>
              apply((t) => t.copy(unratedCapCents: _cents(v, 'Unrated limit'))),
        ),
        CheckboxListTile(
          key: const ValueKey('prize-withdrawn'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Withdrawn players stay eligible'),
          value: table.withdrawnEligible,
          onChanged: (v) => apply((t) => t.copy(withdrawnEligible: v ?? false)),
        ),
        const Divider(),
        if (table.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No prizes yet.', style: muted),
          ),
        for (final p in table.list) _prizeRow(context, s, table, p),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('add-prize'),
            onPressed: addPrize,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add prize'),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              key: const ValueKey('prize-error'),
              style: TextStyle(color: colors.error),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${table.list.length} ${table.list.length == 1 ? 'prize' : 'prizes'}'
              ' · ${dollars(table.list.fold(0, (sum, p) => sum + p.cents))} in cash',
              key: const ValueKey('prize-summary'),
              style: muted,
            ),
            TextButton(
              key: const ValueKey('prize-report'),
              onPressed: () => showPrint(
                context,
                widget.controller.event!,
                sectionId: s.id,
                kind: ReportKind.prizes,
              ),
              child: const Text('Prize report…'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _prizeRow(BuildContext context, Section s, PrizeTable table, Prize p) {
    final colors = Theme.of(context).colorScheme;
    final named = p.kind == PrizeKind.junior || p.kind == PrizeKind.senior;
    return Container(
      key: ValueKey('prize-${p.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 8),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _CommitField(
                  key: ValueKey('prize-label-${p.id}'),
                  label: 'Label',
                  hint: p.describe(),
                  value: p.label,
                  onCommit: (v) =>
                      editPrize(p.id, (x) => x.copy(label: v.trim())),
                ),
              ),
              IconButton(
                key: ValueKey('remove-prize-${p.id}'),
                tooltip: 'Remove prize',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => apply(
                  (t) => t.copy(
                    list: [
                      for (final x in t.list)
                        if (x.id != p.id) x,
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: PlainSelect<PrizeKind>(
                  key: ValueKey('prize-kind-${p.id}'),
                  label: 'Kind',
                  value: p.kind,
                  options: [
                    for (final k in PrizeKind.values) SelectOption(k, k.label),
                  ],
                  onChanged: (k) => editPrize(p.id, (x) => x.copy(kind: k)),
                ),
              ),
              if (p.kind != PrizeKind.points) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: _CommitField(
                    key: ValueKey('prize-place-${p.id}'),
                    label: 'Place',
                    value: '${p.place}',
                    onCommit: (v) => editPrize(
                      p.id,
                      (x) => x.copy(place: _whole(v, 'Place', min: 1)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (p.kind == PrizeKind.classRange ||
              p.kind == PrizeKind.under ||
              p.kind == PrizeKind.points) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (p.kind == PrizeKind.classRange) ...[
                  Expanded(
                    child: _CommitField(
                      key: ValueKey('prize-min-${p.id}'),
                      label: 'From rating',
                      value: p.min == 0 ? '' : '${p.min}',
                      onCommit: (v) => editPrize(
                        p.id,
                        (x) => x.copy(min: _whole(v, 'From rating')),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CommitField(
                      key: ValueKey('prize-max-${p.id}'),
                      label: 'To rating',
                      value: p.max == 0 ? '' : '${p.max}',
                      onCommit: (v) => editPrize(
                        p.id,
                        (x) => x.copy(max: _whole(v, 'To rating')),
                      ),
                    ),
                  ),
                ],
                if (p.kind == PrizeKind.under)
                  Expanded(
                    child: _CommitField(
                      key: ValueKey('prize-max-${p.id}'),
                      label: 'Under rating',
                      hint: 'e.g. 1800',
                      value: p.max == 0 ? '' : '${p.max}',
                      onCommit: (v) => editPrize(
                        p.id,
                        (x) => x.copy(max: _whole(v, 'Under rating')),
                      ),
                    ),
                  ),
                if (p.kind == PrizeKind.points)
                  Expanded(
                    child: _CommitField(
                      key: ValueKey('prize-points-${p.id}'),
                      label: 'Points scored',
                      hint: 'e.g. 4.5',
                      value: p.points == 0 ? '' : scoreText(p.points),
                      onCommit: (v) =>
                          editPrize(p.id, (x) => x.copy(points: _halves(v))),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 110,
                child: _CommitField(
                  key: ValueKey('prize-cents-${p.id}'),
                  label: 'Cash \$',
                  value: _money(p.cents),
                  onCommit: (v) =>
                      editPrize(p.id, (x) => x.copy(cents: _cents(v, 'Cash'))),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: CheckboxListTile(
                  key: ValueKey('prize-trophy-${p.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Trophy'),
                  value: p.trophy,
                  onChanged: (v) =>
                      editPrize(p.id, (x) => x.copy(trophy: v ?? false)),
                ),
              ),
            ],
          ),
          if (table.basedOn > 0)
            CheckboxListTile(
              key: ValueKey('prize-guaranteed-${p.id}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Guaranteed in full'),
              value: p.guaranteed,
              onChanged: (v) =>
                  editPrize(p.id, (x) => x.copy(guaranteed: v ?? false)),
            ),
          if (named) ...[
            const SizedBox(height: 4),
            Text(
              'Who qualifies (no birth dates are kept):',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final id in s.players)
                  FilterChip(
                    key: ValueKey('prize-eligible-${p.id}-$id'),
                    label: Text(
                      widget.controller.event!.player(id).name,
                      style: const TextStyle(fontSize: 12),
                    ),
                    visualDensity: VisualDensity.compact,
                    selected: p.eligible.contains(id),
                    onSelected: (on) => editPrize(
                      p.id,
                      (x) => x.copy(
                        eligible: on
                            ? [...x.eligible, id]
                            : x.eligible.where((e) => e != id).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _money(int cents) => cents == 0
    ? ''
    : cents % 100 == 0
    ? '${cents ~/ 100}'
    : (cents / 100).toStringAsFixed(2);

int _cents(String text, String label) {
  final t = text.trim().replaceAll(RegExp(r'[\$,\s]'), '');
  if (t.isEmpty) return 0;
  final value = double.tryParse(t);
  if (value == null || value < 0) {
    throw TournamentException('$label must be a dollar amount.');
  }
  return (value * 100).round();
}

int _whole(String text, String label, {int min = 0}) {
  final t = text.trim();
  if (t.isEmpty) return min;
  final value = int.tryParse(t);
  if (value == null || value < min) {
    throw TournamentException('$label must be a whole number of $min or more.');
  }
  return value;
}

int _halves(String text) {
  final t = text.trim().replaceAll('½', '.5');
  if (t.isEmpty) return 0;
  final value = double.tryParse(t);
  if (value == null || value < 0 || (value * 2) % 1 != 0) {
    throw const TournamentException('Points are whole or half points.');
  }
  return (value * 2).round();
}

/// A text field that applies on Enter or when focus leaves, and follows
/// the saved value when it changes underneath it (undo, automation).
class _CommitField extends StatefulWidget {
  const _CommitField({
    required this.label,
    required this.value,
    required this.onCommit,
    this.hint,
    super.key,
  });
  final String label, value;
  final String? hint;
  final ValueChanged<String> onCommit;
  @override
  State<_CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<_CommitField> {
  late final controller = TextEditingController(text: widget.value);
  final focus = FocusNode();
  String committed = '';

  @override
  void initState() {
    super.initState();
    committed = widget.value;
    focus.addListener(() {
      if (!focus.hasFocus) commit();
    });
  }

  @override
  void didUpdateWidget(_CommitField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !focus.hasFocus) {
      controller.text = widget.value;
      committed = widget.value;
    }
  }

  @override
  void dispose() {
    // Closing the panel mid-edit keeps what was typed. The save runs after
    // the tree is unlocked, since it notifies the whole workspace.
    final pending = controller.text, onCommit = widget.onCommit;
    if (pending != committed) {
      committed = pending;
      scheduleMicrotask(() => onCommit(pending));
    }
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  void commit() {
    if (controller.text == committed) return;
    committed = controller.text;
    widget.onCommit(controller.text);
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    focusNode: focus,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      isDense: true,
    ),
    onSubmitted: (_) => commit(),
  );
}
