import 'package:flutter/material.dart';

/// A practice copy looks different at a glance, so nobody runs the real
/// event in it by mistake.
class PracticeBanner extends StatelessWidget {
  const PracticeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Amber paper, unlike any other surface in the app; text at 7:1+.
    final background = dark ? const Color(0xff3d2e10) : const Color(0xfff8e4b8);
    final ink = dark ? const Color(0xfff6dfa9) : const Color(0xff4a3000);
    return Container(
      key: const ValueKey('practice-banner'),
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: 18, color: ink),
          const SizedBox(width: 8),
          Text(
            'Practice copy',
            style: TextStyle(fontWeight: FontWeight.w600, color: ink),
          ),
          Flexible(
            child: Text(
              '  ·  Changes here don’t touch a real event.',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the last post wants the director to check, kept until dismissed.
class PostNotes extends StatelessWidget {
  const PostNotes({required this.notes, required this.onDismiss, super.key});
  final List<String> notes;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('post-notes'),
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(
              Icons.info_outline,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final note in notes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(note),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// What is safe: when the file was last saved, when it was last backed up,
/// and where it lives. Backups open from here.
class WorkspaceStatusBar extends StatelessWidget {
  const WorkspaceStatusBar({
    required this.savedAt,
    required this.backup,
    required this.summary,
    required this.onBackups,
    required this.workspaceStateFailed,
    required this.onRetryWorkspaceState,
    super.key,
  });

  /// When the event was last saved, as History writes it; null if unknown.
  final String? savedAt;

  /// The backup button's label.
  final String backup;

  /// Players, sections and the file's path.
  final String summary;
  final VoidCallback onBackups;

  /// Whether a draft or workspace setting could not be written.
  final bool workspaceStateFailed;
  final VoidCallback onRetryWorkspaceState;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    return Container(
      key: const ValueKey('status-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Icon(Icons.check, size: 14, color: colors.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              savedAt == null ? 'Event saved' : 'Event saved $savedAt',
              key: const ValueKey('status-saved'),
              style: style,
            ),
            Text('  ·  ', style: style),
            TextButton(
              key: const ValueKey('status-backup'),
              onPressed: onBackups,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 24),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Text(backup),
            ),
            Text('  ·  ', style: style),
            Text(summary, overflow: TextOverflow.ellipsis, style: style),
            if (workspaceStateFailed) ...[
              Text(
                ' · Draft or workspace state not saved',
                style: TextStyle(color: colors.error),
              ),
              TextButton(
                onPressed: onRetryWorkspaceState,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
