import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../infrastructure/ratings_api.dart';

const _secure = FlutterSecureStorage();
const _keyName = 'uschess-v2';

/// Fetches a member record, or null when no API key is set.
Future<MemberObservation?> fetchMember(
  TournamentController c,
  String memberId,
) async {
  final key = await _secure.read(key: _keyName);
  if (key == null) return null;
  final client = http.Client();
  try {
    final observation = await RatingsApi(client).member(memberId, key);
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
