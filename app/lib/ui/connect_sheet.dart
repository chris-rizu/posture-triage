import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../device/ble_link.dart';
import '../device/demo_link.dart';
import '../device/harness.dart';
import 'common.dart';

Future<void> showConnectSheet(BuildContext context, Harness harness, {bool demoOnly = false}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ConnectSheet(harness: harness, demoOnly: demoOnly),
    );

class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet({required this.harness, required this.demoOnly});
  final Harness harness;
  final bool demoOnly;
  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  final _subs = <StreamSubscription>[];
  List<ScanResult> _results = [];
  bool _scanning = false;
  BluetoothAdapterState _adapter = BluetoothAdapterState.unknown;
  String? _busy, _error;
  String _profile = 'healthy';
  bool _quick = true;

  @override
  void initState() {
    super.initState();
    if (widget.demoOnly) return;
    try {
      _subs.add(BleDeviceLink.scanResults.listen((r) => setState(() => _results = r)));
      _subs.add(BleDeviceLink.isScanning.listen((s) => setState(() => _scanning = s)));
      _subs.add(BleDeviceLink.adapterState.listen((s) => setState(() => _adapter = s)));
      BleDeviceLink.startScan().catchError((e) => setState(() => _error = 'Bluetooth search did not start.'));
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    if (_scanning) BleDeviceLink.stopScan();
    super.dispose();
  }

  Future<void> _connect(ScanResult r) async {
    setState(() => _busy = r.device.remoteId.str);
    try {
      await BleDeviceLink.stopScan();
      await widget.harness.attach(await BleDeviceLink.connect(r.device));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not connect. Move closer and try again.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _demo() async {
    await widget.harness.attach(DemoDeviceLink(profile: _profile, speed: _quick ? 5 : 1));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final btOff = !kIsWeb && _adapter == BluetoothAdapterState.off;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!widget.demoOnly) ...[
            Row(children: [
              Expanded(child: Text('Connect harness', style: t.titleLarge)),
              if (_scanning) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else IconButton(onPressed: btOff ? null : () => BleDeviceLink.startScan(), icon: const Icon(Icons.refresh)),
            ]),
            const SizedBox(height: 4),
            if (btOff) Text('Turn on Bluetooth.', style: t.bodyMedium?.copyWith(color: Tok.refer)),
            if (_error != null) Text(_error!, style: t.bodyMedium?.copyWith(color: Tok.refer)),
            for (final r in _results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.accessibility_new, color: Tok.blue),
                title: Text(r.device.platformName.isEmpty ? 'PostureTriage' : r.device.platformName),
                subtitle: Text('Signal ${r.rssi} dBm'),
                trailing: _busy == r.device.remoteId.str
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_right),
                onTap: _busy == null ? () => _connect(r) : null,
              ),
            if (!_scanning && _results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('No harness found. Switch it on and tap refresh.', style: t.bodyMedium?.copyWith(color: Tok.inkSoft)),
              ),
            const Divider(height: 28),
          ],
          Text('Demo', style: t.titleLarge),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in demoProfiles)
              ChoiceChip(label: Text(p.short), selected: _profile == p.key, onSelected: (_) => setState(() => _profile = p.key)),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Quick trials (6 s)'),
            value: _quick,
            onChanged: (v) => setState(() => _quick = v),
          ),
          FilledButton(onPressed: _demo, child: const Text('Start demo')),
        ]),
      ),
    );
  }
}
