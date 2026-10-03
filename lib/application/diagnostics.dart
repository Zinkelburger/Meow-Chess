import 'dart:developer' as developer;

/// Readable, timestamped diagnostics shared by desktop and headless operations. Recording
/// a diagnostic must never change whether a tournament operation succeeds.
class Diagnostics {
  static void Function(String line)? sink;

  static void record(
    String operation,
    String result, {
    Map<String, Object?> context = const {},
    Object? error,
    StackTrace? stack,
  }) {
    try {
      final lines = <String>[
        '${DateTime.now().toUtc().toIso8601String()} '
            '${error == null ? 'INFO' : 'ERROR'} $operation — $result',
        for (final entry in context.entries)
          '  ${entry.key}: ${entry.value}'.replaceAll('\n', '\n  '),
        if (error != null) '  Error: $error'.replaceAll('\n', '\n  '),
        if (stack != null) ...[
          '  Stack trace:',
          for (final frame in '$stack'.trimRight().split('\n')) '    $frame',
        ],
      ];
      final line = lines.join('\n');
      developer.log(
        line,
        name: 'Meow-Chess',
        level: error == null ? 800 : 1000,
      );
      sink?.call(line);
    } catch (_) {
      // A full disk or broken logging destination must not prevent a save.
    }
  }

  static String sourceUrl(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null || !uri.hasAuthority) return '(invalid URL)';
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }
}
