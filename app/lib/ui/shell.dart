import 'dart:async';

import 'package:flutter/material.dart';

import '../data/records.dart';
import '../device/harness.dart';
import 'assessment_screen.dart';
import 'common.dart';
import 'connect_sheet.dart';
import 'home_tab.dart';
import 'progress_tab.dart';
import 'sensors_tab.dart';
import 'settings_tab.dart';

/// The app frame: four tabs in a bottom menu.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.harness, required this.records});
  final Harness harness;
  final Records records;

  @override
  State<AppShell> createState() => AppShellState();

  static AppShellState of(BuildContext context) => context.findAncestorStateOfType<AppShellState>()!;
}

class AppShellState extends State<AppShell> {
  int tab = 0;
  StreamSubscription? _errSub;
  bool _wasConnected = false;

  Harness get harness => widget.harness;
  Records get records => widget.records;

  @override
  void initState() {
    super.initState();
    _errSub = harness.messages.where((m) => m['t'] == 'err').listen((_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) showSnack(context, harness.lastError ?? '');
    });
    harness.addListener(_onHarness);
  }

  void _onHarness() {
    if (_wasConnected && !harness.connected && mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      showSnack(context, harness.lastError ?? 'Harness disconnected.');
      harness.clearError();
    }
    _wasConnected = harness.connected;
  }

  @override
  void dispose() {
    _errSub?.cancel();
    harness.removeListener(_onHarness);
    super.dispose();
  }

  void go(int i) => setState(() => tab = i);

  Future<void> connect() => showConnectSheet(context, harness);

  Future<void> startAssessment() async {
    if (!harness.connected) {
      await connect();
      if (!harness.connected || !mounted) return;
    }
    final code = await askParticipantCode(context);
    if (code == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AssessmentScreen(harness: harness, records: records, participant: code),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeTab(harness: harness, records: records, active: tab == 0),
      ProgressTab(records: records),
      SensorsTab(harness: harness, active: tab == 2),
      SettingsTab(harness: harness, records: records),
    ];
    return Scaffold(
      body: SafeArea(bottom: false, child: IndexedStack(index: tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Progress'),
          NavigationDestination(icon: Icon(Icons.sensors_outlined), selectedIcon: Icon(Icons.sensors), label: 'Sensors'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

/// Participant code (e.g. P001). Names are never entered.
Future<String?> askParticipantCode(BuildContext context) {
  final ctl = TextEditingController();
  final re = RegExp(r'^[A-Za-z]{1,3}\d{2,4}$');
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final ok = re.hasMatch(ctl.text.trim());
      return AlertDialog(
        title: const Text('Participant code'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'P001', helperText: 'From the consent form. No names.'),
          onChanged: (_) => setS(() {}),
          onSubmitted: (_) => ok ? Navigator.pop(ctx, ctl.text.trim().toUpperCase()) : null,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: ok ? () => Navigator.pop(ctx, ctl.text.trim().toUpperCase()) : null, child: const Text('Start')),
        ],
      );
    }),
  );
}
