import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../application/diagnostics.dart';
import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/pairing.dart';
import '../domain/standings.dart';
import '../infrastructure/artifact_save.dart';
import '../infrastructure/reports.dart';
import '../infrastructure/remembered_printing.dart';
import 'dialogs.dart' show FieldSpec, showFailure;
import 'drafts.dart';
import 'side_panel.dart';
import 'select.dart';
import 'theme.dart' show noChipAnimation;
import 'workspace_status.dart' show showUndoNotice;

export 'section_panel.dart' show sectionSettingsPanel;

/// What a direct print is doing, for the workspace's status line.
class PrintStatus {
  const PrintStatus(this.message, {this.sending = false});
  final String message;

  /// Whether the job is still on its way: another print waits for it.
  final bool sending;
}

/// The tool docked at the right of the workspace: one at a time, beside
/// the table it acts on, never over it.
class DockController extends ChangeNotifier {
  DockController({this.tournament});
  final TournamentController? tournament;
  FocusNode? _returnFocus;

  /// The direct print in flight or just sent, or null: one at a time, shown
  /// in the workspace's status line.
  final printStatus = ValueNotifier<PrintStatus?>(null);
  bool _disposed = false;

  /// A print may finish after the workspace it started in has closed.
  void reportPrint(PrintStatus? status) {
    if (!_disposed) printStatus.value = status;
  }

  Object? _guardOwner;
  bool Function()? _leaveGuard;

  /// Lets the panel showing now have its say before it is closed or
  /// replaced: [canLeave] saves what the panel holds and answers true, or
  /// answers false to stay open on a problem it now shows. [owner] is the
  /// panel's state, which calls [clearLeaveGuard] as it is disposed.
  void setLeaveGuard(Object owner, bool Function() canLeave) {
    _guardOwner = owner;
    _leaveGuard = canLeave;
  }

  /// Withdraws [owner]'s guard; one set since by another panel stays.
  void clearLeaveGuard(Object owner) {
    if (!identical(_guardOwner, owner)) return;
    _guardOwner = null;
    _leaveGuard = null;
  }

  /// Asks the panel showing now to save and go. False means it stays open,
  /// and whatever was about to replace it must not.
  bool canLeave() {
    final guard = _leaveGuard;
    if (guard == null) return true;
    // A panel can neither save nor show a problem while the tree is being
    // built; what it holds stays its draft.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      return true;
    }
    return guard();
  }

  /// Claims the same panel slot for a view's embedded player editor. False
  /// when the panel showing now would not leave.
  bool claim(Object owner) {
    if (id == owner) return true;
    return show(owner, null);
  }

  /// Opens [owner] from inside the panel showing now, as a step away
  /// from it: the opened panel's header names [backLabel], and closing it
  /// brings this panel back, rebuilt from its draft. [onBack] runs just
  /// before it rebuilds, so it can leave word of where to land.
  void detour(Object owner, {required String backLabel, VoidCallback? onBack}) {
    if (id == owner) return;
    final from = (id: id, panel: panel, label: backLabel, onBack: onBack);
    // The panel left behind comes back with its draft, so it is not asked
    // to save first.
    _replace(owner, null);
    if (from.id != null) _back = from;
  }

  ({Object? id, Widget? panel, String label, VoidCallback? onBack})? _back;

  /// Set while a [detour] is showing: what closing it returns to.
  String? get backLabel => _back?.label;

  Widget? panel;

  /// What [panel] is for, so asking for it again toggles it closed.
  Object? id;

  /// Shows [panel] in place of the one showing now. False, changing nothing,
  /// when that one would not leave (see [setLeaveGuard]).
  bool show(Object id, Widget? panel) {
    if (!canLeave()) return false;
    _replace(id, panel);
    return true;
  }

  void _replace(Object id, Widget? panel) {
    if (this.id == null) _returnFocus = FocusManager.instance.primaryFocus;
    _back = null;
    this.id = id;
    this.panel = panel == null || tournament == null
        ? panel
        : _LivePanel(tournament: tournament!, child: panel);
    notifyListeners();
  }

  /// Closes the panel showing now. False, changing nothing, when it would
  /// not leave (see [setLeaveGuard]).
  bool close() {
    if (!canLeave()) return false;
    if (_back case final back?) {
      _back = null;
      back.onBack?.call();
      id = back.id;
      panel = back.panel;
      notifyListeners();
      return true;
    }
    if (id == null) return true;
    id = panel = null;
    notifyListeners();
    final focus = _returnFocus;
    _returnFocus = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (focus?.context != null && focus!.canRequestFocus) {
        focus.requestFocus();
      }
    });
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    printStatus.dispose();
    super.dispose();
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

