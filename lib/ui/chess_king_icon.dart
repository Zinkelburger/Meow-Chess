import 'package:flutter/material.dart';

/// A conventional chess king, distinct from the URL refresh arrow.
class ChessKingIcon extends StatelessWidget {
  const ChessKingIcon({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Text(
      '♔',
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontFamily: 'Segoe UI Symbol',
        fontFamilyFallback: const ['DejaVu Sans', 'Apple Symbols'],
        fontSize: 24,
        height: 1,
        color: IconTheme.of(context).color,
      ),
    ),
  );
}
