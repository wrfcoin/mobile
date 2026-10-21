import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/core/utils/wrf_units.dart';

void main() {
  group('wrfDisplayToBaseUnits', () {
    test('uses 10^8 base units per WRF (core4 WRF_UNITS_PER_COIN)', () {
      expect(wrfBaseUnitsPerCoin, BigInt.from(100000000));
      expect(wrfDisplayToBaseUnits('1'), '100000000');
      expect(wrfDisplayToBaseUnits('250'), '25000000000');
      expect(wrfDisplayToBaseUnits('1.5'), '150000000');
      expect(wrfDisplayToBaseUnits('0.00000001'), '1');
      expect(wrfDisplayToBaseUnits(' 2. '), '200000000');
    });

    test('is exact where binary floating point is not', () {
      // 0.29 * 1e8 == 28999999.999999996 in IEEE-754 doubles.
      expect(wrfDisplayToBaseUnits('0.29'), '29000000');
      expect(wrfDisplayToBaseUnits('1.1'), '110000000');
      expect(wrfDisplayToBaseUnits('90071992.54740991'), '9007199254740991');
    });

    test('accepts one comma decimal separator exactly like a dot', () {
      expect(wrfDisplayToBaseUnits('1,25'), '125000000');
      expect(wrfDisplayToBaseUnits('1,25'), wrfDisplayToBaseUnits('1.25'));
      expect(wrfDisplayToBaseUnits('0,5'), '50000000');
      expect(wrfDisplayToBaseUnits('1,5'), '150000000');
      expect(wrfDisplayToBaseUnits('0,00000001'), '1');
      expect(wrfDisplayToBaseUnits('90071992,54740991'), '9007199254740991');
    });

    test('refuses ambiguous three-digit comma fractions', () {
      for (final ambiguous in [
        '1,000',
        '10,000',
        '10,500',
        '0,125',
        ' 1,000 ',
      ]) {
        expect(wrfDisplayToBaseUnits(ambiguous), isNull, reason: ambiguous);
      }
    });

    test('dot forms and unambiguous comma precision remain accepted', () {
      expect(wrfDisplayToBaseUnits('1.000'), '100000000');
      expect(wrfDisplayToBaseUnits('0.125'), '12500000');
      expect(wrfDisplayToBaseUnits('1,2500'), '125000000');
      for (final fraction in [
        '2',
        '25',
        '2500',
        '25000',
        '250000',
        '2500000',
        '25000000',
      ]) {
        expect(
          wrfDisplayToBaseUnits('1,$fraction'),
          wrfDisplayToBaseUnits('1.$fraction'),
        );
      }
    });

    test('comma edge forms follow the existing dot rules', () {
      expect(wrfDisplayToBaseUnits('1,'), '100000000');
      expect(wrfDisplayToBaseUnits('1,'), wrfDisplayToBaseUnits('1.'));
      expect(wrfDisplayToBaseUnits(' 2, '), '200000000');
      expect(wrfDisplayToBaseUnits(',5'), isNull);
      expect(wrfDisplayToBaseUnits(',5'), wrfDisplayToBaseUnits('.5'));
    });

    test('rejects mixed or repeated separators and grouping forms', () {
      for (final bad in [
        '1,2,3',
        '1.000,5',
        '1,000.5',
        '1,250.5',
        '1.250,5',
        '1,250,000',
        '1..25',
        '1,,25',
        '1.,',
      ]) {
        expect(wrfDisplayToBaseUnits(bad), isNull, reason: bad);
      }
    });

    test(
      'comma amounts keep precision, positivity and safe-integer limits',
      () {
        for (final bad in [
          '0,0',
          '0,',
          '-1,25',
          '1,000000001',
          '90071992,54740992',
        ]) {
          expect(wrfDisplayToBaseUnits(bad), isNull, reason: bad);
        }
      },
    );

    test('rejects rather than rounds values the backend refuses', () {
      for (final bad in [
        '',
        '0',
        '0.0',
        '-1',
        '1e3',
        '.5',
        '1.000000001',
        'abc',
        '90071992.54740992',
      ]) {
        expect(wrfDisplayToBaseUnits(bad), isNull, reason: bad);
      }
    });
  });

  group('wrfBaseUnitsToDisplay', () {
    test('formats integer base units as WRF with exact string math', () {
      expect(wrfBaseUnitsToDisplay('25000000'), '0.25');
      expect(wrfBaseUnitsToDisplay('150000'), '0.0015');
      expect(wrfBaseUnitsToDisplay('1'), '0.00000001');
      expect(wrfBaseUnitsToDisplay('0'), '0');
      expect(wrfBaseUnitsToDisplay('100000000'), '1');
      expect(wrfBaseUnitsToDisplay('9007199254740991'), '90071992.54740991');
    });

    test('rejects non-integer strings', () {
      for (final bad in ['', '0.25', '-1', '1e8', 'abc']) {
        expect(wrfBaseUnitsToDisplay(bad), isNull, reason: bad);
      }
    });

    test('round-trips display amounts', () {
      for (final wrf in ['1', '0.25', '1.5', '0.00000001', '12345.6789']) {
        expect(wrfBaseUnitsToDisplay(wrfDisplayToBaseUnits(wrf)!), wrf);
      }
    });
  });
}
