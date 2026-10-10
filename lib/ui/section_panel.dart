import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/bye_policy.dart';
import '../domain/fixed_schedule.dart';
import '../domain/model.dart';
import '../domain/pairing.dart' show swissVariations, swissVariationLabels;
import '../domain/prizes.dart';
import '../domain/team_standings.dart';
import '../domain/tiebreaks.dart';
import '../domain/us_chess.dart';
import 'dialogs.dart' show FieldSpec, showFailure;
import 'drafts.dart';
import 'event_panel.dart' show eventPanelFocusKey;
import 'format_extensions.dart';
import 'panels.dart' show Dock;
import 'prize_panel.dart' show PrizeTableEditor;
import 'select.dart';
import 'side_panel.dart';
import 'theme.dart';

/// One section, described the way it was announced: format, rounds, time
/// control, games per round, then the announced rules in four closed
/// groups. Shared by New section and Section settings so nothing is learned
/// twice. Values travel as strings in [text] so the workspace draft can
/// keep them; [readSection] turns them back into a [Section].

/// A validation problem that belongs beside one field.
class SectionFieldProblem extends TournamentException {
  const SectionFieldProblem(this.field, super.message);
  final String field;
}

/// Formats with a "two games a round" variant: the blitz double round,
/// the double round robin, two-game knockout matches, bughouse matches.
bool supportsDoubleGames(Format format) => const [
  Format.swiss,
  Format.roundRobin,
  Format.knockout,
  Format.bughouse,
].contains(format);

/// Quads play their fixed three rounds; a ladder has no rounds at all.
bool hasRoundsField(Format format) =>
    format != Format.quad && format != Format.ladder;

/// The format's own extension, if one is registered.
FormatExtension? extensionFor(Format format) =>
    formatExtensions.where((x) => x.format == format).firstOrNull;

/// Draft key for an extension field: namespaced by format so two formats
/// may use the same field name.
String extensionKey(Format format, String field) => '${format.name}.$field';

/// The New section panel's "Holland system" choice: not a [Format] but a
/// set of round-robin prelims made at once ([TournamentController.makeHolland]).
const hollandChoice = 'holland';

/// A section as the form shows it. [section] null is a new section with
/// the rulebook defaults, stored blank so an untouched form is not a draft.
Map<String, String> sectionValues(Section? section) {
  final s = section;
  final policy = s == null ? null : ByePolicy.fromJson(s.byeRules);
  final values = <String, String>{
    'name': s?.name ?? '',
    'format': (s?.format ?? Format.swiss).name,
    'rounds': s == null ? '' : '${s.plannedRounds}',
    'board': s == null ? '' : '${s.boardStart}',
    'timeControl': s?.timeControl ?? '',
    'ratingCeiling': s == null || s.ratingCeiling == 0
        ? ''
        : '${s.ratingCeiling}',
    'doubleGames': '${s?.doubleGames ?? false}',
    'sideGames': '${s?.sideGames ?? false}',
    'rrTable': s?.rrTable ?? '',
    'doubleCycle': '${s?.doubleCycle ?? false}',
    'accelerated': s?.accelerated ?? '',
    'avoidTeammates': '${s?.avoidTeammates ?? false}',
    'variations': ((s?.variations ?? const {}).toList()..sort()).join(', '),
    'lastHalfByeRound': policy == null ? '' : '${policy.lastHalfByeRound}',
    'maxHalfByes': policy == null ? '' : '${policy.maxHalfByes}',
    'byeDeadline': policy == null ? '' : '${policy.deadlineMinutes}',
    'irrevocableFromRound': policy == null
        ? ''
        : '${policy.irrevocableFromRound}',
    'holland': '',
    'hollandGroups': '',
    'hollandQualifiers': '',
    'hollandUnbalanced': '',
    ...teamAwardValues(s),
  };
  for (final x in formatExtensions) {
    final probe = s != null && s.format == x.format
        ? s
        : Section(id: '', name: '', players: const [], format: x.format);
    for (final e in x.values(probe).entries) {
      values[extensionKey(x.format, e.key)] = e.value;
    }
    // Every field the extension can show needs a controller, even when
    // values() leaves it out.
    for (final f in x.fields(s, locked: false)) {
      values.putIfAbsent(extensionKey(x.format, f.key), () => '');
    }
  }
  return values;
}

/// Labels for the draft-conflict message.
Map<String, String> sectionLabels() => {
  'name': 'Name',
  'format': 'Format',
  'rounds': 'Rounds',
  'board': 'First board',
  'timeControl': 'Time control',
  'ratingCeiling': 'Rating cap',
  'doubleGames': 'Games per round',
  'sideGames': 'Side games',
  'rrTable': 'Round-robin table',
  'doubleCycle': 'Second cycle',
  'accelerated': 'Accelerated pairings',
  'avoidTeammates': 'Keep team-mates apart',
  'variations': 'Pairing variations',
  'lastHalfByeRound': 'Last round for half-point byes',
  'maxHalfByes': 'Half-point byes per player',
  'byeDeadline': 'Bye request deadline',
  'irrevocableFromRound': 'Byes irrevocable from round',
  'holland': 'Holland system',
  'hollandGroups': 'Preliminary groups',
  'hollandQualifiers': 'Qualifiers per group',
  'hollandUnbalanced': 'Unbalanced prelims',
  'teamMethod': 'Team scoring',
  'teamCounting': 'Scores that count',
  for (final x in formatExtensions)
    for (final f in x.fields(null, locked: false))
      extensionKey(x.format, f.key): f.label,
};

