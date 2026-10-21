import '../utils/wrf_units.dart';

/// Reads an amount whose denomination and scale are not established.
/// Preserves decimal precision and never applies a monetary conversion.
String? reportedAmount(dynamic value) {
  if (value == null || (value is num && !value.isFinite)) return null;
  if (value is! String && value is! num) return null;
  final raw = value.toString().trim();
  if (!RegExp(r'^-?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d+)?(?:[eE][+-]?\d+)?$')
      .hasMatch(raw)) {
    return null;
  }
  return raw.replaceAll(',', '');
}

/// Formats only an available field whose response declares the WRF contract.
/// Unknown/missing metadata and encodings never establish a monetary amount.
String? declaredWrfAmount(Object? value, Object? amountUnits, String field) {
  if (value is! String || amountUnits is! Map) return null;
  final fields = amountUnits['fields'];
  if (amountUnits['available'] != true ||
      amountUnits['denomination'] != 'WRF' ||
      amountUnits['baseUnitDecimals'] is! int ||
      amountUnits['baseUnitDecimals'] != wrfDecimals ||
      amountUnits['baseUnitsPerUnit'] != wrfBaseUnitsPerCoin.toString() ||
      fields is! Map) {
    return null;
  }
  final raw = value.trim();
  final String? display;
  switch (fields[field]) {
    case 'base_units':
      display = wrfBaseUnitsToDisplay(raw);
    case 'display_units':
      display = RegExp(r'^\d+(?:\.\d{1,8})?$').hasMatch(raw) ? raw : null;
    default:
      return null;
  }
  return display == null ? null : '$display WRF';
}
