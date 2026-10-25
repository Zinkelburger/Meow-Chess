import 'package:csv/csv.dart';
import '../domain/model.dart';
import '../domain/teams.dart';

String teamPolicy(int best) =>
    '${best == 0 ? 'All unique players' : 'Best $best unique players'} per team in each section. '
    'Individual competition points, including awarded byes and forfeits; '
    'withdrawals keep earned points. House players excluded. '
    'Re-entries count once at their best score; missing scorers count as zero. '
    'Equal totals share places. Current team membership is used. '
    'Team names are matched without case or surrounding spaces. '
    'This report does not establish prize eligibility or team-match results.';

String teamReport(Event event, {String? sectionId, int best = 4}) {
  final lines = [
    '${event.name} | ${event.date} | revision ${event.revision}',
    'TEAM STANDINGS',
    teamPolicy(best),
    '',
  ];
  for (final section in event.sections.where(
    (s) => sectionId == null || s.id == sectionId,
  )) {
    lines.add(section.name);
    final teams = teamStandings(event, section, best: best);
    if (teams.isEmpty) lines.add('No eligible team entries in this section.');
    for (final team in teams) {
      lines.add(
        '${team.rank}. ${team.name} — ${scoreText(team.points)} points (${team.counted.length} scorers)',
      );
      for (final member in team.members) {
        lines.add(
          '  ${team.counted.contains(member) ? "Counted" : "Not counted"}: ${member.player.name} — ${scoreText(member.points)}',
        );
      }
    }
    lines.add('');
  }
  return lines.join('\n');
}

String teamReportCsv(Event event, {String? sectionId, int best = 4}) {
  String safe(String s) => RegExp(r'^[=+@\-\t\r]').hasMatch(s) ? "'$s" : s;
  return Csv().encode([
    [
      'Event',
      'Revision',
      'Section',
      'Scorers per team (0 = all)',
      'Team place',
      'Team',
      'Team points',
      'Player',
      'Player points',
      'Counted',
      'Policy',
    ],
    for (final s in event.sections.where(
      (s) => sectionId == null || s.id == sectionId,
    ))
      for (final t in teamStandings(event, s, best: best))
        for (final m in t.members)
          [
            safe(event.name),
            event.revision,
            safe(s.name),
            best,
            t.rank,
            safe(t.name),
            scoreText(t.points),
            safe(m.player.name),
            scoreText(m.points),
            t.counted.contains(m) ? 'Yes' : 'No',
            teamPolicy(best),
          ],
  ]);
}
