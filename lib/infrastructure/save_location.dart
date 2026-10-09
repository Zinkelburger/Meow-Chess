import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../application/diagnostics.dart';
import '../domain/model.dart';

/// Returns only a destination accepted by the native save dialog, including
/// its replacement confirmation. Cancellation leaves the destination alone.
/// The chosen file keeps the suggested name's extension, so an event saved as
/// "Spring Open" still shows up in the Open dialog's .meow filter.
Future<FileSaveLocation?> chooseSaveLocation({
  required String suggestedName,
}) async {
  final extension = p.extension(suggestedName);
  FileSaveLocation? location;
  if (defaultTargetPlatform == TargetPlatform.linux) {
    // file_selector_linux does not enable GTK's overwrite confirmation.
    final path = await const MethodChannel(
      'meow_chess/file_save',
    ).invokeMethod<String>('save', suggestedName);
    location = path == null ? null : FileSaveLocation(path);
  } else {
    // The macOS panel appends the extension itself; its sandbox grant covers
    // only the exact name it returns, so that name is never changed below.
    location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        if (extension.length > 1)
          XTypeGroup(
            label: extension == '.meow'
                ? 'Meow-Chess event'
                : '${extension.substring(1).toUpperCase()} file',
            extensions: [extension.substring(1)],
          ),
      ],
    );
  }
  if (location == null) {
    Diagnostics.record('save dialog', 'cancelled');
    return null;
  }
  // Never interpret a malformed native result relative to the launch folder.
  if (!p.isAbsolute(location.path)) {
    Diagnostics.record(
      'save dialog',
      'invalid destination',
      context: {'path': location.path},
    );
    throw const FormatException(
      'The save dialog did not return a full file path.',
    );
  }
  if (defaultTargetPlatform != TargetPlatform.macOS) {
    final completed = withSuggestedExtension(location.path, extension);
    if (completed != location.path) {
      // The dialog confirmed replacing the typed name, not this one.
      if (FileSystemEntity.typeSync(completed, followLinks: false) !=
          FileSystemEntityType.notFound) {
        Diagnostics.record(
          'save dialog',
          'completed name exists',
          context: {'path': completed},
        );
        throw TournamentException(
          '${p.basename(completed)} already exists. Choose it in the save dialog to replace it, or enter another name.',
        );
      }
      location = FileSaveLocation(completed);
    }
  }
  Diagnostics.record(
    'save dialog',
    'accepted',
    context: {'path': location.path},
  );
  return location;
}

/// Event files always end in .meow; other files gain the suggested extension
/// only when the typed name has none, so "results.txt" stays as chosen.
String withSuggestedExtension(String path, String extension) {
  if (extension.length < 2) return path;
  final name = p.basename(path);
  if (name.toLowerCase().endsWith(extension.toLowerCase())) return path;
  if (extension.toLowerCase() != '.meow' && p.extension(name).isNotEmpty) {
    return path;
  }
  return '$path$extension';
}
