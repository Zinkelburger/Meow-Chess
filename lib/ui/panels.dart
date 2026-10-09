import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/pairing.dart';
import '../domain/bye_policy.dart';
import '../domain/us_chess.dart';
import '../domain/standings.dart';
import '../infrastructure/artifact_save.dart';
import '../infrastructure/reports.dart';
import '../infrastructure/remembered_printing.dart';
import 'dialogs.dart' show FieldSpec, showFailure;
import 'drafts.dart';
import 'side_panel.dart';
import 'select.dart';

/// The tool docked at the right of the workspace: one at a time, beside
/// the table it acts on, never over it.
class DockController extends ChangeNotifier {
  DockController({this.tournament});
  final TournamentController? tournament;
  FocusNode? _returnFocus;

  /// Claims the same panel slot for a view's embedded player editor.
  void claim(Object owner) {
    if (id == owner) return;
    show(owner, null);
  }

  Widget? panel;

  /// What [panel] is for, so asking for it again toggles it closed.
  Object? id;

  void show(Object id, Widget? panel) {
    if (this.id == null) _returnFocus = FocusManager.instance.primaryFocus;
    this.id = id;
    this.panel = panel == null || tournament == null
        ? panel
        : _LivePanel(tournament: tournament!, child: panel);
    notifyListeners();
  }

  void close() {
    if (id == null) return;
    id = panel = null;
    notifyListeners();
    final focus = _returnFocus;
    _returnFocus = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (focus?.context != null && focus!.canRequestFocus) {
        focus.requestFocus();
      }
    });
  }
}

/// The dock keeps one panel instance, and Flutter never rebuilds an
/// identical widget on its own; rebuild it whenever the event changes so a
/// docked panel never shows stale players, rounds or settings.
class _LivePanel extends StatefulWidget {
  const _LivePanel({required this.tournament, required this.child});
  final Listenable tournament;
  final Widget child;
  @override
  State<_LivePanel> createState() => _LivePanelState();
}

class _LivePanelState extends State<_LivePanel> {
  @override
  void initState() {
    super.initState();
    widget.tournament.addListener(changed);
  }

  @override
  void didUpdateWidget(_LivePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tournament != widget.tournament) {
      oldWidget.tournament.removeListener(changed);
      widget.tournament.addListener(changed);
    }
  }

  @override
  void dispose() {
    widget.tournament.removeListener(changed);
    super.dispose();
  }

  void changed() {
    if (!mounted) return;
    (context as Element).visitChildElements((panel) => panel.markNeedsBuild());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class Dock extends InheritedNotifier<DockController> {
  const Dock({
    required DockController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// Null outside a workspace, as in a view mounted on its own.
  static DockController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Dock>()?.notifier;
}

/// A short form in the side panel. Save applies at once and closes; a
/// problem stays in the panel beside the field that caused it.
class FieldsPanel extends StatefulWidget {
  const FieldsPanel({
    required this.title,
    required this.fields,
    required this.onSave,
    required this.onClose,
    this.values = const {},
    this.currentValues,
    this.description,
    this.saveLabel = 'Save',
    this.controller,
    this.draftKey,
    this.footer = const [],
    super.key,
  });
  final String title, saveLabel;
  final TournamentController? controller;
  final String? draftKey;
  final String? description;

  /// Actions that belong with these fields but apply on their own.
  final List<Widget> footer;
  final List<FieldSpec> fields;
  final Map<String, String> values;

  /// For editing an existing record, read its latest values at save/discard.
  final Map<String, String> Function()? currentValues;
  final FutureOr<void> Function(Map<String, String>) onSave;
  final VoidCallback onClose;
  @override
  State<FieldsPanel> createState() => _FieldsPanelState();
}

class _FieldsPanelState extends State<FieldsPanel> {
  late final text = {
    for (final f in widget.fields)
      f.key: TextEditingController(
        text: f.options == null || f.options!.containsKey(widget.values[f.key])
            ? widget.values[f.key] ?? ''
            : f.options!.keys.first,
      ),
  };
  FormDraft? draft;
  @override
  void initState() {
    super.initState();
    if (widget.controller != null && widget.draftKey != null) {
      final base = text.map((k, v) => MapEntry(k, v.text));
      draft = FormDraft(
        widget.controller!.workspaceState,
        widget.draftKey!,
        text,
        base,
      );
      for (final f in widget.fields) {
        if (f.options != null && !f.options!.containsKey(text[f.key]!.text)) {
          text[f.key]!.text = base[f.key]!;
        }
      }
    }
  }

  String? error;
  bool busy = false;

  @override
  void dispose() {
    draft?.dispose();
    for (final t in text.values) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    try {
      final values =
          draft?.prepareSave(
            widget.currentValues?.call() ?? widget.values,
            labels: {for (final f in widget.fields) f.key: f.label},
          ) ??
          text.map((k, v) => MapEntry(k, v.text));
      final missing = widget.fields
          .where((f) => f.required && values[f.key]!.trim().isEmpty)
          .firstOrNull;
      if (missing != null) {
        throw TournamentException('Enter the ${missing.label.toLowerCase()}.');
      }
      setState(() => busy = true);
      await widget.onSave(values);
      if (!mounted) {
        // The fields are disposed; only the stored draft is left to clear.
        draft?.clear();
        return;
      }
      draft?.reset(values);
      widget.onClose();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = plainMessage(e);
          busy = false;
        });
      }
    }
  }

  void discard() {
    try {
      draft?.reset(widget.currentValues?.call() ?? widget.values);
      setState(() => error = null);
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final firstTextField = widget.fields
        .where((f) => f.options == null && !f.checkbox)
        .firstOrNull;
    return SidePanel(
      title: widget.title,
      onClose: widget.onClose,
      children: [
        if (draft != null) DraftStatus(draft: draft!),
        if (widget.description != null) ...[
          Text(
            widget.description!,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
        ],
        for (final f in widget.fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: f.checkbox
                ? CheckboxListTile(
                    key: ValueKey('field-${f.key}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(f.label),
                    value: text[f.key]!.text == 'true',
                    onChanged: !f.enabled
                        ? null
                        : (value) =>
                              setState(() => text[f.key]!.text = '$value'),
                  )
                : f.options != null
                ? PlainSelect<String>(
                    key: ValueKey('field-${f.key}'),
                    value: text[f.key]!.text,
                    label: f.label,
                    options: [
                      for (final o in f.options!.entries)
                        SelectOption(o.key, o.value),
                    ],
                    onChanged: !f.enabled
                        ? null
                        : (v) => setState(() => text[f.key]!.text = v),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: ValueKey('field-${f.key}'),
                        controller: text[f.key],
                        autofocus: f == firstTextField,
                        maxLines: f.lines,
                        decoration: InputDecoration(
                          labelText: f.label,
                          alignLabelWithHint: f.lines > 1,
                        ),
                        onChanged: f.note == null
                            ? null
                            : (_) => setState(() {}),
                        onSubmitted: (_) => save(),
                      ),
                      if (f.note?.call(text[f.key]!.text) case final note?)
                        Padding(
                          key: ValueKey('field-note-${f.key}'),
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            note,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'Saving…' : widget.saveLabel),
              ),
              if (draft != null)
                TextButton(
                  onPressed: busy ? null : discard,
                  child: const Text('Discard draft'),
                ),
            ],
          ),
        ),
        ...widget.footer,
      ],
    );
  }
}

