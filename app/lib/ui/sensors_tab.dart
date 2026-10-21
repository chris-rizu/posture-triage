import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../core/indicators.dart';
import '../core/protocol.dart';
import '../device/harness.dart';
import '../twin/live_skeleton.dart';
import 'common.dart';
import 'shell.dart';

/// Live monitor: the skeleton, the five pods and posture monitoring.
class SensorsTab extends StatefulWidget {
  const SensorsTab({super.key, required this.harness, this.active = true});
  final Harness harness;
  final bool active;
  @override
  State<SensorsTab> createState() => _SensorsTabState();
}

const _podName = ['C7 (neck)', 'T12 (mid back)', 'L3 (lower back)', 'L scapula', 'R scapula'];
const _podInd = [Ind.n, Ind.k, Ind.l, Ind.s, Ind.s];

class _SensorsTabState extends State<SensorsTab> {
  TwinView _view = TwinView.side;
  bool _labels = false, _focus = false, _amplify = false, _open = true;
  final _hist = List.generate(5, (_) => ListQueue<(double, double)>());
  StreamSubscription? _mSub, _aSub;
  int _alerts = 0;

  Harness get h => widget.harness;

  @override
  void initState() {
    super.initState();
    h.addListener(_resubscribe);
    _resubscribe();
  }

  Harness? _subscribedTo;
  Object? _link;
  void _resubscribe() {
    if (identical(_link, h.link) && _subscribedTo == h) return;
    _link = h.link;
    _subscribedTo = h;
    _mSub?.cancel();
    _aSub?.cancel();
    for (final q in _hist) {
      q.clear();
    }
    _mSub = h.measurements.listen((m) {
      for (var p = 0; p < 5; p++) {
        _hist[p].add((m.s[p], m.f[p]));
        if (_hist[p].length > 150) _hist[p].removeFirst();
      }
    });
    _aSub = h.messages.where((m) => m['t'] == 'alert').listen((_) => setState(() => _alerts++));
  }

  @override
  void dispose() {
    h.removeListener(_resubscribe);
    _mSub?.cancel();
    _aSub?.cancel();
    super.dispose();
  }

  void _details(int p) => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => _PodSheet(h: h, pod: p, hist: _hist[p]),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: h,
      builder: (context, _) {
        final m = h.latest;
        final monitoring = h.state == DevState.monitor;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(children: [
              Expanded(child: Text('Live monitor', style: t.headlineMedium)),
              _LivePill(on: h.connected && h.streaming),
            ]),
            const SizedBox(height: 14),
            SegmentedButton<TwinView>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: TwinView.back, label: Text('Back')),
                ButtonSegment(value: TwinView.side, label: Text('Side')),
                ButtonSegment(value: TwinView.three, label: Text('¾')),
                ButtonSegment(value: TwinView.front, label: Text('Front')),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            if (!h.connected)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(children: [
                  const Icon(Icons.sensors_off_outlined, size: 40, color: Tok.inkSoft),
                  const SizedBox(height: 8),
                  Text('No harness connected', style: t.titleMedium),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: () => AppShell.of(context).connect(), child: const Text('Connect')),
                ]),
              )
            else ...[
              LiveSkeleton(harness: h, view: _view, labels: _labels, spineFocus: _focus, amplify: _amplify, height: 420, active: widget.active),
              Text('Drag to rotate', textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
              const SizedBox(height: 14),
              AppCard(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                child: Column(children: [
                  InkWell(
                    onTap: () => setState(() => _open = !_open),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Sensor readings', style: t.titleMedium),
                            Text('${h.sensors.where((s) => s == 1).length} of 5 sensors live',
                                style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
                          ]),
                        ),
                        Icon(_open ? Icons.expand_less : Icons.expand_more, color: Tok.inkSoft),
                      ]),
                    ),
                  ),
                  if (_open)
                    for (var p = 0; p < 5; p++) ...[
                      const Divider(height: 1),
                      _PodRow(h: h, pod: p, m: m, onTap: () => _details(p)),
                    ],
                ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(children: [
                  SwitchListTile(title: const Text('Sensor labels'), value: _labels, onChanged: (v) => setState(() => _labels = v)),
                  SwitchListTile(title: const Text('Spine focus'), value: _focus, onChanged: (v) => setState(() => _focus = v)),
                  SwitchListTile(title: const Text('Show tilts 2×'), value: _amplify, onChanged: (v) => setState(() => _amplify = v)),
                ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: SwitchListTile(
                  title: const Text('Vibrate on slouching'),
                  subtitle: Text(monitoring
                      ? (_alerts == 0 ? 'On. No alerts yet.' : 'On. $_alerts alert${_alerts == 1 ? '' : 's'}.')
                      : (h.calibrated ? 'After 10 s out of range' : 'Calibrate first')),
                  value: monitoring,
                  onChanged: h.calibrated ? (v) => h.send(v ? 'MONITOR' : 'STOP') : null,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.on});
  final bool on;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: (on ? Tok.healthy : Tok.inkSoft).withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: on ? Tok.healthy : Tok.inkSoft)),
          const SizedBox(width: 6),
          Text(on ? 'Live' : 'Offline', style: TextStyle(color: on ? Tok.healthy : Tok.inkSoft, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _PodRow extends StatelessWidget {
  const _PodRow({required this.h, required this.pod, required this.m, required this.onTap});
  final Harness h;
  final int pod;
  final Measurement? m;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fault = h.sensors.length > pod && h.sensors[pod] == 0;
    final v = m?.ind[_podInd[pod]];
    final lvl = (v == null || v.isNaN) ? null : h.thresholds.limits[_podInd[pod]]!.levelOf(v);
    final dot = fault ? Tok.refer : riskColor(lvl);
    const num = [FontFeature.tabularFigures()];
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dot.withValues(alpha: 0.15)),
            child: Text('${pod + 1}', style: TextStyle(color: dot, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(_podName[pod], style: t.bodyLarge)),
          if (fault)
            Text('Not responding', style: t.bodyMedium?.copyWith(color: Tok.refer, fontWeight: FontWeight.w700))
          else
            SizedBox(
              width: 120,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Forward ${fmtDeg(m?.s[pod])}', style: t.bodyMedium?.copyWith(fontFeatures: num)),
                Text('Side ${fmtDeg(m?.f[pod])}', style: t.bodySmall?.copyWith(color: Tok.inkSoft, fontFeatures: num)),
              ]),
            ),
          const Icon(Icons.chevron_right, color: Tok.inkSoft),
        ]),
      ),
    );
  }
}

