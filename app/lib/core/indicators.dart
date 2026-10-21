// Indicator definitions, thresholds and the triage rule.
// Mirrors firmware/lib/core/src/indicators.h and triage.h; keep the two in step.

/// Six posture indicators (thesis Table 3.3).
enum Ind { k, l, n, f, s, r }

class IndicatorInfo {
  const IndicatorInfo(this.key, this.name, this.plain, this.formula, this.fromBend);
  final String key; // protocol key: K, L, N, F, S, R
  final String name;
  final String plain; // one line a participant understands
  final String formula;
  final bool fromBend;
}

const indicatorInfo = <Ind, IndicatorInfo>{
  Ind.k: IndicatorInfo('K', 'Upper-back rounding', 'How much the upper back curves forward', 'θs1 − θs2', false),
  Ind.l: IndicatorInfo('L', 'Lower-back curve', 'The inward curve of the lower back', 'θs2 − θs3', false),
  Ind.n: IndicatorInfo('N', 'Neck-base tilt', 'How far the base of the neck leans forward', 'θs1', false),
  Ind.f: IndicatorInfo('F', 'Trunk lean', 'Sideways lean of the trunk', 'θf2', false),
  Ind.s: IndicatorInfo('S', 'Shoulder tilt', 'Difference in shoulder-blade height', '(θf4 + θf5) / 2', false),
  Ind.r: IndicatorInfo('R', 'Trunk rotation', 'Rib or back hump seen in the forward bend', 'max(|(θr4 + θr5)/2|, |θr2|)', true),
};

String indKey(Ind i) => indicatorInfo[i]!.key;
Ind? indFromKey(String k) {
  for (final e in indicatorInfo.entries) {
    if (e.value.key == k) return e.key;
  }
  return null;
}

enum Risk { healthy, monitor, refer }

Risk? riskFromKey(String? k) => switch (k) {
      'healthy' => Risk.healthy,
      'monitor' => Risk.monitor,
      'refer' => Risk.refer,
      _ => null,
    };

String riskKey(Risk r) => r.name;

String riskTitle(Risk r) => switch (r) {
      Risk.healthy => 'Healthy',
      Risk.monitor => 'Monitor',
      Risk.refer => 'Refer',
    };

String riskAdvice(Risk r) => switch (r) {
      Risk.healthy =>
        'No sign of posture-related back risk was found. Keep active, take breaks from sitting, and repeat the check once a year.',
      Risk.monitor =>
        'Some measurements are outside the usual range. Practise good sitting and standing posture, stay active, and repeat the check in three months.',
      Risk.refer =>
        'At least one measurement is well outside the usual range. A check by a physical therapist or doctor is recommended.',
    };

class Limit {
  const Limit(this.mu, this.mon, this.ref);
  final double mu; // reference value (healthy mean)
  final double mon; // |v - mu| >= mon -> monitor  (1.5 sigma)
  final double ref; // |v - mu| >= ref -> refer    (2 sigma)

  Risk levelOf(double v) {
    final d = (v - mu).abs();
    if (d >= ref) return Risk.refer;
    if (d >= mon) return Risk.monitor;
    return Risk.healthy;
  }

  List<double> toJson() => [mu, mon, ref];
}

class Thresholds {
  Thresholds(this.limits, {this.provisional = true});
  final Map<Ind, Limit> limits;
  final bool provisional;

  /// Same provisional defaults as the firmware (triage.h).
  factory Thresholds.defaults() => Thresholds({
        Ind.k: const Limit(38, 12, 16),
        Ind.l: const Limit(-22, 12, 16),
        Ind.n: const Limit(28, 12, 16),
        Ind.f: const Limit(0, 2.25, 3),
        Ind.s: const Limit(0, 3, 4),
        Ind.r: const Limit(0, 3, 5),
      });

  /// Accepts {"K":[mu,mon,ref], ..., "provisional":false}; also the device's "thr" message.
  factory Thresholds.fromJson(Map<String, dynamic> j, {Thresholds? base}) {
    final lim = Map<Ind, Limit>.of((base ?? Thresholds.defaults()).limits);
    for (final i in Ind.values) {
      final a = j[indKey(i)];
      if (a is List && a.length == 3) {
        lim[i] = Limit((a[0] as num).toDouble(), (a[1] as num).toDouble(), (a[2] as num).toDouble());
      }
    }
    return Thresholds(lim, provisional: j['provisional'] == true);
  }

  Map<String, dynamic> toJson() => {
        'provisional': provisional,
        for (final i in Ind.values) indKey(i): limits[i]!.toJson(),
      };

  /// Same checks as validThresholds() in the firmware.
  String? validate() {
    for (final i in Ind.values) {
      final l = limits[i]!;
      if (!(l.mon > 0) || l.ref < l.mon || l.ref > 90 || l.mu.abs() > 90) {
        return '${indKey(i)}: need 0 < monitor ≤ refer ≤ 90 and |reference| ≤ 90';
      }
    }
    return null;
  }
}

Risk worst(Iterable<Risk> levels) =>
    levels.fold(Risk.healthy, (a, b) => a.index >= b.index ? a : b);
