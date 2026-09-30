import 'package:flutter/material.dart';

/// The same transparent badge used by the desktop launchers and app window.
class MeowLogo extends StatelessWidget {
  const MeowLogo({this.size = 38, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/icon/meow_chess.png',
    width: size,
    height: size,
    filterQuality: FilterQuality.high,
    semanticLabel: 'Meow Chess logo',
  );
}
