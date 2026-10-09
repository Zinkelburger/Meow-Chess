import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../application/diagnostics.dart';

/// Small enough for a 1366x768 laptop at 125% scaling (about 1093x614 logical
/// pixels, less the taskbar), where 600 pixels of height did not fit.
const minimumWindowSize = Size(960, 540);

/// A window-manager failure only loses the minimum size; it must never keep
/// the app from starting.
Future<void> initializeDesktopWindow() async {
  try {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(minimumWindowSize);
  } catch (error, stack) {
    Diagnostics.record(
      'initialize window',
      'failed',
      error: error,
      stack: stack,
    );
  }
}

/// Tournament navigation; the operating system owns the window decorations.
class WorkspaceToolbar extends StatelessWidget {
  const WorkspaceToolbar({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      // Grows with large text instead of clipping it.
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: child,
    );
  }
}
