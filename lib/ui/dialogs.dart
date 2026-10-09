import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/diagnostics.dart';
import '../application/failures.dart';

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.lines = 1,
    this.required = false,
    this.secret = false,
    this.checkbox = false,
    this.enabled = true,
    this.options,
    this.note,
  });
  final String key, label;
  final int lines;
  final bool required, secret, checkbox, enabled;

  /// Muted advice under a text field for its current value, such as the
  /// rule 5E2 delay hint; null shows nothing.
  final String? Function(String value)? note;

  /// Stored value → displayed label. When set, the field is a drop-down.
  final Map<String, String>? options;
}

/// Shows a problem until it is dismissed: errors must not time out before
/// a TD who was helping a player gets back to the screen.
void showFailure(BuildContext context, Object error) {
  final message = plainMessage(error);
  Diagnostics.record(
    'error notification',
    'shown',
    error: error,
    context: {'message': message},
  );
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  final colors = Theme.of(context).colorScheme;
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(Icons.error_outline, color: colors.onError, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(color: colors.onError)),
          ),
          IconButton(
            tooltip: 'Copy error message',
            icon: const Icon(Icons.content_copy, size: 20),
            color: colors.onError,
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: message));
              } catch (e, stack) {
                Diagnostics.record(
                  'copy error message',
                  'failed',
                  error: e,
                  stack: stack,
                );
              }
            },
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
