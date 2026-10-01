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
        duration: const Duration(seconds: 8),
        persist: false,
        showCloseIcon: true,
        action: action,
      ),
      snackBarAnimationStyle: AnimationStyle.noAnimation,
    );
}
