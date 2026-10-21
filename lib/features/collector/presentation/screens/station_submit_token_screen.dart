import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/security/screen_security_service.dart';
import '../../data/services/station_submit_token_store.dart';

class StationSubmitTokenScreen extends ConsumerStatefulWidget {
  const StationSubmitTokenScreen({required this.stationId, super.key});
  final String stationId;

  @override
  ConsumerState<StationSubmitTokenScreen> createState() => _State();
}

class _State extends ConsumerState<StationSubmitTokenScreen> {
  final _packet = TextEditingController();
  late final ScreenSecurityService _screen;
  bool _working = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _screen = ref.read(screenSecurityServiceProvider);
    _screen.enableProtection();
  }

  @override
  void dispose() {
    _packet.clear();
    _packet.dispose();
    _screen.disableProtection();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    if (_working) return;
    setState(() {
      _working = true;
      _status = null;
    });
    try {
      final store = ref.read(stationSubmitTokenStoreProvider);
      if (remove) {
        await store.remove(widget.stationId);
      } else {
        await store.importPacket(widget.stationId, _packet.text);
      }
      _packet.clear();
      if (mounted) {
        setState(
          () => _status = remove ? 'Credential removed from this device.' : 'Credential saved securely on this device. Server matching is not verified.',
        );
      }
    } catch (_) {
      _packet.clear();
      if (mounted) {
        setState(
          () => _status = 'Credential could not be saved. Check the station-bound packet and native secure storage.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Station submit credential')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Import the private station credential packet supplied by your operator. '
          'It must belong to this phone station. This does not change your wallet or signed collector uploads.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _packet,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [],
          maxLength: 512,
          enabled: !_working,
          decoration: const InputDecoration(
            labelText: 'Private station packet',
          ),
        ),
        FilledButton(
          onPressed: _working ? null : () => _save(),
          child: const Text('Save credential'),
        ),
        OutlinedButton(
          onPressed: _working ? null : () => _save(remove: true),
          child: const Text('Remove credential'),
        ),
        if (_status != null) Text(_status!),
      ],
    ),
  );
}
