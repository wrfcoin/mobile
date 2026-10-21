import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../weather/data/weather_location_resolver.dart';
import '../../weather/domain/models/coarse_location.dart';
import '../data/bright_stars.dart';
import '../data/catalog_license.dart';
import '../data/sky_sensors.dart';
import '../domain/sky_astronomy.dart';
import '../domain/sky_horizon.dart';
import '../domain/sky_orientation.dart';

class SkyViewScreen extends ConsumerStatefulWidget {
  const SkyViewScreen({super.key});
  @override
  ConsumerState<SkyViewScreen> createState() => _SkyViewScreenState();
}

class _SkyViewScreenState extends ConsumerState<SkyViewScreen>
    with WidgetsBindingObserver {
  StreamSubscription<List<double>>? _gravitySub, _magneticSub;
  Timer? _timer;
  WeatherLocationRequest? _locationRequest;
  CoarseLocation? _cell;
  double? _declination;
  List<double>? _gravity, _magnetic;
  DateTime? _gravityAt, _magneticAt;
  bool _deviceLocation = false, _active = true, _locating = false;
  String? _error;
  int _generation = 0;
  DateTime _now() => ref.read(skyClockProvider)().toUtc();

  @override
  void initState() {
    super.initState();
    registerSkyCatalogLicense();
    WidgetsBinding.instance.addObserver(this);
    _startSensors();
  }

  void _startSensors() {
    final sensors = ref.read(skySensorsProvider);
    void failed(Object _) {
      if (mounted) {
        setState(() {
          _gravity = null;
          _magnetic = null;
        });
      }
    }

    try {
      _gravitySub = sensors.gravity.listen((v) {
        if (mounted && _active) {
          setState(() {
            _gravity = v;
            _gravityAt = _now();
          });
        }
      }, onError: failed);
      _magneticSub = sensors.magnetic.listen((v) {
        if (mounted && _active) {
          setState(() {
            _magnetic = v;
            _magneticAt = _now();
          });
        }
      }, onError: failed);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _active) setState(() {});
      });
    } catch (e) {
      failed(e);
    }
  }

  void _stop() {
    _generation++;
    _locationRequest?.cancel();
    _locationRequest = null;
    _gravitySub?.cancel();
    _gravitySub = null;
    _magneticSub?.cancel();
    _magneticSub = null;
    _timer?.cancel();
    _timer = null;
    _gravity = null;
    _magnetic = null;
    _locating = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_active) {
        _active = true;
        _startSensors();
      }
    } else {
      _active = false;
      _stop();
      // A device-derived cell needs a new explicit read/permission check.
      if (_deviceLocation) _cell = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _locate() async {
    final generation = ++_generation;
    _locationRequest?.cancel();
    setState(() {
      _cell = null;
      _error = null;
      _locating = true;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted || !_active || generation != _generation) return;
      final request = ref.read(weatherLocationResolverProvider).request();
      _locationRequest = request;
      final result = await request.result;
      if (!mounted || !_active || generation != _generation) return;
      setState(() {
        _cell = result.location;
        _deviceLocation = true;
        _error = result.location == null
            ? 'Location unavailable (${result.reason?.name}). Use a manual cell.'
            : null;
      });
    } catch (_) {
      if (mounted && _active && generation == _generation) {
        setState(() {
          _error = 'Location unavailable. Use a manual cell.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _locating = false;
        });
      }
    }
  }

  Future<void> _manual() async {
    var lat = _cell?.latitude.toStringAsFixed(1) ?? '';
    var lon = _cell?.longitude.toStringAsFixed(1) ?? '';
    var dec = _declination?.toString() ?? '';
    var invalid = false;
    final result = await showDialog<(CoarseLocation, double)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Offline sky settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Coordinates round to 0.1°. Magnetic declination is east-positive; '
                  'enter a known local correction, including 0 when appropriate.',
                ),
                for (final field in [
                  (lat, 'Latitude', (String v) => lat = v),
                  (lon, 'Longitude', (String v) => lon = v),
                  (dec, 'Magnetic declination (° east)', (String v) => dec = v),
                ])
                  TextFormField(
                    initialValue: field.$1,
                    onChanged: field.$3,
                    decoration: InputDecoration(labelText: field.$2),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                if (invalid)
                  const Text(
                    'Enter finite latitude ±90, longitude ±180 and declination ±180.',
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final a = double.tryParse(lat),
                    b = double.tryParse(lon),
                    c = double.tryParse(dec);
                if (a == null ||
                    b == null ||
                    c == null ||
                    !a.isFinite ||
                    !b.isFinite ||
                    !c.isFinite ||
                    a.abs() > 90 ||
                    b.abs() > 180 ||
                    c.abs() > 180) {
                  update(() => invalid = true);
                  return;
                }
                Navigator.pop(context, (CoarseLocation.round(a, b), c));
              },
              child: const Text('Use cell'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted && _active) {
      _generation++;
      _locationRequest?.cancel();
      setState(() {
        _cell = result.$1;
        _declination = result.$2;
        _deviceLocation = false;
        _error = null;
        _locating = false;
      });
    }
  }

  bool _fresh(DateTime? sample, DateTime now) =>
      sample != null &&
      !now.isBefore(sample) &&
      now.difference(sample) <= const Duration(seconds: 2);

  void _details(SkyObject object, Horizontal horizontal) {
    final events = nextHorizonEvents(object, _now(), _cell!);
    String time(DateTime? value) => value == null
        ? 'Not found in next 24h'
        : '${value.toIso8601String().substring(0, 16).replaceFirst('T', ' ')} UTC';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(object.name),
        content: Text(
          '${object.id} ${object.constellation}\n'
          'J2000 RA ${object.position.ra.toStringAsFixed(2)}°, Dec ${object.position.dec.toStringAsFixed(2)}°\n'
          'Azimuth ${horizontal.azimuth.toStringAsFixed(1)}°, altitude ${horizontal.altitude.toStringAsFixed(1)}°\n'
          'Geometric, approximate position; no atmospheric refraction.\n\n'
          'Approximate geometric rise/set — next 24h\n'
          '${events == null ? 'Unavailable: the full window exceeds 1800–2050.' : 'Rise: ${time(events.rise)}\nSet: ${time(events.set)}'}\n'
          'Object centre at a flat horizon; terrain and refraction change observed times. '
          'Brief grazing crossings may be missed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = _now();
    final orientation =
        _active &&
            _declination != null &&
            _gravity != null &&
            _magnetic != null &&
            _fresh(_gravityAt, now) &&
            _fresh(_magneticAt, now)
        ? skyOrientation(_gravity!, _magnetic!, _declination!)
        : null;
    final visible = <(SkyObject, Horizontal, double)>[];
    final epochSupported = now.year >= 1800 && now.year <= 2050;
    if (_cell != null && orientation != null && epochSupported) {
      for (final object in [...brightStars, ...solarSystem(now)]) {
        final horizontal = toHorizontal(
          precess(object.position, now),
          now,
          _cell!,
        );
        if (horizontal.altitude < 0) continue;
        final distance = angularDistance(
          Equatorial(horizontal.azimuth, horizontal.altitude),
          Equatorial(orientation.azimuth, orientation.altitude),
        );
        if (distance <= 15) visible.add((object, horizontal, distance));
      }
      visible.sort((a, b) => a.$3.compareTo(b.$3));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        title: const Text('Sky View'),
        actions: [
          IconButton(
            tooltip: 'Catalog licenses',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showLicensePage(context: context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Offline sky — not a camera preview'),
          const Text(
            'Bright-star subset (93 stars), Sun and seven planets. Approximate positions.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Point the rear of the phone at the sky. Hold in portrait. '
            'Calibrate with a figure-eight motion away from magnets. '
            'This view uses accelerometer/magnetometer fallback, not fused attitude.',
          ),
          TextButton(
            onPressed: _manual,
            child: const Text('Set offline sky settings'),
          ),
          TextButton(
            onPressed: _locating ? null : _locate,
            child: const Text('Use device location'),
          ),
          if (_cell != null)
            Text('Coarse cell: ${_cell!.pathSegment} (on device only)'),
          if (_declination == null)
            const Text('Set magnetic declination before identification.'),
          if (_locating) const Text('Obtaining coarse location…'),
          if (_error != null) Text(_error!),
          if (_cell == null)
            const Text('Choose a coarse location to identify objects.'),
          if (!epochSupported)
            const Text('Planet positions unavailable outside 1800–2050.'),
          if (orientation == null)
            const Text('Waiting for fresh calibrated motion sensors.'),
          if (orientation != null)
            Text(
              'True azimuth ${orientation.azimuth.toStringAsFixed(1)}°, '
              'altitude ${orientation.altitude.toStringAsFixed(1)}°',
            ),
          if (_cell != null &&
              orientation != null &&
              epochSupported &&
              visible.isEmpty)
            const Text(
              'No bundled object above the horizon within 15° of this direction.',
            ),
          for (final (object, horizontal, distance) in visible)
            ListTile(
              title: Text(object.name),
              subtitle: Text(
                '${distance.toStringAsFixed(1)}° from pointing; '
                'altitude ${horizontal.altitude.toStringAsFixed(1)}°',
              ),
              onTap: () => _details(object, horizontal),
            ),
        ],
      ),
    );
  }
}