Map<String, String> _sectionSettings(Section section) => {
  'name': section.name,
  'format': section.format.name,
  'sideGames': '${section.sideGames}',
  'doubleGames': '${section.doubleGames}',
  'rrTable': section.rrTable,
  'doubleCycle': '${section.doubleCycle}',
  'accelerated': section.accelerated,
  'avoidTeammates': '${section.avoidTeammates}',
  'variations': (section.variations.toList()..sort()).join(', '),
  'rounds': '${section.plannedRounds}',
  'board': '${section.boardStart}',
  'timeControl': section.timeControl,
  'lastHalfByeRound':
      '${ByePolicy.fromJson(section.byeRules).lastHalfByeRound}',
  'maxHalfByes': '${ByePolicy.fromJson(section.byeRules).maxHalfByes}',
  'byeDeadline': '${ByePolicy.fromJson(section.byeRules).deadlineMinutes}',
  'irrevocableFromRound':
      '${ByePolicy.fromJson(section.byeRules).irrevocableFromRound}',
};

List<FieldSpec> _sectionFields({bool locked = false}) => [
  const FieldSpec('name', 'Name', required: true),
  FieldSpec(
    'format',
    'Pairing format',
    enabled: !locked,
    options: const {
      'swiss': 'Swiss',
      'quad': 'Quad',
      'roundRobin': 'Round robin',
    },
  ),
  FieldSpec('sideGames', 'Side games', checkbox: true, enabled: !locked),
  FieldSpec(
    'doubleGames',
    'Play both colors',
    checkbox: true,
    enabled: !locked,
  ),
  // Rule 30A / 30F: round robins only; a Swiss ignores both.
  FieldSpec(
    'rrTable',
    'Round-robin table',
    enabled: !locked,
    options: const {
      '': 'Circle method',
      crenshawTable: 'Crenshaw-Berger (Chapter 12)',
    },
  ),
  FieldSpec(
    'doubleCycle',
    'Double round robin: second cycle with colors reversed',
    checkbox: true,
    enabled: !locked,
  ),
  // Rules 28R1, 28N1 and the announced 29E variations: Swiss only.
  const FieldSpec(
    'accelerated',
    'Accelerated pairings (rule 28R)',
    options: {'': 'None', 'addedScore': 'Added score, rounds 1–2 (28R1)'},
  ),
  const FieldSpec(
    'avoidTeammates',
    'Keep team-mates apart, plus-two method (rule 28N1)',
    checkbox: true,
  ),
  const FieldSpec(
    'variations',
    'Announced pairing variations (29E4a, 29E4b, 29E4d, 29E5h)',
  ),
  const FieldSpec('rounds', 'Number of rounds', required: true),
  const FieldSpec('board', 'First board number', required: true),
  FieldSpec(
    'timeControl',
    'Time control (blank uses event default)',
    note: delayHint,
  ),
  // Rule 22C: the announced half-point bye policy.
  const FieldSpec(
    'lastHalfByeRound',
    'Last round for half-point byes (0 = any round, rule 22C1)',
  ),
  const FieldSpec(
    'maxHalfByes',
    'Half-point byes per player (0 = no limit, rule 22C3)',
  ),
  const FieldSpec(
    'byeDeadline',
    'Bye requests close, minutes before the round (rule 22C2)',
  ),
  const FieldSpec(
    'irrevocableFromRound',
    'Byes irrevocable from round (0 = never, rule 22C4)',
  ),
];

