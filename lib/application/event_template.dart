import 'package:uuid/uuid.dart';

import '../domain/model.dart';
import '../domain/prizes.dart';

/// A new event set up like [source]: its sections (names, formats,
/// announcement lines, pairing rules, bye rules, prizes, team and home
/// settings), tie-break order, time control, venue, TD and affiliate IDs,
/// and FIDE officials.
/// Never its players, results, rulings, notes or history: the sections come
/// back empty, with fresh ids, ready for a new roster.
Event templateFrom(
  Event source, {
  required String name,
  required String date,
  String Function()? newId,
}) {
  final id = newId ?? const Uuid().v4;
  return Event(
    id: id(),
    name: name,
    date: date,
    timeControl: source.timeControl,
    venue: source.venue,
    tdId: source.tdId,
    assistantTdId: source.assistantTdId,
    otherTdIds: source.otherTdIds,
    affiliateId: source.affiliateId,
    city: source.city,
    state: source.state,
    zip: source.zip,
    level: source.level,
    useTiebreaks: source.useTiebreaks,
    tiebreaks: source.tiebreaks,
    policy: source.policy,
    online: source.online,
    fide: source.fide,
    fideTiebreaks: source.fideTiebreaks,
    sections: [for (final s in source.sections) _sectionTemplate(s, id())],
  );
}

Section _sectionTemplate(Section s, String id) => Section(
  id: id,
  name: s.name,
  players: const [],
  format: s.format,
  plannedRounds: s.plannedRounds,
  boardStart: s.boardStart,
  doubleGames: s.doubleGames,
  ratingCeiling: s.ratingCeiling,
  timeControl: s.timeControl,
  sideGames: s.sideGames,
  accelerated: s.accelerated,
  avoidTeammates: s.avoidTeammates,
  variations: s.variations,
  byeRules: s.byeRules,
  // Named prizes (junior, senior) list who qualifies by player id; those
  // players are not coming along.
  prizes: s.prizes.isEmpty
      ? const {}
      : PrizeTable.fromJson(s.prizes)
            .copy(
              list: [
                for (final p in PrizeTable.fromJson(s.prizes).list)
                  p.copy(eligible: const []),
              ],
            )
            .toJson(),
  rrTable: s.rrTable,
  doubleCycle: s.doubleCycle,
  homeTeam: s.homeTeam,
  holland: s.holland,
  // The bracket's seeds and rounds name players; its match rules stay.
  bracket: {
    for (final e in s.bracket.entries)
      if (e.key != 'seeds' && e.key != 'rounds') e.key: e.value,
  },
  unrated: s.unrated,
  fideRated: s.fideRated,
  fideRanking: s.fideRanking,
  pabPoints: s.pabPoints,
);

/// The one-line note shown when an event is created from a template.
String templateNote(Event source) {
  final n = source.sections.length;
  final parts = [
    if (n > 0) '$n ${n == 1 ? 'section' : 'sections'}',
    if (source.tiebreaks.isNotEmpty) 'tie-break order',
    'time control',
    if (source.tdId.isNotEmpty || source.affiliateId.isNotEmpty)
      'TD and affiliate IDs',
  ];
  return 'Copied from ${source.name}: ${parts.join(', ')}. '
      'No players, results or rulings.';
}
