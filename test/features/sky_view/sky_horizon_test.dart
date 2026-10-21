import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_astronomy.dart';
import 'package:wrfcoin_mobile/features/sky_view/domain/sky_horizon.dart';
import 'package:wrfcoin_mobile/features/weather/domain/models/coarse_location.dart';

void main() {
  final epoch = DateTime.utc(2000, 1, 1, 12);
  // Published J2000 GMST, independent of the implementation's sidereal call.
  const equatorStar = SkyObject(
    'test-star',
    'test-star',
    '',
    Equatorial(280.46061837, 0),
    1,
  );
  final equator = CoarseLocation.round(0, 0);
  const siderealSeconds = 86164.0905;

  test('equator star sets after quarter sidereal day and rises after three quarters', () {
    final events = nextHorizonEvents(equatorStar, epoch, equator)!;
    expect(
      events.set!.difference(epoch).inMilliseconds / 1000,
      closeTo(siderealSeconds / 4, 2),
    );
    expect(
      events.rise!.difference(epoch).inMilliseconds / 1000,
      closeTo(siderealSeconds * 3 / 4, 2),
    );
    expect(
      events.rise!.day,
      2,
    ); // Includes next UTC date, not today's past rise.
    expect(events.rise!.isUtc, isTrue);
  });

  test('east longitude advances both events by one sidereal hour', () {
    final west = nextHorizonEvents(equatorStar, epoch, equator)!;
    final east = nextHorizonEvents(
      equatorStar,
      epoch,
      CoarseLocation.round(0, 15),
    )!;
    for (final pair in [(west.rise!, east.rise!), (west.set!, east.set!)]) {
      expect(
        pair.$1.difference(pair.$2).inMilliseconds / 1000,
        closeTo(siderealSeconds / 24, 2),
      );
    }
  });

  test('circumpolar and never-visible stars report no event rather than default times', () {
    for (final dec in [45.0, -45.0]) {
      final star = SkyObject('test-star', '', '', Equatorial(0, dec), 1);
      final events = nextHorizonEvents(
        star,
        epoch,
        CoarseLocation.round(85, 0),
      )!;
      expect(events.rise, isNull);
      expect(events.set, isNull);
    }
  });

  test('moving Sun crosses using recomputed ephemeris rather than captured coordinates', () {
    final sun = solarSystem(epoch).singleWhere((body) => body.id == 'Sun');
    final events = nextHorizonEvents(sun, epoch, equator)!;
    double height(DateTime time) => toHorizontal(
      precess(
        solarSystem(time).singleWhere((body) => body.id == 'Sun').position,
        time,
      ),
      time,
      equator,
    ).altitude;
    for (final pair in [(events.rise!, true), (events.set!, false)]) {
      final before = height(pair.$1.subtract(const Duration(seconds: 20)));
      final after = height(pair.$1.add(const Duration(seconds: 20)));
      expect(before < 0, pair.$2);
      expect(after > 0, pair.$2);
      expect(pair.$1.isBefore(epoch), isFalse);
      expect(pair.$1.isBefore(epoch.add(const Duration(hours: 24))), isTrue);
    }
  });

  test('identical coarse cells produce identical times and local-zone input preserves UTC', () {
    final a = nextHorizonEvents(
      equatorStar,
      epoch,
      CoarseLocation.round(12.341, 23.441),
    )!;
    final b = nextHorizonEvents(
      equatorStar,
      epoch.toLocal(),
      CoarseLocation.round(12.349, 23.449),
    )!;
    expect(a.rise, b.rise);
    expect(a.set, b.set);
  });

  test('whole-day window outside the supported range is unavailable', () {
    for (final time in [
      DateTime.utc(1799, 12, 31),
      DateTime.utc(2050, 12, 31, 12),
    ]) {
      expect(nextHorizonEvents(equatorStar, time, equator), isNull);
    }
    expect(
      nextHorizonEvents(equatorStar, DateTime.utc(1800), equator),
      isNotNull,
    );
  });

  test('invalid position or cell never yields plausible events', () {
    for (final point in [
      const Equatorial(double.nan, 0),
      const Equatorial(0, 91),
    ]) {
      expect(
        () => nextHorizonEvents(
          SkyObject('test-star', '', '', point, 1),
          epoch,
          equator,
        ),
        throwsRangeError,
      );
    }
    expect(
      () => nextHorizonEvents(equatorStar, epoch, CoarseLocation.round(91, 0)),
      throwsRangeError,
    );
  });
}
