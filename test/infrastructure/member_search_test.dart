import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';

void main() {
  test('bounded public/keyed name search preserves identities', () async {
    for (final key in ['', 'private-test-key']) {
      final client = MockClient((request) async {
        expect(request.url.scheme, 'https');
        expect(request.url.host, 'ratings-api.uschess.org');
        expect(request.url.path, '/api/${key.isEmpty ? 'v1' : 'v2'}/members');
        expect(request.url.queryParameters, {
          'Fuzzy': 'Test & Member',
          'Size': '10',
          'Offset': '0',
        });
        expect(request.headers['X-Api-Key'], key.isEmpty ? isNull : key);
        expect(request.followRedirects, isFalse);
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': '00123456',
                'firstName': 'Test',
                'lastName': 'Member',
                'stateRep': 'MA',
                'ratings': [
                  {'ratingSystem': 'R', 'rating': 1500},
                ],
              },
              {'id': '87654321', 'firstName': 'Test', 'lastName': 'Member'},
            ],
          }),
          200,
        );
      });
      addTearDown(client.close);
      final found = await RatingsApi(
        client,
      ).search(' Test & Member ', key: key);
      expect(found.map((m) => m.id), ['00123456', '87654321']);
      expect(found.first.name, 'Test Member');
      expect(found.first.state, 'MA');
      expect(found.first.ratings['R'], 1500);
      expect(found.last.ratings, isEmpty);
    }
  });
  test(
    'short searches and placeholder IDs never contact the provider',
    () async {
      final client = MockClient((_) async => fail('Unexpected request'));
      addTearDown(client.close);
      final api = RatingsApi(client);
      for (final query in [' ', 'a']) {
        await expectLater(
          api.search(query),
          throwsA(isA<TournamentException>()),
        );
      }
      await expectLater(
        api.member('00000000', '', publicAccess: true),
        throwsA(isA<TournamentException>()),
      );
    },
  );
  test(
    'empty results differ from malformed results and service failures',
    () async {
      final client = MockClient(
        (_) async => http.Response('{"items":[]}', 200),
      );
      addTearDown(client.close);
      expect(await RatingsApi(client).search('Test'), isEmpty);
      for (final body in [
        'secret',
        '{}',
        '{"items":null}',
        '{"items":[{"id":"123","firstName":"Test"}]}',
        '{"items":[{"id":"12345678","ratings":"secret"}]}',
      ]) {
        final client = MockClient((_) async => http.Response(body, 200));
        addTearDown(client.close);
        await expectLater(
          RatingsApi(client).search('Test'),
          throwsA(
            isA<TournamentException>().having(
              (e) => e.message,
              'safe message',
              isNot(contains('secret')),
            ),
          ),
        );
      }
      for (final status in [302, 401, 403, 404, 429, 500]) {
        final client = MockClient((_) async => http.Response('secret', status));
        addTearDown(client.close);
        await expectLater(
          RatingsApi(client).search('Test'),
          throwsA(
            isA<TournamentException>().having(
              (e) => e.message,
              'safe message',
              isNot(contains('secret')),
            ),
          ),
        );
      }
    },
  );
  test('only member 404 means an ID was not found', () async {
    for (final status in [404, 403, 429, 500]) {
      final client = MockClient((_) async => http.Response('', status));
      addTearDown(client.close);
      await expectLater(
        RatingsApi(client).member('12345678', '', publicAccess: true),
        throwsA(
          status == 404 ? isA<MemberNotFound>() : isNot(isA<MemberNotFound>()),
        ),
      );
    }
  });
}
