import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../domain/member_observation.dart';
import 'diagnostic_log.dart';
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

/// Saves the operator's key; an empty key removes it, so lookups go back to
/// the public US Chess route.
Future<void> saveMemberApiKey(String key) => key.trim().isEmpty
    ? _secure.delete(key: _keyName)
    : _secure.write(key: _keyName, value: key.trim());

/// Whether a key is saved. A locked keychain reads as no key, as lookups do.
Future<bool> hasMemberApiKey() async {
  try {
    return (await _secure.read(key: _keyName))?.trim().isNotEmpty ?? false;
  } catch (_) {
    return false;
  }
}

const _categories = ['R', 'Q', 'B'];
const _legacyCategoryKey = 'meow-rating-category';

/// The default rating category is not a secret, so it lives in a plain
/// preferences file in the app data folder, not in the keychain (which may
/// be missing, as on Linux without a Secret Service). Older versions kept it
/// in the keychain; that value is read once to migrate it.
class RatingCategoryPreference {
  RatingCategoryPreference({this.directory, this.storage = _secure});

  /// Defaults to the app data folder that startup set up for the diagnostic
  /// log. Without one (no app startup) only the old keychain entry is used.
  final Directory? directory;
  final FlutterSecureStorage storage;

  File? get file {
    final dir = directory ?? DiagnosticLog.current?.file.parent.parent;
    return dir == null
        ? null
        : File(path.join(dir.path, 'rating-defaults.json'));
  }

  // A few bytes, read and written synchronously like the diagnostic log.
  Future<String> read() async {
    final f = file;
    try {
      if (f != null && f.existsSync()) {
        final saved = (jsonDecode(f.readAsStringSync()) as Map)['category'];
        return _categories.contains(saved) ? saved as String : 'R';
      }
    } catch (_) {
      return 'R';
    }
    final String? legacy;
    try {
      legacy = await storage.read(key: _legacyCategoryKey);
    } catch (_) {
      return 'R';
    }
    final value = _categories.contains(legacy) ? legacy! : 'R';
    if (f != null) {
      try {
        _write(f, value);
      } catch (_) {
        // Migration retries next time.
      }
    }
    return value;
  }

  Future<void> write(String category) async {
    final value = _categories.contains(category) ? category : 'R';
    final f = file;
    if (f == null) {
      return storage.write(key: _legacyCategoryKey, value: value);
    }
    _write(f, value);
  }

  void _write(File f, String category) {
    f.parent.createSync(recursive: true);
    final temporary = File('${f.path}.tmp');
    temporary.writeAsStringSync(
      jsonEncode({'category': category}),
      flush: true,
    );
    temporary.renameSync(f.path);
  }
}

Future<String> readRatingCategory() => RatingCategoryPreference().read();

Future<void> saveRatingCategory(String category) =>
    RatingCategoryPreference().write(category);
