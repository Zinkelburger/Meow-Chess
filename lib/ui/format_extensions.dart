import '../domain/model.dart';
import 'dialogs.dart' show FieldSpec;
import 'formats/bughouse_panel.dart' show bughouseFormatExtension;
import 'formats/knockout_extension.dart';
import 'formats/ladder_extension.dart';
import 'formats/scheveningen_extension.dart';

/// What a format adds to the section panel beyond the announcement line.
/// Each format registers one extension in [formatExtensions]; the panel
/// shows its fields inside the "Pairing rules" group only for that format.
/// Values travel as strings through the panel's draft (see FieldsPanel), so
/// [values] and [apply] convert in both directions.
class FormatExtension {
  const FormatExtension({
    required this.format,
    required this.fields,
    required this.values,
    required this.apply,
    this.summary,
    this.problem,
  });
  final Format format;

  /// Fields for the Pairing rules group. [locked] is true once round 1 is
  /// posted; fields that must be set before round 1 should disable then.
  final List<FieldSpec> Function(Section? current, {required bool locked})
  fields;

  /// Current values for [fields], keyed like the FieldSpecs.
  final Map<String, String> Function(Section section) values;

  /// The section with the edited values applied; throws
  /// TournamentException with a plain message on invalid input.
  final Section Function(Section section, Map<String, String> values) apply;

  /// The closed group's one-line summary, or null for "Standard rules".
  final String? Function(Section section)? summary;

  /// Why the section cannot be created or paired as set, or null.
  final String? Function(Event event, Section section)? problem;
}

/// Registered extensions, one per format that has any. Append yours here.
final formatExtensions = <FormatExtension>[
  ladderFormatExtension,
  scheveningenFormatExtension,
  bughouseFormatExtension,
  knockoutFormatExtension,
];
