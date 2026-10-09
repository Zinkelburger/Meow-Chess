import 'package:flutter/material.dart';
import '../application/failures.dart';
import '../infrastructure/member_directory.dart';
import 'select.dart';

/// An inline field for the US Chess API key. The key is kept in the system
/// keychain, not in the event file, and can be removed here.
class ApiKeyField extends StatefulWidget {
  const ApiKeyField({this.onSaved, super.key});
  final VoidCallback? onSaved;
  @override
  State<ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<ApiKeyField> {
  final text = TextEditingController();
  String? status;
  bool saved = false;

  @override
  void initState() {
    super.initState();
    hasMemberApiKey().then((value) {
      if (mounted) setState(() => saved = value);
    });
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final key = text.text.trim();
    if (key.isEmpty) return;
    try {
      await saveMemberApiKey(key);
      if (!mounted) return;
      text.clear();
      setState(() {
        saved = true;
        status = 'Key saved.';
      });
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Could not save the key. ${plainMessage(e)}');
      }
    }
  }

  /// A revoked key would block every lookup; without one, lookups use the
  /// public US Chess route.
  Future<void> remove() async {
    try {
      await saveMemberApiKey('');
      if (!mounted) return;
      setState(() {
        saved = false;
        status = 'Key removed. Lookups use public US Chess access.';
      });
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Could not remove the key. ${plainMessage(e)}');
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
      if (saved)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('remove-api-key'),
            onPressed: remove,
            child: const Text('Remove saved key'),
          ),
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

/// Shared across events on this computer, in a plain preferences file.
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
      await saveRatingCategory(value);
      if (mounted) {
        setState(() {
          category = value;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = 'Could not save this setting. ${plainMessage(e)}',
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
      PlainSelect<String>(
        key: ValueKey('rating-default-$category'),
        value: category,
        label: 'Default rating category',
        options: const [
          SelectOption('R', 'Regular'),
          SelectOption('Q', 'Quick'),
          SelectOption('B', 'Blitz'),
        ],
        onChanged: save,
      ),
      if (error != null) Text(error!),
    ],
  );
}
