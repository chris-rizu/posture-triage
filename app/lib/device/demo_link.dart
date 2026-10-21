import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../core/indicators.dart';
import '../core/protocol.dart';
import 'device_link.dart';

/// A virtual wearer's true indicator values (same profiles as firmware simulator.h).
class DemoProfile {
  const DemoProfile(this.key, this.label, this.v);
  final String key, label;
  final Map<Ind, double> v;

  String get short => switch (key) {
        'healthy' => 'Healthy',
        'rounded' => 'Rounded back',
        'asymmetric' => 'Uneven',
        _ => 'Rotation',
      };
}

const demoProfiles = [
  DemoProfile('healthy', 'Healthy posture', {Ind.k: 38, Ind.l: -22, Ind.n: 28, Ind.f: 0.3, Ind.s: 0.5, Ind.r: 1.2}),
  DemoProfile('rounded', 'Rounded upper back', {Ind.k: 56, Ind.l: -18, Ind.n: 41, Ind.f: 0.5, Ind.s: 1.0, Ind.r: 1.5}),
  DemoProfile('asymmetric', 'Mild asymmetry', {Ind.k: 40, Ind.l: -24, Ind.n: 29, Ind.f: 2.6, Ind.s: 3.4, Ind.r: 4.0}),
  DemoProfile('scoliotic', 'Trunk rotation (scoliosis sign)', {Ind.k: 42, Ind.l: -26, Ind.n: 30, Ind.f: 3.5, Ind.s: 4.6, Ind.r: 7.5}),
];

/// The built-in demo harness. It speaks the same protocol as the firmware
/// (measurement packets and JSON messages) so every screen can be tried
/// without the hardware. [speed] > 1 shortens the trials for quick demos.
///
/// This works at the message level; the firmware's SIMULATE build is the
/// sensor-level simulator that exercises the real filter and trial logic.
class DemoDeviceLink implements DeviceLink {
  DemoDeviceLink({String profile = 'healthy', this.speed = 1.0, int seed = 3})
      : _rng = Random(seed),
        _profile = demoProfiles.firstWhere((p) => p.key == profile, orElse: () => demoProfiles.first) {
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
    Future.microtask(_status);
  }

  final double speed;
  final Random _rng;
  DemoProfile _profile;
  final _measCtl = StreamController<Measurement>.broadcast();
  final _msgCtl = StreamController<Map<String, dynamic>>.broadcast();
  final _done = Completer<void>();
  late final Timer _timer;

  DevState _state = DevState.idle;
  bool _calibrated = false, _fidget = false, _manualPose = false;
  String _pose = 'stand'; // stand | bend | slouch
  double _bend = 0, _slouch = 0, _t = 0, _phase = 0;
  int _seq = 0, _lastProgress = -1;
  Thresholds _thr = Thresholds.defaults();
  final List<Map<Ind, double>> _stand = [], _bendTrials = [];
  final Map<Ind, double> _over = {};
  double _cooldown = 0;

  DemoProfile get profile => _profile;

  @override
  String get name => 'Demo harness';
  @override
  bool get isDemo => true;
  @override
  Stream<Measurement> get measurements => _measCtl.stream;
  @override
  Stream<Map<String, dynamic>> get messages => _msgCtl.stream;
  @override
  Future<void> get done => _done.future;

