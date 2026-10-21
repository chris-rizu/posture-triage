import 'package:flutter/material.dart';

import '../assessment/assessment.dart';
import '../data/records.dart';
import '../device/harness.dart';
import '../twin/live_skeleton.dart';
import 'common.dart';
import 'result_screen.dart';

class AssessmentScreen extends StatefulWidget {
  const AssessmentScreen({super.key, required this.harness, required this.records, required this.participant});
  final Harness harness;
  final Records records;
  final String participant;

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  late final Assessment a = Assessment(widget.harness, widget.records.store, widget.participant);
  bool _left = false;

  @override
  void initState() {
    super.initState();
    a.begin();
    a.addListener(_onChange);
  }

  void _onChange() {
    if (a.finished && !_left && mounted) {
      _left = true;
      widget.records.reload();
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ResultScreen(record: a.saved!)));
    }
  }

  @override
  void dispose() {
    a.removeListener(_onChange);
    if (a.busy) a.cancel();
    a.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (a.current == 0 && !a.busy) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop the assessment?'),
        content: const Text('Trials so far will be discarded.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continue')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  static String _hint(StepKind k) => switch (k) {
        StepKind.calibrate => 'Stand still and relaxed.',
        StepKind.stand => 'Stand naturally, look ahead, stay still.',
        StepKind.bend => 'Bend forward slowly, arms hanging. Hold.',
        StepKind.result => 'Combine the trials.',
      };

  static String _action(StepKind k) => switch (k) {
        StepKind.calibrate => 'Calibrate',
        StepKind.stand => 'Start',
        StepKind.bend => 'Start',
        StepKind.result => 'See result',
      };

  @override
  Widget build(BuildContext context) {
    final h = widget.harness;
    final t = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Posture assessment'),
          automaticallyImplyLeading: false,
          actions: [IconButton(onPressed: _close, icon: const Icon(Icons.close))],
        ),
        body: ListenableBuilder(
          listenable: Listenable.merge([a, h]),
          builder: (context, _) {
            final s = a.step;
            final running = s.status == StepStatus.running || s.status == StepStatus.countdown;
            final failed = s.status == StepStatus.failed;
            final isTrial = s.kind == StepKind.stand || s.kind == StepKind.bend;
            final moving = h.latest?.moving ?? false;
            final frac = (a.current + (running && a.progressOf > 0 ? a.progressSec / a.progressOf : 0)) / a.steps.length;
            return Column(children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  children: [
                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(value: frac, minHeight: 6, color: Tok.blue, backgroundColor: Tok.line),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('${a.current + 1} of ${a.steps.length}', style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
                    ]),
                    const SizedBox(height: 18),
                    Text(s.title, style: t.headlineMedium),
                    const SizedBox(height: 4),
                    Text(_hint(s.kind), style: t.bodyLarge?.copyWith(color: Tok.inkSoft)),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        color: Tok.panel,
                        child: Stack(children: [
                          LiveSkeleton(
                            harness: h,
                            view: s.kind == StepKind.bend ? TwinView.side : TwinView.back,
                            labels: false,
                            height: 360,
                          ),
                          if (s.status == StepStatus.countdown)
                            Positioned.fill(
                              child: Container(
                                color: Tok.wall.withValues(alpha: 0.6),
                                alignment: Alignment.center,
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Text('${a.countdown}', style: t.displayMedium?.copyWith(fontSize: 72, color: Tok.blue)),
                                  Text('Bend forward now', style: t.titleMedium),
                                ]),
                              ),
                            ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Column(children: [
                        _Check('Harness connected', h.connected && h.streaming ? _CheckState.done : _CheckState.bad),
                        _Check(moving ? 'Movement detected' : 'Holding still', moving ? _CheckState.wait : _CheckState.done),
                        _Check(
                          switch (s.status) {
                            StepStatus.running when isTrial => 'Collecting data, ${a.progressSec} of ${a.progressOf} s',
                            StepStatus.running => s.kind == StepKind.calibrate ? 'Calibrating' : 'Working',
                            StepStatus.countdown => 'Get ready',
                            StepStatus.failed => 'Needs a repeat',
                            _ when s.kind == StepKind.calibrate => h.calibrated ? 'Calibrated' : 'Not calibrated yet',
                            _ => '${a.trials.where((m) => m['ok'] == true).length} valid trials so far',
                          },
                          switch (s.status) {
                            StepStatus.running || StepStatus.countdown => _CheckState.wait,
                            StepStatus.failed => _CheckState.bad,
                            _ when s.kind == StepKind.calibrate && h.calibrated => _CheckState.done,
                            _ => _CheckState.idle,
                          },
                        ),
                      ]),
                    ),
                    if (s.note != null) ...[
                      const SizedBox(height: 10),
                      Text(s.note!, style: t.bodyMedium?.copyWith(color: failed ? Tok.refer : Tok.inkSoft)),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: running
                      ? OutlinedButton(
                          onPressed: a.cancel, style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)), child: const Text('Stop'))
                      : FilledButton(
                          onPressed: a.runStep,
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                          child: Text(failed ? 'Repeat' : _action(s.kind)),
                        ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

enum _CheckState { idle, wait, done, bad }

class _Check extends StatelessWidget {
  const _Check(this.label, this.state);
  final String label;
  final _CheckState state;
  @override
  Widget build(BuildContext context) {
    final icon = switch (state) {
      _CheckState.done => const Icon(Icons.check_circle, color: Tok.healthy, size: 22),
      _CheckState.bad => const Icon(Icons.error, color: Tok.refer, size: 22),
      _CheckState.wait => const SizedBox(width: 22, height: 22, child: Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2.5))),
      _CheckState.idle => const Icon(Icons.radio_button_unchecked, color: Tok.inkSoft, size: 22),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(children: [icon, const SizedBox(width: 12), Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge))]),
    );
  }
}
