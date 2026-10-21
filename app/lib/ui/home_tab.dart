import 'package:flutter/material.dart';

import '../core/protocol.dart';
import '../data/records.dart';
import '../device/harness.dart';
import '../mascot/buko.dart';
import 'common.dart';
import 'connect_sheet.dart';
import 'result_screen.dart';
import 'shell.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.harness, required this.records, this.active = true});
  final Harness harness;
  final Records records;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final shell = AppShell.of(context);
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([harness, records]),
      builder: (context, _) {
        final h = harness;
        final last = records.latest;
        final greeting = !h.connected
            ? 'Hi! Connect the harness to begin.'
            : !h.calibrated
                ? 'Ready when you are.'
                : (h.latest?.moving ?? false)
                    ? 'Hold still for me.'
                    : 'All set. Let’s check.';
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Buko', style: t.displayMedium?.copyWith(fontSize: 34)),
                  Text('Posture check', style: t.bodyMedium?.copyWith(color: Tok.inkSoft)),
                ]),
              ),
              IconButton(onPressed: () => shell.go(3), icon: const Icon(Icons.settings_outlined), tooltip: 'Settings'),
            ]),
            const SizedBox(height: 14),
            _StatusCard(h: h, onConnect: () => shell.connect()),
            SizedBox(
              height: 250,
              child: Stack(children: [
                Positioned(left: 0, top: 0, bottom: 0, width: 190, child: Buko(mode: BukoMode.wave, height: 250, active: active)),
                Positioned(
                  left: 175,
                  right: 0,
                  top: 46,
                  child: _Bubble(greeting),
                ),
              ]),
            ),
            FilledButton(
              onPressed: shell.startAssessment,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Start assessment'),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Tile(icon: Icons.sensors, label: 'Live monitor', onTap: () => shell.go(2))),
              const SizedBox(width: 12),
              Expanded(
                child: h.connected
                    ? _Tile(icon: Icons.tune, label: h.calibrated ? 'Recalibrate' : 'Calibrate', onTap: () => h.send('CAL'))
                    : _Tile(icon: Icons.science_outlined, label: 'Try demo', onTap: () => showConnectSheet(context, h, demoOnly: true)),
              ),
            ]),
            CardHeader('Recent result', action: last == null ? null : 'View all', onAction: () => shell.go(1)),
            if (last == null)
              AppCard(
                child: Row(children: [
                  const Icon(Icons.assignment_outlined, color: Tok.inkSoft),
                  const SizedBox(width: 12),
                  Expanded(child: Text('No assessments yet.', style: t.bodyMedium?.copyWith(color: Tok.inkSoft))),
                ]),
              )
            else
              AppCard(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultScreen(record: last))),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(text: last.score?.toString() ?? '—', style: t.headlineMedium),
                        TextSpan(text: ' / 100', style: t.bodyLarge?.copyWith(color: Tok.inkSoft)),
                      ])),
                      const SizedBox(height: 6),
                      LevelChip(last.valid ? last.risk : null),
                      const SizedBox(height: 6),
                      Text('${last.participant}, ${shortDate(last.started)}', style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, color: Tok.inkSoft),
                ]),
              ),
            const CardHeader('Quick tips'),
            const _Tips(),
          ],
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.h, required this.onConnect});
  final Harness h;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pct = batteryPercent(h.batteryMv);
    final live = h.connected && h.streaming;
    return AppCard(
      onTap: h.connected ? null : onConnect,
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: live ? Tok.healthy : (h.connected ? Tok.monitor : Tok.line))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h.connected ? (h.isDemo ? 'Demo harness' : 'Harness connected') : 'Harness not connected', style: t.titleMedium),
            Text(h.connected ? (live ? 'Live, ${h.packetRate.round()} ${h.packetRate.round() == 1 ? 'reading' : 'readings'} a second' : 'Waiting for data') : 'Tap to connect',
                style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
          ]),
        ),
        if (h.connected && pct >= 0) ...[
          Icon(pct < 20 ? Icons.battery_alert : Icons.battery_full, color: pct < 20 ? Tok.refer : Tok.healthy, size: 20),
          const SizedBox(width: 4),
          Text('$pct%', style: t.bodyMedium),
        ] else if (!h.connected)
          const Icon(Icons.bluetooth_searching, color: Tok.blue),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Tok.panel,
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4)),
          boxShadow: [BoxShadow(color: Tok.ink.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Text(text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Tok.ink, size: 22),
          const SizedBox(width: 8),
          Flexible(child: Text(label, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
        ]),
      );
}

class _Tips extends StatefulWidget {
  const _Tips();
  @override
  State<_Tips> createState() => _TipsState();
}

class _TipsState extends State<_Tips> {
  static const tips = [
    (Icons.desktop_windows_outlined, 'Screen at eye level', 'Less bending of the neck.'),
    (Icons.timer_outlined, 'Move every 30 minutes', 'Stand up and stretch briefly.'),
    (Icons.backpack_outlined, 'Carry on both shoulders', 'Keeps the shoulders level.'),
  ];
  final _pc = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(children: [
      SizedBox(
        height: 88,
        child: PageView(
          controller: _pc,
          onPageChanged: (i) => setState(() => _page = i),
          children: [
            for (final (icon, title, sub) in tips)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: AppCard(
                  child: Row(children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: const Color(0xFFD6E4F5), borderRadius: BorderRadius.circular(14)),
                      child: Icon(icon, color: Tok.blue),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: t.titleMedium),
                        Text(sub, style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
                      ]),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < tips.length; i++)
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? Tok.ink : Tok.line),
          ),
      ]),
    ]);
  }
}
