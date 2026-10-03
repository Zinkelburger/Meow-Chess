import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/standings.dart';
import '../infrastructure/reports.dart';
import 'dialogs.dart' show FieldSpec;
import 'drafts.dart';
import 'players_view.dart' show SidePanel, ratingText;

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
    this.panel = panel;
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
    this.description,
    this.saveLabel = 'Save',
    this.controller,
    this.draftKey,
    super.key,
  });
  final String title, saveLabel;
  final TournamentController? controller;
  final String? draftKey;
  final String? description;
  final List<FieldSpec> fields;
  final Map<String, String> values;
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
    final values = text.map((k, v) => MapEntry(k, v.text));
    final missing = widget.fields
        .where((f) => f.required && values[f.key]!.trim().isEmpty)
        .firstOrNull;
    if (missing != null) {
      setState(() => error = 'Enter the ${missing.label.toLowerCase()}.');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.onSave(values);
      draft?.reset(values);
      if (mounted) widget.onClose();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = plainMessage(e);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
        for (final (i, f) in widget.fields.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: f.options != null
                ? DropdownButtonFormField<String>(
                    key: ValueKey('field-${f.key}'),
                    initialValue: text[f.key]!.text,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: f.label),
                    items: [
                      for (final o in f.options!.entries)
                        DropdownMenuItem(value: o.key, child: Text(o.value)),
                    ],
                    onChanged: (v) => text[f.key]!.text = v!,
                  )
                : TextField(
                    key: ValueKey('field-${f.key}'),
                    controller: text[f.key],
                    autofocus: i == 0,
                    maxLines: f.lines,
                    decoration: InputDecoration(
                      labelText: f.label,
                      hintText: f.hint,
                    ),
                    onSubmitted: (_) => save(),
                  ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Saving…' : widget.saveLabel),
          ),
        ),
      ],
    );
  }
}

/// Creates sections: quads previewed beside the roster, where two clicks
/// swap players between groups, or one Swiss or round-robin section.
class NewSectionsPanel extends StatefulWidget {
  const NewSectionsPanel({
    required this.controller,
    required this.onCreated,
    required this.onClose,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onCreated, onClose;
  @override
  State<NewSectionsPanel> createState() => _NewSectionsPanelState();
}

class _NewSectionsPanelState extends State<NewSectionsPanel> {
  Format? type;
  final name = TextEditingController(), rounds = TextEditingController();
  bool doubleGames = false;
  String? error;

  /// The quad groups on screen, and the roster revision they came from.
  List<Section> groups = const [];
  int revision = -1;
  String? picked;
  TournamentController get c => widget.controller;
  final configuration = TextEditingController();
  late FormDraft draft;
  @override
  void initState() {
    super.initState();
    draft = FormDraft(
      c.workspaceState,
      'draft-new-sections',
      {'name': name, 'rounds': rounds, 'configuration': configuration},
      {'name': '', 'rounds': '', 'configuration': ''},
    );
    try {
      final saved = jsonDecode(configuration.text) as Map;
      type = Format.values.where((f) => f.name == saved['type']).firstOrNull;
      doubleGames = saved['doubleGames'] == true;
      revision = saved['revision'] as int? ?? -1;
      groups = (saved['groups'] as List? ?? [])
          .map((s) => Section.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList();
    } catch (_) {
      // An absent or outdated preview is safely regenerated from the roster.
    }
  }

  void rememberConfiguration() {
    configuration.text = jsonEncode({
      'type': type?.name,
      'doubleGames': doubleGames,
      'revision': revision,
      'groups': groups.map((s) => s.toJson()).toList(),
    });
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    rememberConfiguration();
  }

  @override
  void dispose() {
    draft.dispose();
    configuration.dispose();
    name.dispose();
    rounds.dispose();
    super.dispose();
  }

  int get free {
    final e = c.event!;
    return e.players
        .where((p) => e.sectionOf(p.id) == null && !p.withdrawn)
        .length;
  }

  void choose(Format f) {
    setState(() {
      type = f;
      error = null;
      picked = null;
      if (f == Format.quad) {
        groups = const [];
        revision = -1;
      } else {
        final robin = f == Format.roundRobin;
        name.text = robin ? 'Round robin' : 'Open';
        rounds.text = robin
            ? '${free < 2
                  ? 1
                  : free.isEven
                  ? free - 1
                  : free}'
            : '4';
        doubleGames = false;
      }
    });
  }

  /// Regroups when the roster changes underneath the preview.
  void refreshQuads() {
    if (type != Format.quad || revision == c.event!.revision) return;
    try {
      groups = c.quadPreview();
      revision = c.event!.revision;
      rememberConfiguration();
      picked = null;
      error = null;
    } catch (e) {
      groups = const [];
      error = plainMessage(e);
    }
  }

  /// First click picks a player, the second swaps the two.
  void pick(String id) {
    setState(() {
      if (picked == null || picked == id) {
        picked = picked == id ? null : id;
        return;
      }
      final a = picked!;
      groups = [
        for (final s in groups)
          s.copy(
            players: [
              for (final p in s.players)
                p == a
                    ? id
                    : p == id
                    ? a
                    : p,
            ],
          ),
      ];
      picked = null;
    });
  }

  void create() {
    try {
      if (type == Format.quad) {
        c.applyQuads(groups, revision);
      } else {
        final n = int.tryParse(rounds.text.trim());
        if (name.text.trim().isEmpty) {
          throw const TournamentException('Enter the section name.');
        }
        if (n == null || n < 1 || n > 32) {
          throw const TournamentException(
            'Number of rounds must be between 1 and 32.',
          );
        }
        c.addSection(name.text.trim(), type!, n, doubleGames: doubleGames);
      }
      draft.reset({'name': '', 'rounds': '', 'configuration': ''});
      widget.onCreated();
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme, e = c.event!;
    refreshQuads();
    final muted = TextStyle(color: colors.onSurfaceVariant);
    Widget option(Format f, IconData icon, String title, String body) {
      final selected = type == f;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: selected
              ? colors.primary.withValues(alpha: 0.10)
              : colors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant,
            ),
          ),
          child: Semantics(
            selected: selected,
            child: ListTile(
              key: ValueKey('type-${f.name}'),
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(body),
              onTap: () => choose(f),
            ),
          ),
        ),
      );
    }

