import 'dart:io';

import '../domain/model.dart';

/// A failure as one plain sentence a TD can act on, never a class name or
/// stack-trace fragment.
String plainMessage(Object error) {
  String sentence(String text) {
    final t = text.trim();
    if (t.isEmpty) return 'Something went wrong. Try again.';
    final first = t[0].toUpperCase() + t.substring(1);
    return RegExp(r'[.!?]$').hasMatch(first) ? first : '$first.';
  }

  switch (error) {
    case TournamentException(:final message):
      return message;
    case String text:
      return text;
    case FileSystemException(:final message, :final path, :final osError):
      final why = osError?.message ?? '';
      return sentence(
        [
              message.isEmpty ? 'The file could not be used' : message,
              if (path != null && path.isNotEmpty) path,
            ].join(': ') +
            (why.isEmpty ? '' : ' ($why)'),
      );
    case FormatException(:final message):
      return sentence(
        message.isEmpty
            ? 'This file is not in a format Meow-Chess can read'
            : 'This file is not in a format Meow-Chess can read: $message',
      );
    case StateError(:final message):
      return sentence(message);
  }
  final text = '$error';
  if (text.contains('database is locked') || text.contains('SQLITE_BUSY')) {
    return 'Another program has this event file open. Close it there, then try again.';
  }
  if (text.contains('disk is full') || text.contains('SQLITE_FULL')) {
    return 'The disk is full, so the change was not saved. Free some space, then try again.';
  }
  if (text.contains('readonly') || text.contains('SQLITE_READONLY')) {
    return 'The event file is read-only, so the change was not saved.';
  }
  // Drop a leading "SomeException:" or "SomeException(5):" label.
  final detail = text
      .split('\n')
      .first
      .replaceFirst(RegExp(r'^[A-Za-z]*(Exception|Error)(\([^)]*\))?:\s*'), '');
  return sentence('Something went wrong: $detail');
}
