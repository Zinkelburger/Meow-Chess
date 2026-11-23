import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/scoreboard.dart';

Player player(int i) =>
    Player(id: 'p$i', name: 'Player $i', rating: i == 3 ? 0 : 1900 - i * 20);

Game game(int round, int board, int white, int black, Outcome outcome) => Game(
  id: 'r$round-b$board',
  white: 'p$white',
  black: 'p$black',
  board: board,
  outcome: outcome,
);

Event event(List<Round> rounds, {Format format = Format.swiss}) => Event(
  id: 'e',
  name: 'Fall Open',
  date: '2026-11-21',
  players: [
    for (var i = 0; i < 5; i++) player(i),
    Player(id: 'x', name: 'Side Player'),
    Player(id: 'y', name: 'Other Side'),
  ],
  sections: [
    Section(
      id: 's',
      name: 'Open',
      players: [for (var i = 0; i < 5; i++) 'p$i'],
      format: format,
      plannedRounds: 3,
      rounds: rounds,
    ),
    Section(
      id: 'side',
      name: 'Side games',
      players: const ['x', 'y'],
      sideGames: true,
      boardStart: 40,
    ),
  ],
);

void main() {
  const all = ScoreboardSettings();

  test('nothing is shown before a round is posted', () {
    expect(scoreboardTables(event(const []), all), isEmpty);
  });

  test('a posted round shows boards in order, results and byes', () {
    final e = event([
      Round(
        number: 1,
        games: [
          game(1, 2, 2, 3, Outcome.unreported),
          game(1, 1, 0, 1, Outcome.whiteWin),
        ],
        byes: const [ByeAward('p4', 2, 'odd', allocated: true)],
      ),
    ]);
    final tables = scoreboardTables(e, all);
    // Standings wait for a complete round.
    expect(tables.map((t) => t.kind), ['pairings']);
    final t = tables.single;
    expect(t.section, 'Open');
    expect(t.title, 'Round 1 pairings');
    expect(t.rows, [
      ['1', 'Player 0', '1–0', 'Player 1'],
      ['2', 'Player 2', '', 'Player 3'],
    ]);
    expect(t.notes, ['Byes: Player 4 (full-point bye)']);
    expect(t.toJson()['columns'], ['Board', 'White', 'Result', 'Black']);
  });

  test('standings follow a complete round and rank shared places', () {
    final e = event([
      Round(
        number: 1,
        games: [
          game(1, 1, 0, 1, Outcome.whiteWin),
          game(1, 2, 2, 3, Outcome.draw),
        ],
        byes: const [ByeAward('p4', 1, 'requested')],
      ),
      Round(
        number: 2,
        games: [
          game(2, 1, 2, 0, Outcome.unfinished),
          game(2, 2, 3, 4, Outcome.unreported),
        ],
        byes: const [ByeAward('p1', 0, 'requested')],
      ),
    ]);
    final tables = scoreboardTables(e, all);
    expect(tables.map((t) => t.title), ['Round 2 pairings', 'Standings']);
    expect(tables[0].rows.first, ['1', 'Player 2', 'playing', 'Player 0']);
    expect(tables[0].notes, ['Byes: Player 1 (no game)']);
    expect(tables[1].rows.first, ['1', 'Player 0', '1900', '1']);
    // Three players share second on a half point; the unrated one says so.
    expect(tables[1].rows.where((r) => r[0] == '2').length, 3);
    expect(tables[1].rows.firstWhere((r) => r[1] == 'Player 3')[2], 'unr.');
  });

  test('a fixed schedule shows the first round still being played', () {
    final rounds = [
      Round(
        number: 1,
        games: [
          game(1, 1, 0, 3, Outcome.whiteWin),
          game(1, 2, 1, 2, Outcome.unreported),
        ],
      ),
      Round(
        number: 2,
        games: [
          game(2, 1, 3, 2, Outcome.unreported),
          game(2, 2, 0, 1, Outcome.unreported),
        ],
      ),
    ];
    final rr = event(rounds, format: Format.roundRobin);
    expect(scoreboardRound(rr.sections.first)!.number, 1);
    expect(scoreboardTables(rr, all).first.title, 'Round 1 pairings');
    // A Swiss shows its latest round even while an earlier game runs on.
    expect(scoreboardRound(event(rounds).sections.first)!.number, 2);
  });

  test('settings choose sections and tables, and never show side games', () {
    final e = event([
      Round(
        number: 1,
        games: [
          game(1, 1, 0, 1, Outcome.whiteWin),
          game(1, 2, 2, 3, Outcome.blackWin),
        ],
        byes: const [ByeAward('p4', 2, 'odd', allocated: true)],
      ),
    ]);
    expect(scoreboardTables(e, all).map((t) => t.section).toSet(), {'Open'});
    expect(scoreboardTables(e, all.copy(pairings: false)).map((t) => t.kind), [
      'standings',
    ]);
    expect(scoreboardTables(e, all.copy(hidden: {'s'})), isEmpty);
    // Nothing a wall chart would not show reaches the board.
    final text = scoreboardTables(e, all).map((t) => t.toJson()).toString();
    expect(text, isNot(contains('p0')));
  });

  test('settings survive a round trip and clamp the screen time', () {
    final saved = const ScoreboardSettings(
      hidden: {'b', 'a'},
      standings: false,
      seconds: 25,
    ).toJson();
    expect(saved['hidden'], ['a', 'b']);
    final read = ScoreboardSettings.fromJson(saved);
    expect(read.hidden, {'a', 'b'});
    expect(read.pairings, isTrue);
    expect(read.standings, isFalse);
    expect(read.seconds, 25);
    expect(ScoreboardSettings.fromJson(const {}).seconds, 10);
    expect(ScoreboardSettings.fromJson(const {'seconds': 9000}).seconds, 120);
    expect(ScoreboardSettings.fromJson(const {'seconds': 'x'}).seconds, 10);
    expect(all.copy(seconds: 1).seconds, 3);
  });
}
