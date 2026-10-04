import 'dart:io';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/web_roster.dart';
import 'package:meow_chess/infrastructure/roster_import.dart';
import 'package:meow_chess/infrastructure/roster_sources/html_table.dart';
import '../support.dart';

String table(String rows) =>
    '<table><thead><tr><th>#</th><th>Name</th><th>Rating</th><th>USCF ID</th><th>Section</th><th>Byes</th></tr></thead><tbody>$rows</tbody></table>';
String row(String id, String name, String rating) =>
    '<tr><td>1</td><td>$name</td><td>$rating</td><td><a href="https://ratings.uschess.org/player/$id">$id</a></td><td>Open</td><td>None</td></tr>';
const url = 'https://boylstonchess.org/tournament/entries/1563';

class ExampleClubSource extends HtmlTableRosterSource {
  @override
  bool matches(Uri url) => url.host == 'custom.example';
  @override
  Uri entryListUrl(Uri url) => url.resolve('/registrations.csv');
  @override
  List<ImportRow> parse(String source) => parseRoster(source);
}

void main() {
  test(
    'a roster review cannot be applied to another event at the same revision',
    () {
      final first = fixture(count: 4), second = fixture(count: 4);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      expect(first.event!.revision, second.event!.revision);
      final review = RosterReview(
        first.event!,
        url,
        parseRoster('Name,USCF ID,Rating\nNew Player,99887766,1200'),
      );
      expect(
        () => review.apply(
          second.event!,
          review.changes.map((r) => r.key).toSet(),
        ),
        throwsA(isA<TournamentException>()),
      );
      expect(second.event!.players, hasLength(4));
      expect(second.event!.rosterSource, isEmpty);
    },
  );

  test('October Quads roster confirms, saves, reloads and refreshes', () {
    final dir = Directory.systemTemp.createTempSync('meow-web-roster-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/import.meow';
    final c = TournamentController(SqliteEventRepository(path))
      ..create('October Quads');
    final rows = parseWebRoster(
      File('test/fixtures/boylston_october_quads.html').readAsStringSync(),
    );
    expect(rows, hasLength(24));
    expect(rows.where((r) => r.error != null), isEmpty);
    expect(rows.where((r) => r.player!.rating == 0), hasLength(4));
    const source = 'https://boylstonchess.org/events/1563/october-quads';
    final review = RosterReview(c.event!, source, rows);
    c.change(
      'Confirm website roster',
      review.apply(c.event!, review.changes.map((r) => r.key).toSet()),
    );
    expect(c.event!.players, hasLength(24));
    c.dispose();
    final saved = SqliteEventRepository(path);
    addTearDown(saved.close);
    final event = saved.load()!;
    expect(event.players, hasLength(24));
    expect(event.players[8].registrationNote, 'Hi AndrewB');
    expect(event.players[8].byes, isEmpty);
    expect(event.rosterSource['url'], source);
    final again = RosterReview(event, source, rows);
    expect(again.changes.where((r) => r.changed), isEmpty);
    expect(again.apply(event, {}).players, hasLength(24));
  });

  test('note headers import text independently of private notes and byes', () {
    for (final header in ['Note', 'Notes', 'Byes']) {
      final rows = parseWebRoster(
        '<table><tr><th>$header</th><th>Name</th><th>Rating</th></tr>'
        '<tr><td>Round 1 bye &amp; late arrival</td><td>Player</td><td>UNR</td></tr></table>',
      );
      expect(
        rows.single.player!.registrationNote,
        'Round 1 bye & late arrival',
      );
      expect(rows.single.player!.notes, isEmpty);
      expect(rows.single.player!.byes, isEmpty);
    }
    final legacy = Player(id: 'old', name: 'Old').toJson()
      ..remove('registrationNote');
    expect(Player.fromJson(legacy).registrationNote, isEmpty);
  });

  test('note-only refresh updates, clears, persists and undoes the note', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    c.savePlayer(c.event!.players.first.copy(notes: 'Private TD note'));
    void refresh(String note) {
      final p = c.event!.players.first;
      final rows = parseWebRoster(
        table(
          row(p.memberId, p.name, '${p.rating}'),
        ).replaceFirst('<td>None</td>', '<td>$note</td>'),
      );
      final review = RosterReview(c.event!, url, rows);
      expect(review.changes.single.changed, true);
      c.change(
        'Refresh note',
        review.apply(c.event!, {review.changes.single.key}),
      );
      expect(c.event!.players.first.registrationNote, note);
      expect(c.repository.load()!.players.first.registrationNote, note);
      expect(c.event!.players.first.notes, 'Private TD note');
      expect(RosterReview(c.event!, url, rows).changes.single.changed, false);
    }

    refresh('Arriving late');
    refresh('Round 1 bye');
    refresh('');
    c.undo();
    expect(c.event!.players.first.registrationNote, 'Round 1 bye');
    expect(c.event!.players.first.byes, isEmpty);
  });

  test(
    'posted sections can refresh notes while keeping identity and ratings',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.post(await c.propose());
      final p = c.event!.players.first;
      final rows = parseWebRoster(
        table(
          row(p.memberId, 'Changed website name', '3999'),
        ).replaceFirst('<td>None</td>', '<td>Arrives at noon</td>'),
      );
      final review = RosterReview(c.event!, url, rows);
      final updated = review.apply(c.event!, {review.changes.single.key});
      expect(updated.players.first.registrationNote, 'Arrives at noon');
      expect(updated.players.first.name, p.name);
      expect(updated.players.first.rating, p.rating);
      expect(updated.sections.first.toJson(), c.event!.sections.first.toJson());
    },
  );

  test('Boylston event and entry URLs fetch the same entry list', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return http.Response(table(row('00123456', 'Player', '1520')), 200);
    });
    addTearDown(client.close);
    for (final input in [
      'https://boylstonchess.org/events/1563/october-quads',
      url,
      'https://www.boylstonchess.org/events/1563/october-quads/?ref=calendar',
      'https://boylstonchess.org/events/1563',
      '$url/',
    ]) {
      final rows = await WebRoster(client).fetch(' $input ');
      expect(rows.single.player!.memberId, '00123456');
      expect(requests.last.toString(), url);
    }
    expect(requests, hasLength(5));
  });

  test('generic sources read only the supplied URL, including query', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add(request.url.toString());
      return http.Response(
        '<a href="/tournament/entries/1563">Entries</a>'
        '${table(row('00123456', 'Player', '1520'))}',
        200,
      );
    });
    addTearDown(client.close);
    for (final input in [
      'https://another-club.example/events/1563/name?section=open',
      'https://boylstonchess.org.example/events/1563/name',
      'https://boylstonchess.org/another-format',
    ]) {
      expect(await WebRoster(client).fetch(input), hasLength(1));
      expect(requests.last, input);
    }
    expect(requests, hasLength(3));
  });

  test('generic event pages do not follow entry-list links', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('<a href="/entries">Entry List</a>', 200);
    });
    addTearDown(client.close);
    await expectLater(
      WebRoster(client).fetch('https://another-club.example/events/1563'),
      throwsA(isA<TournamentException>()),
    );
    expect(requests, 1);
  });

  test('club adapters can resolve URLs and parse their own format', () async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://custom.example/registrations.csv',
      );
      return http.Response(
        'Name,Rating,USCF ID\nClub Player,1800,00123456',
        200,
      );
    });
    addTearDown(client.close);
    final rows = await WebRoster(
      client,
      sources: [ExampleClubSource()],
    ).fetch('https://custom.example/event');
    expect(rows.single.player!.name, 'Club Player');
    expect(rows.single.player!.rating, 1800);
  });

  test('generic table finds reordered aliases after a title row', () {
    final rows = parseWebRoster('''
      <table><tr><th>Event</th><th>Date</th></tr><tr><td>Quads</td><td>Today</td></tr></table>
      <table>
        <tr><td colspan="3">Open section</td></tr>
        <tr><td>US Chess ID</td><td>RTG</td><td>Player Name</td></tr>
        <tr><td>00123456</td><td>UNR</td><td>Zoë &amp; Renée</td></tr>
      </table>
    ''');
    expect(rows.single.player!.memberId, '00123456');
    expect(rows.single.player!.rating, 0);
    expect(rows.single.player!.name, 'Zoë & Renée');
  });

  test('generic table requires name and rating columns', () {
    for (final column in ['Name', 'Rating']) {
      expect(
        () => parseWebRoster(
          table(
            row('00123456', 'Player', '1520'),
          ).replaceFirst('<th>$column</th>', '<th>Other</th>'),
        ),
        throwsA(isA<TournamentException>()),
      );
    }
  });

  test('unrated entry list can omit USCF IDs', () {
    final rows = parseWebRoster(
      '<table><tr><th>Name</th><th>Rating</th></tr>'
      '<tr><td>New Player</td><td>UNR</td></tr></table>',
    );
    expect(rows.single.player!.memberId, isEmpty);
    expect(rows.single.player!.rating, 0);
  });

  test(
    'Boylston structure extracts IDs, Unicode names and raw section/byes',
    () {
      final rows = parseWebRoster(
        table(row('00123456', 'Zoë &amp; Renée', '1520')),
      );
      expect(rows.single.player!.memberId, '00123456');
      expect(rows.single.player!.name, 'Zoë & Renée');
      expect(rows.single.player!.rating, 1520);
      expect(rows.single.raw, contains('Open'));
    },
  );
  test('empty, ambiguous and non-table pages fail closed', () {
    for (final source in [
      '<h1>Oops</h1>',
      table(''),
      table(row('00123456', 'Test', '1')) * 2,
    ]) {
      expect(() => parseWebRoster(source), throwsA(isA<TournamentException>()));
    }
    expect(
      parseWebRoster(table(row('123', 'Bad ID', '1500'))).single.error,
      contains('eight'),
    );
  });
  test(
    'updates never remove, preserve local fields and protect supplement ratings',
    () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.savePlayer(
        c.event!.players.first.copy(
          notes: 'Keep me',
          ratingEvidence: {'supplementDate': '2026-10-01'},
        ),
      );
      final original = c.event!;
      final rows = parseWebRoster(
        table(
          row('12000000', 'Changed Name', '3999') +
              row('99887766', 'New Player', '1200'),
        ),
      );
      final review = RosterReview(original, url, rows);
      final updated = review.apply(
        original,
        review.changes.map((r) => r.key).toSet(),
      );
      expect(updated.players.length, 5);
      expect(updated.players.first.rating, original.players.first.rating);
      expect(updated.players.first.notes, 'Keep me');
      expect(updated.players.first.ratingEvidence['registrationRating'], 3999);
      expect(updated.sections.first.players, original.sections.first.players);
      c.change('Apply source', updated);
      final missing = RosterReview(
        c.event!,
        url,
        parseWebRoster(table(row('99887766', 'New Player', '1200'))),
      );
      expect(
        missing.missing.map((p) => p.id),
        contains(original.players.first.id),
      );
      final kept = missing.apply(c.event!, {});
      expect(kept.players.length, 5);
      expect(Event.decode(kept.encode()).rosterSource['url'], url);
      c.undo();
      expect(c.event!.players.length, 4);
    },
  );
  test(
    'duplicate and ambiguous identities cannot be approved; stale proposals fail',
    () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final duplicate = RosterReview(
        c.event!,
        url,
        parseWebRoster(
          table(row('99887766', 'One', '1') + row('99887766', 'Two', '2')),
        ),
      );
      expect(duplicate.changes.every((r) => r.problem != null), true);
      expect(
        () => duplicate.apply(c.event!, {duplicate.changes.first.key}),
        throwsA(isA<TournamentException>()),
      );
      final ambiguous = RosterReview(
        c.event!,
        url,
        parseWebRoster(table(row('', 'Player 00', '1'))),
      );
      expect(ambiguous.changes.single.problem, isNotNull);
      c.savePlayer(c.event!.players.first.copy(notes: 'New revision'));
      expect(
        () => duplicate.apply(c.event!, {}),
        throwsA(isA<TournamentException>()),
      );
    },
  );
  test(
    'network failures do not become roster data; credentials never sent',
    () async {
      final client = MockClient((request) async {
        expect(request.followRedirects, false);
        expect(request.headers.keys, isNot(contains('X-Api-Key')));
        return http.Response(
          '',
          302,
          headers: {'location': 'http://localhost/'},
        );
      });
      addTearDown(client.close);
      await expectLater(
        WebRoster(client).fetch(url),
        throwsA(isA<TournamentException>()),
      );
      await expectLater(
        WebRoster(client).fetch('file:///tmp/secret'),
        throwsA(isA<TournamentException>()),
      );
    },
  );
  test(
    'unchanged source preserves manual corrections and manual edits clear verification',
    () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final rows = parseWebRoster(
        table(row('12000000', 'Registration Name', '1400')),
      );
      final first = RosterReview(c.event!, url, rows);
      c.change('Keep source', first.apply(c.event!, {}));
      c.savePlayer(
        c.event!.players.first.copy(name: 'Corrected Name', rating: 1800),
      );
      final next = RosterReview(c.event!, url, rows);
      expect(next.changes.single.changed, false);
      expect(next.apply(c.event!, {}).players.first.name, 'Corrected Name');
      c.savePlayer(
        c.event!.players.first.copy(
          ratingEvidence: {'id': '12000000', 'supplementDate': '2026-10-01'},
        ),
      );
      c.savePlayer(c.event!.players.first.copy(rating: 1900));
      expect(c.event!.players.first.ratingEvidence['supplementDate'], isNull);
      expect(c.event!.players.first.ratingEvidence['kind'], 'TD-assigned');
    },
  );
}
