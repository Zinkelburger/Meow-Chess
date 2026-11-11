// A seeded, shrinking fuzzer over the real workspace: taps, typing, keys and
// scrolling chosen from what the semantics tree says can be done, on events
// built by the controller fuzzer, at several window sizes and text scales.
// See docs/TESTING.md, "UI fuzzer".
import 'dart:io';
import 'dart:math';
import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' hide LayoutCallback;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
// ignore: implementation_imports
import 'package:printing/src/interface.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';

import 'controller_fuzzer.dart';

/// Stands in for the printer: every print builds its PDF through the app's
/// real layout callback, so a report that cannot be laid out fails the run.
class FakePrinter extends PrintingPlatform {
  var printed = 0;
  @override
  Future<PrintingInfo> info() async => const PrintingInfo(
    canPrint: true,
    canShare: true,
    canRaster: true,
    canListPrinters: true,
  );
  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
    bool windowsModernDialog,
  ) async {
    await onLayout(format);
    printed++;
    return true;
  }

  @override
  Future<List<Printer>> listPrinters() async => const [];
  @override
  Future<Printer?> pickPrinter(Rect bounds) async => null;
  @override
  Future<bool> sharePdf(
    Uint8List bytes,
    String filename,
    Rect bounds,
    String? subject,
    String? body,
    List<String>? emails,
  ) async => true;
  @override
  Future<Uint8List> convertHtml(
    String html,
    String? baseUrl,
    PdfPageFormat format,
  ) async => Uint8List(0);
  @override
  Stream<PdfRaster> raster(Uint8List document, List<int>? pages, double dpi) =>
      const Stream.empty();
}

/// A window the director might have: size and text scale.
typedef Viewport = ({String name, Size size, double text});

const viewports = <Viewport>[
  (name: 'desktop', size: Size(1400, 900), text: 1),
  (name: 'minimum window', size: Size(960, 540), text: 1),
  (name: 'large text', size: Size(1400, 900), text: 2),
];

/// Text a director might type, and text that stresses fields.
const _texts = [
  '',
  '1',
  '0',
  '=',
  '1-0',
  '½',
  'Kim Lee',
  '1800',
  '12345678',
  'A6012345',
  'Zoë Ñúñez-李',
  '=HYPERLINK("x")',
  '    ',
  '-5',
  '99999',
  '2026-02-30',
  'A very long name that keeps going well past any column width anyone set',
];

const _keys = [
  LogicalKeyboardKey.tab,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.escape,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit0,
  LogicalKeyboardKey.equal,
  LogicalKeyboardKey.space,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.backspace,
];

/// What can be acted on: a semantics node with a tap action, on screen.
class Target {
  Target(this.node, this.rect, this.label, this.textField);
  final SemanticsNode node;
  final Rect rect;
  final String label;
  final bool textField;

  /// Stable across steps: what the node says it is, not its tree position.
  String get identity => '$label|${textField ? 'field' : 'button'}';
}

Rect _globalRect(SemanticsNode n) {
  var rect = n.rect;
  for (SemanticsNode? x = n; x != null; x = x.parent) {
    if (x.transform case final t?) rect = MatrixUtils.transformRect(t, rect);
  }
  return rect;
}

