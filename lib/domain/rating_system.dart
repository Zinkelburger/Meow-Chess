/// A published player rating system, distinct from an event's time-control
/// category (which may be Dual). Wire evidence uses the US Chess R/Q/B codes.
enum RatingSystem {
  regular('R', 'Regular'),
  quick('Q', 'Quick'),
  blitz('B', 'Blitz');

  const RatingSystem(this.code, this.label);
  final String code, label;

  /// Accept older descriptive evidence as well as current provider codes.
  static RatingSystem? parse(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim().toLowerCase();
    return values
        .where(
          (system) =>
              system.code.toLowerCase() == normalized ||
              system.name == normalized,
        )
        .firstOrNull;
  }
}
