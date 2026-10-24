import 'package:flutter/material.dart';

import '../core/indicators.dart';
import '../core/protocol.dart';
import '../core/score.dart';
import '../data/record_store.dart';
import '../data/session_record.dart';
import '../mascot/buko.dart';
import '../twin/live_skeleton.dart';
import 'common.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.record});
  final SessionRecord record;
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _allAreas = false;

  SessionRecord get r => widget.record;

  Measurement? _pose() {
    final p = r.standingPose;
    if (p == null) return null;
    return Measurement(
      state: DevState.idle,
      seq: 0,
      s: p.s,
      f: p.f,
      r: List.filled(5, double.nan),
      ind: {for (final i in Ind.values) i: r.value(i) ?? double.nan},
      batteryMv: 0,
      flags: 0,
    );
  }

  String _summary(List<(Area, Risk?)> ranked) {
    final off = [for (final (a, l) in ranked) if (l == Risk.refer || l == Risk.monitor) a.name.toLowerCase()];
    if (off.isEmpty) return 'All areas are within the normal range.';
    final names = off.length == 1 ? off.first : '${off.take(off.length - 1).join(', ')} and ${off.last}';
    return '${names[0].toUpperCase()}${names.substring(1)} ${off.length == 1 ? 'is' : 'are'} outside the normal range.';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final risk = r.valid ? r.risk : null;
    final ranked = [for (final a in areas) (a, r.level(a.ind))]
      ..sort((x, y) => (y.$2?.index ?? -1).compareTo(x.$2?.index ?? -1));
    final pose = _pose();
    final recs = _recommend(ranked);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Assessment result'),
          Text('${r.participant}, ${shortDate(r.started)}', style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
        ]),
        actions: [IconButton(onPressed: () => shareSession(r), icon: const Icon(Icons.ios_share), tooltip: 'Export CSV')],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          AppCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: r.score?.toString() ?? '—', style: t.displayMedium?.copyWith(fontSize: 52)),
                    TextSpan(text: ' / 100', style: t.titleLarge?.copyWith(color: Tok.inkSoft, fontWeight: FontWeight.w400)),
                  ])),
                  const SizedBox(height: 6),
                  LevelChip(risk),
                  const SizedBox(height: 10),
                  Text(risk == null ? 'Some trials did not agree. Repeat the assessment.' : _summary(ranked), style: t.bodyLarge),
                  if (risk != null) ...[
                    const SizedBox(height: 6),
                    Text('Triage level: ${riskTitle(risk)}', style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
                  ],
                ]),
              ),
              SizedBox(
                width: 96,
                height: 128,
                child: Buko(
                  mode: switch (risk) {
                    Risk.healthy => BukoMode.celebrate,
                    Risk.refer => BukoMode.concerned,
                    _ => BukoMode.thinking,
                  },
                  height: 128,
                ),
              ),
            ]),
          ),
          if (pose != null) ...[
            const CardHeader('Posture overview'),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                color: Tok.panel,
                child: LiveSkeleton(fixed: pose, thresholds: r.thresholds, view: TwinView.side, labels: false, height: 280),
              ),
            ),
          ],
          const CardHeader('Areas to focus on'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              for (final (k, (a, l)) in ranked.take(_allAreas ? 6 : 3).indexed) ...[
                if (k > 0) const Divider(height: 1),
                _AreaRow(a, l, r.value(a.ind)),
              ],
              TextButton(
                onPressed: () => setState(() => _allAreas = !_allAreas),
                child: Text(_allAreas ? 'Show less' : 'Show all 6'),
              ),
            ]),
          ),
          const CardHeader('Suggestions'),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final (icon, kind, title, time) = recs[i];
                return SizedBox(
                  width: 128,
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(kind, style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
                      const SizedBox(height: 6),
                      Icon(icon, color: Tok.blue, size: 28),
                      const Spacer(),
                      Text(title, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700), maxLines: 2),
                      Text(time, style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          Text('Screening only, not a diagnosis.', textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
        ],
      ),
    );
  }

  List<(IconData, String, String, String)> _recommend(List<(Area, Risk?)> ranked) {
    const per = {
      Ind.n: (Icons.self_improvement, 'Stretch', 'Chin tucks', '2 min'),
      Ind.k: (Icons.accessibility_new, 'Stretch', 'Chest opener', '5 min'),
      Ind.l: (Icons.airline_seat_flat_outlined, 'Mobility', 'Cat and cow', '5 min'),
      Ind.s: (Icons.fitness_center, 'Strengthen', 'Shoulder squeezes', '3 min'),
      Ind.f: (Icons.sports_gymnastics, 'Strengthen', 'Side plank', '3 min'),
      Ind.r: (Icons.medical_services_outlined, 'Check-up', 'Physical therapist', 'Book a visit'),
    };
    final out = [for (final (a, l) in ranked) if (l == Risk.refer || l == Risk.monitor) per[a.ind]!];
    out.add((Icons.desktop_windows_outlined, 'Daily habit', 'Screen at eye level', 'Every day'));
    if (out.length == 1) out.insert(0, (Icons.directions_walk, 'Daily habit', 'Move every 30 min', 'Every day'));
    return out;
  }
}

class _AreaRow extends StatelessWidget {
  const _AreaRow(this.a, this.l, this.v);
  final Area a;
  final Risk? l;
  final double? v;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = riskColor(l);
    final off = l == Risk.refer || l == Risk.monitor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle),
          child: Icon(off ? Icons.priority_high_rounded : Icons.check_rounded, color: c, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.name, style: t.titleMedium),
            Text('${off ? a.off : a.good}, ${fmtDeg(v)}', style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
          ]),
        ),
        LevelChip(l, text: switch (l) {
          Risk.refer => 'Priority',
          Risk.monitor => 'Review',
          Risk.healthy => 'Good',
          null => '—',
        }),
      ]),
    );
  }
}
