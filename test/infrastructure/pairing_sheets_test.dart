import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/infrastructure/reports.dart';

Event sample({bool doubles = false}) {
  final names = [
    'Alexandra Montgomery',
    'Benjamin Chen',
    'Charlotte Rodriguez',
    'Daniel Kim',
    'Eleanor Thompson',
    'Felix Nguyen',
    'Gabriela Silva',
    'Henry Patel',
    'Isabella Martinez',
    'James Wilson',
    'Katherine Lee',
    'Liam Anderson',
    'Morgan Taylor',
  ];
  return Event(
    id: 'sample',
    name: 'Saturday Quads',
    date: '2026-10-03',
    players: [
      for (final (i, name) in names.indexed) Player(id: 'p$i', name: name),
    ],
    sections: [
      Section(
        id: 'a',
        name: 'Quad 1',
        format: Format.quad,
        players: ['p0', 'p1', 'p2', 'p3'],
        doubleGames: doubles,
      ),
      Section(
        id: 'b',
        name: 'Quad 2',
        format: Format.quad,
        players: ['p4', 'p5', 'p6', 'p7'],
        boardStart: 3,
        doubleGames: doubles,
      ),
      Section(
        id: 'c',
        name: 'Bottom Swiss',
        format: Format.swiss,
        players: ['p8', 'p9', 'p10', 'p11', 'p12'],
        boardStart: 5,
      ),
    ],
  );
}

List<(int, int, String, String)> draw(Round round) => [
  for (final g in round.games) (g.board, g.leg, g.white, g.black),
];

// Default PDF fonts keep ASCII labels in the page's drawing commands. Decode
// those streams to verify printed content without a platform PDF dependency.
String pdfText(Uint8List bytes) {
  final raw = latin1.decode(bytes);
  final commands =
      RegExp(r'<<(.*?)>>\s*stream\r?\n(.*?)\r?\nendstream', dotAll: true)
          .allMatches(raw)
          .map((match) {
            final data = latin1.encode(match[2]!);
            return latin1.decode(
              match[1]!.contains('/FlateDecode') ? zlib.decode(data) : data,
            );
          })
          .join('\n');
  return RegExp(r'\(([^()]*)\)').allMatches(commands).map((m) => m[1]!).join();
}

