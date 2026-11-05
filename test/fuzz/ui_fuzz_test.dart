// Runs the UI fuzzer. By default two seeds in each window, plus a
// keyboard-only run, so the widget suite stays quick; set the variables
// below for a campaign. Failures are shrunk and written to build/fuzz/ui-*.
//
//   MEOW_UI_FUZZ_SEEDS=0-49 MEOW_UI_FUZZ_STEPS=120 flutter test test/fuzz/ui_fuzz_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_fuzzer.dart';
import 'ui_fuzzer.dart';

void main() {
  final env = Platform.environment;
  final seeds = (env['MEOW_UI_FUZZ_SEEDS'] ?? '0-1').split('-').map(int.parse);
  final steps = int.parse(env['MEOW_UI_FUZZ_STEPS'] ?? '40');
  final out = Directory('build/fuzz')..createSync(recursive: true);

  for (final mode in ['mixed', 'keyboard']) {
    for (final viewport in mode == 'mixed' ? viewports : viewports.take(1)) {
      for (var seed = seeds.first; seed <= seeds.last; seed++) {
        // Each seed runs as one of the desktop platforms the app ships for.
        final platform = const [
          TargetPlatform.linux,
          TargetPlatform.windows,
          TargetPlatform.macOS,
        ][seed % 3];
        testWidgets(
          '$mode · ${viewport.name} · ${platform.name} · seed $seed',
          (tester) async {
            final dir = Directory.systemTemp.createTempSync('meow-ui-fuzz-');
            addTearDown(() => dir.deleteSync(recursive: true));
            // The starting event comes from the controller fuzzer: a seeded
            // tournament day, part way through.
            final source = (await tester.runAsync(
              () => buildEvent(seed, 60 + seed % 5 * 20, dir),
            ))!;
            final rng = Random(seed * 7919 + viewport.name.length);
            final weights = mode == 'mixed' ? uiMixed : uiKeyboard;
            final trace = [
              for (var i = 0; i < steps; i++) generateUi(rng, i, weights),
            ];
            var copies = 0;
            Future<TraceFailure?> attempt(List<Act> t) async {
              final path = freshCopy(source, dir, 'run${copies++}');
              try {
                await UiHarness(
                  tester,
                  path,
                  viewport,
                  platform: platform,
                ).run(t);
                return null;
              } on TraceFailure catch (f) {
                return f;
              }
            }

            final failure = await attempt(trace);
            if (failure == null) return;
            final minimal = await shrinkWith(
              trace.take(failure.step + 1).toList(),
              (t) async =>
                  (await attempt(t))?.violation.signature ==
                  failure.violation.signature,
              budget: 60,
            );
            final confirmed = await attempt(minimal) ?? failure;
            final name = 'ui-$mode-${viewport.name.replaceAll(' ', '-')}-$seed';
            File('${out.path}/$name.json').writeAsStringSync(
              const JsonEncoder.withIndent(' ').convert({
                'seed': seed,
                'mode': mode,
                'viewport': viewport.name,
                'platform': platform.name,
                'violation': '${confirmed.violation}',
                'trace': [for (final a in minimal) a.toJson()],
              }),
            );
            fail(
              [
                'violation ${confirmed.violation}',
                'at step ${confirmed.step}: ${confirmed.act}',
                'minimal trace (${minimal.length} steps):',
                for (final a in minimal) '  $a',
              ].join('\n'),
            );
          },
          timeout: const Timeout(Duration(minutes: 10)),
        );
      }
    }
  }
}
