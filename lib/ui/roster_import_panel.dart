import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../infrastructure/roster_import.dart';
import '../domain/model.dart';
import 'select.dart';
import 'theme.dart';

/// Imports roster text and returns a one-line summary.
String importRoster(TournamentController c, String source) {
  return importRosterRows(c, parseRoster(source));
}

/// Commits the same interpreted rows that were reviewed in the preview.
String importRosterRows(TournamentController c, List<ImportRow> rows) {
  final valid = rows.where((r) => r.player != null).toList();
  if (valid.isEmpty) {
    throw const TournamentException('No players found.');
  }
  final skipped = c.importPlayers(valid.map((r) => r.player!).toList());
  final bad = rows.where((r) => r.error != null).map((r) => r.line).toList();
  return [
    'Imported ${valid.length - skipped} players',
    if (skipped > 0) '$skipped already in the event',
    if (bad.isNotEmpty) '${bad.length} unreadable (line ${bad.join(', ')})',
  ].join(' · ');
}

/// Opens the import window for a file's text (or pasted rows). Nothing is
/// added until Import; returns the import summary, or null if cancelled.
Future<String?> showRosterImport(
  BuildContext context, {
  required TournamentController controller,
  required String source,
  required String filename,
}) => showDialog<String>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: 0.32),
  animationStyle: AnimationStyle.noAnimation,
  builder: (context) => RosterImportDialog(
    controller: controller,
    source: source,
    filename: filename,
  ),
);

/// The player fields a file column can fill, in menu order.
const _fieldLabels = {
  RosterField.name: 'Name',
  RosterField.firstName: 'First name',
  RosterField.lastName: 'Last name',
  RosterField.rating: 'Rating',
  RosterField.memberId: 'US Chess ID',
  RosterField.state: 'State',
  RosterField.team: 'Team',
  RosterField.club: 'Club',
  RosterField.registrationNote: 'Registration note',
};

/// Standard separators, as a spreadsheet's text import offers them.
const _separators = {',': 'Comma', '\t': 'Tab', ';': 'Semicolon', ' ': 'Space'};

/// File interpretation stays local until the reviewed rows are imported.
class RosterImportDialog extends StatefulWidget {
  const RosterImportDialog({
    required this.controller,
    required this.source,
    required this.filename,
    super.key,
  });

  final TournamentController controller;
  final String source, filename;

  @override
  State<RosterImportDialog> createState() => _RosterImportDialogState();
}

class _RosterImportDialogState extends State<RosterImportDialog> {
  final separators = <String>{};
  final other = TextEditingController();
  final across = ScrollController(), down = ScrollController();
  String? quote = '"';
  bool merge = false;

  /// What auto-detection picked, shown until the TD changes the separators.
  String? detected;
  late RosterTable table;
  late bool hasHeader;
  late Map<RosterField, int> columns;
  List<ImportRow> rows = [];
  Set<int> existingLines = {};
  String? importError;
  bool skipInvalid = false, onlyProblems = false;

  @override
  void initState() {
    super.initState();
    detected = detectSeparator(widget.source);
    separators.add(detected ?? ',');
    decode();
  }

  @override
  void dispose() {
    other.dispose();
    across.dispose();
    down.dispose();
    super.dispose();
  }

  Set<String> get splitOn => {
    ...separators,
    ...other.text.split('').where((ch) => ch != quote),
  };

  /// Reads the file again with the current separator settings.
  void decode() {
    table = RosterTable.split(
      widget.source,
      separators: splitOn,
      quote: quote,
      merge: merge,
    );
    hasHeader = table.suggestsHeader;
    suggestColumns();
  }

  void suggestColumns() {
    columns = table.suggestColumns(hasHeader);
    if (columns.containsKey(RosterField.name)) {
      columns
        ..remove(RosterField.firstName)
        ..remove(RosterField.lastName);
    }
    interpret();
  }

  void interpret() {
    importError = null;
    rows = table.interpret(hasHeader: hasHeader, columns: columns);
    final fresh = newEntries(widget.controller.event!.players, [
      for (final r in rows) ?r.player,
    ]).toSet();
    existingLines = {
      for (final r in rows)
        if (r.player != null && !fresh.contains(r.player)) r.line,
    };
    if (!rows.any((r) => r.error != null)) onlyProblems = false;
  }

  void settings(VoidCallback change) => setState(() {
    change();
    detected = null;
    skipInvalid = false;
    decode();
  });

  /// Points column [index] at [field], taking it from any other column.
  /// A full name and first/last names are alternatives.
  void assign(int index, RosterField? field) => setState(() {
    columns.removeWhere((f, i) => i == index);
    if (field != null) {
      columns[field] = index;
      if (field == RosterField.name) {
        columns
          ..remove(RosterField.firstName)
          ..remove(RosterField.lastName);
      } else if (field == RosterField.firstName ||
          field == RosterField.lastName) {
        columns.remove(RosterField.name);
      }
    }
    interpret();
  });

