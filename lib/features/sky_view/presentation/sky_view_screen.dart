import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../weather/data/weather_location_resolver.dart';
import '../../weather/domain/models/coarse_location.dart';
import '../data/catalog_license.dart';
import '../data/sky_catalog.dart';
import '../data/sky_sensors.dart';
import '../domain/sky_accuracy.dart';
import '../domain/sky_astronomy.dart';
import '../domain/sky_attitude.dart';
import '../domain/sky_horizon.dart';
import '../domain/wmm.dart';
import 'sky_map_painter.dart';

const _alignAzimuthKey = 'sky_view.align_azimuth';
const _alignAltitudeKey = 'sky_view.align_altitude';
const _declinationKey = 'sky_view.declination_override';

/// A sensor silent for longer than this no longer describes where the phone is.
const _staleAfter = Duration(seconds: 4);

/// How long to wait for a first rotation-vector reading before using the
/// fallback. Covers a sensor that is listed but never reports.
const _firstSampleWait = Duration(seconds: 2);

/// Time constants for the attitude filter: the fused sensor needs very little,
/// the raw magnetometer path a lot more.
const _fusedTau = 0.08, _fallbackTau = 0.35;

/// Redraw limit, in microseconds between frames. About 30 fps, matching sensors.
const _minFrameMicros = 30000;

class SkyViewScreen extends ConsumerStatefulWidget {
  const SkyViewScreen({super.key});
  @override
  ConsumerState<SkyViewScreen> createState() => _SkyViewScreenState();
}