/// Validated values from the form. [previousControl] is a time control
/// already saved, which is not re-checked so an older spelling still saves.
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
  int? board,
  int ratingCeiling,
  String timeControl,
  Json byeRules,
})
readSection(
  Map<String, String> v, {
  String previousControl = '',
  bool boardRequired = true,
}) {
  final format = Format.values.byName(v['format'] ?? 'swiss');
  final roundsText = v['rounds']?.trim() ?? '';
  final rounds = !hasRoundsField(format) && roundsText.isEmpty
      ? 3
      : int.tryParse(roundsText);
  if (rounds == null || rounds < 1 || rounds > 32) {
    throw const SectionFieldProblem(
      'rounds',
      'Number of rounds must be between 1 and 32.',
    );
  }
  final boardText = v['board']?.trim() ?? '';
  final board = boardText.isEmpty ? null : int.tryParse(boardText);
  if ((boardText.isNotEmpty || boardRequired) && (board == null || board < 1)) {
    throw const SectionFieldProblem(
      'board',
      'The first board number must be 1 or more.',
    );
  }
  final capText = v['ratingCeiling']?.trim() ?? '';
  final cap = capText.isEmpty ? 0 : int.tryParse(capText);
  if (cap == null || cap < 0) {
    throw const SectionFieldProblem(
      'ratingCeiling',
      'The rating cap is a rating, like 1600, or blank for none.',
    );
  }
  final control = v['timeControl']?.trim() ?? '';
  if (control.isNotEmpty && control != previousControl) {
    try {
      TimeControl.parse(control);
    } on TournamentException catch (e) {
      throw SectionFieldProblem('timeControl', e.message);
    }
  }
  int byeNumber(String key, String label, {int blank = 0}) {
    final text = v[key]?.trim() ?? '';
    final n = text.isEmpty ? blank : int.tryParse(text);
    if (n == null || n < 0 || n > 999) {
      throw SectionFieldProblem(key, '$label must be a whole number.');
    }
    return n;
  }

  final variations = {
    for (final code in (v['variations'] ?? '').split(RegExp(r'[,\s]+')))
      if (code.trim().isNotEmpty) code.trim(),
  };
  for (final code in variations) {
    if (!swissVariations.contains(code)) {
      throw SectionFieldProblem(
        'variations',
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
  if (policy.lastHalfByeRound > rounds) {
    throw SectionFieldProblem(
      'lastHalfByeRound',
      'Bye policy rounds cannot exceed the $rounds planned rounds.',
    );
  }
  if (policy.irrevocableFromRound > rounds) {
    throw SectionFieldProblem(
      'irrevocableFromRound',
      'Bye policy rounds cannot exceed the $rounds planned rounds.',
    );
  }
  return (
    name: v['name']?.trim() ?? '',
    format: format,
    sideGames: v['sideGames'] == 'true',
    doubleGames: v['doubleGames'] == 'true' && supportsDoubleGames(format),
    rrTable: v['rrTable'] ?? '',
    doubleCycle: v['doubleCycle'] == 'true',
    accelerated: v['accelerated'] ?? '',
    avoidTeammates: v['avoidTeammates'] == 'true',
    variations: variations,
    rounds: rounds,
    board: board,
    ratingCeiling: cap,
    timeControl: control,
    byeRules: policy.toJson(),
  );
}

/// The section's extension values as the extension wants them, read from
/// the namespaced draft.
Map<String, String> extensionValues(Format format, Map<String, String> v) {
  final x = extensionFor(format);
  if (x == null) return const {};
  return {
    for (final f in x.fields(null, locked: false))
      f.key: v[extensionKey(format, f.key)] ?? '',
  };
}

/// Applies [values] (already validated by [readSection]) to [section],
/// including the format extension, and checks what the whole must satisfy.
/// The returned section is ready to commit.
Section applySectionValues(
  Event event,
  Section section,
  Map<String, String> values, {
  bool boardRequired = true,
}) {
  final n = readSection(
    values,
    previousControl: section.timeControl,
    boardRequired: boardRequired,
  );
  var next = section.copy(
    name: n.name.isEmpty ? section.name : n.name,
    format: n.format,
    sideGames: n.sideGames,
    doubleGames: n.doubleGames,
    rrTable: n.rrTable,
    doubleCycle: n.doubleCycle,
    accelerated: n.accelerated,
    avoidTeammates: n.avoidTeammates,
    variations: n.variations,
    plannedRounds: n.rounds,
    boardStart: n.board ?? section.boardStart,
    ratingCeiling: n.ratingCeiling,
    timeControl: n.timeControl,
    byeRules: n.byeRules,
  );
  if (extensionFor(n.format) case final x?) {
    next = x.apply(next, extensionValues(n.format, values));
    if (x.problem?.call(event, next) case final problem?) {
      throw TournamentException(problem);
    }
  }
  if (next.rrTable == crenshawTable &&
      next.format == Format.roundRobin &&
      next.players.length > crenshawMaxPlayers) {
    throw SectionFieldProblem(
      'rrTable',
      'The Crenshaw-Berger tables cover 3 to $crenshawMaxPlayers players; this section has ${next.players.length}.',
    );
  }
  if (doubleCycleProblem(next) case final problem?) {
    throw SectionFieldProblem('doubleCycle', problem);
  }
  return applyTeamAwardValues(next, values);
}

// ---- Team awards (Scholastic Regulations 10.2, 12.3.3; rule 31A1) ------

/// The section's team awards as the form shows them: blank method is off,
/// blank count is the default 4.
Map<String, String> teamAwardValues(Section? section) {
  final awards = section == null ? null : TeamAwards.tryOf(section);
  return {
    'teamMethod': awards?.method.code ?? '',
    'teamCounting': awards == null ? '' : '${awards.counting}',
  };
}

/// [section] with the form's team awards stored under
/// `Section.prizes['teams']`; the minimum team size is kept as stored.
Section applyTeamAwardValues(Section section, Map<String, String> v) {
  if (!v.containsKey('teamMethod')) return section;
  final method = TeamScoring.values
      .where((m) => m.code == v['teamMethod'])
      .firstOrNull;
  if (method == null) return withTeamAwards(section, null);
  final text = v['teamCounting']?.trim() ?? '';
  final counting = text.isEmpty ? 4 : int.tryParse(text);
  if (counting == null || counting < 1 || counting > 99) {
    throw const SectionFieldProblem(
      'teamCounting',
      'Scores that count is a number of players, like 4 or 3.',
    );
  }
  final stored = TeamAwards.tryOf(section);
  return withTeamAwards(
    section,
    TeamAwards(
      counting: counting,
      method: method,
      minPlayers: stored?.minPlayers ?? 2,
    ),
  );
}

/// Which closed group a field lives in, so a problem there opens it.
String? sectionGroupOf(String key) {
  if (const [
    'lastHalfByeRound',
    'maxHalfByes',
    'byeDeadline',
    'irrevocableFromRound',
  ].contains(key)) {
    return 'byes';
  }
  if (key == 'teamMethod' || key == 'teamCounting') return 'teams';
  if (const ['board', 'ratingCeiling', 'sideGames'].contains(key)) {
    return 'players';
  }
  if (const [
        'rrTable',
        'doubleCycle',
        'accelerated',
        'avoidTeammates',
        'variations',
      ].contains(key) ||
      key.contains('.')) {
    return 'pairing';
  }
  return null;
}

/// Workspace-state key remembering whether a group is open.
String sectionGroupPref(String group) => 'section-panel-group-$group';

String _formatSentence(Format format) => switch (format) {
  Format.quad =>
    'Groups of four by rating, three rounds each. Five to seven left over play a small Swiss.',
  Format.swiss => 'Players meet others on the same score each round.',
  Format.roundRobin => 'Everyone plays everyone.',
  Format.scheveningen =>
    'Two teams: every player meets every player of the other team.',
  Format.knockout => 'A bracket of mini-matches; losers are out.',
  Format.ladder => 'A standing challenge list; games are recorded by hand.',
  Format.bughouse => 'Partnerships on two boards, paired as a Swiss. Unrated.',
};

const _setBeforeRound1 = 'Set before round 1';

/// The format row, the announcement band and the four groups.
class SectionFormFields extends StatefulWidget {
  const SectionFormFields({
    required this.controller,
    required this.current,
    required this.text,
    required this.keyPrefix,
    required this.problems,
    required this.onChanged,
    required this.onSubmit,
    this.playerCount = 0,
    this.nameAutofocus = false,
    this.allowHolland = false,
    super.key,
  });
  final TournamentController controller;

  /// Offers "Holland system" under Other format: New section only, since
  /// it creates several prelims rather than describing one section.
  final bool allowHolland;

  /// The section being edited, or null for one not created yet.
  final Section? current;
  final Map<String, TextEditingController> text;

  /// `new-section-` or `field-`: every control's ValueKey is the prefix
  /// plus its value key.
  final String keyPrefix;

  /// Problems beside fields, by value key.
  final Map<String, String> problems;
  final VoidCallback onChanged, onSubmit;

  /// How many players the section will have, for the round-robin helper.
  final int playerCount;
  final bool nameAutofocus;

  @override
  State<SectionFormFields> createState() => _SectionFormFieldsState();
}

class _SectionFormFieldsState extends State<SectionFormFields> {
  /// "Other format…" was pressed: the rare-format select is showing.
  bool choosingOther = false;

  TournamentController get c => widget.controller;
  Map<String, TextEditingController> get text => widget.text;
  String value(String key) => text[key]?.text ?? '';
  bool flag(String key) => value(key) == 'true';
  Format get format => Format.values.byName(value('format'));
  bool get holland => widget.allowHolland && flag('holland');
  bool get locked => widget.current?.rounds.isNotEmpty ?? false;
  Key k(String key) => ValueKey('${widget.keyPrefix}$key');

  void set(String key, String v) {
    if (text[key]?.text == v) return;
    text[key]?.text = v;
    widget.onChanged();
  }

  bool groupOpen(String group) =>
      c.workspaceState.read(sectionGroupPref(group)) == 'open';

  void toggleGroup(String group) {
    c.workspaceState.write(
      sectionGroupPref(group),
      groupOpen(group) ? 'closed' : 'open',
    );
    setState(() {});
  }

  // ---- Summaries -------------------------------------------------------

  String get byesSummary {
    int n(String key, int blank) =>
        int.tryParse(value(key).trim()) ??
        (value(key).trim().isEmpty ? blank : -1);
    final last = n('lastHalfByeRound', 0),
        max = n('maxHalfByes', 0),
        deadline = n('byeDeadline', 60),
        irrevocable = n('irrevocableFromRound', 0);
    final parts = [
      if (last > 0) 'Through round $last',
      if (max > 0) '$max per player',
      if (deadline != 60) 'Requests close $deadline min before',
      if (irrevocable > 0) 'Irrevocable from round $irrevocable',
    ];
    return parts.isEmpty ? 'US Chess default' : parts.join(' · ');
  }

  String get pairingSummary {
    if (locked) return _setBeforeRound1;
    final x = extensionFor(format);
    if (x != null &&
        widget.current != null &&
        widget.current!.format == format) {
      if (x.summary?.call(widget.current!) case final own?) return own;
    }
    final parts = switch (format) {
      Format.swiss || Format.bughouse => [
        if (value('accelerated').isNotEmpty) 'Accelerated rounds 1–2',
        if (flag('avoidTeammates')) 'Team-mates apart',
        if (value('variations').trim().isNotEmpty) value('variations').trim(),
      ],
      Format.roundRobin => [
        if (value('rrTable') == crenshawTable) 'Crenshaw-Berger table',
        if (flag('doubleCycle') && flag('doubleGames')) 'Second cycle',
      ],
      _ => const <String>[],
    };
    return parts.isEmpty ? 'US Chess default' : parts.join(' · ');
  }

  String get prizesSummary {
    final s = widget.current;
    if (s == null || s.prizes.isEmpty) return 'None';
    final table = PrizeTable.fromJson(s.prizes);
    if (table.isEmpty) return 'None';
    final count =
        '${table.list.length} ${table.list.length == 1 ? 'prize' : 'prizes'}';
    return table.announcedCents == 0
        ? count
        : '${dollars(table.announcedCents)} · $count';
  }

  /// Team awards appear for a Swiss or round robin with two or more
  /// schools among its players, or one that already has them.
  bool get offersTeams {
    final s = widget.current;
    final event = c.event;
    return s != null &&
        event != null &&
        offersTeamAwards(event, s.copy(format: format));
  }

  String get teamsSummary {
    final method = TeamScoring.values
        .where((m) => m.code == value('teamMethod'))
        .firstOrNull;
    if (method == null) return 'Off';
    final n = int.tryParse(value('teamCounting').trim()) ?? 4;
    return TeamAwards(counting: n, method: method).summary;
  }

  String get playersSummary {
    final board = value('board').trim(), cap = value('ratingCeiling').trim();
    final parts = [
      if (flag('sideGames') && format != Format.quad) 'Side games',
      if (board.isNotEmpty) 'Boards from $board',
      if (cap.isNotEmpty) 'Under $cap',
    ];
    // With no first board set, the section takes the next free boards.
    return parts.isEmpty ? 'Next free boards' : parts.join(' · ');
  }

  // ---- Pieces ----------------------------------------------------------

  Widget textField(
    String key,
    String label, {
    String? helper,
    bool autofocus = false,
    int helperLines = 2,
  }) => TextField(
    key: k(key),
    controller: text[key],
    autofocus: autofocus,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: helperLines,
      errorText: widget.problems[key],
      errorMaxLines: 4,
    ),
    onChanged: (_) => widget.onChanged(),
    onSubmitted: (_) => widget.onSubmit(),
  );

  Widget checkbox(String key, String label, {bool? on, VoidCallback? toggle}) {
    final checked = on ?? flag(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggle ?? () => set(key, '${!checked}'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: PlainCheckbox(
                key: k(key),
                label: label,
                value: checked,
                onChanged: (_) => (toggle ?? () => set(key, '${!checked}'))(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(label),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A value that cannot change now, stated rather than greyed.
  Widget readOnlyLine(String label, String value) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget lockNote() {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline, size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            _setBeforeRound1,
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  /// A field from a [FieldSpec]: the format extensions describe theirs
  /// this way. [key] is the draft key; [spec].key names the ValueKey.
  Widget specField(FieldSpec spec, String key) {
    final readOnly = locked && !spec.enabled;
    if (readOnly) {
      final shown = spec.options?[value(key)] ?? value(key);
      return readOnlyLine(
        spec.label,
        spec.checkbox
            ? (flag(key) ? 'Yes' : 'No')
            : shown.isEmpty
            ? '—'
            : shown,
      );
    }
    if (spec.checkbox) return checkbox(key, spec.label);
    if (spec.options case final options?) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: PlainSelect<String>(
          key: k(key),
          label: spec.label,
          value: options.containsKey(value(key))
              ? value(key)
              : options.keys.first,
          options: [
            for (final o in options.entries) SelectOption(o.key, o.value),
          ],
          onChanged: spec.enabled ? (v) => set(key, v) : null,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: textField(
        key,
        spec.label,
        helper: spec.note?.call(value(key)),
        helperLines: 4,
      ),
    );
  }

  DisclosureGroup group(
    String id,
    String title,
    List<Widget> children, {
    required String summary,
    bool locked = false,
  }) => DisclosureGroup(
    key: ValueKey('section-disclosure-$id'),
    // The header carries the group's key: tapping it opens and closes the
    // group, and its semantics value is the closed summary.
    headerKey: ValueKey('section-group-$id'),
    title: title,
    open: groupOpen(id),
    onToggle: () => toggleGroup(id),
    summary: summary,
    locked: locked,
    children: children,
  );

  // ---- Sections of the form -------------------------------------------

  Widget formatRow(TextStyle muted) {
    final colors = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    final common = format.common && !holland && !choosingOther;
    final rare = [
      for (final f in Format.values)
        if (!f.common) SelectOption(f.name, f.label),
      if (widget.allowHolland)
        const SelectOption(hollandChoice, 'Holland system (30H)'),
    ];
    final current = widget.current;
    final convertedQuad =
        current != null &&
        current.format == Format.quad &&
        pairingFormat(current) == Format.swiss;
    final smallSwiss =
        current != null &&
        current.format == Format.swiss &&
        current.players.length >= 2 &&
        current.players.length <= 6 &&
        current.plannedRounds >= current.players.length - 1 &&
        current.rounds.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A wrap, so at large text the lock note or "Other format…" drops
        // under the title instead of running past the panel edge.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text('Format', style: titleStyle),
            if (locked)
              lockNote()
            else if (common)
              TextButton(
                key: k('other-format'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => setState(() => choosingOther = true),
                child: const Text('Other format…'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (locked)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              convertedQuad
                  ? 'Swiss (was quads: ${current.players.length} players)'
                  : format.label,
              key: k('format-locked'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          )
        else ...[
          SegmentedButton<Format>(
            key: k('format'),
            expandedInsets: EdgeInsets.zero,
            emptySelectionAllowed: true,
            // Room for "Round robin" on one line in the 360px column.
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: Format.quad, label: Text('Quads')),
              ButtonSegment(value: Format.swiss, label: Text('Swiss')),
              ButtonSegment(
                value: Format.roundRobin,
                label: Text('Round robin'),
              ),
            ],
            selected: {if (format.common && !holland) format},
            onSelectionChanged: (v) {
              if (v.isEmpty) return;
              setState(() => choosingOther = false);
              set('holland', '');
              set('format', v.first.name);
            },
          ),
          if (!common)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: PlainSelect<String>(
                key: k('other-format-select'),
                label: 'Other format',
                hint: 'Choose a format',
                value: holland
                    ? hollandChoice
                    : format.common
                    ? ''
                    : format.name,
                options: rare,
                openOnMount: choosingOther,
                onChanged: (v) {
                  setState(() => choosingOther = false);
                  if (v == hollandChoice) {
                    set('format', Format.roundRobin.name);
                    set('holland', 'true');
                  } else {
                    set('holland', '');
                    set('format', v);
                  }
                },
              ),
            ),
        ],
        const SizedBox(height: 8),
        Text(
          holland
              ? 'Round-robin preliminary groups by rating; the top finishers of each meet in a final.'
              : convertedQuad && !locked
              ? 'Pairs as a Swiss: ${current.players.length} players, not four. ${_formatSentence(Format.quad)}'
              : _formatSentence(format),
          style: muted,
        ),
        if (holland) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: textField('hollandGroups', 'Prelim groups')),
              const SizedBox(width: 12),
              Expanded(
                child: textField('hollandQualifiers', 'Qualify per group'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          checkbox(
            'hollandUnbalanced',
            'Unbalanced prelims (30I): groups of different sizes',
          ),
        ],
        if (smallSwiss)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Rule 29K: a small Swiss with this many rounds can be run as a round robin; change the format before posting round 1.',
              style: muted.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  /// Rounds and time control on one row, the time control's rating
  /// category under it, then games per round.
  Widget announcementBand(TextStyle muted) {
    final e = c.event!;
    final count = widget.playerCount;
    final rr = format == Format.roundRobin;
    final roundsHelper = rr && count >= 2
        ? '$count players: ${count.isOdd ? count : count - 1} rounds'
        : null;
    final control = value('timeControl').trim();
    String? category;
    if (control.isEmpty) {
      category = 'Event default · ${e.timeControl}';
      try {
        final cat = TimeControl.parse(e.timeControl).category;
        if (cat != null) category = '$category · ${cat.label.split(' ').first}';
      } on TournamentException {
        // The event's control is checked where it is entered.
      }
    } else {
      try {
        final cat = TimeControl.parse(control).category;
        category = cat == null ? 'Not a ratable time control' : cat.label;
      } on TournamentException {
        category = null;
      }
    }
    final hint = delayHint(control);
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final rounds = hasRoundsField(format) && !holland
        ? textField('rounds', 'Rounds', helper: roundsHelper)
        : null;
    final time = textField('timeControl', 'Time control');
    final showDouble = supportsDoubleGames(format) && !holland;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rounds == null)
          time
        else if (stacked) ...[
          rounds,
          const SizedBox(height: 12),
          time,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: rounds),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: time),
            ],
          ),
        if (category != null || hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              [?category, ?hint].join('\n'),
              key: k('time-control-note'),
              style: muted.copyWith(fontSize: 12),
            ),
          ),
        if (showDouble) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Games per round'),
              if (locked) ...[
                Text(
                  flag('doubleGames') ? 'Two' : 'One',
                  key: k('double-locked'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                lockNote(),
              ] else
                SegmentedButton<bool>(
                  key: k('doubleGames'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('One')),
                    ButtonSegment(value: true, label: Text('Two')),
                  ],
                  selected: {flag('doubleGames')},
                  onSelectionChanged: (v) => set('doubleGames', '${v.first}'),
                ),
            ],
          ),
          if (flag('doubleGames'))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(switch (format) {
                Format.roundRobin =>
                  'Both games in the same round, colors reversed. A second cycle instead is under Pairing rules.',
                Format.knockout => 'Two-game matches, colors reversed.',
                _ =>
                  'Each pairing plays twice, colors reversed; byes score for both games.',
              }, style: muted),
            ),
        ],
      ],
    );
  }

  List<Widget> byesFields() => [
    const SizedBox(height: 4),
    for (final (key, label) in const [
      ('lastHalfByeRound', 'Last round for half-point byes (0 = any, 22C1)'),
      ('maxHalfByes', 'Half-point byes per player (0 = no limit, 22C3)'),
      ('byeDeadline', 'Requests close, minutes before the round (22C2)'),
      ('irrevocableFromRound', 'Byes irrevocable from round (0 = never, 22C4)'),
    ])
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: textField(key, label),
      ),
  ];

  List<Widget> pairingFields(TextStyle muted) {
    final e = c.event!;
    final s = widget.current;
    final x = extensionFor(format);
    final tiebreaks = e.useTiebreaks
        ? sectionTiebreaks(e, format).map((m) => m.label).join(', ')
        : 'off (equal scores share a place)';
    final variations = {
      for (final code in value('variations').split(RegExp(r'[,\s]+')))
        if (code.trim().isNotEmpty) code.trim(),
    };
    void toggleVariation(String code) {
      final next = {...variations};
      next.contains(code) ? next.remove(code) : next.add(code);
      set('variations', (next.toList()..sort()).join(', '));
    }

    final accelerated = {
      '': 'None',
      'addedScore': 'Added score, rounds 1–2 (28R1)',
      'adjustedRating': 'Adjusted rating, rounds 1–2 (28R2)',
      'sixths': 'Sixths, rounds 1–2 (28R3)',
    };
    final tables = {
      '': 'Circle method',
      crenshawTable: 'Crenshaw-Berger (Chapter 12)',
    };
    final canDrawLots =
        s != null &&
        hasFixedSchedule(s) &&
        !s.sideGames &&
        s.rounds.isEmpty &&
        s.format == format;
    return [
      const SizedBox(height: 4),
      if (format == Format.swiss || format == Format.bughouse) ...[
        if (locked) ...[
          readOnlyLine(
            'Accelerated pairings (28R)',
            accelerated[value('accelerated')] ?? value('accelerated'),
          ),
          readOnlyLine(
            'Keep team-mates apart (28N1)',
            flag('avoidTeammates') ? 'Yes' : 'No',
          ),
          readOnlyLine(
            'Announced variations',
            variations.isEmpty
                ? 'None'
                : (variations.toList()..sort()).join(', '),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PlainSelect<String>(
              key: k('accelerated'),
              label: 'Accelerated pairings (28R)',
              value: accelerated.containsKey(value('accelerated'))
                  ? value('accelerated')
                  : '',
              options: [
                for (final o in accelerated.entries)
                  SelectOption(o.key, o.value),
              ],
              onChanged: (v) => set('accelerated', v),
            ),
          ),
          checkbox(
            'avoidTeammates',
            'Keep team-mates apart, plus-two method (28N1)',
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text('Announced variations', style: muted),
          ),
          for (final code in swissVariations)
            checkbox(
              'variation-$code',
              '${swissVariationLabels[code]} ($code)',
              on: variations.contains(code),
              toggle: () => toggleVariation(code),
            ),
          if (widget.problems['variations'] case final problem?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                problem,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ],
      if (format == Format.roundRobin) ...[
        if (locked) ...[
          readOnlyLine(
            'Table (30A)',
            tables[value('rrTable')] ?? value('rrTable'),
          ),
          if (flag('doubleGames'))
            readOnlyLine(
              'Second cycle with colors reversed (30F)',
              flag('doubleCycle') ? 'Yes' : 'No',
            ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PlainSelect<String>(
              key: k('rrTable'),
              label: 'Table (30A)',
              value: tables.containsKey(value('rrTable'))
                  ? value('rrTable')
                  : '',
              options: [
                for (final o in tables.entries) SelectOption(o.key, o.value),
              ],
              onChanged: (v) => set('rrTable', v),
            ),
          ),
          if (widget.problems['rrTable'] case final problem?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                problem,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (flag('doubleGames'))
            checkbox(
              'doubleCycle',
              'Second cycle with colors reversed (30F), not both games in one round',
            ),
          if (widget.problems['doubleCycle'] case final problem?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                problem,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ],
      if (format == Format.quad)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Quads follow the fixed three-round schedule; colors are drawn by lot.',
            style: muted,
          ),
        ),
      if (x != null)
        for (final f in x.fields(s, locked: locked))
          specField(f, extensionKey(format, f.key)),
      if (canDrawLots)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const ValueKey('draw-lots'),
              onPressed: () {
                try {
                  c.drawLots(s.id);
                } catch (e) {
                  showFailure(context, e);
                }
              },
              child: const Text('Draw lots for pairing numbers (30A)'),
            ),
          ),
        ),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Tie-breaks: $tiebreaks', style: muted),
          const SizedBox(width: 4),
          TextButton(
            key: k('event-tiebreaks'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 13),
            ),
            onPressed: () {
              c.workspaceState.write(eventPanelFocusKey, 'tiebreaks');
              Dock.maybeOf(context)?.claim('event');
            },
            child: const Text('Event details'),
          ),
        ],
      ),
    ];
  }

  List<Widget> prizesFields(TextStyle muted) {
    final s = widget.current;
    if (s == null) {
      return [
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Add prizes once the section exists: open its settings from the section tab.',
            style: muted,
          ),
        ),
      ];
    }
    return [
      const SizedBox(height: 4),
      PrizeTableEditor(controller: c, sectionId: s.id),
    ];
  }

  List<Widget> teamsFields(TextStyle muted) {
    final on = TeamScoring.values.any((m) => m.code == value('teamMethod'));
    final teams = c.event == null || widget.current == null
        ? const <String>[]
        : sectionTeams(c.event!, widget.current!);
    return [
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Schools score together from their players\' results. '
          '${teams.length} teams: ${teams.join(', ')}.',
          style: muted,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: PlainSelect<String>(
          key: k('teamMethod'),
          label: 'Team scoring',
          value: on ? value('teamMethod') : '',
          options: [
            const SelectOption('', 'Off'),
            for (final m in TeamScoring.values) SelectOption(m.code, m.label),
          ],
          onChanged: (v) => set('teamMethod', v),
        ),
      ),
      if (on) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: textField(
            'teamCounting',
            'Scores that count (N)',
            helper: value('teamMethod') == TeamScoring.rollins.code
                ? 'Rule 31A1: each player earns the field size minus their place; the top N of each team add up.'
                : 'Scholastic Regulations 10.2.1: top 4 at Spring Nationals, top 3 at Grade Nationals and blitz. Blank is 4.',
            helperLines: 4,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'A team needs at least 2 players for a team prize (10.2.2). '
            'Team tie-breaks (12.3.3): ${teamTiebreakLabels.join(', ')}. '
            'Add team prizes in Prizes with the kind Team.',
            style: muted,
          ),
        ),
      ],
    ];
  }

  List<Widget> playersFields() => [
    const SizedBox(height: 4),
    if (format != Format.quad)
      checkbox('sideGames', 'Side games: pair extra games by hand'),
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: textField(
        'board',
        widget.current == null
            ? 'First board (blank continues numbering)'
            : 'First board number',
        helper: widget.current == null
            ? null
            : 'A new number applies from the next round.',
      ),
    ),
    Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: textField(
        'ratingCeiling',
        'Rating cap: Under (blank = open)',
        helper: 'Rule 28H: entrants rated at or above this are refused.',
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        formatRow(muted),
        const SizedBox(height: 16),
        if ((format != Format.quad || widget.current != null) && !holland) ...[
          textField('name', 'Section name', autofocus: widget.nameAutofocus),
          const SizedBox(height: 12),
        ],
        announcementBand(muted),
        const SizedBox(height: 16),
        group('byes', 'Byes', byesFields(), summary: byesSummary),
        group(
          'pairing',
          'Pairing rules',
          pairingFields(muted),
          summary: pairingSummary,
          locked: locked,
        ),
        group('prizes', 'Prizes', prizesFields(muted), summary: prizesSummary),
        group('players', 'Players', playersFields(), summary: playersSummary),
        if (offersTeams)
          group(
            'teams',
            'Team awards',
            teamsFields(muted),
            summary: teamsSummary,
          ),
        const Divider(height: 1),
      ],
    );
  }
}

