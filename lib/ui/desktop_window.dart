import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'brand.dart';

Future<void> initializeDesktopWindow() async {
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(960, 600));
}

/// Tournament navigation; the operating system owns the window decorations.
class WorkspaceToolbar extends StatelessWidget {
  const WorkspaceToolbar({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          const Tooltip(message: 'Meow Chess', child: MeowLogo()),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}
