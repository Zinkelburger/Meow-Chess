import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

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

/// A titled part of a panel that opens and closes in place, instantly.
/// Closed, it shows [summary] so the value reads without opening it.
class DisclosureGroup extends StatefulWidget {
  const DisclosureGroup({
    required this.title,
    required this.open,
    required this.onToggle,
    required this.children,
    this.summary,
    this.summaryColor,
    this.focusNode,
    super.key,
  });
  final String title;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;
  final String? summary;
  final Color? summaryColor;
  final FocusNode? focusNode;

  @override
  State<DisclosureGroup> createState() => _DisclosureGroupState();
}

class _DisclosureGroupState extends State<DisclosureGroup> {
  bool focused = false, hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final summary = widget.open ? null : widget.summary;
    final header = Semantics(
      button: true,
      expanded: widget.open,
      label: widget.title,
      value: summary,
      excludeSemantics: true,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) => setState(() => focused = v),
        onShowHoverHighlight: (v) => setState(() => hovered = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onToggle();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              color: hovered ? colors.onSurface.withValues(alpha: 0.04) : null,
              borderRadius: BorderRadius.circular(4),
              border: focused
                  ? Border.all(color: focusRing(colors), width: focusRingWidth)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  widget.open ? Icons.expand_more : Icons.chevron_right,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                // Large text wraps the summary under the title, never clips.
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    children: [
                      Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (summary != null)
                        Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                widget.summaryColor ?? colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        header,
        if (widget.open)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}
