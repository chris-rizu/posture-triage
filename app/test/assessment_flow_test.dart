import 'package:flutter_test/flutter_test.dart';
import 'package:posture_triage/assessment/assessment.dart';
import 'package:posture_triage/core/indicators.dart';
import 'package:posture_triage/data/store_memory.dart';
import 'package:posture_triage/device/demo_link.dart';
import 'package:posture_triage/device/harness.dart';

Future<Assessment> runAll(String profile, {bool fidgetFirstStand = false}) async {
  final h = Harness();
  final link = DemoDeviceLink(profile: profile, speed: 60);
  await h.attach(link);
  final a = Assessment(h, MemoryRecordStore(), 'P001', bendCountdown: 0);
  await a.begin();
  var guard = 0;
  while (!a.finished && guard++ < 30) {
    if (fidgetFirstStand && a.step.kind == StepKind.stand && a.trials.isEmpty) {
      await h.send('SIM FIDGET ON');
      await a.runStep();
      expect(a.step.status, StepStatus.failed);
      expect(a.step.note, contains('moved'));
      await h.send('SIM FIDGET OFF');
    }
    await a.runStep();
  }
  await h.detach();
  return a;
}

void main() {
  test('healthy demo participant completes the protocol as healthy', () async {
    final a = await runAll('healthy');
    expect(a.saved, isNotNull);
    expect(a.saved!.valid, isTrue);
    expect(a.saved!.risk, Risk.healthy);
    expect(a.trials.where((t) => t['ok'] == true).length, 6);
    expect(a.saved!.streamCsv.split('\n').first, startsWith('t_s,phase,state,s1'));
    expect(a.saved!.trialsCsv().split('\n').where((l) => l.isNotEmpty).length, 7); // header + 6
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('scoliotic demo participant is referred', () async {
    final a = await runAll('scoliotic');
    expect(a.saved!.risk, Risk.refer);
    expect(a.saved!.level(Ind.r), Risk.refer);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('asymmetric demo participant is monitored', () async {
    final a = await runAll('asymmetric');
    expect(a.saved!.risk, Risk.monitor);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a trial with movement is rejected and can be repeated', () async {
    final a = await runAll('healthy', fidgetFirstStand: true);
    expect(a.saved!.valid, isTrue);
    expect(a.trials.where((t) => t['ok'] == false).length, 1);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('summary CSV row has one value per header column', () async {
    final a = await runAll('rounded');
    final header = a.saved!.summaryRow().split(',');
    expect(header.length, 'session_id,participant,date_time,device,firmware,demo,thresholds_provisional,complete,agree,risk'.split(',').length + 18);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
