import 'dart:convert';
import 'dart:io';

import '../domain/fide_checker.dart';
import '../domain/fide_generator.dart';
import '../domain/model.dart';
import '../domain/pairing.dart';
import '../domain/standings.dart';
import '../domain/trf.dart';
import '../domain/trf_read.dart';

/// The command line of Meow-Chess's FIDE tools: the Pairings and
/// Tie-Breaks Checker (PTC) and the Random Tournament Generator (RTG) the
/// FIDE Technical Commission describes (TEC Manual 3.9.4), plus pairing
/// one round from a TRF. Both `meow_chess -check file.trf` (the TEC
/// Manual's form) and `meow_fide check file.trf` reach it.
const fideCliUsage = '''
Meow-Chess FIDE tools

  check FILE [--round N]... [--pairings-only | --standings-only]
             [--inputs DIR]
      Rebuilds the tournament in a TRF (TRF26, TRF16 or TRF06), pairs each
      round with the FIDE Dutch engine, ranks the standings by the file's
      tie-breaks (record 202 or 212) and lists every difference. --inputs
      saves the engine's input file for each round. Exit status 0 when the
      file matches, 1 when it does not, 3 when it cannot be read.

  generate --output FILE [--count K] [--seed S] [--players N] [--rounds R]
           [--ratings HIGH LOW] [--unrated RATE] [--draws RATE]
           [--forfeits RATE] [--half-byes RATE] [--zero-byes RATE]
           [--full-byes RATE] [--withdrawals RATE] [--late-entries RATE]
           [--unusual RATE] [--short-games RATE] [--baku]
           [--pab win|draw|loss] [--tiebreaks CODE,CODE,...]
      Simulates FIDE-rated Swiss tournaments, paired by the FIDE Dutch
      engine with results drawn from the FIDE rating table, and writes each
      as a TRF26 file. With --count above 1, FILE may contain %d for the
      tournament number (the seed); otherwise the number is added before
      the extension.

  pair FILE
      Pairs the next round of the tournament in a TRF and prints the pairs
      as "white black" starting ranks, the pairing-allocated bye as
      "rank 0", after a line with the number of pairs.

  values FILE [--tiebreaks CODE,CODE,...]
      Prints each player's starting rank, place, points and tie-break
      values, tab separated: the file's tie-breaks, or those given.
''';

/// Whether [arg] starts a FIDE tools command (`-check`, `check`, …), so
/// the app runs it instead of opening its window.
bool isFideCliCommand(String arg) => const {
  'check',
  'generate',
  'pair',
  'values',
  'help',
}.contains(arg.replaceFirst(RegExp(r'^-+'), ''));

/// Runs the FIDE tools on [args]; returns the exit status.
Future<int> runFideCli(List<String> args, {IOSink? out, IOSink? err}) async {
  final o = out ?? stdout, e = err ?? stderr;
  final command = args.isEmpty
      ? ''
      : args.first.replaceFirst(RegExp(r'^-+'), '');
  if (command.isEmpty || command == 'help' || command == 'h') {
    o.write(fideCliUsage);
    return command.isEmpty ? 64 : 0;
  }
  final rest = args.skip(1).toList();
  try {
    switch (command) {
      case 'check':
        return await _check(rest, o);
      case 'generate':
        return await _generate(rest, o);
      case 'pair':
        return await _pair(rest, o);
      case 'values':
        return await _values(rest, o);
      default:
        e.writeln('Unknown command "${args.first}".\n');
        e.write(fideCliUsage);
        return 64;
    }
  } on TrfFormatException catch (x) {
    e.writeln('The file cannot be read: $x');
    return 3;
  } on TournamentException catch (x) {
    e.writeln(x.message);
    return 3;
  } on _Usage catch (x) {
    e.writeln('${x.message}\n');
    e.write(fideCliUsage);
    return 64;
  } on FileSystemException catch (x) {
    e.writeln('${x.message}: ${x.path ?? ''}');
    return 5;
  }
}

