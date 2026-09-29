import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../infrastructure/ratings_api.dart';
import 'dialogs.dart';

const _secure = FlutterSecureStorage();
Future<void> configureApi(BuildContext context) async {
  await editFields(
    context,
    title: 'US Chess data source',
    description:
        'Provide your own API key. It is stored in the operating system credential store, never in an event file. Offline tournament operation does not need a key.',
    fields: const [FieldSpec('key', 'API key', secret: true, required: true)],
    onSave: (v) => _secure.write(key: 'uschess-v2', value: v['key']!.trim()),
  );
}

Future<void> checkIdentity(
  BuildContext context,
  TournamentController c,
  Player player,
) async {
  final revision = c.event!.revision;
  final client = http.Client();
  try {
    var key = await _secure.read(key: 'uschess-v2');
    if (key == null) {
      if (!context.mounted) return;
      await configureApi(context);
      key = await _secure.read(key: 'uschess-v2');
      if (key == null) return;
    }
    if (!context.mounted) return;
    showFailure(context, 'Checking ${player.name}…');
    final observation = await RatingsApi(client).member(player.memberId, key);
    c.repository.writePreference(
      'member:${player.memberId}',
      jsonEncode(observation.toJson()),
    );
    if (!context.mounted) return;
    await editFields(
      context,
      title: 'Review identity and rating',
      description:
          'Entered: ${player.name} · ${player.memberId} · rating ${player.rating}\nProvider: ${observation.name} · ${observation.id}\nMembership: ${observation.status ?? 'unknown'} · expires ${observation.expiration ?? 'unknown'}\nRetrieved ${observation.retrievedAt}\nPublished ratings: ${observation.ratings}\nLatest/unofficial rating is unavailable or unverified. Apply only fields you have reviewed; no update happens automatically.',
      fields: const [
        FieldSpec('name', 'Confirmed name', required: true),
        FieldSpec('rating', 'Reviewed regular pairing rating', required: true),
      ],
      values: {'name': player.name, 'rating': '${player.rating}'},
      onSave: (v) {
        if (c.event!.revision != revision) {
          throw const TournamentException(
            'The event changed during lookup. Close this review and check again.',
          );
        }
        final rating = int.tryParse(v['rating']!);
        if (rating == null) {
          throw const TournamentException('Enter an integer rating.');
        }
        c.savePlayer(player.copy(name: v['name']!, rating: rating));
      },
    );
  } catch (e) {
    if (context.mounted) showFailure(context, e);
  } finally {
    client.close();
  }
}
