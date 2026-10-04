import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../domain/member_observation.dart';
import 'ratings_api.dart' show RatingsApi;

const _secure = FlutterSecureStorage();
const _keyName = 'uschess-v2';

/// Owns provider credentials and short-lived HTTP clients. Reads never write to
/// an event repository; the application must accept evidence before storing it.
class MemberDirectory {
  const MemberDirectory({
    this.storage = _secure,
    this.createClient = http.Client.new,
  });
  final FlutterSecureStorage storage;
  final http.Client Function() createClient;

  Future<T> _read<T>(Future<T> Function(RatingsApi, String) request) async {
    String? key;
    try {
      key = await storage.read(key: _keyName);
    } catch (_) {
      // Public lookup also works when the system keychain is unavailable.
    }
    final client = createClient();
    try {
      return await request(RatingsApi(client), key ?? '');
    } finally {
      client.close();
    }
  }

  Future<List<MemberObservation>> search(String name) =>
      _read((api, key) => api.search(name, key: key));

  Future<MemberObservation> supplement(String id) =>
      _read((api, key) => api.supplement(id, key: key));

  Future<MemberObservation> member(String id) => _read(
    (api, key) => api.member(id, key, publicAccess: key.trim().isEmpty),
  );
}

Future<List<MemberObservation>> searchMembers(String name) =>
    const MemberDirectory().search(name);

Future<MemberObservation> fetchMember(String id) =>
    const MemberDirectory().supplement(id);

Future<MemberObservation> fetchMembership(String id) =>
    const MemberDirectory().member(id);

Future<void> saveMemberApiKey(String key) =>
    _secure.write(key: _keyName, value: key);

Future<String> readRatingCategory() async {
  try {
    final value = await _secure.read(key: 'meow-rating-category');
    return ['R', 'Q', 'B'].contains(value) ? value! : 'R';
  } catch (_) {
    return 'R';
  }
}

Future<void> saveRatingCategory(String category) =>
    _secure.write(key: 'meow-rating-category', value: category);