class _Usage implements Exception {
  const _Usage(this.message);
  final String message;
}

/// Reads a TRF as UTF-8, or as Latin-1 when it is not valid UTF-8 (older
/// programs write 8-bit files).
Future<String> readTrfFile(String path) async {
  final bytes = await File(path).readAsBytes();
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// Splits [args] into positional arguments and `--name value` options;
/// [flags] take no value. Repeated options keep every value.
(List<String>, Map<String, List<String>>) _options(
  List<String> args, {
  Set<String> flags = const {},
  Map<String, int> arity = const {},
}) {
  final positional = <String>[];
  final options = <String, List<String>>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) {
      positional.add(a);
      continue;
    }
    final name = a.substring(2);
    if (flags.contains(name)) {
      (options[name] ??= []).add('true');
      continue;
    }
    final count = arity[name] ?? 1;
    for (var k = 0; k < count; k++) {
      if (i + 1 >= args.length) throw _Usage('$a needs a value.');
      (options[name] ??= []).add(args[++i]);
    }
  }
  return (positional, options);
}

String _file(List<String> positional, String command) {
  if (positional.length != 1) throw _Usage('$command takes one TRF file.');
  return positional.single;
}

Future<int> _check(List<String> args, IOSink o) async {
  final (positional, options) = _options(
    args,
    flags: {'pairings-only', 'standings-only'},
  );
  final path = _file(positional, 'check');
  final rounds = options['round']?.map((r) {
    final n = int.tryParse(r);
    if (n == null || n < 1) throw _Usage('--round needs a round number.');
    return n;
  }).toSet();
  final inputs = options['inputs']?.single;
  final report = checkTrf(
    await readTrfFile(path),
    rounds: rounds,
    pairings: options['standings-only'] == null,
    ranking: options['pairings-only'] == null,
    keepInputs: inputs != null,
  );
  if (inputs != null) {
    final dir = await Directory(inputs).create(recursive: true);
    for (final MapEntry(key: n, value: text) in report.inputs.entries) {
      await File('${dir.path}/round$n.trf').writeAsString(text);
    }
  }
  o.writeln(report.text);
  return report.ok ? 0 : 1;
}

double _rate(Map<String, List<String>> options, String name, double fallback) {
  final v = options[name]?.last;
  if (v == null) return fallback;
  final r = double.tryParse(v);
  if (r == null || r < 0 || r > 1) {
    throw _Usage('--$name needs a rate between 0 and 1.');
  }
  return r;
}

int _int(Map<String, List<String>> options, String name, int fallback) {
  final v = options[name]?.last;
  if (v == null) return fallback;
  return int.tryParse(v) ?? (throw _Usage('--$name needs a whole number.'));
}

