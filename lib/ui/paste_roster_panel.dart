import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/tournament_controller.dart';
import 'side_panel.dart';
import 'roster_import_panel.dart';

/// Pastes spreadsheet rows as players. The text is kept as a draft until
/// it imports.
class PasteRosterPanel extends StatefulWidget {
  const PasteRosterPanel({
    super.key,
    required this.controller,
    required this.onClose,
    required this.onImported,
  });
  final TournamentController controller;
  final VoidCallback onClose;
  final ValueChanged<String> onImported;
  @override
  State<PasteRosterPanel> createState() => PasteRosterPanelState();
}

class PasteRosterPanelState extends State<PasteRosterPanel> {
  late final text = TextEditingController(
    text: widget.controller.workspaceState.read('import-draft') ?? '',
  );

  /// Reviews the pasted rows in the import window; the draft stays until
  /// they are imported.
  Future<void> review() async {
    if (text.text.trim().isEmpty) return;
    final summary = await showRosterImport(
      context,
      controller: widget.controller,
      source: text.text,
      filename: 'Pasted rows',
    );
    if (summary == null || !mounted) return;
    widget.controller.workspaceState.write('import-draft', '');
    text.clear();
    widget.onImported(summary);
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final draftError =
        widget.controller.workspaceState.failures['import-draft'];
    return SidePanel(
      title: 'Paste players',
      onClose: widget.onClose,
      children: [
        Text(
          'Paste your rows, then review the columns before importing.',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 12),
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): review,
            const SingleActivator(LogicalKeyboardKey.numpadEnter): review,
          },
          child: TextField(
            key: const ValueKey('paste-roster'),
            controller: text,
            autofocus: true,
            minLines: 10,
            maxLines: 20,
            decoration: const InputDecoration(
              helperText: 'Enter to review · Shift+Enter for a new line',
              helperMaxLines: 2,
            ),
            onChanged: (v) {
              widget.controller.workspaceState.write('import-draft', v);
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 12),
        if (draftError != null || text.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              draftError == null
                  ? 'Draft saved · not imported'
                  : 'Draft not saved to disk. $draftError',
              style: TextStyle(
                color: draftError == null
                    ? colors.onSurfaceVariant
                    : colors.error,
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: text.text.trim().isEmpty ? null : review,
                child: const Text('Review import'),
              ),
              if (widget.controller.workspaceState.failures.containsKey(
                'import-draft',
              ))
                TextButton(
                  onPressed: () {
                    widget.controller.workspaceState.retry();
                    setState(() {});
                  },
                  child: const Text('Retry draft save'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
