import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'event_repository.dart';
import 'failures.dart';

/// UI drafts are independent of tournament history. Keep failed writes in memory
/// so navigating away cannot discard them, and make their durability explicit.
class WorkspaceState extends ChangeNotifier {
  WorkspaceState(this.repository);
  final EventRepository repository;
  final _memory = <String, String>{};
  final failures = <String, String>{};
  bool _scheduled = false, _disposed = false;

  String? read(String key) => _memory[key] ?? repository.readPreference(key);

  Map<String, dynamic> readMap(String key) {
    try {
      final value = read(key);
      return value == null || value.isEmpty
          ? {}
          : Map<String, dynamic>.from(jsonDecode(value) as Map);
    } catch (_) {
      return {};
    }
  }

  bool write(String key, String value) {
    if (_memory[key] == value && !failures.containsKey(key)) return true;
    _memory[key] = value;
    try {
      repository.writePreference(key, value);
      failures.remove(key);
    } catch (error) {
      failures[key] = plainMessage(error);
    }
    // Forms also save from focus/dispose callbacks during a frame.
    if (!_scheduled && !_disposed) {
      _scheduled = true;
      scheduleMicrotask(() {
        _scheduled = false;
        if (!_disposed) notifyListeners();
      });
    }
    return !failures.containsKey(key);
  }

  bool writeMap(String key, Map<String, dynamic> value) =>
      write(key, jsonEncode(value));

  void retry() {
    for (final key in failures.keys.toList()) {
      write(key, _memory[key]!);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
