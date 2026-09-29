import 'dart:async';
import 'package:flutter/material.dart';

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.lines = 1,
    this.hint,
    this.required = false,
    this.secret = false,
  });
  final String key, label;
  final int lines;
  final String? hint;
  final bool required, secret;
}

Future<Map<String, String>?> editFields(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  Map<String, String> values = const {},
  String? description,
  String saveLabel = 'Save',
  Map<String, String> secondaryActions = const {},
  void Function(Map<String, String>)? onDraft,
  FutureOr<void> Function(Map<String, String>)? onSave,
}) => showDialog<Map<String, String>>(
  context: context,
  builder: (_) => _FieldsDialog(
    title: title,
    fields: fields,
    values: values,
    description: description,
    saveLabel: saveLabel,
    secondaryActions: secondaryActions,
    onDraft: onDraft,
    onSave: onSave,
  ),
);

class _FieldsDialog extends StatefulWidget {
  const _FieldsDialog({
    required this.title,
    required this.fields,
    required this.values,
    required this.saveLabel,
    required this.secondaryActions,
    this.description,
    this.onDraft,
    this.onSave,
  });
  final String title, saveLabel;
  final Map<String, String> secondaryActions;
  final List<FieldSpec> fields;
  final Map<String, String> values;
  final String? description;
  final void Function(Map<String, String>)? onDraft;
  final FutureOr<void> Function(Map<String, String>)? onSave;
  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  late final controllers = {
    for (final f in widget.fields)
      f.key: TextEditingController(text: widget.values[f.key] ?? ''),
  };
  final form = GlobalKey<FormState>();
  String? error;
  bool busy = false;
  Map<String, String> values() =>
      controllers.map((k, v) => MapEntry(k, v.text));
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save([String? action]) async {
    if (!form.currentState!.validate() || busy) return;
    setState(() => busy = true);
    try {
      await widget.onSave?.call(values());
      if (mounted) {
        Navigator.pop(context, {...values(), '_action': ?action});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.description != null) ...[
                Text(widget.description!),
                const SizedBox(height: 18),
              ],
              for (final (i, f) in widget.fields.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextFormField(
                    key: ValueKey('field-${f.key}'),
                    controller: controllers[f.key],
                    autofocus: i == 0,
                    maxLines: f.lines,
                    obscureText: f.secret,
                    decoration: InputDecoration(
                      labelText: f.label,
                      hintText: f.hint,
                    ),
                    validator: (v) => f.required && (v?.trim().isEmpty ?? true)
                        ? 'Required'
                        : null,
                    onChanged: (_) {
                      try {
                        widget.onDraft?.call(values());
                      } catch (e) {
                        if (mounted) {
                          setState(
                            () => error = 'Draft could not be saved: $e',
                          );
                        }
                      }
                    },
                    onFieldSubmitted: (_) {
                      if (i == widget.fields.length - 1) save();
                    },
                  ),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      for (final entry in widget.secondaryActions.entries)
        TextButton(
          onPressed: busy ? null : () => save(entry.key),
          child: Text(entry.value),
        ),
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(busy ? 'Saving…' : widget.saveLabel),
      ),
    ],
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'Continue',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

void showFailure(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error.toString()),
      duration: const Duration(seconds: 8),
      showCloseIcon: true,
    ),
  );
}
