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
    await showDialog<void>(
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
                    Expanded(
                      child: Text('${event.name} · revision ${event.revision}'),
                    ),
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
      title: 'US Chess package · unverified',
      saveLabel: 'Create validation package',
      description:
          'The encoder follows the archived 2C schema. Portal acceptance has NOT been verified. Use this package only with a qualified TD’s validation workflow. R/D/Q must be chosen under current federation rules; no automatic time-control classification is claimed.',
      fields: const [
        FieldSpec('city', 'City', required: true),
        FieldSpec('state', 'State · two letters', required: true),
        FieldSpec('zip', 'ZIP', required: true),
        FieldSpec('system', 'Rating system · R / D / Q', required: true),
      ],
      values: {'city': event.venue, 'state': '', 'zip': '', 'system': 'R'},
    );
    if (values == null || !context.mounted) return;
    try {
      final folder = await getDirectoryPath(confirmButtonText: 'Save package');
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
        showFailure(
          context,
          'Validation package saved: $path. Submission and acceptance are separate steps.',
        );
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
        Text(
          'Paper for the room. A record for later.',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Every report uses one saved event revision. Current revision: ${e.revision}.',
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final (kind, label, icon) in [
              (ReportKind.packet, 'Round packet', Icons.print_outlined),
              (ReportKind.pairings, 'Pairing sheets', Icons.grid_view),
              (ReportKind.standings, 'Standings', Icons.leaderboard_outlined),
              (ReportKind.crosstable, 'Crosstable', Icons.table_chart_outlined),
            ])
              SizedBox(
                width: 240,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 28),
                        const SizedBox(height: 20),
                        Text(
                          label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: e.sections.isEmpty
                              ? null
                              : () => previewPacket(
                                  context,
                                  e,
                                  sectionId: sectionId,
                                  kind: kind,
                                ),
                          child: const Text('Preview & print'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
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
              child: const Text('Export CSV'),
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
              child: const Text('Export ASCII crosstable'),
            ),
          ],
        ),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 20),
        Text(
          'Rating report preflight',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'External validation is pending. This pilot does not claim accepted US Chess reporting, certified Swiss pairing, or verified latest ratings.',
        ),
        const SizedBox(height: 12),
        for (final issue in issues)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline),
            title: Text(issue),
          ),
        if (issues.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.fact_check_outlined),
            title: Text(
              'Local preflight passed. Provider acceptance remains unverified.',
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: issues.isEmpty ? () => exportRating(context) : null,
            icon: const Icon(Icons.folder_outlined),
            label: const Text('Create 2C validation package'),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Submission record',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          e.submission.isEmpty
              ? 'No submission or acceptance recorded.'
              : e.submission,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => editFields(
              context,
              title: 'Submission and corrections',
              description:
                  'Record the portal reference, submitted revision, acceptance status and any corrections. Exporting alone does not submit a tournament.',
              fields: const [
                FieldSpec('submission', 'Private submission history', lines: 5),
              ],
              values: {'submission': e.submission},
              onSave: (v) => controller.change(
                'Update submission record',
                controller.event!.copy(submission: v['submission']),
              ),
            ),
            child: const Text('Update record'),
          ),
        ),
      ],
    );
  }
}
