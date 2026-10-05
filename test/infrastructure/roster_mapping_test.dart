import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/infrastructure/roster_import.dart';

void main() {
  test(
    'arbitrary headers and reordered fields preserve quoted names and IDs',
    () {
      final rows = parseRoster(
        '\uFEFFMember;Seed;Registrant\r\n00123456;1600;"Lee; Morgan"',
        delimiter: ';',
        hasHeader: true,
        columns: {
          RosterField.memberId: 0,
          RosterField.rating: 1,
          RosterField.name: 2,
        },
      );
      expect(rows.single.player!.name, 'Lee; Morgan');
      expect(rows.single.player!.memberId, '00123456');
      expect(rows.single.player!.rating, 1600);
      expect(rows.single.line, 2);
    },
  );

  test('headerless custom delimiter and omitted optional fields', () {
    final rows = parseRoster(
      'ignored~Ada Lee~extra\nignored~Bo Chen',
      delimiter: '~',
      hasHeader: false,
      columns: {RosterField.name: 1},
    );
    expect(rows.map((r) => r.player!.name), ['Ada Lee', 'Bo Chen']);
    expect(rows.first.player!.memberId, '');
    expect(rows.first.player!.rating, 0);
    expect(rows.first.player!.club, '');
  });

  test('explicit header toggle retains a first player named like a header', () {
    final rows = parseRoster(
      'Player,00123456,1200\nAda,00123457,1500',
      hasHeader: false,
    );
    expect(rows.length, 2);
    expect(rows.first.player!.name, 'Player');
  });

  test(
    'split names, tab detection and optional state and team map by header',
    () {
      final rows = parseRoster(
        'Surname\tGiven name\tState\tTeam\tRtg\nLee\tAda\tma\tKnights\tUNR',
      );
      expect(rows.single.player!.name, 'Ada Lee');
      expect(rows.single.player!.state, 'MA');
      expect(rows.single.player!.team, 'Knights');
      expect(rows.single.player!.club, '');
      expect(rows.single.player!.rating, 0);
    },
  );

  test(
    'blank and ragged rows preserve record positions and identify bad values',
    () {
      final rows = parseRoster(
        'Name,Rating,ID\n\nAda,1400,00123456\nBo\nCy,nope\nDee,1000,bad',
      );
      expect(rows.length, 4);
      expect(rows.first.line, 3);
      expect(rows[1].player!.rating, 0);
      expect(rows[2].error, contains('Rating'));
      expect(rows[3].error, contains('eight digits'));
    },
  );

  test('explicit delimiter overrides auto-detection inside quoted fields', () {
    final table = RosterTable(
      'Name|Rating\n"Lee, Morgan"|1550',
      delimiter: '|',
    );
    expect(table.columnCount, 2);
    expect(
      table
          .interpret(hasHeader: true, columns: table.suggestColumns(true))
          .single
          .player!
          .name,
      'Lee, Morgan',
    );
    expect(parseRoster('').isEmpty, true);
  });
}