    final replacing = e.sections.any((s) => s.players.isNotEmpty);
    return SidePanel(
      title: 'New sections',
      width: 400,
      onClose: widget.onClose,
      children: [
        DraftStatus(draft: draft),
        option(
          Format.quad,
          Icons.grid_view,
          'Quads',
          'Split all players by rating into groups of four. Leftovers play a small Swiss.',
        ),
        option(
          Format.swiss,
          Icons.shuffle,
          'Swiss',
          'One section. Players meet opponents with the same score each round.',
        ),
        option(
          Format.roundRobin,
          Icons.sync_alt,
          'Round robin',
          'One section. Everyone plays everyone.',
        ),
        if (type == Format.quad && groups.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Grouped by rating. Click two players to swap them.'
            '${replacing ? ' This replaces the current sections.' : ''}',
            style: muted,
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!, style: TextStyle(color: colors.error)),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const ValueKey('create-sections'),
              onPressed: create,
              child: Text('Create ${groups.length} sections'),
            ),
          ),
          for (final s in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(
                '${s.name} · ${s.players.length} players',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final id in s.players)
              _QuadPlayer(
                key: ValueKey('quad-player-$id'),
                player: e.player(id),
                picked: picked == id,
                onTap: () => pick(id),
              ),
          ],
        ],
        if (type == Format.swiss || type == Format.roundRobin) ...[
          const SizedBox(height: 8),
          Text(
            free == 0
                ? 'Everyone is already in a section, so this one starts empty.'
                : 'The $free ${free == 1 ? 'player' : 'players'} not yet in a section will be added.',
            style: muted,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('field-name'),
            controller: name,
            decoration: const InputDecoration(labelText: 'Section name'),
            onSubmitted: (_) => create(),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('field-rounds'),
            controller: rounds,
            decoration: const InputDecoration(labelText: 'Number of rounds'),
            onSubmitted: (_) => create(),
          ),
          if (type == Format.roundRobin) ...[
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              key: const ValueKey('field-double'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('One game')),
                ButtonSegment(value: true, label: Text('Two games each')),
              ],
              selected: {doubleGames},
              onSelectionChanged: (v) => setState(() => doubleGames = v.first),
            ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!, style: TextStyle(color: colors.error)),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const ValueKey('create-sections'),
              onPressed: create,
              child: const Text('Create section'),
            ),
          ),
        ],
        if (type == Format.quad && groups.isEmpty && error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
      ],
    );
  }
}

