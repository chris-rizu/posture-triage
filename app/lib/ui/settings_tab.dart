import 'package:flutter/material.dart';

import '../core/protocol.dart';
import '../data/record_store.dart';
import '../data/records.dart';
import '../device/demo_link.dart';
import '../device/harness.dart';
import 'common.dart';
import 'shell.dart';
import 'thresholds_screen.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key, required this.harness, required this.records});
  final Harness harness;
  final Records records;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: harness,
      builder: (context, _) {
        final h = harness;
        final pct = batteryPercent(h.batteryMv);
        final missing = [for (var i = 0; i < 5; i++) if (i < h.sensors.length && h.sensors[i] == 0) 'IMU${i + 1}'];
        Widget group(String title, List<Widget> rows) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CardHeader(title),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final (k, r) in rows.indexed) ...[if (k > 0) const Divider(height: 1, indent: 56), r],
                ]),
              ),
            ]);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text('Settings', style: t.headlineMedium),
            group('Device', [
              ListTile(
                leading: Icon(h.connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: h.connected ? Tok.healthy : Tok.inkSoft),
                title: Text(h.connected ? h.name : 'Not connected'),
                subtitle: h.connected
                    ? Text([
                        if (pct >= 0) 'Battery $pct%' else 'USB power',
                        if (h.firmware.isNotEmpty) 'firmware ${h.firmware}',
                      ].join(', '))
                    : null,
                trailing: h.connected
                    ? TextButton(onPressed: h.detach, child: const Text('Disconnect'))
                    : TextButton(onPressed: () => AppShell.of(context).connect(), child: const Text('Connect')),
              ),
              if (h.connected) ...[
                ListTile(
                  leading: Icon(Icons.sensors, color: missing.isEmpty ? Tok.healthy : Tok.refer),
                  title: const Text('Sensors'),
                  subtitle: Text(missing.isEmpty ? 'All 5 responding' : '${missing.join(', ')} not responding'),
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Calibrate'),
                  subtitle: Text(h.calibrated ? 'Done. Repeat after refitting the harness.' : 'Stand still for 3 seconds'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => h.send('CAL'),
                ),
              ],
            ]),
            group('Assessment', [
              ListTile(
                leading: const Icon(Icons.straighten),
                title: const Text('Thresholds'),
                subtitle: Text(h.thresholds.provisional ? 'Provisional' : 'From the development set'),
                trailing: const Icon(Icons.chevron_right),
                onTap: h.connected
                    ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ThresholdsScreen(harness: h)))
                    : null,
              ),
            ]),
            group('Data', [
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Export all assessments'),
                subtitle: const Text('summary.csv and trials.csv'),
                onTap: () => shareAll(records.store),
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Stored on this phone'),
                subtitle: Text(records.store.location),
              ),
            ]),
            if (h.isDemo || h.simulated)
              group('Demo', [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Virtual participant'),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.arrow_drop_down),
                    onSelected: (k) => h.send('SIM PROFILE $k'),
                    itemBuilder: (_) => [for (final p in demoProfiles) PopupMenuItem(value: p.key, child: Text(p.short))],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.directions_walk),
                  title: const Text('Fidget'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(onPressed: () => h.send('SIM FIDGET ON'), child: const Text('On')),
                    TextButton(onPressed: () => h.send('SIM FIDGET OFF'), child: const Text('Off')),
                  ]),
                ),
              ]),
            group('About', [
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Screening aid, not a diagnosis'),
                subtitle: Text('Results suggest who should see a professional.'),
              ),
              ListTile(
                leading: const Icon(Icons.copyright),
                title: const Text('Credits'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Posture Triage',
                  applicationLegalese: 'Skeleton: BodyParts3D, © 2008 Life Science Integrated Database Center, '
                      'CC BY-SA 2.1 Japan. 3D rendering: three.js (MIT). Typeface: Atkinson Hyperlegible (OFL).',
                ),
              ),
            ]),
          ],
        );
      },
    );
  }
}
