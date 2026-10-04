import '../domain/model.dart';
import 'package:flutter/material.dart';
import '../domain/membership.dart';

Color membershipColor(ColorScheme colors, MembershipSummary summary) =>
    switch (summary.severity) {
      MembershipSeverity.error => colors.error,
      MembershipSeverity.warning =>
        colors.brightness == Brightness.dark
            ? const Color(0xffffd966)
            : const Color(0xff785500),
      MembershipSeverity.normal => colors.onSurfaceVariant,
    };

/// Keep the date visible; warnings and provenance are also readable by assistive technology.
class MembershipCell extends StatelessWidget {
  const MembershipCell({
    required this.player,
    required this.eventDate,
    super.key,
  });
  final Player player;
  final String eventDate;

  @override
  Widget build(BuildContext context) {
    final summary = MembershipSummary(player, eventDate: eventDate);
    final colors = Theme.of(context).colorScheme;
    final color = membershipColor(colors, summary);
    return Tooltip(
      message: summary.detail,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    summary.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (summary.attention) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.warning_amber_rounded, size: 14, color: color),
                ],
              ],
            ),
            if (summary.warning != null)
              Text(
                summary.warning!,
                style: TextStyle(color: color, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