/// Validated values from the section fields.
({
  String name,
  Format format,
  bool sideGames,
  bool doubleGames,
  String rrTable,
  bool doubleCycle,
  String accelerated,
  bool avoidTeammates,
  Set<String> variations,
  int rounds,
  int board,
  String timeControl,
  Json byeRules,
})
_readSection(Map<String, String> v, {String previousControl = ''}) {
  final rounds = int.tryParse(v['rounds']!.trim()),
      board = int.tryParse(v['board']!.trim());
  if (rounds == null || rounds < 1 || rounds > 32) {
    throw const TournamentException(
      'Number of rounds must be between 1 and 32.',
    );
  }
  if (board == null || board < 1) {
    throw const TournamentException(
      'The first board number must be 1 or more.',
    );
  }
  final control = v['timeControl']!.trim();
  if (control.isNotEmpty && control != previousControl) {
    TimeControl.parse(control);
  }
  int byeNumber(String key, String label, {int blank = 0}) {
    final text = v[key]?.trim() ?? '';
    final n = text.isEmpty ? blank : int.tryParse(text);
    if (n == null || n < 0 || n > 999) {
      throw TournamentException('$label must be a whole number.');
    }
    return n;
  }

  final variations = {
    for (final code in (v['variations'] ?? '').split(RegExp(r'[,\s]+')))
      if (code.trim().isNotEmpty) code.trim(),
  };
  for (final code in variations) {
    if (!swissVariations.contains(code)) {
      throw TournamentException(
        'Unknown pairing variation "$code". Use ${swissVariations.join(', ')}.',
      );
    }
  }
  final policy = ByePolicy(
    lastHalfByeRound: byeNumber(
      'lastHalfByeRound',
      'Last round for half-point byes',
    ),
    maxHalfByes: byeNumber('maxHalfByes', 'Half-point byes per player'),
    deadlineMinutes: byeNumber(
      'byeDeadline',
      'The bye request deadline',
      blank: 60,
    ),
    irrevocableFromRound: byeNumber(
      'irrevocableFromRound',
      'Byes irrevocable from round',
    ),
  );
  if (policy.lastHalfByeRound > rounds ||
      policy.irrevocableFromRound > rounds) {
    throw TournamentException(
      'Bye policy rounds cannot exceed the $rounds planned rounds.',
    );
  }
  return (
    name: v['name']!.trim(),
    format: Format.values.byName(v['format']!),
    sideGames: v['sideGames'] == 'true',
    doubleGames: v['doubleGames'] == 'true',
    rrTable: v['rrTable'] ?? '',
    doubleCycle: v['doubleCycle'] == 'true',
    accelerated: v['accelerated'] ?? '',
    avoidTeammates: v['avoidTeammates'] == 'true',
    variations: variations,
    rounds: rounds,
    board: board,
    timeControl: control,
    byeRules: policy.toJson(),
  );
}

/// Name, length and board numbers of one section.
Widget sectionSettingsPanel(
  TournamentController c,
  String sectionId,
  VoidCallback onClose,
) {
  Section currentSection() {
    final section = c.event!.sections
        .where((s) => s.id == sectionId)
        .firstOrNull;
    if (section == null) {
      throw const TournamentException('This section no longer exists.');
    }
    return section;
  }

  // Built on each rebuild of the dock, so the title and the format lock
  // follow the section as rounds are posted or undone.
  return Builder(
    builder: (context) {
      final s = c.event!.sections.where((s) => s.id == sectionId).firstOrNull;
      if (s == null) {
        return SidePanel(
          key: ValueKey('section-settings-$sectionId'),
          title: 'Section removed',
          onClose: onClose,
          children: const [Text('This section no longer exists.')],
        );
      }
      return _sectionSettingsFields(c, s, currentSection, onClose);
    },
  );
}

