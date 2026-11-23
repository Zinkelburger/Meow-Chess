import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/results_sources/boylston.dart';
import 'package:meow_chess/infrastructure/web_results.dart';

/// A results page in the club's layout, with invented players.
String resultsPage(String sections) =>
    '<html><body><div id="main"><div class="col">$sections</div></div></body></html>';

String section(String heading, String rows) =>
    '''
<h2>$heading</h2>
<div class="table-responsive">
<table class="table table-bordered table-sm pairings">
  <thead><tr><th></th><th title="Board Number">Bd</th><th title="Result">Res</th>
  <th class="al">White</th><th title="Result">Res</th><th class="al">Black</th></tr></thead>
  <tbody>$rows</tbody>
</table></div>''';

String board(
  int number,
  String white,
  String black, {
  String whiteResult = '',
  String blackResult = '',
}) =>
    '''
<tr data-id="${52000 + number}">
  <td><a href="/result/${52000 + number}/enter" class="btn btn-info">Enter Result</a></td>
  <td class="board-number">$number</td>
  <td class="white-result fw-bold">$whiteResult</td>
  <td class="white-name al">$white <br class="d-block d-md-none" />(1800 0.0)</td>
  <td class="black-result fw-bold">$blackResult</td>
  <td class="black-name al">$black <br class="d-block d-md-none" />(unr 0.0)</td>
</tr>''';

const bye = '''
<tr><td></td><td class="board-number"></td>
  <td class="white-result fw-bold">&frac12;</td>
  <td class="white-name al">Resting Player <br class="d-block d-md-none" />(1224 0.5)</td>
  <td class="black-result fw-bold"></td>
  <td class="black-name al"><em>bye</em></td></tr>''';

