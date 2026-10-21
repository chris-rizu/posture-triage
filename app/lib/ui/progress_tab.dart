import 'package:flutter/material.dart';

import '../core/indicators.dart';
import '../core/score.dart';
import '../data/record_store.dart';
import '../data/records.dart';
import '../data/session_record.dart';
import 'common.dart';
import 'result_screen.dart';

class ProgressTab extends StatefulWidget {
  const ProgressTab({super.key, required this.records});
  final Records records;
  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  int _section = 0; // overview, history, insights
  String? _who;
  int _range = 30; // days; 0 = all

  void _open(SessionRecord r) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultScreen(record: r)));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.records,
      builder: (context, _) {
        final recs = widget.records;
        final people = recs.participants;
        if (_who == null || !people.contains(_who)) _who = people.isEmpty ? null : people.first;
        final mine = _who == null ? <SessionRecord>[] : recs.of(_who!);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(children: [
              Expanded(child: Text('Progress', style: t.headlineMedium)),
              if (people.isNotEmpty)
                PopupMenuButton<String>(
                  initialValue: _who,
                  onSelected: (v) => setState(() => _who = v),
                  itemBuilder: (_) => [for (final p in people) PopupMenuItem(value: p, child: Text(p))],
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                    decoration: BoxDecoration(color: Tok.panel, borderRadius: BorderRadius.circular(20)),
                    child: Row(children: [Text(_who!, style: t.titleMedium), const Icon(Icons.arrow_drop_down)]),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Overview')),
                ButtonSegment(value: 1, label: Text('History')),
                ButtonSegment(value: 2, label: Text('Insights')),
              ],
              selected: {_section},
              onSelectionChanged: (s) => setState(() => _section = s.first),
            ),
            const SizedBox(height: 14),
            if (mine.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Column(children: [
                  const Icon(Icons.insights_outlined, size: 40, color: Tok.inkSoft),
                  const SizedBox(height: 8),
                  Text('No assessments yet', style: t.titleMedium),
                ]),
              )
            else if (_section == 0)
              ..._overview(context, mine)
            else if (_section == 1)
              ..._history(context, recs.items)
            else
              ..._insights(context, mine),
          ],
        );
      },
    );
  }

  List<Widget> _overview(BuildContext context, List<SessionRecord> mine) {
    final t = Theme.of(context).textTheme;
    final cutoff = _range == 0 ? DateTime(2000) : DateTime.now().subtract(Duration(days: _range));
    final pts = mine.where((r) => r.score != null && r.started.isAfter(cutoff)).toList().reversed.toList();
    final valid = mine.where((r) => r.score != null).toList();
    final first = valid.isEmpty ? null : valid.last, last = valid.isEmpty ? null : valid.first;
    final changes = <(String, String, double)>[];
    if (first != null && last != null && first != last) {
      changes.add(('Overall score', 'From ${first.score} to ${last.score}', (last.score! - first.score!).toDouble()));
      for (final a in areas) {
        final a0 = indicatorScore(first.value(a.ind) ?? double.nan, first.thresholds.limits[a.ind]!);
        final a1 = indicatorScore(last.value(a.ind) ?? double.nan, last.thresholds.limits[a.ind]!);
        if ((a1 - a0).abs() >= 3) changes.add((a.name, a1 > a0 ? 'Closer to normal' : 'Further from normal', a1 - a0));
      }
      changes.sort((x, y) => y.$3.abs().compareTo(x.$3.abs()));
    }
    return [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Posture score', style: t.titleMedium)),
            for (final (d, l) in [(7, '7D'), (30, '30D'), (90, '3M'), (0, 'All')])
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ChoiceChip(
                  label: Text(l),
                  selected: _range == d,
                  onSelected: (_) => setState(() => _range = d),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ]),
          const SizedBox(height: 10),
          SizedBox(height: 170, width: double.infinity, child: CustomPaint(painter: _ScoreChart(pts))),
          if (pts.length < 2)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Two or more assessments draw a trend.', style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
            ),
        ]),
      ),
      if (changes.isNotEmpty) ...[
        const CardHeader('Key changes'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            for (final (k, (name, sub, d)) in changes.take(4).indexed) ...[
              if (k > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Icon(d >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      color: d >= 0 ? Tok.healthy : Tok.refer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: t.titleMedium),
                      Text(sub, style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
                    ]),
                  ),
                  Text('${d >= 0 ? '+' : ''}${d.round()}',
                      style: t.titleMedium?.copyWith(color: d >= 0 ? Tok.healthy : Tok.refer)),
                ]),
              ),
            ],
          ]),
        ),
      ],
      CardHeader('Recent assessments', action: 'View all', onAction: () => setState(() => _section = 1)),
      for (final r in mine.take(3)) ...[_RecordTile(r, onTap: () => _open(r)), const SizedBox(height: 8)],
    ];
  }

  List<Widget> _history(BuildContext context, List<SessionRecord> all) => [
        Row(children: [
          Expanded(child: Text('${all.length} assessments', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Tok.inkSoft))),
          TextButton.icon(onPressed: () => shareAll(widget.records.store), icon: const Icon(Icons.ios_share, size: 18), label: const Text('Export all')),
        ]),
        for (final r in all) ...[
          Dismissible(
            key: ValueKey(r.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(color: Tok.refer, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            confirmDismiss: (_) => showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Delete ${r.participant}?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                ],
              ),
            ),
            onDismissed: (_) => widget.records.delete(r.id),
            child: _RecordTile(r, showWho: true, onTap: () => _open(r)),
          ),
          const SizedBox(height: 8),
        ],
      ];

  List<Widget> _insights(BuildContext context, List<SessionRecord> mine) {
    final t = Theme.of(context).textTheme;
    final last = mine.firstWhere((r) => r.valid, orElse: () => mine.first);
    return [
      for (final a in areas) ...[
        AppCard(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.name, style: t.titleMedium),
                const SizedBox(height: 6),
                SizedBox(
                  height: 34,
                  child: CustomPaint(
                    size: const Size(double.infinity, 34),
                    painter: _Spark([for (final r in mine.reversed) r.value(a.ind) ?? double.nan]),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(fmtDeg(last.value(a.ind)), style: t.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              LevelChip(last.level(a.ind), text: switch (last.level(a.ind)) {
                Risk.healthy => 'Good',
                Risk.monitor => 'Review',
                Risk.refer => 'Priority',
                null => '—',
              }),
            ]),
          ]),
        ),
        const SizedBox(height: 8),
      ],
    ];
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile(this.r, {required this.onTap, this.showWho = false});
  final SessionRecord r;
  final VoidCallback onTap;
  final bool showWho;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: r.score?.toString() ?? '—', style: t.titleLarge),
              TextSpan(text: ' / 100', style: t.bodyMedium?.copyWith(color: Tok.inkSoft)),
            ])),
            const SizedBox(height: 4),
            LevelChip(r.valid ? r.risk : null),
            const SizedBox(height: 4),
            Text('${showWho ? '${r.participant}, ' : ''}${shortDate(r.started)}', style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
          ]),
        ),
        const Icon(Icons.chevron_right, color: Tok.inkSoft),
      ]),
    );
  }
}