Widget _sectionSettingsFields(
  TournamentController c,
  Section s,
  Section Function() currentSection,
  VoidCallback onClose,
) {
  final sectionId = s.id;
  // Rule 29K: a small Swiss with nearly everyone-plays-everyone rounds.
  final smallSwiss =
      s.format == Format.swiss &&
      s.players.length >= 2 &&
      s.players.length <= 6 &&
      s.plannedRounds >= s.players.length - 1 &&
      s.rounds.isEmpty;
  return FieldsPanel(
    key: ValueKey('section-settings-$sectionId'),
    controller: c,
    draftKey: 'draft-section-$sectionId',
    title: '${s.name} settings',
    description:
        'Choose how this section plays. A new first board number applies from the next round.'
        '${smallSwiss ? '\nRule 29K: a small Swiss with this many rounds can be run as a round robin; change the format before posting round 1.' : ''}',
    fields: _sectionFields(locked: s.rounds.isNotEmpty),
    footer: [
      if (s.format != Format.swiss && !s.sideGames && s.rounds.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (context) => OutlinedButton(
                key: const ValueKey('draw-lots'),
                onPressed: () {
                  try {
                    c.drawLots(sectionId);
                  } catch (e) {
                    showFailure(context, e);
                  }
                },
                child: const Text('Draw lots for pairing numbers (30A)'),
              ),
            ),
          ),
        ),
    ],
    values: _sectionSettings(s),
    currentValues: () => _sectionSettings(currentSection()),
    onClose: onClose,
    onSave: (v) {
      final current = currentSection();
      final n = _readSection(v, previousControl: current.timeControl);
      if (current.rounds.isNotEmpty &&
          (n.format != current.format ||
              n.sideGames != current.sideGames ||
              n.doubleGames != current.doubleGames ||
              n.rrTable != current.rrTable ||
              n.doubleCycle != current.doubleCycle)) {
        throw const TournamentException(
          'Pairing format cannot change after rounds are posted.',
        );
      }
      if (n.rounds < current.rounds.length) {
        throw TournamentException(
          '${current.rounds.length} rounds are already posted, so the section needs at least that many.',
        );
      }
      final next = current.copy(
        name: n.name,
        format: n.format,
        sideGames: n.sideGames,
        doubleGames: n.doubleGames,
        rrTable: n.rrTable,
        doubleCycle: n.doubleCycle,
        accelerated: n.accelerated,
        avoidTeammates: n.avoidTeammates,
        variations: n.variations,
        plannedRounds: n.rounds,
        boardStart: n.board,
        timeControl: n.timeControl,
        byeRules: n.byeRules,
      );
      if (next.rrTable == crenshawTable &&
          next.format == Format.roundRobin &&
          next.players.length > crenshawMaxPlayers) {
        throw TournamentException(
          'The Crenshaw-Berger tables cover 3 to $crenshawMaxPlayers players; this section has ${next.players.length}.',
        );
      }
      if (doubleCycleProblem(next) case final problem?) {
        throw TournamentException(problem);
      }
      c.change(
        'Edit section ${current.name}',
        c.event!.copy(
          sections: [
            for (final x in c.event!.sections) x.id == current.id ? next : x,
          ],
        ),
      );
    },
  );
}

/// Moves every player of one section into another.
class CombinePanel extends StatefulWidget {
  const CombinePanel({
    required this.controller,
    required this.sectionId,
    required this.onClose,
    super.key,
  });
  final TournamentController controller;
  final String sectionId;
  final VoidCallback onClose;
  @override
  State<CombinePanel> createState() => _CombinePanelState();
}

class _CombinePanelState extends State<CombinePanel> {
  String? target;
  final reason = TextEditingController();
  String? error;
  final targetText = TextEditingController();
  late FormDraft draft;
  @override
  void initState() {
    super.initState();
    draft = FormDraft(
      widget.controller.workspaceState,
      'draft-combine-${widget.sectionId}',
      {'target': targetText, 'reason': reason},
      {'target': '', 'reason': ''},
    );
    if (widget.controller.event!.sections.any(
      (s) => s.id == targetText.text && s.id != widget.sectionId,
    )) {
      target = targetText.text;
    }
  }

  @override
  void dispose() {
    draft.dispose();
    targetText.dispose();
    reason.dispose();
    super.dispose();
  }

