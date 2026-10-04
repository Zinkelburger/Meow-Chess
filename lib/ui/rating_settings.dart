import 'package:flutter/material.dart';
import '../application/failures.dart';
import '../infrastructure/member_directory.dart';

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
      await saveMemberApiKey(key);
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
      await saveRatingCategory(value);
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