void main() {
  test('a Boylston results page reads as rounds, boards and results', () {
    final rounds = parseBoylstonResults(
      resultsPage(
        section(
              'Open - Round 2',
              board(
                    1,
                    'Ada Example',
                    'Ben Sample',
                    whiteResult: '1',
                    blackResult: '0',
                  ) +
                  board(2, 'Cy Made-Up', "Dee O'Invented") +
                  board(
                    3,
                    'Eve Placeholder',
                    'Flo Fictional',
                    whiteResult: '&frac12;',
                    blackResult: '&frac12;',
                  ) +
                  bye,
            ) +
            section('U1800 - Round 0', ''),
      ),
    );
    expect(rounds.map((r) => (r.section, r.round, r.games.length)), [
      ('Open', 2, 3),
      ('U1800', 0, 0),
    ]);
    final open = rounds.first.games;
    expect(open.map((g) => (g.board, g.white, g.black)), [
      (1, 'Ada Example', 'Ben Sample'),
      (2, 'Cy Made-Up', "Dee O'Invented"),
      (3, 'Eve Placeholder', 'Flo Fictional'),
    ]);
    expect(open.map((g) => g.outcome), [Outcome.whiteWin, null, Outcome.draw]);
    expect(open.map((g) => g.hasResult), [true, false, true]);
  });

  test(
    'the monitor screen, with its headings in table rows, reads the same',
    () {
      final rounds = parseBoylstonResults('''
<h2 class="ac">Pairings</h2>
<table class="table pairings max-font-size nw"><tbody>
<tr class="no-border"><td colspan="5" class="ac"> Under 1800 - Round 3 </td></tr>
<tr class="thead"><th>Bd</th><th>Res</th><th>White Player</th><th>Res</th><th>Black Player</th></tr>
<tr data-id="7"><td class="board-number">4</td><td class="white-result fw-bold">0</td>
<td class="white-name al">Ada Example <span class="player-rating-score">(1700 2.0)</span></td>
<td class="black-result fw-bold">1</td>
<td class="black-name al">Ben Sample <span class="player-rating-score">(1650 1.5)</span></td></tr>
</tbody></table>
<h2>Standings</h2>
<table class="table standings"><tbody>
<tr class="no-border"><td colspan="6" class="ac">Under 1800</td></tr>
<tr><td>1</td><td>1</td><td class="al">Ben Sample</td><td>2.5</td></tr>
</tbody></table>''');
      expect(rounds, hasLength(1));
      expect(rounds.single.section, 'Under 1800');
      expect(rounds.single.round, 3);
      expect(rounds.single.games.single.outcome, Outcome.blackWin);
      expect(rounds.single.games.single.board, 4);
    },
  );

  test('a page without a pairings table is refused, not read as no rounds', () {
    expect(
      () => parseBoylstonResults('<html><body><h2>Sign in</h2></body></html>'),
      throwsFormatException,
    );
    // The club's own sign-in page is not an empty round either.
    expect(
      () => parseBoylstonResults(
        '<html><head><title>Boylston Chess Foundation</title></head><body>'
        '<div id="main"><form><input type="password"></form></div>'
        '</body></html>',
      ),
      throwsFormatException,
    );
  });

  test('the club\'s page with no round posted yet reads as no rounds', () {
    const shell =
        '<html><head><title>Boylston Chess Foundation</title></head><body>';
    expect(
      parseBoylstonResults(
        '$shell<div id="main" class="container-fluid"><div class="col">'
        '</div></div></body></html>',
      ),
      isEmpty,
    );
    // The monitor screen between rounds.
    expect(
      parseBoylstonResults(
        '$shell<div id="pairings-column" class="col-6">'
        '<h2 class="ac">Pairings</h2></div></body></html>',
      ),
      isEmpty,
    );
  });

  test(
    'only the club\'s results pages are accepted, and all read /results',
    () {
      for (final url in [
        'https://beta.boylstonchess.org/results',
        'https://beta.boylstonchess.org/result',
        'https://beta.boylstonchess.org/monitor/',
        'https://boylstonchess.org/results',
      ]) {
        final resolved = resolveResultsUrl(url);
        expect(resolved.path, '/results');
        expect(resolved.host, Uri.parse(url).host);
      }
      for (final url in [
        'http://beta.boylstonchess.org/results',
        'https://beta.boylstonchess.org/result/52996/enter',
        'https://beta.boylstonchess.org.example.com/results',
        'https://example.org/results',
        'not a url',
      ]) {
        expect(
          () => resolveResultsUrl(url),
          throwsA(isA<TournamentException>()),
          reason: url,
        );
      }
    },
  );

  test('a Boylston entry list suggests the club\'s results page', () {
    expect(
      suggestResultsUrl('https://boylstonchess.org/tournament/entries/1563'),
      'https://beta.boylstonchess.org/results',
    );
    expect(suggestResultsUrl('https://example.org/entries'), isNull);
    expect(suggestResultsUrl(''), isNull);
  });

  test('fetch only reads: one GET of the results page, no redirects', () async {
    final requests = <http.BaseRequest>[];
    final web = WebResults(
      MockClient((request) async {
        requests.add(request);
        return http.Response(
          resultsPage(
            section(
              'Open - Round 1',
              board(
                1,
                'Ada Example',
                'Ben Sample',
                whiteResult: '0',
                blackResult: '1',
              ),
            ),
          ),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );
    final rounds = await web.fetch('https://beta.boylstonchess.org/monitor');
    expect(rounds.single.games.single.outcome, Outcome.blackWin);
    expect(requests.single.method, 'GET');
    expect(
      requests.single.url.toString(),
      'https://beta.boylstonchess.org/results',
    );
    expect(requests.single.followRedirects, isFalse);
  });

  test('a page that cannot be read says so plainly', () async {
    Future<void> refused(http.Response response, String message) async {
      await expectLater(
        WebResults(
          MockClient((_) async => response),
        ).fetch('https://beta.boylstonchess.org/results'),
        throwsA(
          isA<TournamentException>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
      );
    }

    await refused(http.Response('', 503), 'HTTP 503');
    await refused(http.Response('', 302), 'HTTP 302');
    await refused(
      http.Response('<html><body>Maintenance</body></html>', 200),
      'no pairings',
    );
    await expectLater(
      WebResults(
        MockClient((_) async => throw http.ClientException('offline')),
      ).fetch('https://beta.boylstonchess.org/results'),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('Could not reach beta.boylstonchess.org'),
        ),
      ),
    );
  });
}