/// Moves every player of one section into another. A section that has not
/// been paired goes with them; one with played rounds keeps those rounds
/// and stays, empty.
class CombinePanel extends StatefulWidget {
  const CombinePanel({
    required this.controller,
    required this.sectionId,
    required this.onClose,
    this.onCombined,
    super.key,
  });
  final TournamentController controller;
  final String sectionId;
  final VoidCallback onClose;

  /// Closes the panel after combining, given the section the players went
  /// to; [onClose] when null.
  final ValueChanged<String>? onCombined;
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
      final c = widget.controller, into = target!;
      final destination = c.event!.sections
          .where((s) => s.id == into)
          .firstOrNull
          ?.name;
      c.movePlayers(source.players, into, reason: reason.text.trim());
      // With no rounds of its own the emptied section has nothing left to
      // show. Its removal is a second step in History.
      var removed = false;
      if (source.rounds.isEmpty) {
        try {
          c.removeSection(source.id);
          removed = true;
        } on TournamentException {
          // The players have moved; the empty tab can still be deleted.
        }
      }
      draft.reset({"target": "", "reason": ""});
      final where = destination ?? 'the other section';
      showUndoNotice(
        context,
        c,
        removed
            ? 'Combined ${source.name} into $where and removed the empty '
                  '${source.name} tab. Undo brings the tab back; undo again '
                  'to move the players back.'
            : 'Combined ${source.name} into $where.',
      );
      (widget.onCombined ?? (_) => widget.onClose())(into);
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  /// What Combine will do, in the words of the sections chosen.
  List<String> preview(Section source, Section? into) {
    final n = source.players.length;
    final players = n == 1 ? 'the 1 player' : 'all $n players';
    final to = into?.name ?? 'the section you choose';
    if (source.rounds.isEmpty) {
      return [
        'Moves $players of ${source.name} into $to and removes the '
            '${source.name} tab, which would be left empty.',
        'Both sections must be unpaired, or have played the same number of '
            'rounds.',
      ];
    }
    return [
      'Moves $players of ${source.name} into $to, which pairs as a Swiss '
          'from the next round. Games and points already played are kept.',
      '${source.name} keeps its played rounds and stays as an empty tab.',
      'After this the US Chess rating report cannot be made from this '
          'event: it cannot yet report players who changed section once '
          'play had started.',
      'Both sections must have played the same number of rounds, with '
          'every result in.',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.controller.event!, colors = Theme.of(context).colorScheme;
    final source = e.sections
        .where((s) => s.id == widget.sectionId)
        .firstOrNull;
    if (source == null) return const SizedBox.shrink();
    final others = e.sections.where((s) => s.id != source.id).toList();
    final into = others.where((s) => s.id == target).firstOrNull;
    return SidePanel(
      title: 'Combine ${source.name}',
      onClose: widget.onClose,
      children: [
        DraftStatus(draft: draft),
        Column(
          key: const ValueKey('combine-preview'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final line in preview(source, into))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  line,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
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
  const _PrintPreviewJob(
    this.event,
    this.pdf, {
    required this.a4,
    this.approvedAtRevision,
  });
  final Event event;
  final Future<Uint8List> pdf;

  /// The paper [pdf] is laid out for.
  final bool a4;
  final int? approvedAtRevision;

  bool isStale(int? currentRevision) =>
      currentRevision != null && currentRevision != event.revision;

  bool canPrint(int? currentRevision) =>
      !isStale(currentRevision) || approvedAtRevision == currentRevision;

  _PrintPreviewJob approve(int? currentRevision) =>
      _PrintPreviewJob(event, pdf, a4: a4, approvedAtRevision: currentRevision);
}

class _PrintPanelState extends State<PrintPanel> {
  late _PrintPreviewJob preview = createPreview(widget.event);

  /// Rule 28J TD TIP: a by-name list after each round's board table.
  bool alphabetical = false;

  RememberedPrinting get service =>
      widget.printing ?? RememberedPrinting.shared;
  Event get snapshot => preview.event;
  bool printing = false;
  String? savedPath;

  /// Set when the last print went out on other paper than the preview.
  String? paperNote;
  int? get currentRevision => widget.controller?.event?.revision;
  bool get stale => preview.isStale(currentRevision);

  // A preview replaced before it was shown is never listened to; its error
  // (such as nothing to print) is shown by the preview that is, not raised
  // as an unhandled one. Found by the UI fuzzer.
  _PrintPreviewJob createPreview(Event event) {
    final a4 = service.a4;
    return _PrintPreviewJob(event, generate(event, a4: a4)..ignore(), a4: a4);
  }

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

  Future<void> changePaper(bool value) async {
    final saved = service.setPaper(value);
    refresh();
    try {
      await saved;
    } catch (error, stack) {
      Diagnostics.record(
        'save paper size',
        'failed',
        error: error,
        stack: stack,
      );
      if (mounted) {
        showFailure(
          context,
          const TournamentException(
            'The paper size could not be saved. Choose it again next time.',
          ),
        );
      }
    }
  }

  /// Printers come from the computer; one added while the panel waits shows
  /// up here without starting the print over.
  Future<void> refreshPrinters() async {
    try {
      final found = await service.available();
      if (!mounted || choosing == null) return;
      if (found.isEmpty) {
        throw const TournamentException(
          'No printers are available. Add one in this computer\'s printer '
          'settings, or use Save PDF.',
        );
      }
      setState(() {
        printers = found;
        printer =
            found.where((p) => p.url == printer?.url).firstOrNull ??
            found.where((p) => p.isDefault).firstOrNull ??
            found.first;
      });
    } catch (e) {
      if (mounted) showFailure(context, e);
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

  Future<Uint8List> generate(Event event, {required bool a4}) async {
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
      a4: a4,
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
        builtA4: job.a4,
        relayout: (a4) => generate(job.event, a4: a4),
      );
      notePaper(job);
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  void notePaper(_PrintPreviewJob job) {
    final printed = service.printedA4;
    if (!mounted) return;
    setState(() {
      paperNote = printed == null || printed == job.a4
          ? null
          : 'Printed on ${printed ? 'A4' : 'Letter'} to match the printer.';
    });
  }

  /// The computer's own print window, for copies, two-sided printing and
  /// trays. Opened only by asking for it.
  Future<void> printWithDialog() async {
    if (printing) return;
    final job = preview;
    bool canSend() =>
        mounted && identical(preview, job) && job.canPrint(currentRevision);
    if (!canSend()) return;
    setState(() => printing = true);
    try {
      final bytes = await job.pdf;
      if (!mounted || !canSend()) return;
      await service.printWithDialog(
        bytes,
        job.event.name,
        canSend: canSend,
        builtA4: job.a4,
        relayout: (a4) => generate(job.event, a4: a4),
      );
      notePaper(job);
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  /// The previewed PDF as a file, to print from another computer or to send.
  Future<void> savePdf() async {
    final job = preview;
    try {
      final what = switch (widget.kind) {
        ReportKind.sections => 'player-list',
        ReportKind.packet || ReportKind.pairings => 'pairing-sheets',
        ReportKind.standings => 'standings',
        ReportKind.crosstable => 'crosstable',
        ReportKind.wallChart => 'wall-chart',
        ReportKind.prizes => 'prizes',
        ReportKind.conditions => 'event-conditions',
      };
      final path = await saveArtifact(
        '$what-r${job.event.revision}.pdf',
        await job.pdf,
      );
      if (path != null && mounted) setState(() => savedPath = path);
    } catch (e) {
      if (mounted) showFailure(context, e);
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
          : widget.kind == ReportKind.wallChart
          ? await saveArtifact(
              'wall-chart-r${e.revision}.txt',
              wallChart(
                e,
                asciiOnly: true,
                sectionId: widget.sectionId,
              ).codeUnits,
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
      ReportKind.wallChart => 'Wall chart',
      ReportKind.prizes => 'Prizes',
      ReportKind.conditions => 'Event conditions',
    };
    final ranking =
        widget.kind == ReportKind.standings ||
        widget.kind == ReportKind.crosstable ||
        widget.kind == ReportKind.wallChart ||
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
      if (pairingSheet && hasFixedSchedule(s) && !s.sideGames) {
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
                          // Each sheet is a whole word on its own chip, and
                          // the chips wrap: equal segments in one row broke
                          // "Crosstable" across two lines in this column.
                          Wrap(
                            key: const ValueKey('print-ranking-kind'),
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final (kind, label) in const [
                                (ReportKind.standings, 'Standings'),
                                (ReportKind.crosstable, 'Crosstable'),
                                (ReportKind.wallChart, 'Wall chart'),
                                (ReportKind.prizes, 'Prizes'),
                              ])
                                ChoiceChip(
                                  key: ValueKey('print-kind-${kind.name}'),
                                  chipAnimationStyle: noChipAnimation,
                                  label: Text(label, softWrap: false),
                                  selected: widget.kind == kind,
                                  onSelected: (_) {
                                    if (kind == widget.kind) return;
                                    showPrint(
                                      context,
                                      widget.controller?.event ?? snapshot,
                                      sectionId: widget.sectionId,
                                      ceiling: widget.ceiling,
                                      forPrizes: widget.forPrizes,
                                      kind: kind,
                                    );
                                  },
                                ),
                            ],
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
                              TextButton(
                                key: const ValueKey('print-refresh-printers'),
                                onPressed: refreshPrinters,
                                child: const Text('Refresh list'),
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
                              // A browser's Print already opens its own window.
                              if (!kIsWeb)
                                TextButton(
                                  key: const ValueKey('print-system-dialog'),
                                  onPressed: canPrint && !printing
                                      ? printWithDialog
                                      : null,
                                  child: const Text('Copies and options…'),
                                ),
                              TextButton(
                                key: const ValueKey('save-pdf'),
                                onPressed: canPrint ? savePdf : null,
                                child: const Text('Save PDF'),
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
                        ],
                        if (savedPath != null)
                          SelectableText(
                            'Saved to $savedPath',
                            key: const ValueKey('print-saved'),
                          ),
                        if (paperNote case final note?)
                          Text(note, key: const ValueKey('print-paper-note')),
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
                        const SizedBox(height: 8),
                        PlainSelect<bool>(
                          key: const ValueKey('print-paper'),
                          label: 'Paper',
                          value: service.a4,
                          options: const [
                            SelectOption(false, 'Letter'),
                            SelectOption(true, 'A4'),
                          ],
                          onChanged: printing
                              ? null
                              : (value) {
                                  if (value != service.a4) changePaper(value);
                                },
                        ),
                        if (widget.ceiling > 0)
                          Text('Prize class: Under ${widget.ceiling}'),
                        if (widget.forPrizes)
                          const Text('Excluding early round-robin withdrawals'),
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
  RememberedPrinting? printing,
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
      printing: printing,
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
/// it directly. True once the job has gone to a printer.
Future<bool> sendToPrinter(
  BuildContext context,
  Uint8List bytes,
  String name, {
  required Future<Printer?> Function(List<Printer>) choose,
  bool changePrinter = false,
  bool Function()? canSend,
  RememberedPrinting? printing,
  bool? builtA4,
  Future<Uint8List> Function(bool a4)? relayout,
}) async {
  Object? preferenceError;
  final success = await (printing ?? RememberedPrinting.shared).print(
    bytes,
    name,
    builtA4: builtA4,
    relayout: relayout,
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
  return success;
}

/// Prints straight to the remembered printer, saying so in the workspace's
/// status line from the first press until the job has gone: a job can take
/// minutes, and a second press meanwhile is answered there, not printed.
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
  final service = printing ?? RememberedPrinting.shared;
  final panels = dock ?? Dock.maybeOf(context);
  // The printer's name, once known, for "Sending to …" and "Sent to …".
  String? printer;
  String sending() =>
      printer == null ? 'Sending to the printer…' : 'Sending to $printer…';
  if (panels?.printStatus.value?.sending ?? false) {
    final now = panels!.printStatus.value!.message;
    panels.reportPrint(
      PrintStatus(
        now.startsWith('Already printing') ? now : 'Already printing · $now',
        sending: true,
      ),
    );
    return;
  }
  panels?.reportPrint(PrintStatus(sending(), sending: true));
  var sent = false;
  try {
    try {
      printer = (await service.preference.read())?.name;
    } catch (_) {
      // The print itself reports a preference it cannot read.
    }
    if (printer != null && (panels?.printStatus.value?.sending ?? false)) {
      panels?.reportPrint(PrintStatus(sending(), sending: true));
    }
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-SemiBold.ttf'),
    );
    Future<Uint8List> sheet(bool a4) => reportPdf(
      event,
      kind,
      sectionId: sectionId,
      roundNumber: roundNumber,
      currentRoundOnly: currentRoundOnly,
      ceiling: ceiling,
      forPrizes: forPrizes,
      a4: a4,
      font: font,
      bold: bold,
    );
    final a4 = service.a4;
    final bytes = await sheet(a4);
    if (!context.mounted) return;
    sent = await sendToPrinter(
      context,
      bytes,
      event.name,
      printing: printing,
      builtA4: a4,
      relayout: sheet,
      // No printer remembered yet: choose one in the print panel, which
      // prints as soon as it opens.
      choose: (_) async {
        // The panel takes over from the status line.
        panels?.reportPrint(null);
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
            printing: printing,
          );
        }
        return null;
      },
    );
  } catch (e) {
    if (context.mounted) showFailure(context, e);
  } finally {
    panels?.reportPrint(
      sent ? PrintStatus('Sent to ${printer ?? 'the printer'}') : null,
    );
  }
}