Future<int> _generate(List<String> args, IOSink o) async {
  final (positional, options) = _options(
    args,
    flags: {'baku'},
    arity: {'ratings': 2},
  );
  if (positional.isNotEmpty) {
    throw _Usage('generate takes options only, such as --output FILE.');
  }
  final output = options['output']?.last;
  if (output == null) throw _Usage('generate needs --output FILE.');
  final count = _int(options, 'count', 1);
  final first = _int(options, 'seed', 1);
  final ratings = options['ratings'];
  final high = ratings == null ? 2600 : int.tryParse(ratings[0]);
  final low = ratings == null ? 1400 : int.tryParse(ratings[1]);
  if (high == null || low == null) {
    throw _Usage('--ratings needs the highest and lowest rating.');
  }
  final pab = switch (options['pab']?.last ?? 'win') {
    'win' => 2,
    'draw' => 1,
    'loss' => 0,
    _ => throw const _Usage('--pab is win, draw or loss.'),
  };
  final tiebreaks = options['tiebreaks']?.last.split(',');
  for (var i = 0; i < count; i++) {
    final seed = first + i;
    final settings = RandomTournamentSettings(
      seed: seed,
      players: _int(options, 'players', 30),
      rounds: _int(options, 'rounds', 9),
      highestRating: high,
      lowestRating: low,
      unratedRate: _rate(options, 'unrated', 0),
      drawRate: _rate(options, 'draws', 0.3),
      forfeitRate: _rate(options, 'forfeits', 0.02),
      halfByeRate: _rate(options, 'half-byes', 0.03),
      zeroByeRate: _rate(options, 'zero-byes', 0.01),
      fullByeRate: _rate(options, 'full-byes', 0),
      withdrawRate: _rate(options, 'withdrawals', 0.01),
      lateEntryRate: _rate(options, 'late-entries', 0),
      unusualRate: _rate(options, 'unusual', 0),
      shortGameRate: _rate(options, 'short-games', 0),
      baku: options['baku'] != null,
      pabPoints: pab,
      tiebreaks: [
        for (final c in tiebreaks ?? const ['BH/C1', 'BH', 'SB', 'DE', 'WIN'])
          fideTiebreakCode(c) ??
              (throw _Usage('Tie-break "$c" is not one Meow-Chess computes.')),
      ],
    );
    final event = generateFideTournament(settings);
    final path = count == 1
        ? output
        : output.contains('%d')
        ? output.replaceAll('%d', '$seed'.padLeft(5, '0'))
        : output.replaceFirst(
            RegExp(r'(\.[^./\\]*)?$'),
            '-${'$seed'.padLeft(5, '0')}${RegExp(r'\.[^./\\]*$').firstMatch(output)?[0] ?? '.trf'}',
          );
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '### Meow-Chess random tournament, seed $seed\r\n${writeTrf(event, event.sections.single)}',
    );
    if (count > 1 && (i + 1) % 100 == 0) o.writeln('${i + 1} written');
  }
  o.writeln(count == 1 ? 'Wrote $output' : 'Wrote $count tournaments');
  return 0;
}

Future<int> _pair(List<String> args, IOSink o) async {
  final (positional, _) = _options(args);
  final file = TrfFile.parse(await readTrfFile(_file(positional, 'pair')));
  var ids = 0;
  final event = trfToEvent(
    file,
    newId: () => 'x${++ids}',
    today: '2026-01-01',
  ).event;
  final section = event.sections.single;
  final rankOf = {for (final (i, id) in section.fideOrder.indexed) id: i + 1};
  final round = proposeRound(event, section, () => 'next');
  o.writeln(round.games.length + round.byes.where((b) => b.allocated).length);
  for (final g in round.games) {
    o.writeln('${rankOf[g.white]} ${rankOf[g.black]}');
  }
  for (final b in round.byes.where((b) => b.allocated)) {
    o.writeln('${rankOf[b.player]} 0');
  }
  return 0;
}

Future<int> _values(List<String> args, IOSink o) async {
  final (positional, options) = _options(args);
  final file = TrfFile.parse(await readTrfFile(_file(positional, 'values')));
  var ids = 0;
  var event = trfToEvent(
    file,
    newId: () => 'x${++ids}',
    today: '2026-01-01',
  ).event;
  if (options['tiebreaks']?.last case final codes?) {
    event = event.copy(
      fideTiebreaks: [
        for (final c in codes.split(','))
          fideTiebreakCode(c) ??
              (throw _Usage('Tie-break "$c" is not one Meow-Chess computes.')),
      ],
    );
  }
  final section = event.sections.single;
  final rankOf = {for (final (i, id) in section.fideOrder.indexed) id: i + 1};
  final rows = standings(event, section);
  o.writeln(['Rank', 'StartNo', 'PTS', ...event.fideTiebreaks].join('\t'));
  final byStart = [...rows]
    ..sort((a, b) => rankOf[a.player.id]!.compareTo(rankOf[b.player.id]!));
  for (final row in byStart) {
    o.writeln(
      [
        row.rank,
        rankOf[row.player.id],
        _number(row.points / 2),
        for (final t in row.tiebreaks) _number(t.number),
      ].join('\t'),
    );
  }
  return 0;
}

String _number(num v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();