  double _g() {
    // Gaussian (Box-Muller)
    final u1 = max(_rng.nextDouble(), 1e-9), u2 = _rng.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  void _emit(Map<String, dynamic> m) => Future.microtask(() {
        if (!_msgCtl.isClosed) _msgCtl.add(m);
      });

  // ------------------------------------------------------------------ pod angles
  ({List<double> s, List<double> f, List<double> r}) _angles() {
    final v = _profile.v;
    final s1 = v[Ind.n]!, s2 = s1 - v[Ind.k]!, s3 = s2 - v[Ind.l]!;
    final scap = s2 + 0.55 * v[Ind.k]!;
    final s = [s1, s2, s3, scap, scap];
    final f = [0.5 * v[Ind.f]!, v[Ind.f]!, 0.6 * v[Ind.f]!, v[Ind.s]! + 0.4, v[Ind.s]! - 0.4];
    final roll = [0.3 * v[Ind.r]!, 0.55 * v[Ind.r]!, 0.3 * v[Ind.r]!, v[Ind.r]! + 0.3, v[Ind.r]! - 0.3];
    final sl = _slouch * _slouch * (3 - 2 * _slouch);
    final b = _bend * _bend * (3 - 2 * _bend);
    final out = (s: <double>[], f: <double>[], r: <double>[]);
    for (var p = 0; p < 5; p++) {
      var sp = s[p] + (p == 0 ? 18 * sl : 0) + (p >= 3 ? 10 * sl : 0);
      sp += 0.25 * sin(2 * pi * 0.25 * _t + p) + 0.3 * sin(2 * pi * 0.07 * _t) + 0.05 * _g();
      var fp = f[p] + 0.2 * sin(2 * pi * 0.05 * _t) + 0.05 * _g();
      if (_fidget) {
        sp += 6 * sin(2 * pi * 1.1 * _t);
        fp += 4 * sin(2 * pi * 0.9 * _t + 1);
      }
      final bent = 88.0 + (p == 0 ? 6 : (p == 2 ? -14 : 0));
      sp = sp + (bent - sp) * b;
      fp = fp * (1 - b);
      // f is undefined when bent past ~60 deg, r when bent less than ~30 deg (as in the firmware)
      out.s.add(sp);
      out.f.add(sp.abs() > 60 ? double.nan : fp);
      out.r.add(sp.abs() < 30 ? double.nan : roll[p] * b + 0.05 * _g());
    }
    return out;
  }

  Map<Ind, double> _live(List<double> s, List<double> f, List<double> r) {
    final scap = ((r[3] + r[4]) / 2).abs();
    final tl = r[1].abs();
    return {
      Ind.k: s[0] - s[1],
      Ind.l: s[1] - s[2],
      Ind.n: s[0],
      Ind.f: f[1],
      Ind.s: (f[3] + f[4]) / 2,
      Ind.r: (scap.isNaN || tl.isNaN) ? double.nan : max(scap, tl),
    };
  }

  // ------------------------------------------------------------------ 5 Hz tick
  void _tick() {
    const dt = 0.2;
    _t += dt;
    final goalBend = _pose == 'bend' ? 1.0 : 0.0, goalSlouch = _pose == 'slouch' ? 1.0 : 0.0;
    _bend += (goalBend - _bend).clamp(-dt / 0.8, dt / 0.8);
    _slouch += (goalSlouch - _slouch).clamp(-dt / 2, dt / 2);
    final a = _angles();
    final live = _live(a.s, a.f, a.r);

    final scaled = dt * speed;
    switch (_state) {
      case DevState.calibrating:
        _phase += scaled;
        if (_phase >= 3) {
          final ok = !_fidget;
          _calibrated = _calibrated || ok;
          _emit(ok ? {'t': 'cal', 'ok': true} : {'t': 'cal', 'ok': false, 'why': 'moved', 'pod': 1});
          _setState(DevState.idle);
        }
      case DevState.stand:
      case DevState.bend:
        _phase += scaled;
        final stand = _state == DevState.stand;
        final dur = stand ? 30.0 : 5.0;
        final sec = _phase.round();
        if (sec != _lastProgress && _phase < dur) {
          _lastProgress = sec;
          _emit({'t': 'progress', 'kind': stand ? 'stand' : 'bend', 'sec': sec, 'of': dur.round()});
        }
        if (_phase >= dur) _finishTrial(stand, a);
      case DevState.monitor:
        if (_cooldown > 0) _cooldown -= scaled;
        for (final i in [Ind.k, Ind.n, Ind.f, Ind.s]) {
          final v = live[i]!;
          final over = !v.isNaN && _thr.limits[i]!.levelOf(v) != Risk.healthy;
          _over[i] = over ? (_over[i] ?? 0) + scaled : 0;
          if (_cooldown <= 0 && _over[i]! >= 10) {
            _emit({'t': 'alert', 'ind': indKey(i), 'v': double.parse(v.toStringAsFixed(1))});
            _cooldown = 30;
            _over.clear();
            break;
          }
        }
      default:
        break;
    }

    var flags = MeasFlags.simulated;
    if (_calibrated) flags |= MeasFlags.calibrated;
    if (_fidget || (_bend > 0.02 && _bend < 0.98)) flags |= MeasFlags.moving;
    _measCtl.add(Measurement(
      state: _state,
      seq: _seq++ & 0xFFFF,
      s: a.s,
      f: a.f,
      r: a.r,
      ind: live,
      batteryMv: 3950 - (_t / 60).round(),
      flags: flags,
    ));
  }

  double _r2(double v) => double.parse(v.toStringAsFixed(2));

  void _finishTrial(bool stand, ({List<double> s, List<double> f, List<double> r}) a) {
    final kind = stand ? 'stand' : 'bend';
    String why = '';
    if (_fidget) why = 'moved';
    if (!stand && _pose != 'bend') why = 'not_bent'; // the virtual wearer did not bend
    final ok = why.isEmpty;
    final ind = <Ind, double>{};
    if (stand) {
      for (final i in [Ind.k, Ind.l, Ind.n, Ind.f, Ind.s]) {
        ind[i] = _profile.v[i]! + 0.25 * _g();
      }
    } else {
      ind[Ind.r] = _profile.v[Ind.r]! + 0.25 * _g();
    }
    if (ok) {
      final list = stand ? _stand : _bendTrials;
      list.add(ind);
      if (list.length > 3) list.removeAt(0);
    }
    final pods = stand
        ? {'s': a.s.map(_r2).toList(), 'f': a.f.map(_r2).toList()}
        : {'s': a.s.map(_r2).toList(), 'r': a.r.map((v) => v.isNaN ? null : _r2(v)).toList()};
    _emit({
      't': 'trial',
      'kind': kind,
      'ok': ok,
      'why': why,
      'n': stand ? _stand.length : _bendTrials.length,
      'ind': {for (final e in ind.entries) indKey(e.key): _r2(e.value)},
      'pods': pods,
    });
    if (!_manualPose && !stand) _pose = 'stand';
    _setState(DevState.idle);
  }

  void _setState(DevState s) {
    _state = s;
    _phase = 0;
    _lastProgress = -1;
    if (s != DevState.stand && s != DevState.bend) _status();
  }

  void _status() => _emit({
        't': 'status',
        'state': switch (_state) {
          DevState.lowBattery => 'low_battery',
          _ => _state.name,
        },
        'cal': _calibrated,
        'bat': 3.95,
        'sim': true,
        'fw': 'demo',
        'stand': _stand.length,
        'bend': _bendTrials.length,
        'provisional': _thr.provisional,
        'sensors': [1, 1, 1, 1, 1],
      });

  void _err(String msg) => _emit({'t': 'err', 'msg': msg});

  bool get _busy => _state == DevState.calibrating || _state == DevState.stand || _state == DevState.bend;

  void _result() {
    final complete = _stand.length == 3 && _bendTrials.length == 3;
    var agree = true;
    final retake = <String>{};
    final ind = <String, dynamic>{};
    final levels = <Risk>[];
    for (final i in Ind.values) {
      final list = (i == Ind.r ? _bendTrials : _stand).map((t) => t[i]!).toList();
      if (list.isEmpty) {
        ind[indKey(i)] = [null, null, null];
        continue;
      }
      final mean = list.reduce((a, b) => a + b) / list.length;
      final range = list.reduce(max) - list.reduce(min);
      final lvl = _thr.limits[i]!.levelOf(mean);
      levels.add(lvl);
      if (range > 3) {
        agree = false;
        retake.add(i == Ind.r ? 'bend' : 'stand');
      }
      ind[indKey(i)] = [_r2(mean), _r2(range), riskKey(lvl)];
    }
    final risk = complete && agree ? riskKey(worst(levels)) : null;
    _emit({
      't': 'result',
      'complete': complete,
      'agree': agree,
      'risk': risk,
      'stand': _stand.length,
      'bend': _bendTrials.length,
      'retake': retake.toList(),
      'provisional': _thr.provisional,
      'ind': ind,
    });
  }

  @override
  Future<void> send(String command) async {
    final text = command.trim();
    final sp = text.indexOf(' ');
    final kw = sp < 0 ? text : text.substring(0, sp);
    final arg = sp < 0 ? '' : text.substring(sp + 1).trim();
    switch (kw) {
      case 'PING':
        _emit({'t': 'pong'});
      case 'STATUS':
        _status();
      case 'CAL':
        if (_busy) return _err('busy');
        _setState(DevState.calibrating);
      case 'STAND':
      case 'BEND':
        if (_busy) return _err('busy');
        if (!_calibrated) return _err('not_calibrated');
        if (kw == 'BEND' && !_manualPose) _pose = 'bend';
        _setState(kw == 'STAND' ? DevState.stand : DevState.bend);
      case 'RESULT':
        _result();
      case 'CLEAR':
        _stand.clear();
        _bendTrials.clear();
        if (_busy && _state != DevState.calibrating) _setState(DevState.idle);
        _status();
      case 'MONITOR':
        if (_busy) return _err('busy');
        if (!_calibrated) return _err('not_calibrated');
        _over.clear();
        _cooldown = 0;
        _setState(DevState.monitor);
      case 'STOP':
        if (_state == DevState.stand || _state == DevState.bend) {
          _emit({'t': 'trial', 'kind': _state == DevState.stand ? 'stand' : 'bend', 'ok': false, 'why': 'aborted'});
          if (!_manualPose) _pose = 'stand';
        }
        _setState(DevState.idle);
      case 'THR':
        try {
          final t = Thresholds.fromJson(jsonDecode(arg) as Map<String, dynamic>, base: _thr);
          if (t.validate() != null) return _err('bad_thresholds');
          _thr = t;
          _emit({'t': 'thr', ..._thr.toJson()});
        } catch (_) {
          _err('bad_thresholds');
        }
      case 'GETTHR':
        _emit({'t': 'thr', ..._thr.toJson()});
      case 'SIM':
        if (!_sim(arg)) return _err('sim_unavailable');
        _status();
      default:
        _err('unknown_command');
    }
  }

  bool _sim(String arg) {
    final w = arg.toLowerCase().split(RegExp(r'\s+'));
    if (w.length != 2) return false;
    switch (w[0]) {
      case 'profile':
        final p = demoProfiles.where((p) => p.key == w[1]);
        if (p.isEmpty) return false;
        _profile = p.first;
        return true;
      case 'pose':
        if (w[1] == 'auto') {
          _manualPose = false;
          _pose = 'stand';
          return true;
        }
        if (!['stand', 'bend', 'slouch'].contains(w[1])) return false;
        _pose = w[1];
        _manualPose = true;
        return true;
      case 'fidget':
        _fidget = w[1] == 'on';
        return w[1] == 'on' || w[1] == 'off';
      case 'noise':
        return true;
    }
    return false;
  }

  @override
  Future<void> close() async {
    _timer.cancel();
    if (!_done.isCompleted) _done.complete();
  }
}
