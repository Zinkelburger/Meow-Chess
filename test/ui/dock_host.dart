import 'package:flutter/material.dart';
import 'package:meow_chess/ui/panels.dart';

/// Hosts a view with the workspace's docked panel beside it, for tests that
/// mount a single view rather than the whole workspace.
class DockHost extends StatefulWidget {
  const DockHost({required this.child, super.key});
  final Widget child;
  @override
  State<DockHost> createState() => _DockHostState();
}

class _DockHostState extends State<DockHost> {
  final dock = DockController();

  @override
  void initState() {
    super.initState();
    dock.addListener(changed);
  }

  void changed() => setState(() {});

  @override
  void dispose() {
    dock
      ..removeListener(changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dock(
    controller: dock,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: widget.child),
        if (dock.panel != null) SizedBox(width: 384, child: dock.panel),
      ],
    ),
  );
}
