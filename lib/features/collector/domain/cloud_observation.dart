/// A user-confirmed cloud observation. This is deliberately distinct from an
/// ML inference: no model is bundled with the app yet.
enum CloudGenus {
  cirrus('Cirrus'),
  cirrocumulus('Cirrocumulus'),
  cirrostratus('Cirrostratus'),
  altocumulus('Altocumulus'),
  altostratus('Altostratus'),
  nimbostratus('Nimbostratus'),
  stratocumulus('Stratocumulus'),
  stratus('Stratus'),
  cumulus('Cumulus'),
  cumulonimbus('Cumulonimbus'),
  clearSky('Clear sky'),
  hazeOrFog('Haze or fog'),
  uncertain('Other or uncertain');

  const CloudGenus(this.label);

  final String label;
}

/// Formats a transparent, backend-compatible note using the existing imagery
/// description field until an ML-classification API contract exists.
String cloudObservationDescription({
  required CloudGenus genus,
  required String description,
}) {
  final observation = 'Cloud observation (user confirmed): ${genus.label}.';
  final trimmedDescription = description.trim();
  return trimmedDescription.isEmpty
      ? observation
      : '$observation $trimmedDescription';
}
