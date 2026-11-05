// Runs the controller fuzzer. By default a small fixed budget, so the unit
// suite stays fast and deterministic; set the variables below for a long
// campaign. Every failure is shrunk to a minimal trace and written to
// build/fuzz/, ready to pin in test/fuzz/regressions/.
//
//   MEOW_FUZZ_SEEDS=0-499 MEOW_FUZZ_STEPS=400 flutter test test/fuzz
//   MEOW_FUZZ_REPLAY=build/fuzz/seed-17.json flutter test test/fuzz
//   MEOW_FUZZ_STRICT=1   also fail on commands the repository had to refuse
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'controller_fuzzer.dart';

(int, int) _range(String? spec, (int, int) fallback) {
  if (spec == null || spec.isEmpty) return fallback;
  final parts = spec.split('-').map(int.parse).toList();
  return (parts.first, parts.last);
}

String _report(int? seed, List<Act> minimal, TraceFailure f) {
  final stack = f.violation.stack?.toString().split('\n').take(12).join('\n');
  return [
    if (seed != null) 'seed $seed',
    'violation ${f.violation}',
    'at step ${f.step}: ${f.act}',
    'minimal trace (${minimal.length} steps):',
    for (final a in minimal) '  $a',
    if (stack != null) 'stack:\n$stack',
  ].join('\n');
}

void main() {
  final env = Platform.environment;
  final strict = env['MEOW_FUZZ_STRICT'] == '1';
  final (first, last) = _range(env['MEOW_FUZZ_SEEDS'], (0, 11));
  final steps = int.parse(env['MEOW_FUZZ_STEPS'] ?? '120');
  final out = Directory('build/fuzz')..createSync(recursive: true);

  Future<void> check(
    int? seed,
    List<Act> trace,
    TraceFailure? f,
    Harness h,
  ) async {
    if (f == null) {
      if (strict && h.soft.isNotEmpty) {
        fail(
          'seed $seed: the repository refused an invalid event:\n  ${h.soft.toSet().join('\n  ')}',
        );
      }
      return;
    }
    final work = Directory.systemTemp.createTempSync('meow-shrink-');
    addTearDown(() => work.deleteSync(recursive: true));
    final minimal = await shrink(
      trace,
      f.violation.signature,
      work,
      strict: strict,
    );
    final confirmed = await replay(minimal, work, strict: strict) ?? f;
    final name = seed == null ? 'replay' : 'seed-$seed';
    File('${out.path}/$name.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'seed': seed,
        'violation': '${confirmed.violation}',
        'trace': [for (final a in minimal) a.toJson()],
      }),
    );
    fail(_report(seed, minimal, confirmed));
  }

  if (env['MEOW_FUZZ_REPLAY'] case final path?) {
    test('replay $path', () async {
      final j = jsonDecode(File(path).readAsStringSync()) as Map;
      final trace = [
        for (final a in j['trace'] as List)
          Act.fromJson(a as Map<String, dynamic>),
      ];
      final f = await replay(trace, Directory.systemTemp, strict: strict);
      if (f != null) fail(_report(null, trace, f));
    });
    return;
  }

  group('pinned traces', () {
    final dir = Directory('test/fuzz/regressions');
    if (!dir.existsSync()) return;
    for (final file in dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.json'),
    )) {
      test(file.uri.pathSegments.last, () async {
        final j = jsonDecode(file.readAsStringSync()) as Map;
        final trace = [
          for (final a in j['trace'] as List)
            Act.fromJson(a as Map<String, dynamic>),
        ];
        final f = await replay(
          trace,
          Directory.systemTemp,
          strict: strict || j['strict'] == true,
        );
        if (f != null) {
          fail('${j['violation']} is back:\n${_report(null, trace, f)}');
        }
      });
    }
  });

  group('random tournament days', () {
    var commands = 0, refused = 0, skipped = 0;
    final soft = <String>{};
    final tally = <String, List<int>>{};
    final depth = <int>[];
    final reasons = <String, Map<String, int>>{};
    for (var seed = first; seed <= last; seed++) {
      test('seed $seed', () async {
        final dir = Directory.systemTemp.createTempSync('meow-fuzz-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final (trace, f, h) = await fuzzOnce(seed, steps, dir, strict: strict);
        commands += h.commands;
        refused += h.refused;
        skipped += h.skipped;
        soft.addAll(h.soft);
        depth.add(h.maxRounds);
        for (final MapEntry(:key, :value) in h.reasons.entries) {
          final r = reasons[key] ??= {};
          for (final MapEntry(key: m, value: n) in value.entries) {
            r[m] = (r[m] ?? 0) + n;
          }
        }
        for (final MapEntry(:key, :value) in h.tally.entries) {
          final t = tally[key] ??= [0, 0];
          t[0] += value[0];
          t[1] += value[1];
        }
        await check(seed, trace, f, h);
      }, timeout: const Timeout(Duration(minutes: 10)));
    }
    tearDownAll(() {
      if (env['MEOW_FUZZ_VERBOSE'] == '1') {
        for (final MapEntry(:key, :value) in reasons.entries) {
          final top = value.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          // ignore: avoid_print
          print(
            '$key refused: ${top.take(3).map((e) => '${e.value}× ${e.key}').join(' | ')}',
          );
        }
      }
      // ignore: avoid_print
      print(
        'fuzz: seeds $first-$last × $steps steps, $commands commands, '
        '$refused refused, $skipped skipped, ${soft.length} invalid events refused by the repository'
        '${soft.isEmpty ? '' : ':\n  ${soft.take(20).join('\n  ')}'}\n'
        'deepest section per seed (rounds): ${depth.join(' ')}\n'
        'accepted/refused: ${(tally.keys.toList()..sort()).map((k) => '$k ${tally[k]![0]}/${tally[k]![1]}').join(', ')}',
      );
    });
  });
}
