import '../../domain/model.dart';
import '../../domain/scheveningen.dart';
import '../dialogs.dart' show FieldSpec;
import '../format_extensions.dart';

/// What a Scheveningen adds to the section panel: which team label is side
/// A (the home team). Everyone else in the section is side B. The label is
/// typed as the players carry it; the panel's problem line says when no
/// player, or every player, has it.
final scheveningenFormatExtension = FormatExtension(
  format: Format.scheveningen,
  fields: (current, {required locked}) => [
    FieldSpec(
      'homeTeam',
      'Home team (side A)',
      enabled: !locked,
      note: (value) => value.trim().isEmpty
          ? 'Give the players two team labels first, then type side A\'s label here.'
          : 'Players labelled "${value.trim()}" are side A; everyone else is side B.',
    ),
  ],
  values: (section) => {'homeTeam': section.homeTeam},
  apply: (section, values) =>
      section.copy(homeTeam: (values['homeTeam'] ?? '').trim()),
  summary: (section) => section.homeTeam.trim().isEmpty
      ? 'Choose the home team'
      : '${section.homeTeam.trim()} vs the rest',
  problem: scheveningenProblem,
);
