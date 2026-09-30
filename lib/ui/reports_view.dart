import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../infrastructure/reports.dart';
import '../infrastructure/dbf_export.dart';
import 'dialogs.dart';

Future<void> saveArtifact(String name, Uint8List bytes) async {
  final location = await getSaveLocation(suggestedName: name);
  if (location != null) {
    await XFile.fromData(bytes, name: name).saveTo(location.path);
  }
}

Future<void> previewPacket(
  BuildContext context,
  Event event, {
  String? sectionId,
  ReportKind kind = ReportKind.packet,
}) async {
  try {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
    );
    final bytes = await reportPdf(
      event,
      kind,
      sectionId: sectionId,
      font: font,
    );
    if (!context.mounted) return;
    await openDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 1000,
          height: 760,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(child: Text(event.name)),
                    IconButton(
                      tooltip: 'Close preview',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PdfPreview(
                  build: (_) => bytes,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  allowSharing: false,
                  pdfFileName: 'meow-r${event.revision}.pdf',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) showFailure(context, e);
  }
}

class ReportsView extends StatefulWidget {
  const ReportsView({required this.controller, this.sectionId, super.key});
  final TournamentController controller;
  final String? sectionId;
  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  String? scope;
  TournamentController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    scope = widget.sectionId;
  }

  Future<void> exportRating(BuildContext context) async {
    final event = controller.event!;
    final values = await editFields(
      context,
      title: 'US Chess rating report',
      saveLabel: 'Choose folder…',
      description:
          'These files have not yet been tested with the US Chess upload site. Check them before uploading.',
      fields: const [
        FieldSpec('city', 'City', required: true),
        FieldSpec('state', 'State (2 letters)', required: true),
        FieldSpec('zip', 'ZIP code', required: true),
        FieldSpec(
          'system',
          'Rating system',
          options: {'R': 'Regular', 'D': 'Dual', 'Q': 'Quick'},
        ),
      ],
      values: {'city': event.venue, 'state': '', 'zip': '', 'system': 'R'},
    );
    if (values == null || !context.mounted) return;
    try {
      final folder = await getDirectoryPath(confirmButtonText: 'Save here');
      if (folder == null) return;
      final path = await writeRatingPackage(
        event,
        ReportMetadata(
          city: values['city']!,
          state: values['state']!.toUpperCase(),
          zip: values['zip']!,
          ratingSystem: values['system']!.toUpperCase(),
        ),
        folder,
      );
      if (controller.event?.id == event.id) {
        controller.secondaryBackup();
        controller.repository.writePreference(
          'lastExport',
          '$path|${event.revision}',
        );
      }
      if (context.mounted) {
        showFailure(context, 'Rating report saved to $path');
      }
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = controller.event!, issues = ratingPreflight(e);
    if (scope != null && !e.sections.any((s) => s.id == scope)) scope = null;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Reports', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text('Print handouts or export tournament results.'),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Print & export',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                key: ValueKey(
                  'report-scope-${e.sections.map((s) => s.id).join('-')}',
                ),
                initialValue: e.sections.any((s) => s.id == scope)
                    ? scope!
                    : '',
                decoration: const InputDecoration(
                  labelText: 'Include sections',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All sections'),
                  ),
                  for (final s in e.sections)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (id) => setState(() => scope = id == '' ? null : id),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (kind, label, icon) in [
              (ReportKind.packet, 'Round packet', Icons.print_outlined),
              (ReportKind.pairings, 'Pairings', Icons.grid_view),
              (ReportKind.standings, 'Standings', Icons.leaderboard_outlined),
              (ReportKind.crosstable, 'Crosstable', Icons.table_chart_outlined),
            ])
              OutlinedButton.icon(
                onPressed: e.sections.isEmpty
                    ? null
                    : () => previewPacket(
                        context,
                        e,
                        sectionId: scope,
                        kind: kind,
                      ),
                icon: Icon(icon),
                label: Text(label),
              ),
          ],
        ),
        const SizedBox(height: 28),

        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton(
              onPressed: () async {
                try {
                  await saveArtifact(
                    'standings-r${e.revision}.csv',
                    Uint8List.fromList(
                      utf8.encode(standingsCsv(e, sectionId: scope)),
                    ),
                  );
                } catch (error) {
                  if (context.mounted) showFailure(context, error);
                }
              },
              child: const Text('Standings (CSV)'),
            ),
            OutlinedButton(
              onPressed: () async {
                try {
                  await saveArtifact(
                    'crosstable-r${e.revision}.txt',
                    Uint8List.fromList(
                      crosstable(
                        e,
                        asciiOnly: true,
                        sectionId: scope,
                      ).codeUnits,
                    ),
                  );
                } catch (error) {
                  if (context.mounted) showFailure(context, error);
                }
              },
              child: const Text('Crosstable (text)'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          'US Chess rating report',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Includes the entire event, regardless of the section filter above.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Not yet tested with the US Chess upload site. Check the files before uploading.',
        ),
        const SizedBox(height: 8),
        if (issues.isNotEmpty) _warnings(context, issues),
        if (issues.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.fact_check_outlined),
            title: Text('No problems found.'),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: issues.isEmpty ? () => exportRating(context) : null,
            icon: const Icon(Icons.folder_outlined),
            label: const Text('Create rating report files'),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Submission notes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(e.submission.isEmpty ? 'Nothing recorded yet.' : e.submission),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => editFields(
              context,
              title: 'Submission notes',
              description:
                  'Keep track of when you uploaded the report, its reference number, and any corrections.',
              fields: const [FieldSpec('submission', 'Notes', lines: 5)],
              values: {'submission': e.submission},
              onSave: (v) => controller.change(
                'Update submission record',
                controller.event!.copy(submission: v['submission']),
              ),
            ),
            child: const Text('Edit notes'),
          ),
        ),
      ],
    );
  }

  /// Keep preflight details available without overwhelming the print controls.
  Widget _warnings(BuildContext context, List<String> issues) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('rating-warnings'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ExpansionTile(
        key: const PageStorageKey('rating-preflight-details'),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          Icons.info_outline,
          color: colors.onSurfaceVariant,
          size: 20,
        ),
        title: Text(
          '${issues.length} ${issues.length == 1 ? 'item needs' : 'items need'} attention',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: const Text('Review before creating the rating report.'),
        childrenPadding: const EdgeInsets.fromLTRB(56, 0, 20, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('• $issue'),
            ),
        ],
      ),
    );
  }
}
