import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Every tool shares the same reserved column, even while it is closed.
double detailsColumnWidth(double availableWidth) =>
    (availableWidth * 0.48).clamp(0.0, 360.0);

/// Keeps a stable details column so opening a panel never reflows the table.
class PlayerDetailsLayout extends StatelessWidget {
  const PlayerDetailsLayout({
    required this.child,
    this.panel,
    this.expandContent = false,
    this.reserveSpace = true,
    super.key,
  });
  final Widget child;
  final Widget? panel;
  final bool expandContent;
  final bool reserveSpace;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final panelWidth = panel == null && !reserveSpace
          ? 0.0
          : detailsColumnWidth(constraints.maxWidth);
      final contentWidth = (constraints.maxWidth - panelWidth).clamp(
        0.0,
        expandContent ? double.infinity : 1100.0,
      );
      // Small windows can scroll across the table and details together.
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth < contentWidth + panelWidth
              ? contentWidth + panelWidth
              : constraints.maxWidth,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: contentWidth, child: child),
              const Spacer(),
              SizedBox(
                key: const ValueKey('player-details-area'),
                width: panelWidth,
                child: panel == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: panel,
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A panel docked beside a table. Esc or the close button calls [onClose].
class SidePanel extends StatelessWidget {
  const SidePanel({
    required this.title,
    required this.onClose,
    required this.children,
    this.footer = const [],
    this.width = 360,
    this.scrolls = true,
    super.key,
  });
  final String title;
  final VoidCallback onClose;
  final List<Widget> children;
  final List<Widget> footer;
  final double width;

  /// False when the single child fills the panel and scrolls itself.
  final bool scrolls;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // A fresh scope lets field autofocus take over from the workspace.
    return FocusScope(
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
        child: Container(
          width: width,
          margin: const EdgeInsets.fromLTRB(0, 0, 24, 16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            border: Border.all(color: colors.outlineVariant),
          ),
          // List tiles inside draw their highlight on this.
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close (Esc)',
                        icon: const Icon(Icons.close),
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: scrolls
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: children,
                          ),
                        )
                      : children.single,
                ),
                if (footer.isNotEmpty) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: footer,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
