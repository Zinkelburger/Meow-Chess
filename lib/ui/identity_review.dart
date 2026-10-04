import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../infrastructure/ratings_api.dart';

const _secure = FlutterSecureStorage();
const _keyName = 'uschess-v2';

Future<List<MemberObservation>> searchMembers(String name) async {
  String? key;
  try {
    key = await _secure.read(key: _keyName);
  } catch (_) {
    /* Public lookup also works without a keychain. */
  }
  final client = http.Client();
  try {
    return await RatingsApi(client).search(name, key: key ?? '');
  } finally {
    client.close();
  }
}

/// Fetches a dated supplement using the public endpoint when no key is set.
Future<MemberObservation?> fetchMember(
  TournamentController c,
  String memberId,
) => _fetchMember(c, memberId, membershipOnly: false);

/// Membership does not require a published rating or a monthly supplement.
Future<MemberObservation?> fetchMembership(
  TournamentController c,
  String memberId,
) => _fetchMember(c, memberId, membershipOnly: true);

Future<MemberObservation?> _fetchMember(
  TournamentController c,
  String memberId, {
  required bool membershipOnly,
}) async {
  String? key;
  try {
    key = await _secure.read(key: _keyName);
  } catch (_) {
    /* Public lookup also works without a keychain. */
  }
  final client = http.Client();
  try {
    final api = RatingsApi(client);
    final observation = membershipOnly
        ? await api.member(
            memberId,
            key ?? '',
            publicAccess: (key ?? '').trim().isEmpty,
          )
        : await api.supplement(memberId, key: key ?? '');
    c.repository.writePreference(
      'member:$memberId',
      jsonEncode(observation.toJson()),
    );
    return observation;
  } finally {
    client.close();
  }
}

/// An inline field for the US Chess API key. The key is kept in the system
/// keychain, not in the event file.
class ApiKeyField extends StatefulWidget {
  const ApiKeyField({this.onSaved, super.key});
  final VoidCallback? onSaved;
  @override
  State<ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<ApiKeyField> {
  final text = TextEditingController();
  String? status;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final key = text.text.trim();
    if (key.isEmpty) return;
    try {
      await _secure.write(key: _keyName, value: key);
      if (!mounted) return;
      text.clear();
      setState(() => status = 'Key saved.');
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Could not save the key. ${plainMessage(e)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('api-key'),
              controller: text,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'US Chess API key'),
              onSubmitted: (_) => save(),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: save, child: const Text('Save key')),
        ],
      ),
      if (status != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            status!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ],
  );
}

Future<String> readRatingCategory() async {
  try {
    final value = await _secure.read(key: 'meow-rating-category');
    return ['R', 'Q', 'B'].contains(value) ? value! : 'R';
  } catch (_) {
    return 'R';
  }
}

/// Shared across events on this computer, alongside the operator's API key.
class RatingSettings extends StatefulWidget {
  const RatingSettings({super.key});
  @override
  State<RatingSettings> createState() => _RatingSettingsState();
}

class _RatingSettingsState extends State<RatingSettings> {
  String category = 'R';
  String? error;
  @override
  void initState() {
    super.initState();
    readRatingCategory().then((value) {
      if (mounted) setState(() => category = value);
    });
  }

  Future<void> save(String value) async {
    try {
      await _secure.write(key: 'meow-rating-category', value: value);
      if (mounted) {
        setState(() {
          category = value;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not save this setting in the system keychain.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Rating defaults · all events'),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        isExpanded: true,
        key: ValueKey('rating-default-$category'),
        initialValue: category,
        decoration: const InputDecoration(labelText: 'Default rating category'),
        items: const [
          DropdownMenuItem(value: 'R', child: Text('Regular')),
          DropdownMenuItem(value: 'Q', child: Text('Quick')),
          DropdownMenuItem(value: 'B', child: Text('Blitz')),
        ],
        onChanged: (value) => save(value!),
      ),
      if (error != null) Text(error!),
    ],
  );
}