  void combine() {
    if (target == null) {
      setState(() => error = 'Choose the section to combine into.');
      return;
    }
    try {
      // The roster as it is now, not as it was when the panel last built.
      final source = widget.controller.event!.sections
          .where((s) => s.id == widget.sectionId)
          .firstOrNull;
      if (source == null) {
        throw const TournamentException('This section no longer exists.');
      }
      widget.controller.movePlayers(
        source.players,
        target!,
        reason: reason.text.trim(),
      );
      draft.reset({"target": "", "reason": ""});
      widget.onClose();
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.controller.event!, colors = Theme.of(context).colorScheme;
    final source = e.sections
        .where((s) => s.id == widget.sectionId)
        .firstOrNull;
    if (source == null) return const SizedBox.shrink();
    final others = e.sections.where((s) => s.id != source.id).toList();
    return SidePanel(
      title: 'Combine ${source.name}',
      onClose: widget.onClose,
      children: [
        DraftStatus(draft: draft),
        Text(
          'Moves all ${source.players.length} players into the section you choose, which then pairs as a Swiss. Games and points already played are kept. Both sections must have played the same number of rounds.',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (others.isEmpty)
          const Text('There is no other section to combine into.')
        else
          RadioGroup<String>(
            groupValue: target,
            onChanged: (v) => setState(() {
              target = v;
              targetText.text = v ?? '';
              error = null;
            }),
            child: Column(
              children: [
                for (final s in others)
                  RadioListTile<String>(
                    key: ValueKey('combine-into-${s.id}'),
                    value: s.id,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(s.name),
                    subtitle: Text(
                      '${s.players.length} players · ${s.rounds.length} rounds played',
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('combine-reason'),
          controller: reason,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Reason (needed once rounds are played)',
          ),
          onSubmitted: (_) => combine(),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: others.isEmpty ? null : combine,
            child: const Text('Combine'),
          ),
        ),
      ],
    );
  }
}

/// A preview stays on its original revision until explicitly refreshed.
class PrintPanel extends StatefulWidget {
  const PrintPanel({
    required this.event,
    required this.kind,
    required this.onClose,
    this.controller,
    this.sectionId,
    this.roundNumber,
    this.roundNumbers,
    this.ceiling = 0,
    this.forPrizes = false,
    this.generate,
    this.printing,
    this.printNow = false,
    super.key,
  });
  final Event event;
  final TournamentController? controller;

  /// The printing service; tests pass their own.
  final RememberedPrinting? printing;

  /// Starts printing as soon as the panel opens, as when a direct print
  /// needs a printer chosen first.
  final bool printNow;
  final ReportKind kind;
  final String? sectionId;
  final int? roundNumber;
  final Map<String, int>? roundNumbers;
  final int ceiling;
  final bool forPrizes;
  final VoidCallback onClose;
  final Future<Uint8List> Function(Event event)? generate;
  @override
  State<PrintPanel> createState() => _PrintPanelState();
}

/// Binds generated bytes and stale-report approval to one event snapshot.
class _PrintPreviewJob {
  const _PrintPreviewJob(this.event, this.pdf, {this.approvedAtRevision});
  final Event event;
  final Future<Uint8List> pdf;
  final int? approvedAtRevision;

  bool isStale(int? currentRevision) =>
      currentRevision != null && currentRevision != event.revision;

  bool canPrint(int? currentRevision) =>
      !isStale(currentRevision) || approvedAtRevision == currentRevision;

  _PrintPreviewJob approve(int? currentRevision) =>
      _PrintPreviewJob(event, pdf, approvedAtRevision: currentRevision);
}

class _PrintPanelState extends State<PrintPanel> {
  late _PrintPreviewJob preview = createPreview(widget.event);

  /// Rule 28J TD TIP: a by-name list after each round's board table.
  bool alphabetical = false;
  Event get snapshot => preview.event;
  bool printing = false;
  String? savedPath;
  int? get currentRevision => widget.controller?.event?.revision;
  bool get stale => preview.isStale(currentRevision);

  _PrintPreviewJob createPreview(Event event) =>
      _PrintPreviewJob(event, generate(event));

  /// Printers to choose from, shown in the panel while a print waits for
  /// one; [choosing] completes with the TD's choice, or null for Cancel.
  List<Printer>? printers;
  Printer? printer;
  Completer<Printer?>? choosing;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(changed);
    if (widget.printNow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) printPreview();
      });
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller?.removeListener(changed);
    choosing?.complete(null);
    choosing = null;
    super.dispose();
  }

  Future<Printer?> choosePrinter(List<Printer> available) {
    if (!mounted) return Future.value(null);
    choosing?.complete(null);
    final choice = choosing = Completer<Printer?>();
    setState(() {
      printers = available;
      printer =
          available.where((p) => p.url == printer?.url).firstOrNull ??
          available.where((p) => p.isDefault).firstOrNull ??
          available.first;
    });
    return choice.future;
  }

  void finishChoice(Printer? chosen) {
    final choice = choosing;
    choosing = null;
    setState(() => printers = null);
    choice?.complete(chosen);
  }

  Future<Uint8List> generate(Event event) async {
    if (widget.generate != null) return widget.generate!(event);
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-SemiBold.ttf'),
    );
    return reportPdf(
      event,
      widget.kind,
      sectionId: widget.sectionId,
      roundNumber: widget.roundNumber,
      roundNumbers: widget.roundNumbers,
      ceiling: widget.ceiling,
      forPrizes: widget.forPrizes,
      alphabetical: alphabetical,
      font: font,
      bold: bold,
    );
  }

