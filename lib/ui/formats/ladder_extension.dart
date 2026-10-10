import '../../domain/ladder.dart';
import '../../domain/model.dart';
import '../dialogs.dart' show FieldSpec;
import '../format_extensions.dart';

/// What a ladder adds to the section panel: only whether its games are
/// rated. The challenge range is a fixed house rule (see `ladder.dart`).
final ladderFormatExtension = FormatExtension(
  format: Format.ladder,
  fields: (current, {required locked}) => const [
    FieldSpec('unrated', 'Not rated', checkbox: true),
  ],
  values: (section) => {'unrated': section.unrated ? 'true' : 'false'},
  apply: (section, values) =>
      section.copy(unrated: values['unrated'] == 'true'),
  summary: (section) =>
      'Challenge up to $ladderChallengeRange places; '
      '${section.unrated ? 'unrated' : 'rated'}',
);
