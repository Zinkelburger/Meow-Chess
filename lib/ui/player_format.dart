import '../domain/model.dart';

/// A rating as typed and shown: UNR for unrated.
String ratingText(int rating) => rating == 0 ? 'UNR' : '$rating';

/// Reads a typed rating. Blank, UNR and "unrated" mean unrated (0).
int? parseRating(String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty || t == 'unr' || t == 'unr.' || t == 'unrated') return 0;
  final n = int.tryParse(t);
  return n == null || n < 0 ? null : n;
}

/// ½-point units as a short label: 0, ½, 1, 1½ …
String halves(int n) => n == 1
    ? '½'
    : n.isOdd
    ? '${n ~/ 2}½'
    : '${n ~/ 2}';

/// First and last board a section uses, e.g. "boards 3–4".
String boardRange(Section s) {
  final count = (s.players.length + 1) ~/ 2;
  if (count <= 1) return 'board ${s.boardStart}';
  return 'boards ${s.boardStart}–${s.boardStart + count - 1}';
}