  RosterField? fieldOf(int index) =>
      columns.entries.where((e) => e.value == index).firstOrNull?.key;

  String? get mappingError =>
      !columns.containsKey(RosterField.name) &&
          !columns.containsKey(RosterField.firstName) &&
          !columns.containsKey(RosterField.lastName)
      ? 'Choose the column that holds player names'
      : null;

  void commit() {
    try {
      Navigator.of(context).pop(importRosterRows(widget.controller, rows));
    } catch (e) {
      setState(() => importError = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final invalid = rows.where((r) => r.error != null).length;
    final ready = rows.length - invalid - existingLines.length;
    final problem = mappingError;
    final canImport =
        problem == null && ready > 0 && (invalid == 0 || skipInvalid);
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    return Dialog(
      key: const ValueKey('roster-import'),
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: colors.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: colors.outline),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1120,
          maxHeight: size.height > 820 ? 780 : size.height,
        ),
        child: LayoutBuilder(
          builder: (context, box) => _layout(
            roomy: box.maxHeight >= 560,
            top: [
              // Title
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                child: Row(
                  children: [
                    Text(
                      'Import players',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.filename,
                        style: muted,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close (Esc)',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.outlineVariant),
              _options(context),
              Divider(height: 1, color: colors.outlineVariant),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Choose what each column holds',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Columns set to Don’t import are left out',
                      style: muted,
                    ),
                    if (invalid > 0)
                      SegmentedButton<bool>(
                        key: const ValueKey('import-row-filter'),
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: false,
                            label: Text('All rows ${rows.length}'),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Need attention $invalid'),
                          ),
                        ],
                        selected: {onlyProblems},
                        onSelectionChanged: (v) =>
                            setState(() => onlyProblems = v.first),
                      ),
                  ],
                ),
              ),
            ],
            grid: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _grid(context),
            ),
            footer: _footer(context, ready, invalid, problem, canImport),
          ),
        ),
      ),
    );
  }

  /// With room, only the rows scroll. In a short window (or with large
  /// text) everything above the footer scrolls together, so the Import
  /// button always stays in view.
  Widget _layout({
    required bool roomy,
    required List<Widget> top,
    required Widget grid,
    required Widget footer,
  }) {
    final rule = Divider(
      height: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (roomy) ...[
          ...top,
          Expanded(child: grid),
        ] else
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...top,
                  SizedBox(height: 320, child: grid),
                ],
              ),
            ),
          ),
        rule,
        footer,
      ],
    );
  }

  Widget _check(
    String key,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PlainCheckbox(
        key: ValueKey(key),
        label: label,
        value: value,
        onChanged: (v) => onChanged(v ?? false),
      ),
      const SizedBox(width: 6),
      ExcludeSemantics(
        child: GestureDetector(
          onTap: () => onChanged(!value),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Text(label),
          ),
        ),
      ),
    ],
  );

  Widget _options(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    Widget label(String text) => SizedBox(
      width: 112,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
    return Container(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              label('Separated by'),
              for (final MapEntry(key: ch, value: name) in _separators.entries)
                _check(
                  'separator-${name.toLowerCase()}',
                  name,
                  separators.contains(ch),
                  (v) => settings(
                    () => v ? separators.add(ch) : separators.remove(ch),
                  ),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Other'),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    height: controlHeight,
                    child: TextField(
                      key: const ValueKey('import-other-separator'),
                      controller: other,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      style: const TextStyle(fontFamily: 'SourceCodePro'),
                      onChanged: (_) => settings(() {}),
                    ),
                  ),
                ],
              ),
              if (detected case final ch?)
                Text(
                  'Detected ${_separators[ch]?.toLowerCase() ?? ch}',
                  key: const ValueKey('import-detected'),
                  style: muted,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              label('Text in quotes'),
              SegmentedButton<String>(
                key: const ValueKey('import-quote'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: '"', label: Text('"  Double')),
                  ButtonSegment(value: "'", label: Text("'  Single")),
                  ButtonSegment(value: '', label: Text('None')),
                ],
                selected: {quote ?? ''},
                onSelectionChanged: (v) =>
                    settings(() => quote = v.first.isEmpty ? null : v.first),
              ),
              _check(
                'import-merge',
                'Merge repeated separators',
                merge,
                (v) => settings(() => merge = v),
              ),
              _check(
                'import-header',
                'First row is column names',
                hasHeader,
                (v) => setState(() {
                  hasHeader = v;
                  skipInvalid = false;
                  suggestColumns();
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final rowWidth = 56.0 * scale,
        cellWidth = 176.0 * scale,
        statusWidth = 260.0 * scale;
    final count = table.columnCount;
    if (count == 0) {
      return Center(
        child: Text(
          'This file has no rows',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      );
    }
    final byLine = {for (final r in rows) r.line: r};
    final lines = [
      for (final r in rows)
        if (!onlyProblems || r.error != null) r.line,
    ];
    final border = BorderSide(color: colors.outlineVariant);
    final mono = const TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
    Widget cell(double width, Widget child, {Color? color}) => Container(
      width: width,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: child,
    );

    Widget status(int line) {
      final r = byLine[line]!;
      if (r.error case final error?) {
        return Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: colors.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                error,
                style: TextStyle(color: colors.error, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      }
      return Text(
        existingLines.contains(line) ? 'Already in the event' : 'New player',
        style: TextStyle(
          fontSize: 13,
          color: existingLines.contains(line)
              ? colors.onSurfaceVariant
              : colors.onSurface,
        ),
      );
    }

    final header = Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: border),
      ),
      child: Row(
        children: [
          cell(
            rowWidth,
            Text('Row', style: TextStyle(color: colors.onSurfaceVariant)),
          ),
          for (var i = 0; i < count; i++)
            Container(
              width: cellWidth,
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PlainSelect<RosterField?>(
                    key: ValueKey('map-column-$i'),
                    dense: true,
                    label: 'Column ${i + 1}',
                    value: fieldOf(i),
                    options: [
                      const SelectOption(null, 'Don’t import'),
                      for (final MapEntry(:key, :value) in _fieldLabels.entries)
                        SelectOption(key, value),
                    ],
                    onChanged: (f) => assign(i, f),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      hasHeader &&
                              table.rows.isNotEmpty &&
                              i < table.rows.first.length &&
                              '${table.rows.first[i]}'.trim().isNotEmpty
                          ? '${table.rows.first[i]}'.trim()
                          : 'Column ${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          cell(
            statusWidth,
            Text('Status', style: TextStyle(color: colors.onSurfaceVariant)),
          ),
        ],
      ),
    );
    final width = rowWidth + cellWidth * count + statusWidth;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.fromBorderSide(border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LayoutBuilder(
          builder: (context, constraints) => Scrollbar(
            controller: across,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: across,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width < constraints.maxWidth
                    ? constraints.maxWidth
                    : width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    Expanded(
                      child: lines.isEmpty
                          ? Center(
                              child: Text(
                                'No player rows',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            )
                          : Scrollbar(
                              controller: down,
                              thumbVisibility: true,
                              child: ListView.builder(
                                controller: down,
                                key: const ValueKey('import-rows'),
                                itemCount: lines.length,
                                itemExtent: 32 * scale + 4,
                                itemBuilder: (context, index) {
                                  final line = lines[index];
                                  final cells = line - 1 < table.rows.length
                                      ? table.rows[line - 1]
                                      : const [];
                                  final error = byLine[line]!.error != null;
                                  return Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: colors.outlineVariant
                                              .withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        cell(
                                          rowWidth,
                                          Text(
                                            '$line',
                                            style: mono.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                        for (var i = 0; i < count; i++)
                                          cell(
                                            cellWidth,
                                            Text(
                                              i < cells.length
                                                  ? '${cells[i]}'
                                                  : '',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color:
                                                    fieldOf(i) == null && !error
                                                    ? colors.onSurfaceVariant
                                                    : colors.onSurface,
                                              ),
                                            ),
                                            color: fieldOf(i) == null
                                                ? colors.surface
                                                : null,
                                          ),
                                        cell(statusWidth, status(line)),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(
    BuildContext context,
    int ready,
    int invalid,
    String? problem,
    bool canImport,
  ) {
    final colors = Theme.of(context).colorScheme;
    final existing = existingLines.length;
    final message = problem ?? importError;
    final summary = [
      '$ready new ${ready == 1 ? 'player' : 'players'}',
      if (existing > 0) '$existing already in the event',
      if (invalid > 0)
        '$invalid ${invalid == 1 ? 'row needs' : 'rows need'} attention',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  message ?? summary,
                  key: const ValueKey('import-summary'),
                  style: TextStyle(
                    color: message != null ? colors.error : colors.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (invalid > 0 && message == null)
                _check(
                  'import-skip-invalid',
                  'Leave out ${invalid == 1 ? 'that row' : 'those $invalid rows'}',
                  skipInvalid,
                  (v) => setState(() => skipInvalid = v),
                ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('confirm-roster-import'),
                onPressed: canImport ? commit : null,
                child: Text(
                  'Import $ready ${ready == 1 ? 'player' : 'players'}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
