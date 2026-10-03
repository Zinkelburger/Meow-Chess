import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../infrastructure/roster_import.dart';
import 'players_view.dart' show SidePanel, importRosterRows;

/// File interpretation stays local until the reviewed rows are imported.
class RosterImportPanel extends StatefulWidget {
  const RosterImportPanel({
    required this.controller,
    required this.source,
    required this.filename,
    required this.onClose,
    this.onImported,
    super.key,
  });

  final TournamentController controller;
  final String source, filename;
  final VoidCallback onClose;
  final ValueChanged<String>? onImported;

  @override
  State<RosterImportPanel> createState() => _RosterImportPanelState();
}

class _RosterImportPanelState extends State<RosterImportPanel> {
  String delimiter = 'auto';
  final customDelimiter = TextEditingController();
  late RosterTable table;
  late bool hasHeader, splitName;
  late Map<RosterField, int> columns;
  List<ImportRow> rows = [];
  String? parseError, importError, importedSummary;
  bool skipInvalid = false;

  @override
  void initState() {
    super.initState();
    decode();
  }

  @override
  void dispose() {
    customDelimiter.dispose();
    super.dispose();
  }

  void decode() {
    parseError = importError = null;
    skipInvalid = false;
    try {
      final separator = delimiter == 'custom'
          ? customDelimiter.text
          : delimiter;
      if (delimiter == 'custom' &&
          (separator.runes.length != 1 ||
              ['"', '\r', '\n'].contains(separator))) {
        throw const FormatException(
          'Enter one separator character, such as |.',
        );
      }
      table = RosterTable(
        widget.source,
        delimiter: delimiter == 'auto' ? null : separator,
      );
      hasHeader = table.suggestsHeader;
      suggestColumns();
    } catch (e) {
      parseError = e is FormatException
          ? e.message
          : 'Could not read this file. Check the delimiter.';
      rows = [];
    }
  }

  void suggestColumns() {
    columns = table.suggestColumns(hasHeader);
    splitName =
        !columns.containsKey(RosterField.name) &&
        (columns.containsKey(RosterField.firstName) ||
            columns.containsKey(RosterField.lastName));
    if (!splitName) {
      columns.remove(RosterField.firstName);
      columns.remove(RosterField.lastName);
    }
    interpret();
  }

  void interpret() {
    importError = null;
    skipInvalid = false;
    rows = table.interpret(hasHeader: hasHeader, columns: columns);
  }

  String? get mappingError {
    if (parseError != null) return null;
    if (!columns.containsKey(RosterField.name) &&
        !columns.containsKey(RosterField.firstName) &&
        !columns.containsKey(RosterField.lastName)) {
      return 'Choose a column for the player’s name.';
    }
    if (columns.values.toSet().length != columns.length) {
      return 'Each file column can be used only once.';
    }
    return null;
  }

  void commit() {
    try {
      final summary = importRosterRows(widget.controller, rows);
      if (widget.onImported case final onImported?) {
        onImported(summary);
      } else {
        setState(() => importedSummary = summary);
      }
    } catch (e) {
      setState(() => importError = plainMessage(e));
    }
  }

  String columnLabel(int index) {
    final header =
        hasHeader && table.rows.isNotEmpty && index < table.rows.first.length
        ? table.rows.first[index].toString().trim()
        : '';
    return header.isEmpty ? 'Column ${index + 1}' : '${index + 1}: $header';
  }