class _SkyViewScreenState extends ConsumerState<SkyViewScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // Sensors.
  StreamSubscription<RotationVectorSample>? _rotationSub;
  StreamSubscription<List<double>>? _gravitySub, _magneticSub;
  Timer? _firstSampleTimer, _clockTimer;
  bool _fallback = false, _active = true;
  List<double>? _gravity, _magnetic;
  DateTime? _lastSampleAt;
  Quat? _target;
  int _displayRotation = 0;
  bool _landscape = false;
  SkyAccuracy _accuracy = SkyAccuracy.unknown;
  bool _hideCalibrationPrompt = false;

  // Drawing.
  late final Ticker _ticker = createTicker(_onFrame);
  final _pose = ValueNotifier<SkyPose?>(null);
  final _labels = SkyLabelCache();
  AttitudeSmoother _smoother = AttitudeSmoother(tau: _fusedTau);
  Duration _lastFrame = Duration.zero;
  List<SkyFix> _fixes = const [];
  DateTime? _fixesAt;
  Size _mapSize = Size.zero;

  // Location.
  WeatherLocationRequest? _locationRequest;
  CoarseLocation? _cell;
  bool _wantDeviceLocation = true, _locating = false, _asking = false;
  LocationUnavailableReason? _locationProblem;
  int _generation = 0;

  // Calibration.
  double? _declinationOverride;
  SkyAlignment _alignment = SkyAlignment.none;
  bool _aligning = false;
  String? _notice;

  DateTime _now() => ref.read(skyClockProvider)().toUtc();

  bool get _epochSupported {
    final year = _now().year;
    return year >= 1800 && year <= 2050;
  }

  WmmField? get _wmm {
    final cell = _cell;
    if (cell == null) return null;
    return wmmField(cell.latitude, cell.longitude, wmmDecimalYear(_now()));
  }

  /// East-positive. Null only if the model has expired and nothing was entered:
  /// the map then runs on magnetic north and says so.
  double? get _declination => _declinationOverride ?? _wmm?.declination;

  @override
  void initState() {
    super.initState();
    registerSkyCatalogLicense();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadCalibration());
    _startSensors();
    _startClock();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askForLocation());
  }

  @override
  void dispose() {
    _generation++;
    _locationRequest?.cancel();
    _stopSensors();
    _clockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _pose.dispose();
    _labels.dispose();
    super.dispose();
  }

  // --- Lifecycle ---------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_active) return;
        _active = true;
        _startSensors();
        _startClock();
        // A device-derived cell needs a fresh read and permission check.
        if (_wantDeviceLocation && _cell == null) unawaited(_readLocation());
      case AppLifecycleState.inactive:
        // Keep going: Android's own permission dialog puts the app here, and so
        // does the notification shade. Neither hides the map for long.
        return;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (!_active) return;
        _active = false;
        _stopSensors();
        _clockTimer?.cancel();
        _generation++;
        _locationRequest?.cancel();
        _locationRequest = null;
        _locating = false;
        if (_wantDeviceLocation) {
          _cell = null;
          _fixes = const [];
        }
    }
    if (mounted) setState(() {});
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || !_active) return;
      final now = _now();
      final last = _lastSampleAt;
      if (last != null &&
          (now.isBefore(last) || now.difference(last) > _staleAfter)) {
        _clearAttitude();
      }
      _refreshFixes();
      setState(() {});
    });
  }

  // --- Sensors -----------------------------------------------------------

  void _startSensors() {
    final sensors = ref.read(skySensorsProvider);
    _firstSampleTimer = Timer(_firstSampleWait, _startFallback);
    try {
      _rotationSub = sensors.rotationVector.listen(
        _onRotationVector,
        onError: (Object _) => _startFallback(),
      );
    } catch (_) {
      _startFallback();
    }
  }

  void _stopSensors() {
    _firstSampleTimer?.cancel();
    _firstSampleTimer = null;
    _rotationSub?.cancel();
    _rotationSub = null;
    _stopFallback();
    _fallback = false; // Resume tries the fused sensor first again.
    _clearAttitude();
  }

  void _stopFallback() {
    _gravitySub?.cancel();
    _gravitySub = null;
    _magneticSub?.cancel();
    _magneticSub = null;
    _gravity = null;
    _magnetic = null;
  }

  void _clearAttitude() {
    _target = null;
    _lastSampleAt = null;
    _smoother = AttitudeSmoother(tau: _fallback ? _fallbackTau : _fusedTau);
    _accuracy = SkyAccuracy.unknown;
    _ticker.stop();
    _pose.value = null;
  }

  void _onRotationVector(RotationVectorSample sample) {
    if (!mounted || !_active) return;
    _firstSampleTimer?.cancel();
    _firstSampleTimer = null;
    final wasFallback = _fallback;
    if (wasFallback) {
      _fallback = false;
      _stopFallback();
      _smoother = AttitudeSmoother(tau: _fusedTau)..current = _smoother.current;
    }
    _displayRotation = sample.displayRotation;
    final accuracy = rotationVectorAccuracy(
      sample.status,
      sample.headingAccuracy,
    );
    final changed = accuracy != _accuracy || wasFallback || _target == null;
    _accuracy = accuracy;
    _accept(sample.attitude);
    if (changed) setState(() {});
  }

  void _startFallback() {
    _firstSampleTimer?.cancel();
    _firstSampleTimer = null;
    if (!mounted || !_active || _fallback) return;
    final sensors = ref.read(skySensorsProvider);
    void failed(Object _) {
      if (mounted) setState(_clearAttitude);
    }

    setState(() {
      _fallback = true;
      _smoother = AttitudeSmoother(tau: _fallbackTau)
        ..current = _smoother.current;
    });
    try {
      _gravitySub = sensors.gravity.listen((v) {
        _gravity = v;
        _onFallbackSample();
      }, onError: failed);
      _magneticSub = sensors.magnetic.listen((v) {
        _magnetic = v;
        _onFallbackSample();
      }, onError: failed);
    } catch (e) {
      failed(e);
    }
  }

  void _onFallbackSample() {
    final gravity = _gravity, magnetic = _magnetic;
    if (!mounted || !_active || gravity == null || magnetic == null) return;
    final attitude = magneticAttitudeFromVectors(gravity, magnetic);
    if (attitude == null) return; // The staleness timer handles a long gap.
    _displayRotation = inferDisplayRotation(
      landscape: _landscape,
      gravityX: gravity[0],
    );
    final accuracy = fallbackAccuracy(
      Vec3(magnetic[0], magnetic[1], magnetic[2]).length,
    );
    final changed = accuracy != _accuracy || _target == null;
    _accuracy = accuracy;
    _accept(attitude);
    if (changed) setState(() {});
  }

  void _accept(Quat attitude) {
    _target = attitude;
    _lastSampleAt = _now();
    _refreshFixes();
    final current = _smoother.current;
    final moved =
        current == null ||
        current.degreesTo(attitude) >= AttitudeSmoother.deadBandDegrees;
    // A resting phone asks for no frames at all, even though samples still come.
    if (moved && !_ticker.isActive) {
      _lastFrame = Duration.zero;
      _ticker.start();
    }
  }

  void _onFrame(Duration elapsed) {
    final target = _target;
    if (target == null) {
      _ticker.stop();
      return;
    }
    final micros = (elapsed - _lastFrame).inMicroseconds;
    if (_smoother.current != null && micros < _minFrameMicros) return;
    _lastFrame = elapsed;
    final seconds = micros.clamp(_minFrameMicros, 100000) / 1e6;
    if (_smoother.step(target, seconds) || _pose.value == null) {
      _publishPose();
    } else {
      // Settled inside the dead band: draw nothing until the next real move.
      _ticker.stop();
    }
  }

  SkyPose? _unalignedPose() {
    final attitude = _smoother.current;
    if (attitude == null) return null;
    return SkyPose.from(
      attitude,
      declination: _declination ?? 0,
      displayRotation: _displayRotation,
    );
  }

  void _publishPose() {
    final attitude = _smoother.current;
    if (attitude == null) return;
    _pose.value = SkyPose.from(
      attitude,
      declination: _declination ?? 0,
      alignment: _alignment,
      displayRotation: _displayRotation,
    );
  }

  void _refreshFixes() {
    final cell = _cell;
    if (cell == null || !_epochSupported) {
      if (_fixes.isNotEmpty) _fixes = const [];
      return;
    }
    final now = _now();
    final last = _fixesAt;
    if (_fixes.isNotEmpty &&
        last != null &&
        !now.isBefore(last) &&
        now.difference(last) < const Duration(seconds: 5)) {
      return;
    }
    _fixes = computeSky(now, cell);
    _fixesAt = now;
  }

  // --- Location ----------------------------------------------------------

  Future<void> _askForLocation() async {
    if (!mounted || _asking) return;
    _asking = true;
    try {
      var permission = await Geolocator.checkPermission();
      if (!mounted) return;
      if (permission == LocationPermission.denied) {
        final allowed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: const Text(
              'Sky View uses your rough location (about 11 km) to place the '
              'stars. It stays on this phone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Enter it myself'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (allowed != true) {
          setState(() {
            _locationProblem = LocationUnavailableReason.permissionDenied;
          });
          return;
        }
        permission = await Geolocator.requestPermission();
        if (!mounted) return;
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        setState(() {
          _locationProblem = permission == LocationPermission.denied
              ? LocationUnavailableReason.permissionDenied
              : LocationUnavailableReason.permissionBlocked;
        });
        return;
      }
      await _readLocation();
    } catch (_) {
      if (mounted) {
        setState(() {
          _locationProblem = LocationUnavailableReason.noFix;
        });
      }
    } finally {
      _asking = false;
    }
  }

  /// Reads only. Asking is [_askForLocation]'s job, once, with its reason shown.
  Future<void> _readLocation() async {
    if (!mounted || !_active || _locating) return;
    final generation = ++_generation;
    setState(() {
      _locating = true;
      _locationProblem = null;
    });
    final request = ref.read(weatherLocationResolverProvider).request();
    _locationRequest = request;
    final result = await request.result;
    if (!mounted || generation != _generation || !_active) return;
    setState(() {
      _locating = false;
      _locationProblem = result.reason;
      final location = result.location;
      if (location != null) _useCell(location);
    });
  }

  void _useCell(CoarseLocation cell) {
    _cell = cell;
    _fixes = const [];
    _fixesAt = null;
    _refreshFixes();
    _publishPose();
  }

  // --- Calibration -------------------------------------------------------

  Future<void> _loadCalibration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final azimuth = prefs.getDouble(_alignAzimuthKey);
      final altitude = prefs.getDouble(_alignAltitudeKey);
      setState(() {
        _declinationOverride = prefs.getDouble(_declinationKey);
        if (azimuth != null && altitude != null) {
          _alignment = SkyAlignment(azimuth, altitude);
        }
        _publishPose();
      });
    } catch (_) {
      // No store on this platform: calibration lasts for this session only.
    }
  }

  Future<void> _saveCalibration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final override = _declinationOverride;
      if (override == null) {
        await prefs.remove(_declinationKey);
      } else {
        await prefs.setDouble(_declinationKey, override);
      }
      if (_alignment.isSet) {
        await prefs.setDouble(_alignAzimuthKey, _alignment.azimuth);
        await prefs.setDouble(_alignAltitudeKey, _alignment.altitude);
      } else {
        await prefs.remove(_alignAzimuthKey);
        await prefs.remove(_alignAltitudeKey);
      }
    } catch (_) {
      // Same as above: kept in memory only.
    }
  }

  void _alignOn(SkyFix fix) {
    final pose = _unalignedPose();
    final solved = pose == null
        ? null
        : SkyAlignment.solve(pose, fix.horizontal);
    setState(() {
      if (solved == null) {
        _notice =
            '${fix.object.name} is too far from where the phone points, or '
            'too high to align on. Aim at it and try again.';
        return;
      }
      _alignment = solved;
      _aligning = false;
      _notice =
          'Aligned on ${fix.object.name}: '
          '${solved.azimuth.toStringAsFixed(1)}° across, '
          '${solved.altitude.toStringAsFixed(1)}° up.';
      _publishPose();
    });
    unawaited(_saveCalibration());
  }

  void _resetAlignment() {
    setState(() {
      _alignment = SkyAlignment.none;
      _aligning = false;
      _notice = 'Alignment reset.';
      _publishPose();
    });
    unawaited(_saveCalibration());
  }

  // --- Interaction -------------------------------------------------------

  void _select(SkyFix fix) {
    if (_aligning) {
      _alignOn(fix);
    } else {
      _details(fix);
    }
  }

  void _onTapMap(TapUpDetails details) {
    final pose = _pose.value;
    if (pose == null) return;
    final fix = skyObjectAt(details.localPosition, _fixes, pose, _mapSize);
    if (fix != null) _select(fix);
  }

  void _details(SkyFix fix) {
    final object = fix.object;
    final horizontal = fix.horizontal;
    final events = nextHorizonEvents(object, _now(), _cell!);
    String time(DateTime? value) => value == null
        ? 'Not found in next 24h'
        : '${value.toIso8601String().substring(0, 16).replaceFirst('T', ' ')} UTC';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(object.name),
        content: SingleChildScrollView(
          child: Text(
            '${object.id} ${object.constellation}\n'
            'J2000 RA ${object.position.ra.toStringAsFixed(2)}°, Dec ${object.position.dec.toStringAsFixed(2)}°\n'
            'Azimuth ${horizontal.azimuth.toStringAsFixed(1)}°, altitude ${horizontal.altitude.toStringAsFixed(1)}°\n'
            'Geometric, approximate position; no atmospheric refraction.\n\n'
            'Approximate geometric rise/set — next 24h\n'
            '${events == null ? 'Unavailable: the full window exceeds 1800–2050.' : 'Rise: ${time(events.rise)}\nSet: ${time(events.set)}'}\n'
            'Object centre at a flat horizon; terrain and refraction change observed times. '
            'Brief grazing crossings may be missed.',
          ),
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

  Future<void> _settings() async {
    var lat = _cell?.latitude.toStringAsFixed(1) ?? '';
    var lon = _cell?.longitude.toStringAsFixed(1) ?? '';
    var dec = _declinationOverride?.toString() ?? '';
    var invalid = false;
    final auto = _wmm;
    final result = await showDialog<(CoarseLocation, double?)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Location and compass'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Coordinates round to 0.1° and stay on this phone.'),
                for (final field in [
                  (lat, 'Latitude', (String v) => lat = v),
                  (lon, 'Longitude', (String v) => lon = v),
                  (
                    dec,
                    'Declination override (° east, optional)',
                    (String v) => dec = v,
                  ),
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
                const SizedBox(height: 8),
                Text(
                  auto == null
                      ? 'Leave the override blank to compute declination '
                            'automatically once the location is set.'
                      : 'Leave the override blank to use '
                            '${_describeDeclination(auto.declination)}, '
                            'computed here from WMM2025.',
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
                final a = double.tryParse(lat), b = double.tryParse(lon);
                final blank = dec.trim().isEmpty;
                final c = blank ? null : double.tryParse(dec);
                if (a == null ||
                    b == null ||
                    (!blank && c == null) ||
                    !a.isFinite ||
                    !b.isFinite ||
                    a.abs() > 90 ||
                    b.abs() > 180 ||
                    (c != null && (!c.isFinite || c.abs() > 180))) {
                  update(() => invalid = true);
                  return;
                }
                Navigator.pop(context, (CoarseLocation.round(a, b), c));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    final (cell, override) = result;
    setState(() {
      _declinationOverride = override;
      if (cell != _cell) {
        // Typed by hand: stop any device read that could overwrite it.
        _generation++;
        _locationRequest?.cancel();
        _locating = false;
        _wantDeviceLocation = false;
        _locationProblem = null;
        _useCell(cell);
      } else {
        _publishPose();
      }
    });
    unawaited(_saveCalibration());
  }

  void _about() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About this map'),
        content: const SingleChildScrollView(
          child: Text(
            'Drawn from calculation, offline. It uses no camera and no network.\n\n'
            'Shows the 93 brightest catalog stars, the Sun, the Moon and seven '
            'planets. Positions are approximate and geometric: atmospheric '
            'refraction is not included, so objects near the horizon look a '
            'little higher in the real sky.\n\n'
            'Compass error of several degrees is normal on a phone. "Align on a '
            'star" corrects it.\n\n'
            'Your location is rounded to about 11 km and never leaves this phone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => showLicensePage(context: context),
            child: const Text('Catalog licenses'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // --- Display -----------------------------------------------------------

  static String _describeDeclination(double degrees) =>
      '${degrees.abs().toStringAsFixed(1)}° ${degrees < 0 ? 'west' : 'east'}';

  static const _compass = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

  static String _describePointing(Horizontal at) {
    if (at.altitude > 85) return 'Pointing straight up';
    if (at.altitude < -85) return 'Pointing straight down';
    final name = _compass[((at.azimuth + 22.5) % 360 ~/ 45) % 8];
    final height = at.altitude >= 0
        ? '${at.altitude.round()}° up'
        : '${(-at.altitude).round()}° below the horizon';
    return 'Facing $name (${at.azimuth.round()}°), $height';
  }

  /// Objects in or near the reticle, nearest first.
  List<(SkyFix, double)> _nearReticle(SkyPose pose) {
    final at = pose.boresight;
    final near = <(SkyFix, double)>[];
    for (final fix in _fixes) {
      if (fix.horizontal.altitude < 0) continue;
      final distance = angularDistance(
        Equatorial(fix.horizontal.azimuth, fix.horizontal.altitude),
        Equatorial(at.azimuth, at.altitude),
      );
      if (distance <= 15) near.add((fix, distance));
    }
    near.sort((a, b) => a.$2.compareTo(b.$2));
    return near.take(4).toList();
  }

  String? get _locationMessage {
    if (_cell != null) return null;
    if (_locating) return 'Finding your rough location…';
    return switch (_locationProblem) {
      LocationUnavailableReason.permissionBlocked => 'Location is turned off for this app. Enter your location to place the stars.',
      LocationUnavailableReason.servicesOff => 'Location is off on this phone. Enter your location to place the stars.',
      LocationUnavailableReason.noFix =>
        'Could not get a location. Enter yours to place the stars.',
      LocationUnavailableReason.permissionDenied =>
        'Enter your location to place the stars.',
      null => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    _landscape = size.width > size.height;
    _labels.fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final pose = _pose.value;
    final near = pose == null ? const <(SkyFix, double)>[] : _nearReticle(pose);
    return Scaffold(
      backgroundColor: skyBackground,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Sky View'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'Location and compass',
            icon: const Icon(Icons.tune),
            onPressed: _settings,
          ),
          IconButton(
            tooltip: 'About this map',
            icon: const Icon(Icons.info_outline),
            onPressed: _about,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              _mapSize = constraints.biggest;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTapMap,
                child: Semantics(
                  label: 'Sky map',
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: SkyMapPainter(
                      pose: _pose,
                      fixes: _fixes,
                      aligning: _aligning,
                      labels: _labels,
                    ),
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _panel(pose, near),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(SkyPose? pose, List<(SkyFix, double)> near) {
    const dim = TextStyle(color: Color(0xFFB9C7DE), fontSize: 12);
    const bright = TextStyle(color: Colors.white, fontSize: 14);
    final locationMessage = _locationMessage;
    final declination = _declination;
    final wmm = _wmm;
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xD9101A2C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (locationMessage != null) ...[
            Text(locationMessage, style: bright),
            if (!_locating)
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _settings,
                    child: const Text('Enter location'),
                  ),
                  if (_locationProblem !=
                      LocationUnavailableReason.permissionBlocked)
                    TextButton(
                      onPressed: _askForLocation,
                      child: const Text('Use my location'),
                    )
                  else
                    TextButton(
                      onPressed: Geolocator.openAppSettings,
                      child: const Text('Open settings'),
                    ),
                ],
              ),
          ],
          if (!_epochSupported)
            const Text(
              'Positions unavailable outside 1800–2050.',
              style: bright,
            ),
          if (_notice case final notice?)
            Row(
              children: [
                Expanded(child: Text(notice, style: bright)),
                IconButton(
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: Colors.white70,
                  ),
                  onPressed: () => setState(() => _notice = null),
                ),
              ],
            ),
          if (_aligning)
            const Text(
              'Aim the back of the phone at a star you can see, so it would sit '
              'behind the ring. Then tap that star on the map.',
              style: bright,
            ),
          if (_fallback && pose != null)
            const Text(
              'This phone has no fused motion sensor, so the map is less steady.',
              style: dim,
            ),
          if (_accuracy.low && !_hideCalibrationPrompt && pose != null)
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Compass needs calibrating: move the phone in a figure-eight, away from metal.',
                    style: bright,
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _hideCalibrationPrompt = true),
                  child: const Text('Hide'),
                ),
              ],
            ),
          if (wmm != null &&
              wmm.compassUnreliable &&
              _declinationOverride == null)
            const Text(
              'Close to a magnetic pole, a phone compass is unreliable.',
              style: dim,
            ),
          if (pose == null && locationMessage == null && _epochSupported)
            const Text('Waiting for the motion sensors…', style: bright),
          if (pose != null) ...[
            Text(_describePointing(pose.boresight), style: bright),
            Text(
              'Compass: ${_accuracy.label.toLowerCase()} · '
              '${declination == null ? 'magnetic north, uncorrected' : 'true north'}'
              '${_alignment.isSet ? ' · aligned' : ''}',
              style: dim,
            ),
          ],
          if (near.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (fix, _) in near)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(fix.object.name),
                        onPressed: () => _select(fix),
                      ),
                    ),
                ],
              ),
            ),
          if (pose != null && _fixes.isNotEmpty && near.isEmpty)
            const Text('Nothing bright near the ring.', style: dim),
          if (pose != null && _fixes.isNotEmpty)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _aligning = !_aligning;
                    _notice = null;
                  }),
                  child: Text(_aligning ? 'Cancel align' : 'Align on a star'),
                ),
                if (_alignment.isSet)
                  TextButton(
                    onPressed: _resetAlignment,
                    child: const Text('Reset alignment'),
                  ),
                const Text('Approximate, no refraction', style: dim),
              ],
            ),
        ],
      ),
    );
  }
}
