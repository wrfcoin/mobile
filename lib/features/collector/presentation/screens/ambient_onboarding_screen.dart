import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/feature_flags/feature_flags.dart';
import '../../../wallet/presentation/providers/wallet_provider.dart';
import '../../data/repositories/ambient_onboarding_repository.dart';

class AmbientOnboardingScreen extends ConsumerStatefulWidget {
  const AmbientOnboardingScreen({super.key});
  @override
  ConsumerState<AmbientOnboardingScreen> createState() =>
      _AmbientOnboardingState();
}

class _AmbientOnboardingState extends ConsumerState<AmbientOnboardingScreen>
    with WidgetsBindingObserver {
  final _apiKey = TextEditingController();
  final _appKey = TextEditingController();
  final _name = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  VerifiedAmbientAccount? _account;
  AmbientDevice? _device;
  CancelToken? _cancel;
  int _generation = 0;
  bool _active = true;
  bool _busy = false;
  bool _received = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _invalidate({bool clearKeys = false}) {
    _generation++;
    _cancel?.cancel('Onboarding context changed');
    _cancel = null;
    _account = null;
    _device = null;
    _busy = false;
    _received = false;
    _message = null;
    if (clearKeys) {
      _apiKey.clear();
      _appKey.clear();
    }
  }

  void _reset() => setState(() => _invalidate(clearKeys: true));

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) _reset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _invalidate(clearKeys: true);
    for (final controller in [_apiKey, _appKey, _name, _latitude, _longitude]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _run({required bool register}) async {
    final owner = ref.read(walletProvider).asData?.value?.address;
    if (_busy ||
        !_active ||
        !ref.read(featureFlagsProvider).enablePwsAutoDiscovery ||
        owner == null) {
      return;
    }
    if (!register) _invalidate();
    final generation = ++_generation;
    final cancel = _cancel = CancelToken();
    setState(() {
      _busy = true;
      _message = null;
      _received = false;
    });
    bool current() =>
        mounted &&
        _active &&
        generation == _generation &&
        ref.read(featureFlagsProvider).enablePwsAutoDiscovery &&
        ref.read(walletProvider).asData?.value?.address == owner;
    try {
      final repo = ref.read(ambientOnboardingRepositoryProvider);
      if (register) {
        final account = _account;
        final device = _device;
        final lat = double.tryParse(_latitude.text.trim());
        final lon = double.tryParse(_longitude.text.trim());
        if (account == null || device == null || lat == null || lon == null) {
          throw const AmbientOnboardingProblem(
            'Select an account device and enter a valid station location.',
          );
        }
        await repo.register(
          account: account,
          device: device,
          name: _name.text,
          latitude: lat,
          longitude: lon,
          cancel: cancel,
        );
        if (!current()) return;
        setState(() {
          _invalidate(clearKeys: true);
          _received = true;
        });
      } else {
        final account = await repo.verify(
          apiKey: _apiKey.text,
          appKey: _appKey.text,
          cancel: cancel,
        );
        if (!current()) return;
        setState(() {
          _account = account;
          _device = null;
        });
      }
    } on AmbientOnboardingProblem catch (error) {
      if (current()) setState(() => _message = error.message);
    } catch (_) {
      if (current()) {
        setState(
          () => _message = 'Could not complete station onboarding. Try again.',
        );
      }
    } finally {
      if (current()) {
        setState(() {
          _busy = false;
          _cancel = null;
        });
      }
    }
  }

  Widget _field(
    TextEditingController controller,
    String id,
    String label, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: ValueKey(id),
      controller: controller,
      enabled: !_busy,
      decoration: InputDecoration(labelText: label),
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      autofillHints: const [],
      onChanged: secret ? (_) => setState(() => _invalidate()) : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(featureFlagsProvider).enablePwsAutoDiscovery;
    final wallet = ref.watch(walletProvider);
    ref.listen(featureFlagsProvider, (previous, next) {
      if (!next.enablePwsAutoDiscovery) _reset();
    });
    ref.listen(walletProvider, (previous, next) {
      if (previous?.asData?.value?.address != next.asData?.value?.address) {
        _reset();
      }
    });
    return Scaffold(
      appBar: AppBar(title: const Text('Connect Ambient station')),
      body: !enabled
          ? const Center(child: Text('Ambient onboarding is disabled.'))
          : wallet.asData?.value == null
          ? const Center(
              child: Text('Sign in from Wallet before connecting a station.'),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Ambient account', style: TextStyle(fontSize: 20)),
                const Text(
                  'Connect a station already on your AmbientWeather.net account. This uses the internet; it does not scan Wi-Fi or Bluetooth.',
                ),
                const SizedBox(height: 12),
                _field(
                  _apiKey,
                  'ambient-api-key',
                  'Ambient API key',
                  secret: true,
                ),
                _field(
                  _appKey,
                  'ambient-app-key',
                  'Ambient application key',
                  secret: true,
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _run(register: false),
                  child: const Text('Find account stations'),
                ),
                if (_account != null) ...[
                  if (_account!.devices.isEmpty)
                    const Text('No Ambient devices were returned.')
                  else
                    DropdownButton<AmbientDevice>(
                      value: _device,
                      isExpanded: true,
                      hint: const Text('Select your account station'),
                      items: _account!.devices
                          .map(
                            (device) => DropdownMenuItem(
                              value: device,
                              child: Text(device.label),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (device) => setState(() => _device = device),
                    ),
                  _field(_name, 'ambient-station-name', 'Station name'),
                  const Text(
                    'Enter the station location. Only a 0.1° cell is sent.',
                  ),
                  _field(_latitude, 'ambient-latitude', 'Latitude'),
                  _field(_longitude, 'ambient-longitude', 'Longitude'),
                  FilledButton(
                    onPressed: _busy || _device == null
                        ? null
                        : () => _run(register: true),
                    child: const Text('Register selected station'),
                  ),
                ],
                if (_busy) const LinearProgressIndicator(),
                if (_message != null)
                  Text(_message!, key: const ValueKey('ambient-error')),
                if (_received)
                  const Text(
                    'Registration received. Chain activation and rewards are not confirmed.',
                    key: ValueKey('ambient-received'),
                  ),
                const Text(
                  'Keys are sent to the station service. This app does not save them. Registration checks that the device belongs to this Ambient account.',
                ),
              ],
            ),
    );
  }
}
