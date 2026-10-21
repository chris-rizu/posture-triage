// A 0-100 posture score for people, derived from the triage result.
//
// The thesis outcome is the three-level triage (healthy / monitor / refer). The
// score only summarises it for a lay reader and can never disagree with it: it
// always falls inside the band of the triage level, and its position inside the
// band reflects how close the six indicators are to their reference values.
//   healthy 80-100,  monitor 50-79,  refer 0-49
import 'indicators.dart';

/// 100 at the reference value, 75 at the monitor limit, 50 at the refer limit, 0 well beyond.
double indicatorScore(double v, Limit lim) {
  if (v.isNaN) return 100;
  final d = (v - lim.mu).abs();
  if (d < lim.mon) return 100 - 25 * d / lim.mon;
  if (d < lim.ref) return 75 - 25 * (d - lim.mon) / (lim.ref - lim.mon);
  return (50 - 50 * (d - lim.ref) / lim.ref).clamp(0, 50).toDouble();
}

int postureScore(Map<Ind, double> values, Thresholds th, Risk level) {
  final scores = [for (final i in Ind.values) indicatorScore(values[i] ?? double.nan, th.limits[i]!)];
  final q = scores.reduce((a, b) => a + b) / scores.length / 100;
  final s = switch (level) {
    Risk.healthy => 80 + 20 * q,
    Risk.monitor => 50 + 29 * q,
    Risk.refer => 49 * q,
  };
  return s.round().clamp(0, 100);
}

/// Words people understand, for the triage level.
String levelPhrase(Risk r) => switch (r) {
      Risk.healthy => 'Good posture',
      Risk.monitor => 'Needs improvement',
      Risk.refer => 'See a specialist',
    };

/// Body areas shown to people, each tied to one indicator.
class Area {
  const Area(this.ind, this.name, this.good, this.off);
  final Ind ind;
  final String name;
  final String good; // short status when in range
  final String off; // short status when out of range
}

const areas = [
  Area(Ind.n, 'Neck', 'Within normal range', 'Leaning forward'),
  Area(Ind.k, 'Upper back', 'Within normal range', 'Rounded forward'),
  Area(Ind.l, 'Lower back', 'Within normal range', 'Curve out of range'),
  Area(Ind.s, 'Shoulders', 'Level', 'One side higher'),
  Area(Ind.f, 'Trunk', 'Upright', 'Leaning to one side'),
  Area(Ind.r, 'Spine rotation', 'No rotation seen', 'Rotation in the forward bend'),
];
