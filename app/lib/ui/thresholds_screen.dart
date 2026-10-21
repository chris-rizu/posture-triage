import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/indicators.dart';
import '../device/harness.dart';
import 'common.dart';

/// Shows the thresholds stored on the harness and loads new ones produced by the
/// analysis toolkit (analysis/out/thresholds.json) with the THR command.
class ThresholdsScreen extends StatefulWidget {
  const ThresholdsScreen({super.key, required this.harness});
  final Harness harness;

  @override
  State<ThresholdsScreen> createState() => _ThresholdsScreenState();
}

class _ThresholdsScreenState extends State<ThresholdsScreen> {
  final _ctl = TextEditingController();
  String? _err;

  @override
  void initState() {
    super.initState();
    widget.harness.send('GETTHR');
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _err = null);
    Thresholds t;
    try {
      final j = jsonDecode(_ctl.text) as Map<String, dynamic>;
      t = Thresholds.fromJson(j, base: widget.harness.thresholds);
    } catch (e) {
      setState(() => _err = 'Not valid JSON: $e');
      return;
    }
    final v = t.validate();
    if (v != null) {
      setState(() => _err = v);
      return;
    }
    final reply = widget.harness.next('thr', timeout: const Duration(seconds: 5));
    await widget.harness.sendThresholds(t);
    try {
      await reply;
      if (mounted) showSnack(context, 'Thresholds saved on the harness.');
      _ctl.clear();
    } catch (_) {
      if (mounted) setState(() => _err = widget.harness.lastError ?? 'The harness did not confirm.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Thresholds')),
      body: ListenableBuilder(
        listenable: widget.harness,
        builder: (context, _) {
          final th = widget.harness.thresholds;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Text(
                th.provisional
                    ? 'Provisional values. Replace them with the limits computed from the healthy development-set participants (μ + 1.5σ, μ + 2σ).'
                    : 'Limits from the development set. Keep them unchanged during the validation phase.',
                style: t.bodyMedium,
              ),
              const SectionTitle('Limits on the harness'),
              Panel(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Table(
                    columnWidths: const {0: FlexColumnWidth(2.6)},
                    children: [
                      TableRow(children: [
                        for (final h in ['Indicator', 'Ref.', 'Monitor', 'Refer'])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(h, style: t.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                                textAlign: h == 'Indicator' ? TextAlign.left : TextAlign.right),
                          ),
                      ]),
                      for (final i in Ind.values)
                        TableRow(children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text('${indicatorInfo[i]!.name} (${indKey(i)})'),
                          ),
                          for (final v in [th.limits[i]!.mu, th.limits[i]!.mon, th.limits[i]!.ref])
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(fmtDeg(v, digits: 2), textAlign: TextAlign.right),
                            ),
                        ]),
                    ],
                  ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text('Monitor when |value − ref.| ≥ monitor limit; refer when ≥ refer limit.',
                    style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
              const SectionTitle('Load new limits'),
              TextField(
                controller: _ctl,
                minLines: 4,
                maxLines: 10,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  hintText: '{"provisional": false, "K": [38.2, 11.4, 15.2], ...}',
                  errorText: _err,
                  errorMaxLines: 3,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _load, icon: const Icon(Icons.upload), label: const Text('Send to harness')),
            ],
          );
        },
      ),
    );
  }
}
