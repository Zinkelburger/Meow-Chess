import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/fide.dart';
import '../domain/model.dart';
import '../domain/standings.dart' show fideSectionTiebreaks;
import '../domain/trf.dart';
import '../domain/us_chess.dart';
import 'dbf_export.dart' show ReportDestination, ReportIssue, ReportRepair;
import 'publish_file.dart';

/// The FIDE rating report: one TRF26 file per FIDE-rated section, since
/// FIDE registers each section as its own tournament. In the United States
/// the files go to the US Chess FIDE Events Manager after the US Chess
/// report; elsewhere, to the national rating officer.
///
/// Requirements: TRF26 (`research/local/fide-trf26-spec.txt`), the FIDE
/// Rating Regulations and the US Chess FIDE-event policy
/// (`research/local/uscf-fide-events.txt`).

/// Sections in the FIDE report.
List<Section> fideSections(Event e) =>
    e.sections.where((s) => s.fideRated && s.players.isNotEmpty).toList();

String _list(Iterable<String> names) {
  final all = names.toList();
  return all.length <= 6
      ? all.join(', ')
      : '${all.take(5).join(', ')} and ${all.length - 5} more';
}

/// B.02 1.1.x: the least time each player needs for a standard game to be
/// rated, by the highest rating in the game.
int _standardMinimum(int highest) => highest >= 2400
    ? 120
    : highest >= 1800
    ? 90
    : 60;

/// Everything that would stop FIDE rating a section, and advice. Empty
/// means the files can be created.
List<ReportIssue> fideIssues(Event e) {
  final issues = <ReportIssue>[];
  void add(
    String message, {
    List<ReportRepair> repairs = const [],
    bool blocking = true,
  }) => issues.add(ReportIssue(message, repairs, blocking: blocking));
  ReportRepair event(String field) =>
      ReportRepair('Edit FIDE details', ReportDestination.event, field: field);
  ReportRepair player(Player p, String field) => ReportRepair(
    'Edit ${p.name}',
    ReportDestination.player,
    id: p.id,
    field: field,
  );

  final sections = fideSections(e);
  if (sections.isEmpty) {
    add('No section is FIDE rated. Choose FIDE in a section\'s settings.');
    return issues;
  }
  final fide = e.fide;
  if (fide.chiefArbiter.name.trim().isEmpty ||
      !isFideId(fide.chiefArbiter.id.trim())) {
    add(
      'Name the chief arbiter and their FIDE ID. FIDE rates only events run by a licensed arbiter.',
      repairs: [event('chiefArbiter')],
    );
  }
  if (e.city.trim().isEmpty) {
    add(
      'Enter the event\'s city under Report details.',
      repairs: [
        const ReportRepair(
          'Edit report details',
          ReportDestination.report,
          field: 'city',
        ),
      ],
    );
  }
  for (final d in fide.deputies) {
    if (!isFideId(d.id.trim())) {
      add(
        'Deputy arbiter ${d.name} needs a FIDE ID.',
        repairs: [event('deputies')],
      );
    }
  }
  final federation = fide.federation.trim();
  if (federation.isNotEmpty && !isFederationCode(federation)) {
    add(
      'The event federation "$federation" is not a three-letter FIDE code.',
      repairs: [event('federation')],
    );
  }

  for (final s in sections) {
    final players = [for (final id in s.players) e.player(id)];
    if (!s.finished) {
      add(
        '${s.name} is in round ${s.rounds.length} of ${s.plannedRounds}. Its FIDE file is made once every round has results.',
        repairs: [
          ReportRepair(
            'Go to ${s.name} results',
            ReportDestination.results,
            id: s.id,
          ),
        ],
      );
    }
    final TimeControl tc;
    try {
      tc = TimeControl.parse(s.effectiveTimeControl(e));
    } on TournamentException catch (error) {
      add(
        '${s.name}: ${error.message}',
        repairs: [
          ReportRepair('Edit ${s.name}', ReportDestination.section, id: s.id),
        ],
      );
      continue;
    }
    final category = fideCategory(tc);
    if (category == null) {
      add(
        '${s.name}: FIDE does not rate ${s.effectiveTimeControl(e)}. A game needs more than 3 minutes for 60 moves.',
        repairs: [
          ReportRepair('Edit ${s.name}', ReportDestination.section, id: s.id),
        ],
      );
    } else if (category == FideCategory.standard) {
      final highest = players
          .map((p) => fideRating(p, category))
          .fold(0, (a, b) => a > b ? a : b);
      final need = _standardMinimum(highest);
      if (tc.totalMinutes < need) {
        add(
          '${s.name}: ${s.effectiveTimeControl(e)} gives each player ${tc.totalMinutes} minutes for 60 moves. Standard games with a player rated ${highest >= 2400 ? '2400' : '1800'} or more need $need minutes, so FIDE will not rate those games.',
          repairs: [
            ReportRepair('Edit ${s.name}', ReportDestination.section, id: s.id),
          ],
          blocking: false,
        );
      }
    }
    // Only entries that took part go in the report (see trfTournament).
    final reported = trfTournament(e, s, report: true).players;
    final noId = [
      for (final p in reported)
        if (!isFideId(p.fideId)) p,
    ];
    if (noId.isNotEmpty) {
      add(
        '${s.name}: FIDE ID missing for ${_list(noId.map((p) => p.name))}. Every player in a FIDE-rated section needs one; US Chess members without one can request it through US Chess.',
        repairs: [for (final p in noId) player(p, 'fideId')],
      );
    }
    final unratedNoDetails = [
      for (final p in players)
        if (fideRating(p, category) == 0 &&
            (p.birthDate.isEmpty || p.sex.isEmpty || p.federation.isEmpty))
          p,
    ];
    if (unratedNoDetails.isNotEmpty) {
      add(
        '${s.name}: birth year, sex or federation missing for players FIDE has not rated: ${_list(unratedNoDetails.map((p) => p.name))}. FIDE asks for them with a first rating.',
        repairs: [for (final p in unratedNoDetails) player(p, 'birthDate')],
        blocking: false,
      );
    }
    final ratingBased = fideSectionTiebreaks(e, s)
        .where(
          (m) => const {
            'ARO',
            'TPR',
            'PTP',
            'APRO',
            'APPO',
            'RTNG',
          }.contains(m.base),
        )
        .toList();
    // FIDE checklist VCL.17: full-point byes are allowed but deprecated.
    final fullByes = {
      for (final r in s.rounds)
        for (final b in r.byes)
          if (!b.allocated && b.points >= 2) e.player(b.player).name,
    };
    if (fullByes.isNotEmpty) {
      add(
        '${s.name}: ${_list(fullByes)} received a full-point bye. FIDE deprecates them; the report shows them as F.',
        blocking: false,
      );
    }
    if (ratingBased.isNotEmpty &&
        players.any((p) => fideRating(p, category) == 0)) {
      add(
        '${s.name}: ${ratingBased.map((m) => m.code).join(', ')} ${ratingBased.length == 1 ? 'is' : 'are'} rating-based, and some players have no FIDE rating. C.07 Art. 10 drops rating-based tie-breaks then, unless their handling was announced before round 1.',
        repairs: [
          const ReportRepair(
            'Edit tie-breaks',
            ReportDestination.event,
            field: 'tiebreaks',
          ),
        ],
        blocking: false,
      );
    }
    final ids = <String, List<Player>>{};
    for (final p in players.where((p) => isFideId(p.fideId))) {
      ids.putIfAbsent(p.fideId, () => []).add(p);
    }
    for (final MapEntry(key: id, value: same) in ids.entries) {
      if (same.length > 1) {
        add(
          '${s.name}: FIDE ID $id is entered for ${_list(same.map((p) => p.name))}.',
          repairs: [for (final p in same) player(p, 'fideId')],
        );
      }
    }
  }
  return issues;
}