  Future<void> printPreview({bool changePrinter = false}) async {
    if (printing) return;
    final job = preview;
    bool canSend() =>
        mounted && identical(preview, job) && job.canPrint(currentRevision);
    if (!canSend()) return;
    setState(() => printing = true);
    try {
      final bytes = await job.pdf;
      if (!mounted || !canSend()) return;
      await sendToPrinter(
        context,
        bytes,
        job.event.name,
        changePrinter: changePrinter,
        canSend: canSend,
        choose: choosePrinter,
        printing: widget.printing,
      );
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  void refresh() => setState(() {
    preview = createPreview(widget.controller?.event ?? snapshot);
  });

  /// Standings as a spreadsheet or the plain-text crosstable, from the same
  /// revision as the preview.
  Future<void> saveFile({required bool csv}) async {
    final e = snapshot;
    try {
      final path = csv
          ? await saveArtifact(
              'standings-r${e.revision}.csv',
              utf8.encode(standingsCsv(e, sectionId: widget.sectionId)),
            )
          : widget.kind == ReportKind.prizes
          ? await saveArtifact(
              'prizes-r${e.revision}.txt',
              utf8.encode(prizeReport(e, sectionId: widget.sectionId)),
            )
          : await saveArtifact(
              'crosstable-r${e.revision}.txt',
              crosstable(
                e,
                asciiOnly: true,
                sectionId: widget.sectionId,
              ).codeUnits,
            );
      if (path != null && mounted) setState(() => savedPath = path);
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = snapshot.sections
        .where((s) => s.id == widget.sectionId)
        .firstOrNull;
    final what = switch (widget.kind) {
      ReportKind.sections => 'Player list',
      ReportKind.packet || ReportKind.pairings => 'Pairing sheets',
      ReportKind.standings => 'Standings',
      ReportKind.crosstable => 'Crosstable',
      ReportKind.prizes => 'Prizes',
      ReportKind.conditions => 'Event conditions',
    };
    final ranking =
        widget.kind == ReportKind.standings ||
        widget.kind == ReportKind.crosstable ||
        widget.kind == ReportKind.prizes;
    final pairingSheet =
        widget.kind == ReportKind.packet || widget.kind == ReportKind.pairings;
    final scopedSections = snapshot.sections.where(
      (s) =>
          (widget.sectionId == null || s.id == widget.sectionId) &&
          (widget.roundNumbers == null ||
              widget.roundNumbers!.containsKey(s.id)),
    );
    String scopeLabel(Section s) {
      if (widget.kind == ReportKind.conditions) return 'Whole event';
      if (widget.kind == ReportKind.sections) {
        return '${s.players.length} ${s.players.length == 1 ? 'player' : 'players'}';
      }
      if (pairingSheet && pairingFormat(s) != Format.swiss && !s.sideGames) {
        return 'All rounds';
      }
      final number =
          widget.roundNumbers?[s.id] ??
          widget.roundNumber ??
          s.rounds.lastOrNull?.number ??
          0;
      return number == 0 ? 'Before round 1' : 'Round $number';
    }

    final labels = scopedSections.map(scopeLabel).toSet();
    final canPrint = preview.canPrint(currentRevision);
    return SidePanel(
      key: const ValueKey('print-panel'),
      title: '$what · ${section?.name ?? 'all sections'}',
      width: 480,
      scrolls: false,
      onClose: widget.onClose,
      children: [
        LayoutBuilder(
          builder: (context, layout) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: layout.maxHeight * 0.5),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (ranking) ...[
                          SegmentedButton<ReportKind>(
                            key: const ValueKey('print-ranking-kind'),
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: ReportKind.standings,
                                label: Text('Standings'),
                              ),
                              ButtonSegment(
                                value: ReportKind.crosstable,
                                label: Text('Crosstable'),
                              ),
                              ButtonSegment(
                                value: ReportKind.prizes,
                                label: Text('Prizes'),
                              ),
                            ],
                            selected: {widget.kind},
                            onSelectionChanged: (kind) => showPrint(
                              context,
                              widget.controller?.event ?? snapshot,
                              sectionId: widget.sectionId,
                              ceiling: widget.ceiling,
                              forPrizes: widget.forPrizes,
                              kind: kind.single,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        // What is on the paper, per section when rounds differ.
                        Text(
                          labels.length == 1
                              ? labels.single
                              : [
                                  for (final s in scopedSections)
                                    '${s.name}: ${scopeLabel(s)}',
                                ].join('\n'),
                          key: const ValueKey('print-scope'),
                        ),
                        const SizedBox(height: 8),
                        if (printers case final available?) ...[
                          // The first print, or Choose printer…, asks here.
                          PlainSelect<Printer?>(
                            key: const ValueKey('print-printer'),
                            label: 'Printer',
                            value: printer,
                            options: [
                              for (final p in available)
                                SelectOption(p, p.name),
                            ],
                            onChanged: (p) => setState(() => printer = p),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton.icon(
                                key: const ValueKey('print-to-printer'),
                                onPressed: printer == null
                                    ? null
                                    : () => finishChoice(printer),
                                icon: const Icon(Icons.print_outlined),
                                label: const Text('Print'),
                              ),
                              TextButton(
                                key: const ValueKey('print-cancel-printer'),
                                onPressed: () => finishChoice(null),
                                child: const Text('Cancel'),
                              ),
                            ],
                          ),
                        ] else
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton.icon(
                                key: const ValueKey('print-preview'),
                                onPressed: canPrint && !printing
                                    ? printPreview
                                    : null,
                                icon: const Icon(Icons.print_outlined),
                                label: Text(printing ? 'Printing…' : 'Print'),
                              ),
                              TextButton(
                                onPressed: canPrint && !printing
                                    ? () => printPreview(changePrinter: true)
                                    : null,
                                child: const Text('Choose printer…'),
                              ),
                            ],
                          ),
                        if (ranking) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (widget.kind != ReportKind.prizes)
                                TextButton(
                                  key: const ValueKey('save-standings-csv'),
                                  onPressed: () => saveFile(csv: true),
                                  child: const Text('Save CSV'),
                                ),
                              TextButton(
                                key: const ValueKey('save-crosstable-text'),
                                onPressed: () => saveFile(csv: false),
                                child: Text(
                                  widget.kind == ReportKind.prizes
                                      ? 'Save text prize report'
                                      : 'Save text crosstable',
                                ),
                              ),
                            ],
                          ),
                          if (savedPath != null)
                            SelectableText(
                              'Saved to $savedPath',
                              key: const ValueKey('print-saved'),
                            ),
                        ],
                        if (pairingSheet)
                          CheckboxListTile(
                            key: const ValueKey('print-alphabetical'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('Also list each round by name'),
                            value: alphabetical,
                            onChanged: printing
                                ? null
                                : (v) {
                                    alphabetical = v ?? false;
                                    refresh();
                                  },
                          ),
                        if (widget.ceiling > 0)
                          Text('Prize class: Under ${widget.ceiling}'),
                        if (widget.forPrizes)
                          const Text('Excluding early round-robin withdrawals'),
                        if (stale) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Out of date — the event has changed.',
                            key: ValueKey('print-stale'),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: refresh,
                                child: const Text('Refresh preview'),
                              ),
                              if (!canPrint)
                                TextButton(
                                  onPressed: () => setState(
                                    () => preview = preview.approve(
                                      currentRevision,
                                    ),
                                  ),
                                  child: const Text('Print older version'),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<Uint8List>(
                  future: preview.pdf,
                  builder: (context, result) {
                    if (result.connectionState != ConnectionState.done) {
                      return const Center(child: Text('Preparing…'));
                    }
                    if (result.hasError) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              'Could not make the PDF. ${plainMessage(result.error!)}',
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                preview = createPreview(snapshot);
                              }),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      );
                    }
                    if (!result.hasData) {
                      return const Center(child: Text('Preparing…'));
                    }
                    return PdfPreview(
                      build: (_) => result.data!,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      canDebug: false,
                      allowSharing: false,
                      allowPrinting: false,
                      useActions: false,
                      scrollViewDecoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                      ),
                      pdfFileName: 'meow-r${snapshot.revision}.pdf',
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void showPrint(
  BuildContext context,
  Event event, {
  String? sectionId,
  int? roundNumber,
  int ceiling = 0,
  bool forPrizes = false,
  ReportKind kind = ReportKind.packet,
  bool printNow = false,
  DockController? dock,
}) {
  dock ??= Dock.maybeOf(context);
  if (dock == null) return;
  // Freeze the round too: refreshing must not silently switch to a new round.
  final scoped = event.sections.where(
    (s) =>
        (sectionId == null || s.id == sectionId) &&
        (roundNumber == null || s.rounds.any((r) => r.number == roundNumber)),
  );
  final numbers = scoped
      .map((s) => s.rounds.lastOrNull?.number)
      .whereType<int>()
      .toSet();
  final number = roundNumber ?? (numbers.length == 1 ? numbers.single : null);
  dock.show(
    ('print', kind, sectionId, number, event.revision),
    PrintPanel(
      key: ValueKey(('print', kind, sectionId, number, event.revision)),
      event: event,
      controller: dock.tournament,
      kind: kind,
      sectionId: sectionId,
      roundNumber: number,
      roundNumbers: {
        for (final s in scoped)
          s.id: roundNumber ?? s.rounds.lastOrNull?.number ?? 0,
      },
      ceiling: ceiling,
      forPrizes: forPrizes,
      printNow: printNow,
      onClose: dock.close,
    ),
  );
}

/// Where a player is: a large, read-only answer to "where am I playing?",
/// readable by the player standing across the table.
class LookupPanel extends StatefulWidget {
  const LookupPanel({
    required this.controller,
    required this.onClose,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;
  @override
  State<LookupPanel> createState() => _LookupPanelState();
}

class _LookupPanelState extends State<LookupPanel> {
  final query = TextEditingController();
  final queryFocus = FocusNode(debugLabel: 'player-lookup');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) queryFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    query.dispose();
    queryFocus.dispose();
    super.dispose();
  }

