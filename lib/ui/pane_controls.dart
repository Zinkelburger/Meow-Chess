import 'package:flutter/material.dart';

import 'theme.dart';

/// The compact search box above a table. Its height is locked to the control
/// height and the clear button's slot is always reserved, so typing never
/// changes the box's size or nudges the controls beside it.
class SearchField extends StatelessWidget {
  const SearchField({
    required this.controller,
    required this.onChanged,
    this.onSubmitted,
    this.width = 200,
    this.enabled = true,
    super.key,
  });
  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback? onSubmitted;

  /// Unscaled width; grows with the text scale.
  final double width;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final height = scaler.scale(controlHeight);
    final empty = controller.text.isEmpty;
    return SizedBox(
      width: scaler.scale(width),
      height: height,
      child: TextField(
        controller: controller,
        enabled: enabled,
        maxLines: 1,
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search',
          hintStyle: TextStyle(color: colors.onSurfaceVariant),
          contentPadding: EdgeInsets.zero,
          prefixIcon: Icon(
            Icons.search,
            size: 18,
            color: colors.onSurfaceVariant,
          ),
          prefixIconConstraints: BoxConstraints.tightFor(
            width: 34,
            height: height,
          ),
          suffixIconConstraints: BoxConstraints.tightFor(
            width: 34,
            height: height,
          ),
          // Always present so the text area keeps one width.
          suffixIcon: ExcludeFocus(
            excluding: empty,
            child: Visibility.maintain(
              visible: !empty,
              child: IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                onPressed: () {
                  controller.clear();
                  onChanged();
                },
              ),
            ),
          ),
        ),
        onChanged: (_) => onChanged(),
        onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      ),
    );
  }
}

/// The title row above a table pane. It is always at least one control tall,
/// so a pane with round chips and one with a plain title start their tables
/// at the same height and side-by-side panes line up.
class PaneHeading extends StatelessWidget {
  const PaneHeading({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    // Pinned to the top: when one pane's heading wraps (round chips on a
    // narrow pane) and the row grows, both first lines stay on one axis.
    child: Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.textScalerOf(context).scale(controlHeight),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          heightFactor: 1,
          child: child,
        ),
      ),
    ),
  );
}