/// The blocking problems, as text.
List<String> fidePreflight(Event e) => [
  for (final issue in fideIssues(e))
    if (issue.blocking) issue.message,
];

/// A file-system-safe name for a section's TRF file.
String trfFileName(Event e, Section s) {
  String slug(String text) => text
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final event = slug(e.name), section = slug(s.name);
  return '${[event, section].where((x) => x.isNotEmpty).join('-')}.trf';
}

/// The TRF files, by name.
Map<String, String> fideReport(Event e) {
  final problems = fidePreflight(e);
  if (problems.isNotEmpty) throw TournamentException(problems.first);
  final files = <String, String>{};
  for (final s in fideSections(e)) {
    // Two section names may slug alike ("U1800 (Sat)", "U1800 Sat").
    var name = trfFileName(e, s);
    for (var n = 2; files.containsKey(name); n++) {
      name = trfFileName(e, s).replaceFirst(RegExp(r'\.trf$'), '-$n.trf');
    }
    files[name] = writeTrf(e, s);
  }
  return files;
}

/// Writes the FIDE report into a new folder under [parent], as the US Chess
/// package is written: staged, then published whole.
Future<String> writeFideReport(Event e, String parent) async {
  final files = fideReport(e);
  final root = Directory(parent);
  createDirectoryDurably(root.path);
  final staging = await root.createTemp('.meow-fide-r${e.revision}.partial-');
  final suffix = p.basename(staging.path).split('.partial-').last;
  final name = 'meow-fide-r${e.revision}-$suffix';
  try {
    for (final entry in files.entries) {
      await File(
        p.join(staging.path, entry.key),
      ).writeAsBytes(utf8.encode(entry.value), flush: true);
    }
    final target = p.join(parent, name);
    publishDirectory(staging.path, target);
    return target;
  } catch (_) {
    if (await staging.exists()) await staging.delete(recursive: true);
    rethrow;
  }
}