  List<Player> matches(Event e) {
    final q = query.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final words = q.split(RegExp(r'\s+'));
    return e.players
        .where(
          (p) =>
              p.memberId == q ||
              (q.startsWith('#') &&
                  e.sectionOf(p.id) != null &&
                  int.tryParse(q.substring(1)) ==
                      e.sectionOf(p.id)!.players.indexOf(p.id) + 1) ||
              words.every((w) => p.name.toLowerCase().contains(w)),
        )
        .toList();
  }

  int? nextBye(Section s, Player p) {
    final rounds =
        p.byes.keys
            .where((n) => n > s.rounds.length && n <= s.plannedRounds)
            .toList()
          ..sort();
    return rounds.firstOrNull;
  }

  String ratingScore(Event e, Section s, Player p) {
    final points =
        standings(e, s).where((r) => r.player.id == p.id).firstOrNull?.points ??
        0;
    return points.isOdd
        ? '${points ~/ 2 == 0 ? '' : points ~/ 2}½'
        : '${points ~/ 2}';
  }

  /// This round for [p]: board and opponent, a bye, or why neither.
  (String, String?) answer(Event e, Player p) {
    final s = e.sectionOf(p.id);
    if (p.withdrawn) return ('Withdrawn', s?.name);
    if (s == null) return ('Not in a section yet', null);
    final r = s.rounds.lastOrNull;
    if (r == null) return ('Not paired yet', s.name);
    final bye = r.byes.where((b) => b.player == p.id).firstOrNull;
    final where = '${s.name} · round ${r.number}';
    if (bye != null) {
      return (
        'Bye this round · ${bye.points == 2
            ? '1 point'
            : bye.points == 1
            ? '½ point'
            : 'no points'}',
        where,
      );
    }
    final g = r.games
        .where((g) => g.white == p.id || g.black == p.id)
        .firstOrNull;
    if (g == null) return ('Not paired this round', where);
    final white = g.white == p.id;
    final opponent = e.player(white ? g.black : g.white);
    return (
      'Board ${g.board} · ${white ? 'White' : 'Black'} vs ${opponent.name}',
      where,
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.controller.event!, colors = Theme.of(context).colorScheme;
    final found = matches(e);
    return SidePanel(
      key: const ValueKey('lookup-panel'),
      title: 'Find player',
      width: 480,
      onClose: widget.onClose,
      children: [
        TextField(
          key: const ValueKey('lookup-query'),
          controller: query,
          focusNode: queryFocus,
          autofocus: true,
          style: const TextStyle(fontSize: 20),
          decoration: const InputDecoration(
            labelText: 'Name, US Chess ID or #number',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        if (query.text.trim().isNotEmpty && found.isEmpty)
          Text(
            'No player matches “${query.text.trim()}”.',
            style: TextStyle(fontSize: 18, color: colors.onSurfaceVariant),
          ),
        if (found.isNotEmpty)
          Text(
            '${found.length} ${found.length == 1 ? 'match' : 'matches'}${found.length > 20 ? ' · showing the first 20; refine your search' : ''}',
          ),
        for (final p in found.take(20)) ...[
          Semantics(
            container: true,
            child: Padding(
              key: ValueKey('lookup-${p.id}'),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Builder(
                builder: (context) {
                  final (main, where) = answer(e, p);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        'US Chess ID: ${p.memberId.isEmpty ? 'not recorded' : p.memberId}',
                      ),
                      if (e.sectionOf(p.id) case final section?) ...[
                        Text(
                          'Pairing #${section.players.indexOf(p.id) + 1} · Score ${ratingScore(e, section, p)}',
                        ),
                        if (nextBye(section, p) case final round?)
                          Text(
                            'Round $round bye: ${p.byes[round] == 1 ? '½' : p.byes[round]! ~/ 2} point${p.byes[round] == 2 ? '' : 's'}',
                          ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        main,
                        style: const TextStyle(fontSize: 24, height: 1.25),
                      ),
                      if (where != null)
                        Text(
                          where,
                          style: TextStyle(
                            fontSize: 16,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          Divider(color: colors.outlineVariant),
        ],
      ],
    );
  }
}

/// First print chooses a device, through [choose]; subsequent prints use
/// it directly.
Future<void> sendToPrinter(
  BuildContext context,
  Uint8List bytes,
  String name, {
  required Future<Printer?> Function(List<Printer>) choose,
  bool changePrinter = false,
  bool Function()? canSend,
  RememberedPrinting? printing,
}) async {
  Object? preferenceError;
  final success = await (printing ?? RememberedPrinting.shared).print(
    bytes,
    name,
    changePrinter: changePrinter,
    canSend: canSend,
    onPreferenceError: (error) => preferenceError = error,
    choose: choose,
  );
  if (context.mounted && success && preferenceError != null) {
    showFailure(
      context,
      const TournamentException(
        'Sent to printer, but the printer preference could not be saved. Choose the printer again next time.',
      ),
    );
  }
}

Future<void> printSheets(
  BuildContext context,
  Event event, {
  String? sectionId,
  int? roundNumber,
  bool currentRoundOnly = false,
  int ceiling = 0,
  bool forPrizes = false,
  ReportKind kind = ReportKind.sections,
  DockController? dock,
  RememberedPrinting? printing,
}) async {
  try {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-SemiBold.ttf'),
    );
    final bytes = await reportPdf(
      event,
      kind,
      sectionId: sectionId,
      roundNumber: roundNumber,
      currentRoundOnly: currentRoundOnly,
      ceiling: ceiling,
      forPrizes: forPrizes,
      font: font,
      bold: bold,
    );
    if (!context.mounted) return;
    await sendToPrinter(
      context,
      bytes,
      event.name,
      printing: printing,
      // No printer remembered yet: choose one in the print panel, which
      // prints as soon as it opens.
      choose: (_) async {
        if (context.mounted) {
          showPrint(
            context,
            event,
            sectionId: sectionId,
            roundNumber: roundNumber,
            ceiling: ceiling,
            forPrizes: forPrizes,
            kind: kind,
            printNow: true,
            dock: dock,
          );
        }
        return null;
      },
    );
  } catch (e) {
    if (context.mounted) showFailure(context, e);
  }
}
