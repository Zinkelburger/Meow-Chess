import 'dart:async';
import 'package:flutter/material.dart';

import '../application/failures.dart';

/// Opens a dialog with no enter/exit animation so it appears immediately.
Future<T?> openDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  builder: builder,
  barrierDismissible: barrierDismissible,
  animationStyle: AnimationStyle.noAnimation,
);

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.lines = 1,
    this.hint,
    this.required = false,
    this.secret = false,
    this.options,
  });
  final String key, label;
  final int lines;
  final String? hint;
  final bool required, secret;

  /// Stored value → displayed label. When set, the field is a drop-down.
  final Map<String, String>? options;
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
}) => openDialog<Map<String, String>>(
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
      f.key: TextEditingController(
        text: f.options == null || f.options!.containsKey(widget.values[f.key])
            ? widget.values[f.key] ?? ''
            : f.options!.keys.first,
      ),
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
          error = plainMessage(e);
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
                  child: f.options != null
                      ? DropdownButtonFormField<String>(
                          key: ValueKey('field-${f.key}'),
                          initialValue:
                              f.options!.containsKey(controllers[f.key]!.text)
                              ? controllers[f.key]!.text
                              : f.options!.keys.first,
                          decoration: InputDecoration(labelText: f.label),
                          items: [
                            for (final o in f.options!.entries)
                              DropdownMenuItem(
                                value: o.key,
                                child: Text(o.value),
                              ),
                          ],
                          onChanged: (v) => controllers[f.key]!.text = v!,
                        )
                      : TextFormField(
                          key: ValueKey('field-${f.key}'),
                          controller: controllers[f.key],
                          autofocus: i == 0,
                          maxLines: f.lines,
                          obscureText: f.secret,
                          decoration: InputDecoration(
                            labelText: f.label,
                            hintText: f.hint,
                          ),
                          validator: (v) =>
                              f.required && (v?.trim().isEmpty ?? true)
                              ? 'Required'
                              : null,
                          onChanged: (_) {
                            try {
                              widget.onDraft?.call(values());
                            } catch (e) {
                              if (mounted) {
                                setState(
                                  () => error =
                                      'Draft could not be saved. ${plainMessage(e)}',
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
    await openDialog<bool>(
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

/// Shows a problem until it is dismissed: errors must not time out before
/// a TD who was helping a player gets back to the screen.
void showFailure(BuildContext context, Object error) {
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  final colors = Theme.of(context).colorScheme;
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(Icons.error_outline, color: colors.onError, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              plainMessage(error),
              style: TextStyle(color: colors.onError),
            ),
          ),
        ],
      ),
      backgroundColor: colors.error,
      closeIconColor: colors.onError,
      persist: true,
      showCloseIcon: true,
    ),
    snackBarAnimationStyle: AnimationStyle.noAnimation,
  );
}

/// Confirms something that worked, such as a saved file. Not for errors.
void showNotice(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        showCloseIcon: true,
        action: action,
      ),
      snackBarAnimationStyle: AnimationStyle.noAnimation,
    );
}
