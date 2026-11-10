import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'desktop_window.dart';

/// Workspace shortcuts use Command on a Mac and Ctrl elsewhere.
bool get macShortcuts => defaultTargetPlatform == TargetPlatform.macOS;

/// A workspace shortcut as the platform writes it: ⌘⇧Z, or Ctrl+Shift+Z.
String shortcutLabel(String key, {bool shift = false}) => macShortcuts
    ? '⌘${shift ? '⇧' : ''}$key'
    : 'Ctrl+${shift ? 'Shift+' : ''}$key';

/// The History shortcut: ⌘H hides the app on a Mac, so ⌘Y there, as in
/// browsers.
String get historyShortcut => shortcutLabel(macShortcuts ? 'Y' : 'H');

/// The keyboard-shortcut list's own shortcut, beside F1 for Help. The same
/// key on every keyboard layout, which a punctuation key is not.
String get keyboardHelpShortcut => macShortcuts ? '⇧F1' : 'Shift+F1';

/// The top bar: the event name (which opens event details) on the left,
/// help, history and app tools pinned to the right. Below 640 logical
/// pixels the tools wrap under the name.
class WorkspaceTopBar extends StatelessWidget {
  const WorkspaceTopBar({
    required this.eventName,
    required this.eventOpen,
    required this.onToggleEvent,
    required this.helpOpen,
    required this.onHelp,
    required this.rulingsOpen,
    required this.onRulings,
    required this.keyboardHelpOpen,
    required this.onKeyboardHelp,
    required this.undoLabel,
    required this.onUndo,
    required this.redoLabel,
    required this.onRedo,
    required this.historyOpen,
    required this.onToggleHistory,
    required this.onTheme,
    required this.onClose,
    super.key,
  });
  final String eventName;
  final bool eventOpen, helpOpen, rulingsOpen, keyboardHelpOpen, historyOpen;
  final VoidCallback onToggleEvent, onHelp, onRulings, onKeyboardHelp;
  final VoidCallback onToggleHistory, onTheme, onClose;

  /// What Undo and Redo would change, named in their tooltips.
  final String? undoLabel, redoLabel;

  /// Null when there is nothing to undo or redo.
  final VoidCallback? onUndo, onRedo;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return WorkspaceToolbar(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final navigation = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            hitTestBehavior: HitTestBehavior.deferToChild,
            child: Row(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth < 1100 ? 160 : 260,
                  ),
                  child: Tooltip(
                    message: 'Event details',
                    child: TextButton.icon(
                      key: const ValueKey('event-details'),
                      onPressed: onToggleEvent,
                      iconAlignment: IconAlignment.end,
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onSurface,
                        backgroundColor: eventOpen
                            ? colors.primary.withValues(alpha: 0.12)
                            : null,
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      label: Text(
                        eventName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _barIcon(
                colors,
                Icons.help_outline,
                'Help (F1)',
                onHelp,
                selected: helpOpen,
                key: const ValueKey('help'),
              ),
              _barIcon(
                colors,
                Icons.gavel,
                'Rulings, penalties and appeals',
                onRulings,
                selected: rulingsOpen,
                key: const ValueKey('rulings'),
              ),
              _barIcon(
                colors,
                Icons.keyboard_outlined,
                'Keyboard shortcuts ($keyboardHelpShortcut)',
                onKeyboardHelp,
                selected: keyboardHelpOpen,
                key: const ValueKey('keyboard-help'),
              ),
              _divider(colors),
              _barIcon(
                colors,
                Icons.undo,
                onUndo != null
                    ? 'Undo $undoLabel (${shortcutLabel('Z')})'
                    : 'Nothing to undo',
                onUndo,
                key: const ValueKey('undo'),
              ),
              _barIcon(
                colors,
                Icons.redo,
                onRedo != null
                    ? 'Redo $redoLabel (${shortcutLabel('Z', shift: true)})'
                    : 'Nothing to redo',
                onRedo,
                key: const ValueKey('redo'),
              ),
              _barIcon(
                colors,
                Icons.history,
                historyOpen
                    ? 'Hide history ($historyShortcut)'
                    : 'History ($historyShortcut)',
                onToggleHistory,
                selected: historyOpen,
              ),
              _divider(colors),
              _barIcon(
                colors,
                dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                dark ? 'Light mode' : 'Dark mode',
                onTheme,
              ),
              // A way out, unlike the × that closes a panel.
              _barIcon(
                colors,
                Icons.logout,
                'Close event',
                onClose,
                key: const ValueKey('close-event'),
              ),
            ],
          );
          if (constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
              640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                navigation,
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: navigation),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }

  static Widget _divider(ColorScheme colors) => SizedBox(
    height: 20,
    child: VerticalDivider(width: 17, color: colors.outlineVariant),
  );

  static Widget _barIcon(
    ColorScheme colors,
    IconData icon,
    String tooltip,
    VoidCallback? action, {
    bool selected = false,
    Key? key,
  }) => IconButton(
    key: key,
    icon: Icon(icon, size: 20),
    tooltip: tooltip,
    onPressed: action,
    isSelected: selected,
    style: selected
        ? IconButton.styleFrom(
            backgroundColor: colors.primary.withValues(alpha: 0.12),
          )
        : null,
    color: selected ? colors.primary : colors.onSurfaceVariant,
    disabledColor: colors.onSurface.withValues(alpha: 0.35),
    visualDensity: VisualDensity.compact,
  );
}
