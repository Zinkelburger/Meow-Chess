import 'model.dart';
import 'standings.dart';

class TeamStanding {
  const TeamStanding(this.name, this.members, this.counted, this.rank);
  final String name;
  final List<Standing> members, counted;
  final int rank;
  int get points => counted.fold(0, (sum, row) => sum + row.points);
}

/// An individual tournament's team awards, scoped to one section. Equal totals
/// share places. Missing scorers contribute zero. No team-match points are used.
/// Membership is the current roster; withdrawals keep their earned points.
List<TeamStanding> teamStandings(Event event, Section section, {int best = 4}) {
  if (best < 0 || best > 256) {
    throw const TournamentException(
      'Count 1–256 team scorers, or 0 for everyone.',
    );
  }
  final groups = <String, List<Standing>>{};
  for (final row in standings(event, section)) {
    if (row.player.house || row.player.team.trim().isEmpty) continue;
    final key = row.player.team.trim().toLowerCase();
    groups.putIfAbsent(key, () => []).add(row);
  }
  final teams = <TeamStanding>[];
  for (final members in groups.values) {
    // A re-entry of the same person can contribute only once, using its best
    // score. The report still lists every entry so the decision is visible.
    members.sort((a, b) {
      final score = b.points.compareTo(a.points);
      if (score != 0) return score;
      final name = a.player.name.compareTo(b.player.name);
      return name != 0 ? name : a.player.id.compareTo(b.player.id);
    });
    final seen = <String>{};
    final eligible = members.where(
      (m) => seen.add(m.player.personId ?? m.player.id),
    );
    final counted = (best == 0 ? eligible : eligible.take(best)).toList();
    teams.add(
      TeamStanding(
        members.first.player.team.trim(),
        List.unmodifiable(members),
        List.unmodifiable(counted),
        0,
      ),
    );
  }
  teams.sort((a, b) {
    final score = b.points.compareTo(a.points);
    return score != 0
        ? score
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  var rank = 1;
  return [
    for (var i = 0; i < teams.length; i++)
      TeamStanding(
        teams[i].name,
        teams[i].members,
        teams[i].counted,
        rank = i == 0 || teams[i].points != teams[i - 1].points ? i + 1 : rank,
      ),
  ];
}
