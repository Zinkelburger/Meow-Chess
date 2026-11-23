import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/announcement.dart';
import '../domain/eligibility.dart';
import '../domain/model.dart';
import '../domain/us_chess.dart';
import 'drafts.dart';
import 'membership_style.dart';
import 'section_panel.dart';
import 'select.dart';
import 'side_panel.dart';
import 'workspace_status.dart';

/// The tournament in one place, for the step between importing players and
/// pairing them. It reads top to bottom as the event does: the rules every
/// section shares (time control, rounds, the play-up limit), then the
/// sections as one ruled table, then the entrants whose rating puts them in
/// another section, each moved or kept with one press.
class SetupPanel extends StatefulWidget {
  const SetupPanel({
    required this.controller,
    required this.onClose,
    this.onCombine,
    this.onNotes,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;

  /// Opens Combine, which belongs to no one section's row.
  final VoidCallback? onCombine;

  /// Opens the registration notes, the step after this one.
  final VoidCallback? onNotes;

  @override
  State<SetupPanel> createState() => _SetupPanelState();
}

/// The sections Set up lists: every one but side games, which have no
/// rounds of their own.
List<Section> setupSections(Event e) =>
    e.sections.where((s) => !s.sideGames).toList();

/// The saved values of [e] as Set up's fields hold them.
Map<String, String> setupValues(Event e) => {
  'timeControl': e.timeControl,
  'playUp': e.playUpLimit == 0 ? '' : '${e.playUpLimit}',
  for (final s in setupSections(e)) ...{
    'rounds:${s.id}': s.roundsUnset || !hasRoundsField(s.format)
        ? ''
        : '${s.plannedRounds}',
    'format:${s.id}': s.format.name,
  },
};

class _SetupPanelState extends State<SetupPanel> {
  TournamentController get c => widget.controller;
  final fields = <String, TextEditingController>{};
  final every = TextEditingController();
  FormDraft? draft;
  String shape = '';

  /// Problems by field key, and one for the whole form.
  final problems = <String, String>{};
  String? error;
  bool saved = false;

  @override
  void initState() {
    super.initState();
    sync();
    c.addListener(eventChanged);
  }

  /// Sections can come or go while the panel is open (an undo, a combine).
  void eventChanged() {
    if (!mounted || c.event == null) return;
    setState(sync);
  }

  @override
  void dispose() {
    c.removeListener(eventChanged);
    draft?.dispose();
    for (final f in fields.values) {
      f.dispose();
    }
    every.dispose();
    super.dispose();
  }

  /// One field per value, rebuilt when the sections change. What was typed
  /// comes back from the stored draft.
  void sync() {
    final base = setupValues(c.event!);
    final now = base.keys.join('|');
    if (now == shape) {
      draft!.reconcile(base);
      showShared();
      return;
    }
    shape = now;
    draft?.dispose();
    for (final key in fields.keys.toList()) {
      if (base.containsKey(key)) continue;
      // Its text field is still on screen until the next frame.
      final gone = fields.remove(key)!;
      WidgetsBinding.instance.addPostFrameCallback((_) => gone.dispose());
    }
    for (final key in base.keys) {
      fields.putIfAbsent(key, TextEditingController.new);
    }
    draft = FormDraft(c.workspaceState, 'draft-set-up', fields, base);
    showShared();
  }

  void edited() {
    showShared();
    setState(() {
      saved = false;
      error = null;
      problems.clear();
    });
  }

  /// What each section that takes rounds has in its Rounds field.
  Set<String> get roundsTyped => {
    for (final s in setupSections(c.event!))
      if (hasRoundsField(formatOf(s))) fields['rounds:${s.id}']!.text.trim(),
  };

  /// The Rounds field beside the time control says what the sections say:
  /// their number when they agree, nothing when they differ.
  void showShared() {
    final typed = roundsTyped;
    final shared = typed.length == 1 ? typed.single : '';
    if (every.text.trim() != shared) every.text = shared;
  }

  /// One number typed for all sections fills every row that takes rounds.
  void fillRounds(String text) {
    for (final s in setupSections(c.event!)) {
      if (hasRoundsField(formatOf(s))) fields['rounds:${s.id}']!.text = text;
    }
    edited();
  }

  Format formatOf(Section s) =>
      Format.values
          .where((f) => f.name == fields['format:${s.id}']?.text)
          .firstOrNull ??
      s.format;

  void useAnnounced(Announcement a) {
    if (a.timeControl.isNotEmpty) fields['timeControl']!.text = a.timeControl;
    if (a.playUpLimit > 0) fields['playUp']!.text = '${a.playUpLimit}';
    if (a.rounds > 0) {
      for (final s in setupSections(c.event!)) {
        if (s.rounds.isEmpty && hasRoundsField(formatOf(s))) {
          fields['rounds:${s.id}']!.text = '${a.rounds}';
        }
      }
    }
    edited();
  }

  /// Whether the fields already say what the event page announces.
  bool matches(Announcement a) {
    final e = c.event!;
    return (a.timeControl.isEmpty ||
            fields['timeControl']!.text.trim() == a.timeControl) &&
        (a.playUpLimit == 0 ||
            setupSections(e).length < 2 ||
            fields['playUp']!.text.trim() == '${a.playUpLimit}') &&
        (a.rounds == 0 ||
            setupSections(e).every(
              (s) =>
                  s.rounds.isNotEmpty ||
                  !hasRoundsField(formatOf(s)) ||
                  fields['rounds:${s.id}']!.text.trim() == '${a.rounds}',
            ));
  }

  void save() {
    try {
      final e = c.event!;
      final v = draft!.prepareSave(
        setupValues(e),
        labels: {
          'timeControl': 'Time control',
          'playUp': 'Play-up limit',
          for (final s in setupSections(e)) ...{
            'rounds:${s.id}': '${s.name} rounds',
            'format:${s.id}': '${s.name} format',
          },
        },
      );
      final control = v['timeControl']!.trim();
      if (control.isEmpty) {
        throw const SectionFieldProblem(
          'timeControl',
          'Enter the time control, like G/60 d5.',
        );
      }
      if (control != e.timeControl) {
        try {
          TimeControl.parse(control);
        } on TournamentException catch (x) {
          throw SectionFieldProblem('timeControl', x.message);
        }
      }
      final limitText = v['playUp']!.trim();
      final limit = limitText.isEmpty ? 0 : int.tryParse(limitText);
      if (limit == null || limit < 0 || limit > 999) {
        throw const SectionFieldProblem(
          'playUp',
          'The play-up limit is a number of rating points, like 200, or blank for none.',
        );
      }
      final sections = <Section>[];
      for (final s in e.sections) {
        if (s.sideGames) {
          sections.add(s);
          continue;
        }
        final format = Format.values.byName(v['format:${s.id}']!);
        final rounds = v['rounds:${s.id}']!.trim();
        final takesRounds = hasRoundsField(format);
        // A row left blank stays waiting; nothing else about it changes.
        if (s.roundsUnset &&
            format == s.format &&
            takesRounds &&
            rounds.isEmpty) {
          sections.add(s);
          continue;
        }
        if (!s.roundsUnset &&
            format == s.format &&
            (!takesRounds || rounds == '${s.plannedRounds}')) {
          sections.add(s);
          continue;
        }
        if (s.rounds.isNotEmpty && format != s.format) {
          throw SectionFieldProblem(
            'format:${s.id}',
            'The format cannot change once a round is paired.',
          );
        }
        final Section next;
        try {
          next = applySectionValues(e, s, {
            ...sectionValues(s),
            'format': format.name,
            'rounds': rounds,
          });
        } on SectionFieldProblem catch (x) {
          throw SectionFieldProblem(
            x.field == 'rounds' ? 'rounds:${s.id}' : 'format:${s.id}',
            x.message,
          );
        } on TournamentException catch (x) {
          throw SectionFieldProblem('format:${s.id}', x.message);
        }
        if (next.plannedRounds < s.rounds.length) {
          final paired = s.rounds.length;
          throw SectionFieldProblem(
            'rounds:${s.id}',
            '$paired ${paired == 1 ? 'round is' : 'rounds are'} already paired, so the section needs at least that many.',
          );
        }
        sections.add(next);
      }
      final revision = e.revision;
      c.change(
        'Set up sections',
        e.copy(timeControl: control, playUpLimit: limit, sections: sections),
      );
      draft!.reset(setupValues(c.event!));
      showShared();
      setState(() {
        saved = c.event!.revision != revision;
        error = null;
        problems.clear();
      });
    } on SectionFieldProblem catch (x) {
      setState(() {
        error = null;
        problems
          ..clear()
          ..[x.field] = x.message;
      });
    } catch (x) {
      setState(() {
        problems.clear();
        error = plainMessage(x);
      });
    }
  }

  void discard() {
    draft!.reset(setupValues(c.event!));
    showShared();
    setState(() {
      error = null;
      problems.clear();
    });
  }

  /// A one-press roster fix, said afterwards with Undo.
  void fix(String message, VoidCallback change) {
    try {
      change();
      setState(() => error = null);
      showUndoNotice(context, c, message);
    } catch (x) {
      setState(() => error = plainMessage(x));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = c.event;
    if (e == null || setupValues(e).keys.join('|') != shape) {
      return const SizedBox.shrink();
    }
    return _panel(context, e);
  }

  /// The Format and Rounds columns, shared by the event's own Rounds field,
  /// the column captions and every section row so the numbers line up.
  static const formatWidth = 132.0;
  static const roundsWidth = 76.0;

  /// A Rounds field holds a number or the word Varies, so it gives its
  /// narrow width to the text.
  static const roundsPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 8);
  static const figures = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const nameStyle = TextStyle(fontWeight: FontWeight.w600);

  /// Whether a section's name reads cleanly in [width] beside its fields:
  /// in two lines at most, with no word broken across them.
  bool nameFits(BuildContext context, String name, double width) {
    if (width <= 0) return false;
    final painter = TextPainter(
      text: TextSpan(
        text: name,
        style: DefaultTextStyle.of(context).style.merge(nameStyle),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final fits =
        painter.minIntrinsicWidth <= width &&
        painter.computeLineMetrics().length <= 2;
    painter.dispose();
    return fits;
  }

  /// At large text the table's fixed columns would clip their values, so
  /// each section stacks instead: its name, then labelled fields beneath.
  bool largeText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3;

  Widget _panel(BuildContext context, Event e) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    final caption = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    final title = Theme.of(context).textTheme.titleMedium;
    final large = largeText(context);
    final sections = setupSections(e);
    final announced = Announcement.of(e);
    final dirty = draft!.dirty;
    final unset = sections.any((s) => s.roundsUnset && s.players.isNotEmpty);
    final notes = e.players.where((p) => p.noteWaiting && !p.withdrawn).length;
    Widget problem(String key) => problems[key] == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              problems[key]!,
              key: ValueKey('set-up-problem-$key'),
              style: TextStyle(fontSize: 13, color: colors.error),
            ),
          );
    final flagged = [
      for (final s in sections)
        if (s.rounds.isEmpty)
          for (final MapEntry(key: id, value: why) in sectionRangeProblems(
            e,
            s,
          ).entries)
            (player: e.player(id), section: s, why: why),
    ];
    final floors = [
      for (final s in sections)
        if (playUpFloor(e, s) case final floor when floor > 0) (s, floor),
    ];
    // One Rounds field for the event when more than one section takes them.
    final shared =
        sections.where((s) => hasRoundsField(formatOf(s))).length > 1;
    final varies = shared && roundsTyped.length > 1;
    final waiting = sections.any(
      (s) =>
          s.roundsUnset &&
          hasRoundsField(formatOf(s)) &&
          fields['rounds:${s.id}']!.text.trim().isEmpty,
    );
    final timeControl = TextField(
      key: const ValueKey('set-up-time-control'),
      controller: fields['timeControl'],
      decoration: const InputDecoration(labelText: 'Time control'),
      onChanged: (_) => edited(),
      onSubmitted: (_) => save(),
    );
    final everyRounds = TextField(
      key: const ValueKey('set-up-every-rounds'),
      controller: every,
      // The one thing still to type after an import.
      autofocus: unset,
      keyboardType: TextInputType.number,
      style: figures,
      decoration: InputDecoration(
        labelText: 'Rounds',
        contentPadding: roundsPadding,
        // Sections that differ are stated, not shown as blank.
        hintText: varies ? 'Varies' : null,
        // The label would not fit inside a field this narrow.
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      onChanged: fillRounds,
      onSubmitted: (_) => save(),
    );
    return SidePanel(
      key: const ValueKey('set-up'),
      title: 'Set up',
      onClose: widget.onClose,
      footer: [
        // Down here beside Save, so typing never pushes the form down.
        DraftStatus(draft: draft!, pending: 'Not saved yet'),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              error!,
              key: const ValueKey('set-up-error'),
              style: TextStyle(color: colors.error),
            ),
          ),
        if (saved && !dirty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(Icons.check, size: 18, color: colors.onSurface),
                  const SizedBox(width: 8),
                  const Text('Saved', key: ValueKey('set-up-saved')),
                ],
              ),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (dirty) ...[
              FilledButton(
                key: const ValueKey('save-set-up'),
                onPressed: save,
                child: const Text('Save'),
              ),
              TextButton(
                onPressed: discard,
                child: const Text('Discard draft'),
              ),
            ] else ...[
              // With the rounds in, the notes are next: a bye needs a
              // round to land on.
              if (notes > 0 && !unset && widget.onNotes != null)
                FilledButton(
                  key: const ValueKey('set-up-notes'),
                  onPressed: widget.onNotes,
                  child: Text(
                    'Review $notes registration ${notes == 1 ? 'note' : 'notes'}',
                  ),
                ),
              OutlinedButton(
                key: const ValueKey('set-up-done'),
                onPressed: widget.onClose,
                child: const Text('Done'),
              ),
            ],
          ],
        ),
      ],
      children: [
        // The event: what every section shares, in the order an event page
        // states it.
        if (large) ...[
          timeControl,
          if (shared) ...[const SizedBox(height: 12), everyRounds],
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: timeControl),
              if (shared) ...[
                const SizedBox(width: 8),
                SizedBox(width: roundsWidth, child: everyRounds),
              ],
            ],
          ),
        problem('timeControl'),
        if (sections.length > 1) ...[
          const SizedBox(height: 12),
          // What the limit comes to sits beside the number that makes it,
          // and drops underneath when the section names are too long.
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: large ? double.infinity : 148,
                child: TextField(
                  key: const ValueKey('set-up-play-up'),
                  controller: fields['playUp'],
                  keyboardType: TextInputType.number,
                  style: figures,
                  decoration: const InputDecoration(
                    labelText: 'Play up within',
                    suffixText: 'points',
                  ),
                  onChanged: (_) => edited(),
                  onSubmitted: (_) => save(),
                ),
              ),
              if (floors.isNotEmpty)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (s, floor) in floors)
                      Text(
                        '${s.name}: $floor and over',
                        key: ValueKey('set-up-floor-${s.id}'),
                        style: muted.merge(figures),
                      ),
                  ],
                ),
            ],
          ),
          problem('playUp'),
        ],
        if (announced != null) _announced(context, announced, muted),
        const SizedBox(height: 24),
        if (sections.isEmpty)
          Text('No sections yet. Choose New section to make one.', style: muted)
        else ...[
          // The heading is the table's header row: the captions sit over
          // the columns they name, once, instead of a label on every field.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Sections', style: title)),
              if (!large) ...[
                SizedBox(
                  width: formatWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text('Format', style: caption),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: roundsWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text('Rounds', style: caption),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          for (final s in sections)
            _row(
              context,
              e,
              s,
              muted,
              problem,
              flagged.where((f) => f.section.id == s.id).length,
            ),
          const Divider(height: 1),
          if (waiting)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'A section is not paired until its rounds are set.',
                key: const ValueKey('set-up-unset'),
                style: muted,
              ),
            ),
          // One Combine for the table, since it belongs to no one section.
          if (widget.onCombine != null && sections.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                // Its label, not its padding, starts on the column edge.
                child: Transform.translate(
                  offset: const Offset(-8, 0),
                  child: TextButton(
                    key: const ValueKey('set-up-combine'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onPressed: widget.onCombine,
                    child: const Text('Combine sections…'),
                  ),
                ),
              ),
            ),
        ],
        // Last, so moving or keeping a player never shifts the form above.
        if (flagged.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Players to check', style: title),
          const SizedBox(height: 8),
          for (final f in flagged)
            _flag(context, e, f.player, f.section, f.why),
          const Divider(height: 1),
        ],
      ],
    );
  }

  /// What the club's event page announced. When the fields already say the
  /// same, that is all it says; when they differ it names its values and
  /// offers them.
  Widget _announced(BuildContext context, Announcement a, TextStyle muted) {
    final colors = Theme.of(context).colorScheme;
    // Each fact stays whole on its line: a break falls between facts only.
    final facts = [
      if (a.rounds > 0) '${a.rounds} ${a.rounds == 1 ? 'round' : 'rounds'}',
      if (a.timeControl.isNotEmpty) a.timeControl,
      if (a.playUpLimit > 0) 'play up within ${a.playUpLimit}',
    ].map((f) => f.replaceAll(' ', ' ')).join(' · ');
    if (facts.isEmpty) return const SizedBox.shrink();
    if (matches(a)) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            Icon(Icons.check, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Matches the event page',
                key: const ValueKey('set-up-announced'),
                style: muted,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Event page: '),
                TextSpan(
                  text: facts,
                  style: TextStyle(color: colors.onSurface),
                ),
              ],
            ),
            key: const ValueKey('set-up-announced'),
            style: muted.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('set-up-use-announced'),
            onPressed: () => useAnnounced(a),
            child: const Text('Use these'),
          ),
        ],
      ),
    );
  }

  /// One section as a ruled row: its name against Format and Rounds, then
  /// its size and rating range in muted text.
  Widget _row(
    BuildContext context,
    Event e,
    Section s,
    TextStyle muted,
    Widget Function(String key) problem,
    int toCheck,
  ) {
    final colors = Theme.of(context).colorScheme;
    final format = formatOf(s);
    final paired = s.rounds.isNotEmpty;
    final range = ratingRangeText(s);
    final n = s.players.length;
    final large = largeText(context);
    final name = Text(
      s.name,
      style: nameStyle,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
    // In the table the column captions name these; stacked, each says so.
    final select = PlainSelect<Format>(
      key: ValueKey('set-up-format-${s.id}'),
      label: large ? 'Format' : null,
      semanticLabel: '${s.name} format',
      value: format,
      options: [
        for (final f in {Format.swiss, Format.roundRobin, s.format})
          SelectOption(f, f.label),
      ],
      onChanged: paired
          ? null
          : (f) {
              fields['format:${s.id}']!.text = f.name;
              edited();
            },
    );
    final rounds = Semantics(
      label: '${s.name} rounds',
      child: TextField(
        key: ValueKey('set-up-rounds-${s.id}'),
        controller: fields['rounds:${s.id}'],
        // With one section there is no event Rounds field to land in.
        autofocus: s.roundsUnset && setupSections(e).length == 1,
        enabled: hasRoundsField(format),
        keyboardType: TextInputType.number,
        style: figures,
        decoration: InputDecoration(
          labelText: large ? 'Rounds' : null,
          contentPadding: roundsPadding,
          // Quads play their fixed three.
          hintText: hasRoundsField(format) ? null : '3',
        ),
        onChanged: (_) => edited(),
        onSubmitted: (_) => save(),
      ),
    );
    return Container(
      key: ValueKey('set-up-section-${s.id}'),
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (large) ...[
            name,
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: select),
                const SizedBox(width: 8),
                SizedBox(width: 120, child: rounds),
              ],
            ),
          ] else
            // The Format and Rounds columns never move. A name that fits
            // beside them sits there; a longer one takes the line above.
            LayoutBuilder(
              builder: (context, box) {
                final controls = [
                  SizedBox(width: formatWidth, child: select),
                  const SizedBox(width: 8),
                  SizedBox(width: roundsWidth, child: rounds),
                ];
                final room = box.maxWidth - formatWidth - roundsWidth - 16;
                if (nameFits(context, s.name, room)) {
                  return Row(
                    children: [
                      Expanded(child: name),
                      const SizedBox(width: 8),
                      ...controls,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    name,
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: controls,
                    ),
                  ],
                );
              },
            ),
          // A bad value is named right under the field that holds it.
          problem('format:${s.id}'),
          problem('rounds:${s.id}'),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 28),
            child: Row(
              children: [
                // The count to check rides beside the facts while there is
                // room and takes its own line, whole, when there is not.
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        [
                          '$n ${n == 1 ? 'player' : 'players'}',
                          if (range.isNotEmpty) range,
                        ].join(' · '),
                        key: ValueKey('set-up-facts-${s.id}'),
                        style: muted.merge(figures),
                      ),
                      if (toCheck > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: attentionColor(colors),
                            ),
                            const SizedBox(width: 6),
                            // At large text it wraps instead of clipping.
                            Flexible(
                              child: Text(
                                '$toCheck to check',
                                key: ValueKey('set-up-to-check-${s.id}'),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: attentionColor(colors),
                                ).merge(figures),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One entrant whose rating puts them in another section: who, why, and
  /// the two things a director can do about it.
  Widget _flag(BuildContext context, Event e, Player p, Section s, String why) {
    final colors = Theme.of(context).colorScheme;
    final to = sectionByRating(e, p);
    return Container(
      key: ValueKey('set-up-flag-${p.id}'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            why,
            style: TextStyle(
              fontSize: 13,
              color: colors.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (to != null && to.rounds.isEmpty)
                OutlinedButton(
                  key: ValueKey('set-up-move-${p.id}'),
                  onPressed: () => fix(
                    'Moved ${p.name} to ${to.name}.',
                    () => c.movePlayers([p.id], to.id),
                  ),
                  child: Text('Move to ${to.name}'),
                ),
              OutlinedButton(
                key: ValueKey('set-up-keep-${p.id}'),
                onPressed: () => fix(
                  '${p.name} stays in ${s.name}.',
                  () => c.allowOutsideRange(p.id, 'Allowed by the TD'),
                ),
                child: Text('Keep in ${s.name}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