class _ScoreChart extends CustomPainter {
  _ScoreChart(this.recs);
  final List<SessionRecord> recs; // oldest first

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0, bottom = 18.0;
    final w = size.width - left - 8, h = size.height - bottom - 6;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final v in [0, 50, 80, 100]) {
      final y = 6 + h * (1 - v / 100);
      canvas.drawLine(Offset(left, y), Offset(size.width - 8, y), Paint()..color = Tok.line);
      tp.text = TextSpan(text: '$v', style: const TextStyle(fontSize: 11, color: Tok.inkSoft));
      tp.layout();
      tp.paint(canvas, Offset(0, y - 7));
    }
    // band shading: healthy above 80, monitor 50-79
    canvas.drawRect(Rect.fromLTRB(left, 6, size.width - 8, 6 + h * 0.2), Paint()..color = Tok.healthy.withValues(alpha: 0.06));
    if (recs.isEmpty) return;
    final t0 = recs.first.started.millisecondsSinceEpoch.toDouble();
    final t1 = recs.last.started.millisecondsSinceEpoch.toDouble();
    Offset at(SessionRecord r) {
      final x = recs.length == 1 ? left + w / 2 : left + w * (r.started.millisecondsSinceEpoch - t0) / (t1 - t0);
      return Offset(x, 6 + h * (1 - r.score! / 100));
    }

    final path = Path()..moveTo(at(recs.first).dx, at(recs.first).dy);
    for (final r in recs.skip(1)) {
      path.lineTo(at(r).dx, at(r).dy);
    }
    canvas.drawPath(path, Paint()
      ..color = Tok.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
    for (final r in recs) {
      canvas.drawCircle(at(r), 4.5, Paint()..color = riskColor(r.risk));
    }
    final lastP = at(recs.last);
    tp.text = TextSpan(text: '${recs.last.score}', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700));
    tp.layout();
    final box = RRect.fromRectAndRadius(Rect.fromCenter(center: lastP.translate(0, -18), width: tp.width + 12, height: 20), const Radius.circular(6));
    canvas.drawRRect(box, Paint()..color = Tok.ink);
    tp.paint(canvas, Offset(box.left + 6, box.top + 3));
    String md(DateTime d) => '${d.month}/${d.day}';
    for (final r in [recs.first, recs.last]) {
      tp.text = TextSpan(text: md(r.started), style: const TextStyle(fontSize: 11, color: Tok.inkSoft));
      tp.layout();
      tp.paint(canvas, Offset((at(r).dx - tp.width / 2).clamp(left, size.width - tp.width), size.height - 14));
    }
  }

  @override
  bool shouldRepaint(_ScoreChart old) => old.recs != recs;
}

class _Spark extends CustomPainter {
  _Spark(this.v);
  final List<double> v;
  @override
  void paint(Canvas canvas, Size size) {
    final pts = v.where((x) => !x.isNaN).toList();
    if (pts.length < 2) {
      canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), Paint()..color = Tok.line);
      return;
    }
    var lo = pts.reduce((a, b) => a < b ? a : b), hi = pts.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 4) {
      final c = (hi + lo) / 2;
      lo = c - 2;
      hi = c + 2;
    }
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final o = Offset(size.width * i / (pts.length - 1), size.height * (1 - (pts[i] - lo) / (hi - lo)));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, Paint()
      ..color = Tok.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_Spark old) => true;
}
