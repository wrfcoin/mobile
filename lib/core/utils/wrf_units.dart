/// Exact conversion between display WRF and integer base units.
///
/// 1 WRF = 10^8 base units. This matches core4 `WRF_UNITS_PER_COIN`
/// (`shared-protocol/src/common/constants.rs`) and backend
/// `shared/currency.ts` (`WRF_DECIMALS = 8`). The wallet wire contract is
/// integer base units (backend #1197 for `POST /send`).
///
/// Every conversion here is string and [BigInt] arithmetic. Amounts never pass
/// through `double`.
library;

/// Number of fractional WRF digits represented by base units.
const int wrfDecimals = 8;

/// Base units in one WRF (10^8).
final BigInt wrfBaseUnitsPerCoin = BigInt.from(10).pow(wrfDecimals);

/// Largest amount the backend accepts: `Number.MAX_SAFE_INTEGER` (2^53 - 1).
final BigInt maxJsonSafeBaseUnits = BigInt.two.pow(53) - BigInt.one;

final RegExp _displayWrf = RegExp(r'^(\d+)(?:[.,](\d*))?$');
final RegExp _ambiguousCommaWrf = RegExp(r'^\d+,\d{3}$');
final RegExp _baseUnitsInteger = RegExp(r'^\d+$');

/// A three-digit comma fraction could instead be a thousands grouping.
/// Callers can explain the refusal without guessing which amount was intended.
bool wrfDisplayIsAmbiguous(String display) =>
    _ambiguousCommaWrf.hasMatch(display.trim());

/// Converts a display WRF amount such as `"1.5"` to a base-unit integer
/// string such as `"150000000"`.
///
/// A single dot or comma is a decimal separator, never a grouping separator.
/// Mixed or repeated separators are rejected.
/// Exactly three digits after a comma are ambiguous and refused; use a dot.
///
/// Returns `null` instead of rounding when the input is not a plain decimal,
/// has more than [wrfDecimals] fractional digits, is zero, or exceeds
/// [maxJsonSafeBaseUnits]. The backend would reject all of these.
String? wrfDisplayToBaseUnits(String display) {
  if (wrfDisplayIsAmbiguous(display)) return null;
  final match = _displayWrf.firstMatch(display.trim());
  if (match == null) return null;
  final whole = match.group(1)!;
  final fraction = match.group(2) ?? '';
  if (fraction.length > wrfDecimals) return null;

  final units =
      BigInt.parse(whole) * wrfBaseUnitsPerCoin +
      BigInt.parse(fraction.padRight(wrfDecimals, '0'));
  if (units <= BigInt.zero || units > maxJsonSafeBaseUnits) return null;
  return units.toString();
}

/// Formats a base-unit integer string as display WRF, for example
/// `"150000"` becomes `"0.0015"`. Trailing fractional zeros are dropped.
///
/// Returns `null` when [baseUnits] is not a non-negative integer string.
String? wrfBaseUnitsToDisplay(String baseUnits) {
  final raw = baseUnits.trim();
  if (!_baseUnitsInteger.hasMatch(raw)) return null;
  final units = BigInt.parse(raw);
  final whole = units ~/ wrfBaseUnitsPerCoin;
  final fraction = (units % wrfBaseUnitsPerCoin)
      .toString()
      .padLeft(wrfDecimals, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole.$fraction';
}