void main() {
  test(
    'quad PDFs print the complete player grid from every print entry',
    () async {
      final event = sample();
      final section = event.sections.first;
      final posted = section.copy(rounds: [reportPairingRounds(section).first]);
      final snapshot = event.copy(sections: [posted]);
      for (final kind in [
        ReportKind.pairings,
        ReportKind.sections,
        ReportKind.packet,
      ]) {
        final commands = pdfText(
          await reportPdf(
            snapshot,
            kind,
            roundNumber: 1,
            currentRoundOnly: true,
          ),
        );
        expect(commands, contains('Player'));
        for (final round in [1, 2, 3]) {
          expect(commands, contains('Round$round'));
        }
        // Quad a's fixed draw: player 1 faces 4 as White, then 3 and 2 as Black.
        for (final pairing in ['W4', 'B3', 'B2']) {
          expect(commands, contains(pairing));
        }
        expect(commands, isNot(contains('Board')));
        expect(snapshot.sections.single.rounds, hasLength(1));
      }
    },
  );

  test(
    'larger round robins keep board tables and the selected round',
    () async {
      final event = sample();
      var section = event.sections.last.copy(
        format: Format.roundRobin,
        plannedRounds: 5,
      );
      final first = proposeRound(event, section, () => 'r1');
      section = section.copy(rounds: [first]);
      final commands = pdfText(
        await reportPdf(
          event.copy(sections: [section]),
          ReportKind.pairings,
          roundNumber: 1,
          currentRoundOnly: true,
        ),
      );
      for (final label in ['Board', 'White', 'Black', 'Round1']) {
        expect(commands, contains(label));
      }
      expect(commands, isNot(contains('Round2')));
      expect(
        commands,
        isNot(contains('Round-robin pairing sheet'.replaceAll(' ', ''))),
      );
    },
  );

  test('a round-scoped packet keeps quads whose rounds are unposted', () async {
    final event = sample();
    final swiss = event.sections.last;
    final r1 = proposeRound(event, swiss, () => 'g1');
    final scoped = event.copy(
      sections: [
        ...event.sections.take(2),
        swiss.copy(
          rounds: [
            r1.copy(
              games: [for (final g in r1.games) g.copy(outcome: Outcome.draw)],
            ),
            Round(
              number: 2,
              games: [Game(id: 'g2', white: 'p8', black: 'p9', board: 5)],
            ),
          ],
        ),
      ],
    );
    final commands = pdfText(
      await reportPdf(scoped, ReportKind.packet, roundNumber: 2),
    );
    for (final name in ['Quad1', 'Quad2', 'BottomSwiss']) {
      expect(commands, contains(name));
    }
  });

  test('a posted opponent missing from the roster prints by name', () async {
    final event = sample();
    final quad = event.sections.first;
    final posted = quad.copy(
      rounds: [
        Round(
          number: 1,
          games: [
            Game(id: 'x', white: 'p0', black: 'p12', board: 1),
            Game(id: 'y', white: 'p1', black: 'p2', board: 2),
          ],
        ),
      ],
    );
    final commands = pdfText(
      await reportPdf(event.copy(sections: [posted]), ReportKind.pairings),
    );
    expect(commands, isNot(contains('null')));
    expect(commands, contains('MorganTaylor'));
  });

  test('Swiss PDF retains the board layout and selected round', () async {
    final event = sample();
    final section = event.sections.last.copy(
      rounds: [
        Round(
          number: 1,
          games: [Game(id: 'r1', white: 'p8', black: 'p9', board: 5)],
        ),
        Round(
          number: 2,
          games: [Game(id: 'r2', white: 'p10', black: 'p11', board: 5)],
        ),
      ],
    );
    final commands = pdfText(
      await reportPdf(
        event.copy(sections: [section]),
        ReportKind.pairings,
        roundNumber: 1,
        currentRoundOnly: true,
      ),
    );
    for (final label in ['Board', 'Result', 'White', 'Black', 'Round1']) {
      expect(commands, contains(label));
    }
    expect(commands, isNot(contains('Round2')));
    expect(commands, isNot(contains('Round3')));
    expect(commands, isNot(contains('Player')));
  });

  test(
    'quad paper schedule matches posting for every color lot and both legs',
    () {
      for (final id in ['a', 'b', 'c', 'd']) {
        for (final doubles in [false, true]) {
          final event = sample(doubles: doubles);
          var section = Section(
            id: id,
            name: 'Quad',
            format: Format.quad,
            players: event.sections.first.players,
            boardStart: 7,
            doubleGames: doubles,
          );
          final paper = reportPairingRounds(section);
          expect(paper, hasLength(3));
          for (final printed in paper) {
            final posted = proposeRound(event, section, () => 'game');
            expect(draw(printed), draw(posted));
            section = section.copy(
              rounds: [
                ...section.rounds,
                posted.copy(
                  games: [
                    for (final g in posted.games) g.copy(outcome: Outcome.draw),
                  ],
                ),
              ],
            );
          }
          expect(event.games, isEmpty);
        }
      }
    },
  );

  test(
    'quad sheets keep edited posted pairings even from an earlier round',
    () {
      final event = sample();
      final section = event.sections.first;
      final printed = reportPairingRounds(section);
      final changed = printed[1].copy(
        games: [
          Game(
            id: 'changed',
            white: 'p0',
            black: 'p2',
            board: 19,
            outcome: Outcome.whiteWin,
          ),
        ],
      );
      final rounds = reportPairingRounds(
        section.copy(rounds: [printed[0], changed]),
        roundNumber: 1,
      );
      expect(rounds, hasLength(3));
      expect(rounds[1], same(changed));
    },
  );

  test(
    'Swiss prints only the selected posted round, never inventing the next',
    () {
      final section = sample().sections.last;
      expect(reportPairingRounds(section), isEmpty);
      final r1 = Round(
        number: 1,
        games: [Game(id: 'one', white: 'p8', black: 'p9', board: 5)],
        byes: [ByeAward('p12', 2, 'Pairing bye')],
      );
      final r2 = Round(
        number: 2,
        games: [Game(id: 'two', white: 'p10', black: 'p11', board: 6)],
      );
      final posted = section.copy(rounds: [r1, r2]);
      expect(reportPairingRounds(posted), [r2]);
      expect(reportPairingRounds(posted, roundNumber: 1), [r1]);
      expect(reportPairingRounds(posted, roundNumber: 0), isEmpty);
      expect(
        () => reportPairingRounds(posted, roundNumber: 3),
        throwsA(isA<TournamentException>()),
      );
      expect(
        reportPairingRounds(
          sample().sections.first.copy(players: section.players),
        ),
        isEmpty,
      );
    },
  );

  test('odd round robins preserve sit-outs and match the posting engine', () {
    final event = sample();
    var section = event.sections.last.copy(
      format: Format.roundRobin,
      plannedRounds: 5,
    );
    final paper = reportPairingRounds(section);
    expect(paper, hasLength(5));
    for (final printed in paper) {
      final posted = proposeRound(event, section, () => 'game');
      expect(draw(printed), draw(posted));
      expect(printed.byes.single.player, posted.byes.single.player);
      section = section.copy(
        rounds: [
          ...section.rounds,
          posted.copy(
            games: [
              for (final g in posted.games) g.copy(outcome: Outcome.draw),
            ],
          ),
        ],
      );
    }
  });

  test('Letter and A4 put each quad and Swiss section on its own page', () async {
    for (final doubles in [false, true]) {
      var event = sample(doubles: doubles);
      final swiss = event.sections.last;
      final posted = proposeRound(event, swiss, () => 'game');
      event = event.copy(
        sections: [
          ...event.sections.take(2),
          swiss.copy(rounds: [posted]),
        ],
      );
      for (final a4 in [false, true]) {
        for (final kind in [
          ReportKind.sections,
          ReportKind.packet,
          ReportKind.pairings,
        ]) {
          final bytes = await reportPdf(
            event,
            kind,
            a4: a4,
            font: pw.Font.ttf(
              ByteData.sublistView(
                File('assets/fonts/Inter-Regular.ttf').readAsBytesSync(),
              ),
            ),
            bold: pw.Font.ttf(
              ByteData.sublistView(
                File('assets/fonts/Inter-SemiBold.ttf').readAsBytesSync(),
              ),
            ),
          );
          final pages = RegExp(
            r'/Type\s*/Page\b',
          ).allMatches(latin1.decode(bytes)).length;
          expect(pages, 3, reason: '$kind, a4=$a4, doubles=$doubles');
          if (Platform.environment['MEOW_PRINT_SAMPLES'] == '1' &&
              kind == ReportKind.sections &&
              !a4) {
            Directory('artifacts/print-sheets').createSync(recursive: true);
            File(
              'artifacts/print-sheets/${doubles ? 'double' : 'standard'}-pairing-sheets.pdf',
            ).writeAsBytesSync(bytes);
          }
        }
      }
    }
  });
}