class _QuadPlayer extends StatelessWidget {
  const _QuadPlayer({
    required this.player,
    required this.picked,
    required this.onTap,
    super.key,
  });
  final Player player;
  final bool picked;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: picked,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: picked ? colors.primary.withValues(alpha: 0.12) : null,
            border: Border.all(
              color: picked ? colors.primary : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Expanded(child: Text(player.name)),
              Text(
                ratingText(player.rating),
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Name, length and board numbers of one section.
Widget sectionSettingsPanel(
  TournamentController c,
  String sectionId,
  VoidCallback onClose,
) {
  final s = c.event!.sections.firstWhere((s) => s.id == sectionId);
  return FieldsPanel(
    key: ValueKey('section-settings-$sectionId'),
    controller: c,
    draftKey: 'draft-section-$sectionId',
    title: '${s.name} settings',
    description: 'A new first board number applies from the next round.',
    fields: const [
      FieldSpec('name', 'Name', required: true),
      FieldSpec('rounds', 'Number of rounds', required: true),
      FieldSpec('board', 'First board number', required: true),
    ],
    values: {
      'name': s.name,
      'rounds': '${s.plannedRounds}',
      'board': '${s.boardStart}',
    },
    onClose: onClose,
    onSave: (v) {
      final rounds = int.tryParse(v['rounds']!.trim()),
          board = int.tryParse(v['board']!.trim());
      if (rounds == null || rounds < 1 || rounds > 32) {
        throw const TournamentException(
          'Number of rounds must be between 1 and 32.',
        );
      }
      if (rounds < s.rounds.length) {
        throw TournamentException(
          '${s.rounds.length} rounds are already posted, so the section needs at least that many.',
        );
      }
      if (board == null || board < 1) {
        throw const TournamentException(
          'The first board number must be 1 or more.',
        );
      }
      c.change(
        'Edit section ${s.name}',
        c.event!.copy(
          sections: [
            for (final x in c.event!.sections)
              x.id == s.id
                  ? x.copy(
                      name: v['name']!.trim(),
                      plannedRounds: rounds,
                      boardStart: board,
                    )
                  : x,
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

  void combine(Section source) {
    if (target == null) {
      setState(() => error = 'Choose the section to combine into.');
      return;
    }
    try {
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
          decoration: const InputDecoration(
            labelText: 'Reason (needed once rounds are played)',
          ),
          onSubmitted: (_) => combine(source),
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
            onPressed: others.isEmpty ? null : () => combine(source),
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
    super.key,
  });
  final Event event;
  final TournamentController? controller;
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

class _PrintPanelState extends State<PrintPanel> {
  late Event snapshot = widget.event;
  late Future<Uint8List> pdf = generate();
  int? approvedOldRevision;
  int? get currentRevision => widget.controller?.event?.revision;
  bool get stale =>
      currentRevision != null && currentRevision != snapshot.revision;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller?.removeListener(changed);
    super.dispose();
  }

  Future<Uint8List> generate() async {
    final event = snapshot;
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
      font: font,
      bold: bold,
    );
  }

  void refresh() => setState(() {
    snapshot = widget.controller?.event ?? snapshot;
    approvedOldRevision = null;
    pdf = generate();
  });

  @override
  Widget build(BuildContext context) {
    final section = snapshot.sections
        .where((s) => s.id == widget.sectionId)
        .firstOrNull;
    final what = switch (widget.kind) {
      ReportKind.packet => 'Round packet',
      ReportKind.pairings => 'Pairings',
      ReportKind.standings => 'Standings',
      ReportKind.crosstable => 'Crosstable',
    };
    final rounds =
        snapshot.sections
            .where((s) => widget.sectionId == null || s.id == widget.sectionId)
            .map(
              (s) =>
                  widget.roundNumbers?[s.id] ??
                  widget.roundNumber ??
                  s.rounds.lastOrNull?.number,
            )
            .whereType<int>()
            .where((n) => n > 0)
            .toSet()
            .toList()
          ..sort();
    final roundLabel = rounds.isEmpty
        ? 'No posted round'
        : 'Round${rounds.length == 1 ? '' : 's'} ${rounds.join(', ')}';
    final canPrint = !stale || approvedOldRevision == currentRevision;
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
                        Text(
                          '$roundLabel · Revision ${snapshot.revision}',
                          key: const ValueKey('print-scope'),
                        ),
                        if (widget.roundNumbers != null &&
                            widget.roundNumbers!.values.toSet().length > 1)
                          for (final s in snapshot.sections.where(
                            (s) => widget.roundNumbers!.containsKey(s.id),
                          ))
                            Text(
                              '${s.name}: ${widget.roundNumbers![s.id] == 0 ? "no posted round" : "round ${widget.roundNumbers![s.id]}"}',
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
                              FilledButton(
                                onPressed: refresh,
                                child: const Text('Refresh preview'),
                              ),
                              if (!canPrint)
                                TextButton(
                                  onPressed: () => setState(
                                    () => approvedOldRevision = currentRevision,
                                  ),
                                  child: Text(
                                    'Use older revision ${snapshot.revision}',
                                  ),
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
                  future: pdf,
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
                                pdf = generate();
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
                      allowPrinting: canPrint,
                      useActions: canPrint,
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
}) {
  final dock = Dock.maybeOf(context);
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
            hintText: 'Name, US Chess ID or #number',
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
