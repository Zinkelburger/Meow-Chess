import 'package:flutter/material.dart';

import 'side_panel.dart';
import 'workspace_toolbar.dart';

/// One line of the shortcut list: the keys on the left, what they do on the
/// right, and an optional muted line under the action.
class _Shortcut {
  const _Shortcut(this.keys, this.action, {this.detail, this.then = false});

  /// Each entry is one key or chord, drawn as one keycap.
  final List<String> keys;
  final String action;
  final String? detail;

  /// True when the keys are pressed in turn ("Tab then Enter") rather than
  /// being alternatives ("1 or W").
  final bool then;

  String get spoken =>
      '${keys.join(then ? ' then ' : ' or ')}: $action'
      '${detail == null ? '' : '. $detail'}';
}

/// The keyboard shortcut reference, docked on the right.
class KeyboardHelpPanel extends StatelessWidget {
  const KeyboardHelpPanel({required this.onClose, super.key});
  final VoidCallback onClose;

  static List<(String, String?, List<_Shortcut>)> get _groups => [
    (
      'Results',
      'Result keys score the focused player and jump to the next missing '
          'board.',
      const [
        _Shortcut(['1', 'W'], 'This player wins'),
        _Shortcut(['0', 'L'], 'This player loses'),
        _Shortcut(['D'], 'Draw', detail: '½ on the sheet'),
        _Shortcut(['F'], 'No-show: this player forfeits'),
        _Shortcut(['F'], 'Double forfeit', detail: 'Press F on both players'),
        _Shortcut(
          ['F'],
          'Take a no-show back',
          detail: 'Press F again on that player',
        ),
        _Shortcut(['P', '?'], 'Still playing / disputed'),
        _Shortcut(['A'], 'Temporary pairing assumption'),
        _Shortcut(['Delete'], 'Clear the result'),
      ],
    ),
    (
      'Moving around',
      null,
      const [
        _Shortcut(['↑', '↓'], 'Previous / next board'),
        _Shortcut(['←', '→'], 'Other player'),
        _Shortcut(['Space'], "Open a score box's player"),
        _Shortcut(['Tab', 'Enter'], 'Open the focused player', then: true),
        _Shortcut(['Shift+F10', 'Menu'], 'Menu for the focused row or tab'),
      ],
    ),
    (
      'Anywhere',
      null,
      [
        _Shortcut([shortcutLabel('L')], 'Find a player'),
        _Shortcut([shortcutLabel('P')], 'Print this view'),
        _Shortcut([shortcutLabel('Z')], 'Undo'),
        _Shortcut([
          shortcutLabel('Z', shift: true),
          if (!macShortcuts) shortcutLabel('Y'),
        ], 'Redo'),
        _Shortcut([historyShortcut], 'History'),
        const _Shortcut(
          ['Esc'],
          'Close the panel',
          detail:
              'Section settings and player cards save their changes as they '
              'close; other forms keep a draft',
        ),
        const _Shortcut(['F1'], 'Help'),
        _Shortcut([keyboardHelpShortcut], 'This list'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    return SidePanel(
      title: 'Keyboard shortcuts',
      onClose: onClose,
      children: [
        for (final (i, (heading, intro, rows)) in _groups.indexed) ...[
          if (i > 0) const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text(
              heading,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          if (intro != null) ...[
            const SizedBox(height: 4),
            Text(intro, style: muted),
          ],
          const SizedBox(height: 4),
          for (final (j, row) in rows.indexed)
            _ShortcutRow(row, ruled: j < rows.length - 1),
        ],
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow(this.shortcut, {required this.ruled});
  final _Shortcut shortcut;
  final bool ruled;

  /// Wide enough for the longest single key, Ctrl+Shift+Z; a pair that
  /// does not fit wraps under itself.
  static const keyColumn = 112.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final s = shortcut;
    final scaler = MediaQuery.textScalerOf(context);
    // Large text leaves no room for two columns: keys go above the action.
    final stacked = scaler.scale(14) > 14 * 1.3;
    final joiner = Text(
      s.then ? 'then' : '/',
      style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
    );
    final keys = Wrap(
      // Beside the action, keys meet it at one shared edge, so a lone key
      // sits next to its action instead of across a gap.
      alignment: stacked ? WrapAlignment.start : WrapAlignment.end,
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (k, key) in s.keys.indexed)
          // The joiner travels with the key after it, so a pair that wraps
          // reads "then Enter", not a dangling "then".
          k == 0
              ? _Keycap(key)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    joiner,
                    const SizedBox(width: 6),
                    // Too long for the column, the cap wraps its label.
                    Flexible(child: _Keycap(key)),
                  ],
                ),
      ],
    );
    final action = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.action),
        if (s.detail case final detail?) ...[
          const SizedBox(height: 2),
          Text(
            detail,
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );
    return Semantics(
      label: s.spoken,
      container: true,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: ruled
            ? BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              )
            : null,
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [keys, const SizedBox(height: 6), action],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: scaler.scale(keyColumn), child: keys),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      // Centres a one-line action on the 24px keycap.
                      padding: const EdgeInsets.only(top: 3),
                      child: action,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A key, drawn as a small cap on the shelf colour. Not a control, so its
/// edge is the decorative hairline rather than the 3:1 outline.
class _Keycap extends StatelessWidget {
  const _Keycap(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      // Factors of 1 keep the cap as small as its label, centred.
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'SourceCodePro',
            // Inter carries the arrows and the Mac ⌘ and ⇧.
            fontFamilyFallback: const ['Inter'],
            fontSize: 13,
            height: 1,
            color: colors.onSurface,
          ),
        ),
      ),
    );
  }
}
