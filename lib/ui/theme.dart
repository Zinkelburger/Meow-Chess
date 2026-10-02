import 'package:flutter/material.dart';

/// Every button, field and toggle shares this height so rows line up.
const double controlHeight = 36;

/// Keyboard focus is a ring of this width in [focusRing], on every control.
const double focusRingWidth = 2;

/// The focus ring colour: dark on light paper, light on the dark theme, so
/// it shows on filled buttons as well as on the page.
Color focusRing(ColorScheme c) => c.onSurface;

/// A control's border: the 3:1 outline, or the focus ring when focused.
WidgetStateProperty<BorderSide?> focusSide(ColorScheme c, {BorderSide? rest}) =>
    WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: focusRing(c), width: focusRingWidth)
          : rest,
    );

ThemeData meowTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xff1f4e8c),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    primary: dark ? const Color(0xff8fb4e8) : const Color(0xff1f4e8c),
    onPrimary: dark ? const Color(0xff0f2340) : const Color(0xffffffff),
    surface: dark ? const Color(0xff1c1c1b) : const Color(0xfff4f3ef),
    surfaceContainerLowest: dark
        ? const Color(0xff242423)
        : const Color(0xffffffff),
    surfaceContainerLow: dark
        ? const Color(0xff2a2a28)
        : const Color(0xffebe9e2),
    surfaceContainerHigh: dark
        ? const Color(0xff343430)
        : const Color(0xffe5e3dd),
    outlineVariant: dark ? const Color(0xff3d3c38) : const Color(0xffd9d6cc),
    // At least 3:1 against every surface, for field and control edges.
    outline: dark ? const Color(0xff858278) : const Color(0xff7f7b6a),
    inverseSurface: dark ? const Color(0xff0c0c0b) : const Color(0xff1d1d1b),
    onInverseSurface: const Color(0xfff4f3ef),
  );
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(4)),
  );
  const buttonText = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );
  const buttonPadding = EdgeInsets.symmetric(horizontal: 14);
  const minimum = Size(0, controlHeight);
  // Buttons change colour instantly on hover/press instead of fading.
  const instant = Duration.zero;
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    fontFamily: 'Inter',
    // Standard density on desktop too, so controlHeight is the real height.
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    // No ink ripple: taps respond immediately.
    splashFactory: NoSplash.splashFactory,
    scaffoldBackgroundColor: colors.surface,
    focusColor: colors.primary.withValues(alpha: 0.16),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 14),
      bodyMedium: TextStyle(fontSize: 14),
      bodySmall: TextStyle(fontSize: 13),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      centerTitle: false,
    ),
    dividerTheme: DividerThemeData(color: colors.outlineVariant, space: 1),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colors.primary, width: focusRingWidth),
      ),
      isDense: true,
      filled: true,
      fillColor: colors.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(colors.surfaceContainerLow),
      headingTextStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
      dataRowMinHeight: 36,
      dataRowMaxHeight: 44,
      columnSpacing: 24,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        animationDuration: instant,
        minimumSize: minimum,
        padding: buttonPadding,
        textStyle: buttonText,
        shape: shape,
      ).copyWith(side: focusSide(colors)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            animationDuration: instant,
            minimumSize: minimum,
            padding: buttonPadding,
            textStyle: buttonText,
            shape: shape,
            backgroundColor: colors.surfaceContainerLowest,
          ).copyWith(
            side: focusSide(colors, rest: BorderSide(color: colors.outline)),
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        animationDuration: instant,
        minimumSize: minimum,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: buttonText,
        shape: shape,
      ).copyWith(side: focusSide(colors)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(animationDuration: instant, side: focusSide(colors)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        animationDuration: instant,
        shape: const WidgetStatePropertyAll(shape),
        side: focusSide(colors, rest: BorderSide(color: colors.outline)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.surfaceContainerHigh
              : colors.surface,
        ),
        foregroundColor: WidgetStatePropertyAll(colors.onSurface),
      ),
    ),
    chipTheme: ChipThemeData(
      selectedColor: colors.surfaceContainerHigh,
      backgroundColor: colors.surface,
      // A checkmark would widen the chip when picked and shove its neighbours.
      showCheckmark: false,
      shape: shape,
      labelStyle: buttonText.copyWith(color: colors.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      side: WidgetStateBorderSide.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? BorderSide(color: focusRing(colors), width: focusRingWidth)
            : BorderSide(color: colors.outline),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
  );
}

/// Pass to every chip so selecting it changes colour instantly.
final noChipAnimation = ChipAnimationStyle(
  enableAnimation: AnimationStyle.noAnimation,
  selectAnimation: AnimationStyle.noAnimation,
  avatarDrawerAnimation: AnimationStyle.noAnimation,
  deleteDrawerAnimation: AnimationStyle.noAnimation,
);

/// A checkbox that flips state immediately. Material's [Checkbox] scales and
/// fades its tick in, which there is no switch to turn off.
class PlainCheckbox extends StatefulWidget {
  const PlainCheckbox({
    required this.value,
    required this.onChanged,
    this.tristate = false,
    super.key,
  });

  /// `null` draws the mixed state; only meaningful with [tristate].
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool tristate;

  @override
  State<PlainCheckbox> createState() => _PlainCheckboxState();
}

class _PlainCheckboxState extends State<PlainCheckbox> {
  bool focused = false;

  void _toggle() => widget.onChanged?.call(switch (widget.value) {
    false => true,
    true => widget.tristate ? null : false,
    null => false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = widget.onChanged != null;
    final on = widget.value != false;
    final fill = enabled
        ? colors.primary
        : colors.onSurface.withValues(alpha: 0.38);
    return Semantics(
      checked: widget.value == true,
      mixed: widget.tristate && widget.value == null,
      enabled: enabled,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowFocusHighlight: (v) => setState(() => focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _toggle(),
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? _toggle : null,
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: focused
                  ? Border.all(color: focusRing(colors), width: focusRingWidth)
                  : null,
            ),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: on ? fill : null,
                borderRadius: BorderRadius.circular(2),
                border: on
                    ? null
                    : Border.all(
                        color: enabled ? colors.outline : fill,
                        width: 1,
                      ),
              ),
              child: on
                  ? Icon(
                      widget.value == null ? Icons.remove : Icons.check,
                      size: 16,
                      color: colors.onPrimary,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {this.good = false, super.key});
  final String text;
  final bool good;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: good ? c.secondaryContainer : c.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: good ? c.onSecondaryContainer : c.onSurfaceVariant,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    super.key,
  });
  final IconData icon;
  final String title, body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    ),
  );
}
