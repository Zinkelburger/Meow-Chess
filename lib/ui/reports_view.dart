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

class ReportsView extends StatelessWidget {
  const ReportsView({required this.controller, this.sectionId, super.key});
  final TournamentController controller;
  final String? sectionId;
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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Print', style: Theme.of(context).textTheme.titleLarge),
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
                        sectionId: sectionId,
                        kind: kind,
                      ),
                icon: Icon(icon),
                label: Text(label),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Text('Export', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton(
              onPressed: () async {
                try {
                  await saveArtifact(
                    'standings-r${e.revision}.csv',
                    Uint8List.fromList(utf8.encode(standingsCsv(e))),
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
                      crosstable(e, asciiOnly: true).codeUnits,
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

  /// Problems that block the rating report, boxed so they read as warnings
  /// rather than as part of the page.
  Widget _warnings(BuildContext context, List<String> issues) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('rating-warnings'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.35),
        border: Border.all(color: colors.error),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Row(
            spacing: 8,
            children: [
              Icon(Icons.warning_amber_rounded, color: colors.error, size: 20),
              Text(
                issues.length == 1
                    ? 'Fix this before creating the report'
                    : 'Fix these ${issues.length} problems before creating the report',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.error,
                ),
              ),
            ],
          ),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text('• $issue'),
            ),
        ],
      ),
    );
  }
}