/// Every tappable node inside [screen], in tree order.
List<Target> targets(Size screen) {
  final root = RendererBinding
      .instance
      .renderViews
      .first
      .owner
      ?.semanticsOwner
      ?.rootSemanticsNode;
  final out = <Target>[];
  void visit(SemanticsNode n) {
    final d = n.getSemanticsData();
    final enabled = d.flagsCollection.isEnabled != Tristate.isFalse;
    if (!n.isInvisible &&
        !d.flagsCollection.isHidden &&
        enabled &&
        d.hasAction(SemanticsAction.tap)) {
      final rect = _globalRect(n);
      final center = rect.center;
      if (center.dx > 0 &&
          center.dy > 0 &&
          center.dx < screen.width &&
          center.dy < screen.height) {
        out.add(
          Target(
            n,
            rect,
            [d.label, d.tooltip, d.value].where((s) => s.isNotEmpty).join(' '),
            d.flagsCollection.isTextField,
          ),
        );
      }
    }
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  if (root != null) visit(root);
  return out;
}

/// Runs a UI trace against the workspace on [eventPath] in [viewport].
/// Throws [TraceFailure] at the first broken invariant.
class UiHarness {
  UiHarness(
    this.tester,
    this.eventPath,
    this.viewport, {
    this.platform = TargetPlatform.linux,
  });
  final WidgetTester tester;
  final String eventPath;
  final Viewport viewport;

  /// Widget tests default to Android; the app ships for the desktop, whose
  /// keys, scrolling and shortcuts differ.
  final TargetPlatform platform;
  late FuzzController c;
  final ids = FuzzIds();
  var steps = 0, taps = 0, typed = 0, keys = 0, scrolls = 0, skipped = 0;
  final labels = <String>{};
  final printer = FakePrinter();
  final _details = <FlutterErrorDetails>[];

  Future<void> run(List<Act> trace, {Future<void> Function()? after}) async {
    final view = tester.view;
    view.physicalSize = viewport.size;
    view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = viewport.text;
    debugDefaultTargetPlatformOverride = platform;
    final printing = PrintingPlatform.instance;
    PrintingPlatform.instance = printer;
    // App folders, such as where the FIDE rating list is kept.
    final support = Directory.systemTemp.createTempSync('meow-ui-support-');
    const folders = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      folders,
      (_) async => support.path,
    );
    final semantics = tester.ensureSemantics();
    // The details name the widget that caused a layout error.
    final reported = FlutterError.onError;
    FlutterError.onError = (details) {
      _details.add(details);
      reported?.call(details);
    };
    c = FuzzController(SqliteEventRepository(eventPath), ids, pairInline: true);
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: meowTheme(Brightness.light),
          home: Workspace(
            controller: c,
            path: eventPath,
            onClose: () {},
            onTheme: () {},
          ),
        ),
      );
      await _settle();
      _check(-1, const Act('mount', [], -1));
      await _guidelines(-1, const Act('mount', [], -1));
      for (final (i, act) in trace.indexed) {
        ids.begin(act.tag);
        await _step(act);
        await _settle();
        _check(i, act);
        // Every tenth step, and the last, so a shrunk trace still checks.
        if (i % 10 == 9 || i == trace.length - 1) await _guidelines(i, act);
        steps++;
      }
      await after?.call();
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      c.dispose();
      semantics.dispose();
      FlutterError.onError = reported;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      debugDefaultTargetPlatformOverride = null;
      PrintingPlatform.instance = printing;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        folders,
        null,
      );
      support.deleteSync(recursive: true);
    }
  }

  /// Lets frames, timers and microtasks run without waiting for animations
  /// that never end, such as a progress indicator.
  Future<void> _settle() async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (!tester.binding.hasScheduledFrame) break;
    }
  }

  Size get _screen => viewport.size;

  X? _pick<X>(List<X> xs, int arg, String Function(X) key) {
    X? best;
    int? low;
    for (final x in xs) {
      final h = Harness.mixForUi(arg, key(x));
      if (low == null || h < low) {
        best = x;
        low = h;
      }
    }
    return best;
  }

  Future<void> _step(Act a) async {
    switch (a.kind) {
      case 'tap':
        final t = _pick(
          targets(_screen).where((t) => !t.textField).toList(),
          a.arg(0),
          (t) => t.identity,
        );
        if (t == null) return _skip();
        labels.add(t.identity);
        taps++;
        await tester.tapAt(t.rect.center);
      case 'type':
        final t = _pick(
          targets(_screen).where((t) => t.textField).toList(),
          a.arg(0),
          (t) => t.identity,
        );
        if (t == null) return _skip();
        labels.add(t.identity);
        typed++;
        await tester.tapAt(t.rect.center);
        await tester.pump();
        tester.testTextInput.enterText(_texts[a.arg(1).abs() % _texts.length]);
        if (a.arg(2).isEven) {
          await tester.testTextInput.receiveAction(TextInputAction.done);
        }
      case 'key':
        keys++;
        final key = _keys[a.arg(0).abs() % _keys.length];
        final shift = a.arg(1) % 4 == 0, control = a.arg(1) % 7 == 0;
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(key);
        if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      case 'scroll':
        final scrollables = find.byType(Scrollable).hitTestable().evaluate();
        if (scrollables.isEmpty) return _skip();
        scrolls++;
        final list = scrollables.toList();
        final box =
            list[a.arg(0).abs() % list.length].renderObject as RenderBox;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        if (!(Offset.zero & _screen).contains(rect.center)) return _skip();
        await tester.dragFrom(
          rect.center,
          Offset(0, (a.arg(1) % 2 == 0 ? -1 : 1) * 300.0),
        );
      default:
        throw ArgumentError('Unknown UI step ${a.kind}');
    }
  }

  void _skip() => skipped++;

  /// After every step: nothing threw, nothing overflowed, and the event in
  /// memory is the event on disk and in history.
  void _check(int i, Act act) {
    final error = tester.takeException();
    if (error != null) {
      throw TraceFailure(
        i,
        act,
        Violation(
          'ui-exception',
          _describe(error as Object, _details.lastOrNull),
          errorType: '${error.runtimeType}',
        ),
      );
    }
    final e = c.event!;
    try {
      validateEvent(e);
    } on TournamentException catch (x) {
      throw TraceFailure(i, act, Violation('invalid-event', x.message));
    }
    if (c.repository.load()?.encode() != e.encode()) {
      throw TraceFailure(
        i,
        act,
        Violation('persistence', 'Saved rows differ from the event shown.'),
      );
    }
    final head = c.graph.head;
    if (head == null ||
        c.repository.snapshot(head).copy(revision: 0).encode() !=
            e.copy(revision: 0).encode()) {
      throw TraceFailure(
        i,
        act,
        Violation('history-head', 'The current history node is not the event.'),
      );
    }
  }

  /// The error's first line and, for a layout error, the widget that caused
  /// it, which Flutter names as a source location.
  static String _describe(Object error, FlutterErrorDetails? details) {
    final lines = '${details ?? error}'.split('\n');
    final cause = lines.indexWhere(
      (l) => l.contains('relevant error-causing widget'),
    );
    return [
      '$error'.split('\n').first,
      for (final l in lines.skip(cause + 1).take(cause >= 0 ? 2 : 0))
        if (l.trim().isNotEmpty) l.trim(),
    ].join(' · ');
  }

  /// Every control has a name a screen reader can say, and text is legible.
  Future<void> _guidelines(int i, Act act) async {
    for (final guideline in [
      labeledTapTargetGuideline,
      textContrastGuideline,
    ]) {
      final result = await guideline.evaluate(tester);
      if (!result.passed) {
        throw TraceFailure(
          i,
          act,
          Violation(
            'a11y-${guideline.description.split(' ').first.toLowerCase()}',
            result.reason ?? guideline.description,
          ),
        );
      }
    }
  }
}

/// UI step weights: mostly taps, as a director clicks through; or the
/// keyboard alone, as at the score table at the end of a round.
const uiMixed = {'tap': 10, 'type': 3, 'key': 4, 'scroll': 2};
const uiKeyboard = {'key': 1};

Act generateUi(Random rng, int tag, [Map<String, int> weights = uiMixed]) {
  var roll = rng.nextInt(weights.values.fold(0, (a, b) => a + b));
  for (final MapEntry(:key, :value) in weights.entries) {
    if ((roll -= value) < 0) {
      return Act(key, [for (var i = 0; i < 3; i++) rng.nextInt(1 << 16)], tag);
    }
  }
  throw StateError('unreachable');
}

/// Builds the event a UI run starts from: a seeded controller trace, so the
/// UI meets the deep states the controller fuzzer reaches. Returns its path.
Future<String> buildEvent(int seed, int steps, Directory dir) async {
  await fuzzOnce(seed, steps, dir);
  return '${dir.path}/fuzz.meow';
}

/// Copies the starting event, so every replay begins from the same file.
String freshCopy(String source, Directory dir, String name) {
  final path = '${dir.path}/$name.meow';
  File(source).copySync(path);
  return path;
}