class _PodSheet extends StatelessWidget {
  const _PodSheet({required this.h, required this.pod, required this.hist});
  final Harness h;
  final int pod;
  final ListQueue<(double, double)> hist;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: h,
      builder: (context, _) {
        final m = h.latest;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('IMU${pod + 1}, ${_podName[pod]}', style: t.titleLarge),
              const SizedBox(height: 12),
              Row(children: [
                _Big('Forward', fmtDeg(m?.s[pod])),
                _Big('Side', fmtDeg(m?.f[pod])),
                _Big('Roll', fmtDeg(m?.r[pod])),
              ]),
              const SizedBox(height: 14),
              Text('Last 30 seconds', style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
              const SizedBox(height: 6),
              SizedBox(height: 120, width: double.infinity, child: CustomPaint(painter: _Trace(hist.toList()))),
              const SizedBox(height: 6),
              Row(children: [
                Container(width: 14, height: 3, color: Tok.blue),
                const SizedBox(width: 6),
                Text('Forward', style: t.bodySmall),
                const SizedBox(width: 16),
                Container(width: 14, height: 3, color: Tok.pink),
                const SizedBox(width: 6),
                Text('Side', style: t.bodySmall),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

class _Big extends StatelessWidget {
  const _Big(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Tok.inkSoft, fontSize: 13)),
          Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );
}

class _Trace extends CustomPainter {
  _Trace(this.pts);
  final List<(double, double)> pts;

  @override
  void paint(Canvas canvas, Size size) {
    final vals = [for (final p in pts) ...[p.$1, p.$2]].where((v) => !v.isNaN);
    if (vals.isEmpty) return;
    var lo = vals.reduce((a, b) => a < b ? a : b), hi = vals.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 10) {
      final c = (hi + lo) / 2;
      lo = c - 5;
      hi = c + 5;
    }
    final grid = Paint()..color = Tok.line;
    for (var k = 0; k <= 2; k++) {
      canvas.drawLine(Offset(0, size.height * k / 2), Offset(size.width, size.height * k / 2), grid);
    }
    for (final (sel, color) in [(0, Tok.blue), (1, Tok.pink)]) {
      final path = Path();
      var started = false;
      for (var i = 0; i < pts.length; i++) {
        final v = sel == 0 ? pts[i].$1 : pts[i].$2;
        if (v.isNaN) {
          started = false;
          continue;
        }
        final x = size.width * (i + 150 - pts.length) / 149, y = size.height * (1 - (v - lo) / (hi - lo));
        started ? path.lineTo(x, y) : path.moveTo(x, y);
        started = true;
      }
      canvas.drawPath(path, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final (v, y) in [(hi, 0.0), (lo, size.height - 14)]) {
      tp.text = TextSpan(text: '${v.toStringAsFixed(0)}°', style: const TextStyle(fontSize: 11, color: Tok.inkSoft));
      tp.layout();
      tp.paint(canvas, Offset(2, y));
    }
  }

  @override
  bool shouldRepaint(_Trace old) => true;
}
