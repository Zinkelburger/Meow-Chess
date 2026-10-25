import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../domain/model.dart';
import '../infrastructure/team_reports.dart';
import 'dialogs.dart';

class TeamReportDialog extends StatefulWidget {
  const TeamReportDialog({
    required this.event,
    this.sectionId,
    required this.save,
    super.key,
  });
  final Event event;
  final String? sectionId;
  final Future<void> Function(String, Uint8List) save;
  @override
  State<TeamReportDialog> createState() => _TeamReportDialogState();
}

class _TeamReportDialogState extends State<TeamReportDialog> {
  int best = 4;
  Future<void> save(bool csv) async {
    try {
      final report = csv
          ? teamReportCsv(widget.event, sectionId: widget.sectionId, best: best)
          : teamReport(widget.event, sectionId: widget.sectionId, best: best);
      await widget.save(
        'team-standings-r${widget.event.revision}.${csv ? "csv" : "txt"}',
        Uint8List.fromList(utf8.encode(report)),
      );
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Team standings'),
    content: SizedBox(
      width: 800,
      height: 500,
      child: Column(
        children: [
          DropdownButtonFormField<int>(
            key: const ValueKey('team-scorers'),
            initialValue: best,
            decoration: const InputDecoration(labelText: 'Count scores from'),
            items: [
              const DropdownMenuItem(value: 0, child: Text('All team members')),
              for (var n = 1; n <= 16; n++)
                DropdownMenuItem(value: n, child: Text('Best $n per team')),
            ],
            onChanged: (value) => setState(() => best = value!),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                teamReport(
                  widget.event,
                  sectionId: widget.sectionId,
                  best: best,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => save(false), child: const Text('Save text')),
      TextButton(onPressed: () => save(true), child: const Text('Save CSV')),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
