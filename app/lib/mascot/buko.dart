// Buko, the 3D mascot (modelled in Blender, rendered with three.js).
//
// The scene lives in assets/mascot/buko.html (built by mascot/web/build.mjs).
// On the phone it runs in a WebView; in the browser build, in an iframe.
//  * Drag sideways to turn Buko; tap Buko to make it wave and hop.
//  * Tap a sensor pod to see that sensor's live angles.
//  * In BukoMode.live its spine follows the wearer's sensor angles, drawn 2x larger.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/indicators.dart';
import '../core/protocol.dart';
import '../scene/scene_host.dart';

enum BukoMode { wave, idle, calibrate, stand, bendDemo, live, celebrate, thinking, concerned }

/// Live data Buko mirrors.
class BukoLive {
  const BukoLive({this.m, this.thresholds, this.sensors = const [1, 1, 1, 1, 1]});
  final Measurement? m;
  final Thresholds? thresholds;
  final List<int> sensors;

  /// JSON for buko.setLive() (NaN becomes null).
  String toJson() {
    double? n(double? v) => (v == null || v.isNaN) ? null : double.parse(v.toStringAsFixed(2));
    final th = thresholds ?? Thresholds.defaults();
    final mm = m;
    return jsonEncode({
      if (mm != null) ...{
        's': mm.s.map(n).toList(),
        'f': mm.f.map(n).toList(),
        'r': mm.r.map(n).toList(),
        'ind': {for (final i in Ind.values) indKey(i): n(mm.ind[i])},
      },
      'mu': {for (final i in [Ind.k, Ind.l, Ind.n]) indKey(i): th.limits[i]!.mu},
      'lim': {for (final i in Ind.values) indKey(i): th.limits[i]!.toJson()},
      'sensors': sensors,
    });
  }
}

class Buko extends StatefulWidget {
  const Buko({super.key, this.mode = BukoMode.idle, this.live, this.height = 300, this.onPodTap, this.active = true});
  final BukoMode mode;
  final BukoLive? live;
  final double height;
  final ValueChanged<int>? onPodTap;

  /// False while hidden: rendering pauses.
  final bool active;

  @override
  State<Buko> createState() => _BukoState();
}

class _BukoState extends State<Buko> {
  late final WebSceneHost _host = WebSceneHost(asset: 'assets/mascot/buko.html', channel: 'BukoHost', onMessage: _onMessage);
  bool _ready = false;
  String? _lastLive;

  void _onMessage(Map<String, dynamic> m) {
    if (!mounted) return;
    if (m['type'] == 'ready') {
      _ready = true;
      _push(force: true);
    } else if (m['type'] == 'pod') {
      widget.onPodTap?.call((m['index'] as num).toInt());
    }
  }

  void _push({bool force = false}) {
    if (!_ready) return;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final js = StringBuffer("buko.setMode('${widget.mode.name}');buko.setReduceMotion($reduce);buko.setPaused(${!widget.active});");
    final live = widget.live?.toJson();
    if (live != null && (force || live != _lastLive)) {
      js.write('buko.setLive($live);');
      _lastLive = live;
    }
    _host.run(js.toString());
  }

  @override
  void didUpdateWidget(Buko old) {
    super.didUpdateWidget(old);
    _push();
  }

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Buko, the posture mascot. Drag sideways to turn Buko, tap to wave, tap a sensor to read it.',
      child: SizedBox(height: widget.height, width: double.infinity, child: _host.build(context)),
    );
  }
}
