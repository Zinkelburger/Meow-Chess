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
