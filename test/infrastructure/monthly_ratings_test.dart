import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';

void main() {
  for (final key in ['', 'operator-key']) {
    test(
      'dated monthly ratings with ${key.isEmpty ? 'public v1' : 'keyed v2'} preserve unknown categories',
      () async {
        final client = MockClient((request) async {
          expect(
            request.url.path,
            startsWith('/api/${key.isEmpty ? 'v1' : 'v2'}/members/00123456'),
          );
          expect(request.followRedirects, false);
          expect(request.headers['X-Api-Key'], key.isEmpty ? isNull : key);
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('rating-supplements')
                  ? {
                      'items': [
                        {
                          'ratingSupplementDate': '2020-01-01',
                          'ratings': [
                            {'source': 'R', 'rating': 2000},
                          ],
                        },
                        {
                          'ratingSupplementDate': '2020-02-01',
                          'ratings': [
                            {'source': 'R', 'rating': 1900},
                            {'source': 'Q'},
                            {'source': 'B', 'rating': -12},
                          ],
                        },
                      ],
                    }
                  : {
                      'id': '00123456',
                      'expirationDate': '2027-12-31',
                      'status': 'Active',
                      'firstName': 'Test',
                      'lastName': 'Player',
                      'stateRep': 'NH',
                      'ratings': [
                        {'ratingSystem': 'R', 'rating': 999},
                      ],
                    },
            ),
            200,
          );
        });
        addTearDown(client.close);
        final value = await RatingsApi(client).supplement('00123456', key: key);
        expect(value.ratings['R'], 1900);
        expect(value.ratings['Q'], isNull);
        expect(value.ratings['B'], isNull);
        expect(value.supplementDate, '2020-02-01');
        expect(value.expiration, '2027-12-31');
        expect(value.status, 'Active');
        expect(value.state, 'NH');
        expect(value.toJson().toString(), isNot(contains('operator-key')));
      },
    );
  }
  test(
    'membership lookup for an unrated player needs no supplements',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/members/00123456');
        return http.Response(
          jsonEncode({
            'id': '00123456',
            'expirationDate': '2027-01-31',
            'status': 'Active',
          }),
          200,
        );
      });
      addTearDown(client.close);
      final member = await RatingsApi(
        client,
      ).member('00123456', '', publicAccess: true);
      expect(member.expiration, '2027-01-31');
      expect(member.ratings, isEmpty);
      expect(member.provider, 'US Chess public v1');
    },
  );
  test('profile cannot substitute for missing monthly data', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('rating-supplements')
              ? {'items': []}
              : {'id': '00123456', 'ratings': []},
        ),
        200,
      ),
    );
    addTearDown(client.close);
    final found = await RatingsApi(client).supplement('00123456');
    expect(found.ratings, isEmpty);
    expect(found.supplementDate, isNull);
  });
}