/// Opens the group holding [field] (if closed) and, once laid out, scrolls
/// its control into view.
void revealSectionField(TournamentController c, String prefix, String field) {
  if (sectionGroupOf(field) case final group?) {
    c.workspaceState.write(sectionGroupPref(group), 'open');
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final element = _findKey(ValueKey('$prefix$field'));
    if (element != null) {
      Scrollable.ensureVisible(element, alignment: 0.3);
    }
  });
}

BuildContext? _findKey(Key key) {
  BuildContext? found;
  void visit(Element e) {
    if (found != null) return;
    if (e.widget.key == key) {
      found = e;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

/// Section settings: the same form, saved as one undoable edit.
class SectionSettingsPanel extends StatefulWidget {
  const SectionSettingsPanel({
    required this.controller,
    required this.sectionId,
    required this.onClose,
    super.key,
  });
  final TournamentController controller;
  final String sectionId;
  final VoidCallback onClose;

  @override
  State<SectionSettingsPanel> createState() => _SectionSettingsPanelState();
}

class _SectionSettingsPanelState extends State<SectionSettingsPanel> {
  late final Map<String, TextEditingController> text;
  late final FormDraft draft;
  final problems = <String, String>{};
  String? error;

  TournamentController get c => widget.controller;
  Section? get section =>
      c.event?.sections.where((s) => s.id == widget.sectionId).firstOrNull;

  @override
  void initState() {
    super.initState();
    final base = sectionValues(section);
    text = {for (final key in base.keys) key: TextEditingController()};
    draft = FormDraft(
      c.workspaceState,
      'draft-section-${widget.sectionId}',
      text,
      base,
    );
    // A restored draft shows where it was being edited.
    for (final key in text.keys) {
      if (draft.isEdited(key)) {
        if (sectionGroupOf(key) case final group?) {
          c.workspaceState.write(sectionGroupPref(group), 'open');
        }
      }
    }
  }

  @override
  void dispose() {
    draft.dispose();
    for (final t in text.values) {
      t.dispose();
    }
    super.dispose();
  }

  Section currentSection() {
    final s = section;
    if (s == null) {
      throw const TournamentException('This section no longer exists.');
    }
    return s;
  }

  void save() {
    try {
      final current = currentSection();
      final v = draft.prepareSave(
        sectionValues(current),
        labels: sectionLabels(),
      );
      if (v['name']!.trim().isEmpty) {
        throw const SectionFieldProblem('name', 'Enter the name.');
      }
      final next = applySectionValues(c.event!, current, v);
      if (current.rounds.isNotEmpty &&
          (next.format != current.format ||
              next.sideGames != current.sideGames ||
              next.doubleGames != current.doubleGames ||
              next.rrTable != current.rrTable ||
              next.doubleCycle != current.doubleCycle)) {
        throw const TournamentException(
          'Pairing format cannot change after rounds are posted.',
        );
      }
      if (next.plannedRounds < current.rounds.length) {
        throw SectionFieldProblem(
          'rounds',
          '${current.rounds.length} rounds are already posted, so the section needs at least that many.',
        );
      }
      c.change(
        'Edit section ${current.name}',
        c.event!.copy(
          sections: [
            for (final x in c.event!.sections) x.id == current.id ? next : x,
          ],
        ),
      );
      draft.reset(sectionValues(next));
      widget.onClose();
    } on SectionFieldProblem catch (e) {
      setState(() {
        error = null;
        problems
          ..clear()
          ..[e.field] = e.message;
      });
      revealSectionField(c, 'field-', e.field);
    } catch (e) {
      setState(() {
        problems.clear();
        error = plainMessage(e);
      });
    }
  }

  void discard() {
    try {
      draft.reset(sectionValues(currentSection()));
      setState(() {
        error = null;
        problems.clear();
      });
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final s = section;
    if (s == null) {
      return SidePanel(
        key: ValueKey('section-settings-${widget.sectionId}'),
        title: 'Section removed',
        onClose: widget.onClose,
        children: const [Text('This section no longer exists.')],
      );
    }
    return SidePanel(
      key: ValueKey('section-settings-${widget.sectionId}'),
      title: '${s.name} settings',
      onClose: widget.onClose,
      footer: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              error!,
              key: const ValueKey('section-settings-error'),
              style: TextStyle(color: colors.error),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const ValueKey('save-section'),
              onPressed: save,
              child: const Text('Save'),
            ),
            TextButton(onPressed: discard, child: const Text('Discard draft')),
          ],
        ),
      ],
      children: [
        DraftStatus(draft: draft),
        SectionFormFields(
          controller: c,
          current: s,
          text: text,
          keyPrefix: 'field-',
          problems: problems,
          playerCount: s.players.length,
          nameAutofocus: true,
          onChanged: () => setState(() {
            error = null;
            problems.clear();
          }),
          onSubmit: save,
        ),
      ],
    );
  }
}

/// Name, format, announcement line and rules of one section.
Widget sectionSettingsPanel(
  TournamentController c,
  String sectionId,
  VoidCallback onClose,
) => SectionSettingsPanel(
  key: ValueKey('section-settings-panel-$sectionId'),
  controller: c,
  sectionId: sectionId,
  onClose: onClose,
);
