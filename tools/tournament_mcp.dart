// stdio MCP 2025-06-18 adapter; also accepts JSON-lines CLI commands.
import 'dart:convert';
import 'dart:io';

import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/tournament_tools.dart';
import 'package:meow_chess/version.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2 || !['--root', '--cli-root'].contains(args.first)) {
    stderr.writeln(
      'Usage: dart run tools/tournament_mcp.dart --root DATA_DIRECTORY\n'
      'CLI: --cli-root DATA_DIRECTORY; one {"tool":"...","arguments":{...}} per input line.',
    );
    exitCode = 64;
    return;
  }
  final api = TournamentTools(args.last);
  final cli = args.first == '--cli-root';
  var initialized = false;
  try {
    await for (final bytes in _lines(stdin)) {
      dynamic id;
      Json response;
      try {
        // One malformed line is answered and skipped; it never ends the
        // session.
        final line = utf8.decode(bytes);
        if (line.trim().isEmpty) continue;
        final decoded = jsonDecode(line);
        if (decoded is! Json) {
          stdout.writeln(jsonEncode(_error(null, -32600, 'Invalid Request')));
          await stdout.flush();
          continue;
        }
        final request = decoded;
        if (cli) {
          try {
            response = {
              'result': await api.call(
                request['tool'] as String,
                Map<String, dynamic>.from(request['arguments'] ?? {}),
              ),
            };
          } catch (error) {
            response = toolFailure(error);
          }
        } else {
          final rawId = request['id'];
          final validId = rawId == null || rawId is String || rawId is num;
          // An id that cannot be echoed is reported as null.
          id = validId ? rawId : null;
          if (request['jsonrpc'] != '2.0' ||
              request['method'] is! String ||
              !validId) {
            response = _error(id, -32600, 'Invalid Request');
          } else if (!request.containsKey('id')) {
            // Notifications never produce a response (including initialized/cancelled).
            continue;
          } else {
            final params = request['params'] ?? <String, dynamic>{};
            if (params is! Json) {
              response = _error(id, -32602, 'Invalid params');
            } else {
              switch (request['method']) {
                case 'initialize':
                  initialized = true;
                  response = _result(id, {
                    'protocolVersion': '2025-06-18',
                    'capabilities': {
                      'tools': {'listChanged': false},
                    },
                    'serverInfo': {'name': 'meow-chess', 'version': appVersion},
                    'instructions':
                        'Local tournament files only. Read get_event before edits and pass its expectedRevision. Close the event before opening it in the GUI. Never invent results or identities.',
                  });
                case 'ping':
                  response = _result(id, {});
                case 'tools/list':
                  response = initialized
                      ? _result(id, {'tools': TournamentTools.definitions})
                      : _error(id, -32000, 'Initialize first');
                case 'tools/call':
                  if (!initialized) {
                    response = _error(id, -32000, 'Initialize first');
                  } else if (params['name'] is! String ||
                      (params['arguments'] != null &&
                          params['arguments'] is! Json)) {
                    response = _error(id, -32602, 'Invalid tool arguments');
                  } else {
                    try {
                      final value = await api.call(
                        params['name'],
                        Map<String, dynamic>.from(params['arguments'] ?? {}),
                      );
                      response = _result(id, {
                        'content': [
                          {'type': 'text', 'text': jsonEncode(value)},
                        ],
                        'structuredContent': value,
                      });
                    } catch (error) {
                      response = _result(id, toolFailure(error));
                    }
                  }
                default:
                  response = _error(id, -32601, 'Method not found');
              }
            }
          }
        }
      } on FormatException {
        response = _error(null, -32700, 'Parse error');
      } catch (error) {
        response = _error(id, -32603, 'Internal error');
        stderr.writeln(error);
      }
      stdout.writeln(jsonEncode(response));
      await stdout.flush();
    }
  } finally {
    api.close();
  }
}

/// Input lines as bytes, so each line is decoded on its own.
Stream<List<int>> _lines(Stream<List<int>> input) async* {
  var line = <int>[];
  await for (final chunk in input) {
    for (final byte in chunk) {
      if (byte == 0x0A) {
        if (line.isNotEmpty && line.last == 0x0D) line.removeLast();
        yield line;
        line = <int>[];
      } else {
        line.add(byte);
      }
    }
  }
  if (line.isNotEmpty) yield line;
}

Json _result(dynamic id, Json result) => {
  'jsonrpc': '2.0',
  'id': id,
  'result': result,
};
Json _error(dynamic id, int code, String message) => {
  'jsonrpc': '2.0',
  'id': id,
  'error': {'code': code, 'message': message},
};
