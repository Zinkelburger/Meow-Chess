import '../domain/model.dart';
import 'package:flutter/material.dart';
import '../domain/membership.dart';

/// Worth a second look, short of an error. Always paired with words or an icon.
Color attentionColor(ColorScheme colors) => colors.brightness == Brightness.dark
    ? const Color(0xffffd966)
    : const Color(0xff785500);

Color membershipColor(ColorScheme colors, MembershipSummary summary) =>
    switch (summary.severity) {
      MembershipSeverity.error => colors.error,
      MembershipSeverity.warning => attentionColor(colors),
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
    // One line keeps the row height steady; the tooltip has the full detail.
    return Tooltip(
      message: summary.detail,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Text.rich(
          TextSpan(
            style: TextStyle(color: color),
            children: [
              TextSpan(
                text: summary.label,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (summary.warning case final warning?) ...[
                const TextSpan(text: '  '),
                TextSpan(
                  text: warning,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
