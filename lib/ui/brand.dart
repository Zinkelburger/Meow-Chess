import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The same transparent badge used by the desktop launchers and app window.
class MeowLogo extends StatelessWidget {
  const MeowLogo({this.size = 38, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/icon/meow_chess_master.png',
    width: size,
    height: size,
    filterQuality: FilterQuality.high,
    semanticLabel: 'Meow Chess logo',
  );
}

class WelcomeBrandHeader extends StatelessWidget {
  const WelcomeBrandHeader({
    required this.logoKey,
    required this.showLogo,
    required this.light,
    required this.onTheme,
    super.key,
  });

  final GlobalKey logoKey;
  final bool showLogo;
  final bool light;
  final VoidCallback onTheme;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = Theme.of(context).textTheme.displayLarge!.copyWith(
        fontSize: 96,
        fontWeight: FontWeight.w700,
        letterSpacing: -2,
        height: 1.05,
      );
      final measurement = TextPainter(
        text: TextSpan(text: 'Meow Chess', style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final titleWidth = measurement.width;
      measurement.dispose();
      final logoSize = math.min(396.0, constraints.maxWidth * .55);
      const gap = 24.0;
      final scale =
          ((constraints.maxWidth - logoSize - gap * 2) / (titleWidth + 96))
              .clamp(0.0, 1.0);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            key: logoKey,
            width: logoSize,
            height: logoSize,
            child: Opacity(
              opacity: showLogo ? 1 : 0,
              child: MeowLogo(size: logoSize),
            ),
          ),
          const SizedBox(width: gap),
          SizedBox(
            width: titleWidth * scale,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Meow Chess', maxLines: 1, style: style),
            ),
          ),
          const SizedBox(width: gap),
          IconButton(
            onPressed: onTheme,
            tooltip: light ? 'Dark mode' : 'Light mode',
            iconSize: 96 * scale,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(
              light ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            ),
          ),
        ],
      );
    },
  );
}

/// Plays once per app launch; the live target keeps docking correct on resize.
class LogoEntrance extends StatefulWidget {
  const LogoEntrance({
    required this.targetKey,
    required this.onComplete,
    required this.child,
    super.key,
  });

  final GlobalKey targetKey;
  final VoidCallback onComplete;
  final Widget child;

  @override
  State<LogoEntrance> createState() => _LogoEntranceState();
}

class _LogoEntranceState extends State<LogoEntrance>
    with SingleTickerProviderStateMixin {
  late final animation =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2100),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onComplete();
      });
  final stageKey = GlobalKey();
  bool started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (MediaQuery.disableAnimationsOf(context)) {
          animation.value = 1;
        } else {
          animation.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => AnimatedBuilder(
      animation: animation,
      child: widget.child,
      builder: (context, child) {
        final complete = animation.isCompleted;
        final size = constraints.biggest;
        final catSize = math.min(size.width, size.height);
        final center = Rect.fromCenter(
          center: size.center(Offset.zero),
          width: catSize,
          height: catSize,
        );
        final arrival = const Interval(
          0,
          .24,
          curve: Curves.easeOutBack,
        ).transform(animation.value);
        final docking = const Interval(
          .70,
          1,
          curve: Curves.easeInOutCubic,
        ).transform(animation.value);
        Rect? target;
        final logo = widget.targetKey.currentContext?.findRenderObject();
        final stage = stageKey.currentContext?.findRenderObject();
        if (logo is RenderBox && logo.hasSize && stage is RenderBox) {
          target =
              stage.globalToLocal(logo.localToGlobal(Offset.zero)) & logo.size;
        }
        final entering = center.shift(Offset(0, -(size.height + catSize) / 2));
        final position = docking > 0
            ? Rect.lerp(center, target ?? center, docking)!
            : Rect.lerp(entering, center, arrival)!;
        return Stack(
          key: stageKey,
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              excluding: !complete,
              child: IgnorePointer(ignoring: !complete, child: child!),
            ),
            if (!complete) ...[
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(
                    context,
                  ).scaffoldBackgroundColor.withValues(alpha: 1 - docking),
                ),
              ),
              Positioned.fromRect(
                rect: position,
                child: Opacity(
                  opacity: target == null ? 1 - docking : 1,
                  child: MeowLogo(size: position.width),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}
