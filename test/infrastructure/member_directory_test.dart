import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meow_chess/infrastructure/member_directory.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';

class TrackingClient extends MockClient {
  TrackingClient(super.fn);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

class UnavailableKeychain extends FlutterSecureStorage {
  const UnavailableKeychain();
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw StateError('Keychain is locked');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'a locked keychain still permits public lookup and closes the client',
    () async {
      final client = TrackingClient((request) async {
        expect(request.url.path, '/api/v1/members/12000000');
        expect(request.headers.containsKey('X-Api-Key'), false);
        return http.Response(
          jsonEncode({'id': '12000000', 'firstName': 'Test'}),
          200,
        );
      });
      final directory = MemberDirectory(
        storage: const UnavailableKeychain(),
        createClient: () => client,
      );
      expect((await directory.member('12000000')).id, '12000000');
      expect(client.closed, true);
    },
  );

  test(
    'private lookup uses stored credentials and closes after provider failure',
    () async {
      FlutterSecureStorage.setMockInitialValues({'uschess-v2': 'operator-key'});
      final client = TrackingClient((request) async {
        expect(request.url.path, '/api/v2/members/12000000');
        expect(request.headers['X-Api-Key'], 'operator-key');
        return http.Response('not propagated', 403);
      });
      final directory = MemberDirectory(createClient: () => client);
      await expectLater(
        directory.member('12000000'),
        throwsA(isA<MemberLookupFailure>()),
      );
      expect(client.closed, true);
    },
  );
}