  Widget mapping(
    RosterField field,
    String label, {
    String empty = 'Do not import',
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<int>(
      key: ValueKey(
        'mapping-${field.name}-${columns[field]}-${table.columnCount}-$hasHeader',
      ),
      initialValue: columns[field] ?? -1,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem(value: -1, child: Text(empty)),
        for (var i = 0; i < table.columnCount; i++)
          DropdownMenuItem(
            value: i,
            child: Text(columnLabel(i), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) => setState(() {
        if (value == null || value < 0) {
          columns.remove(field);
        } else {
          columns[field] = value;
        }
        interpret();
      }),
    ),
  );

  Widget previewTable(List<String> headings, List<List<String>> values) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          horizontalMargin: 8,
          columnSpacing: 20,
          headingRowHeight: 36,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 60,
          columns: [
            for (final heading in headings) DataColumn(label: Text(heading)),
          ],
          rows: [
            for (final row in values)
              DataRow(
                cells: [
                  for (final cell in row)
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          cell,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (importedSummary case final summary?) {
      return SidePanel(
        title: 'Import complete',
        onClose: widget.onClose,
        children: [
          Semantics(liveRegion: true, child: Text(summary)),
          const SizedBox(height: 12),
          TextButton(onPressed: widget.onClose, child: const Text('Done')),
        ],
      );
    }
    final invalid = rows.where((r) => r.error != null).toList();
    final validCount = rows.length - invalid.length;
    final problem = parseError ?? mappingError;
    final canImport =
        problem == null && validCount > 0 && (invalid.isEmpty || skipInvalid);
    return SidePanel(
      title: 'Import file',
      onClose: widget.onClose,
      scrolls: false,
      children: [
        _ImportContent(
          content: [
            Text(
              widget.filename,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Check the file settings and match your columns. Nothing is added until you import.',
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              key: const ValueKey('import-delimiter'),
              initialValue: delimiter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Delimiter'),
              items: const [
                DropdownMenuItem(
                  value: 'auto',
                  child: Text(
                    'Auto-detect',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(value: ',', child: Text('Comma (CSV)')),
                DropdownMenuItem(value: '\t', child: Text('Tab (TSV)')),
                DropdownMenuItem(value: ';', child: Text('Semicolon')),
                DropdownMenuItem(value: '|', child: Text('Pipe (|)')),
                DropdownMenuItem(value: 'custom', child: Text('Custom')),
              ],
              onChanged: (value) => setState(() {
                delimiter = value!;
                decode();
              }),
            ),
            if (delimiter == 'custom') ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('import-custom-delimiter'),
                controller: customDelimiter,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Separator character',
                ),
                onChanged: (_) => setState(decode),
              ),
            ],
            if (parseError == null) ...[
              CheckboxListTile(
                key: const ValueKey('import-header'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('First row contains column names'),
                value: hasHeader,
                onChanged: (value) => setState(() {
                  hasHeader = value!;
                  suggestColumns();
                }),
              ),
              const SizedBox(height: 8),
              if (table.columnCount > 0)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('File preview · ${table.columnCount} columns'),
                  subtitle: const Text(
                    'First 5 rows · scroll sideways for more',
                  ),
                  initiallyExpanded: true,
                  children: [
                    previewTable(
                      [
                        for (var i = 0; i < table.columnCount; i++)
                          columnLabel(i),
                      ],
                      [
                        for (final row
                            in table.rows.skip(hasHeader ? 1 : 0).take(5))
                          [
                            for (var i = 0; i < table.columnCount; i++)
                              i < row.length ? row[i].toString() : '',
                          ],
                      ],
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              Text(
                'Match columns',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose which file column supplies each player field.',
              ),
              CheckboxListTile(
                key: const ValueKey('import-split-name'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Separate first and last names'),
                value: splitName,
                onChanged: (value) => setState(() {
                  splitName = value!;
                  final suggested = table.suggestColumns(hasHeader);
                  for (final field in [
                    RosterField.name,
                    RosterField.firstName,
                    RosterField.lastName,
                  ]) {
                    columns.remove(field);
                    if ((splitName
                            ? field != RosterField.name
                            : field == RosterField.name) &&
                        suggested.containsKey(field)) {
                      columns[field] = suggested[field]!;
                    }
                  }
                  interpret();
                }),
              ),
              if (splitName) ...[
                mapping(
                  RosterField.firstName,
                  'First name',
                  empty: 'Choose column…',
                ),
                mapping(
                  RosterField.lastName,
                  'Last name',
                  empty: 'Choose column…',
                ),
              ] else
                mapping(
                  RosterField.name,
                  'Name · required',
                  empty: 'Choose column…',
                ),
              mapping(RosterField.rating, 'Rating', empty: 'Unrated'),
              mapping(RosterField.memberId, 'USCF ID', empty: 'Leave blank'),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('More fields'),
                children: [
                  mapping(RosterField.club, 'Club / team'),
                  mapping(RosterField.state, 'State'),
                  mapping(RosterField.registrationNote, 'Note'),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Player preview',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                const Text('No player rows found.')
              else ...[
                const Text('First 5 players with your current settings.'),
                previewTable(
                  ['Row', 'Name', 'Rating', 'USCF ID', 'Status'],
                  [
                    for (final row in rows.take(5))
                      [
                        '${row.line}',
                        row.player?.name ?? '—',
                        row.player == null
                            ? '—'
                            : row.player!.rating == 0
                            ? 'UNR'
                            : '${row.player!.rating}',
                        row.player?.memberId ?? '—',
                        row.error ?? 'Ready',
                      ],
                  ],
                ),
              ],
              if (invalid.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '${invalid.length} rows need attention',
                  style: TextStyle(color: colors.error),
                ),
                for (final row in invalid.take(20))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Row ${row.line}: ${row.error}'),
                  ),
                if (invalid.length > 20)
                  Text('And ${invalid.length - 20} more rows.'),
                CheckboxListTile(
                  key: const ValueKey('import-skip-invalid'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text('Skip ${invalid.length} invalid rows'),
                  value: skipInvalid,
                  onChanged: (value) => setState(() => skipInvalid = value!),
                ),
              ],
            ],
          ],
          footer: [
            if (problem != null || importError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  problem ?? importError!,
                  style: TextStyle(color: colors.error),
                ),
              ),
            Text('$validCount ready to import · Existing players are skipped'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const ValueKey('confirm-roster-import'),
                  onPressed: canImport ? commit : null,
                  child: Text(
                    'Import $validCount ${validCount == 1 ? 'player' : 'players'}',
                  ),
                ),
                TextButton(
                  onPressed: widget.onClose,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _ImportContent extends StatelessWidget {
  const _ImportContent({required this.content, required this.footer});
  final List<Widget> content, footer;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: content,
          ),
        ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: footer,
        ),
      ),
    ],
  );
}
