// The live skeleton twin: an anatomical skeleton (BodyParts3D) whose spine is
// posed from the five sensor pods. The scene is assets/skeleton/skeleton.html,
// built by skeleton/web/build.mjs; this widget feeds it every measurement, or a
// fixed posture (a saved result).
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/indicators.dart';
import '../core/protocol.dart';
import '../device/harness.dart';
import '../scene/scene_host.dart';

enum TwinView { back, side, three, front }

class LiveSkeleton extends StatefulWidget {
  const LiveSkeleton({
    super.key,
    this.harness,
    this.fixed,
    this.thresholds,
    this.view = TwinView.three,
    this.spineFocus = false,
    this.amplify = false,
    this.labels = true,
    this.height = 460,
    this.active = true,
  });

  /// Live source. Ignored when [fixed] is given.
  final Harness? harness;

  /// A fixed posture to show (for example the mean of a result's standing trials).
  final Measurement? fixed;
  final Thresholds? thresholds;
  final TwinView view;
  final bool spineFocus, amplify, labels;
  final double height;

  /// False while the screen holding it is hidden: rendering pauses.
  final bool active;

  @override
  State<LiveSkeleton> createState() => _LiveSkeletonState();
}

class _LiveSkeletonState extends State<LiveSkeleton> {
  late final WebSceneHost _host =
      WebSceneHost(asset: 'assets/skeleton/skeleton.html', channel: 'SkelHost', onMessage: _onMessage);
  bool _ready = false;
  int _lastSeq = -1;

  @override
  void initState() {
    super.initState();
    widget.harness?.addListener(_onData);
  }

  @override
  void didUpdateWidget(LiveSkeleton old) {
    super.didUpdateWidget(old);
    if (old.harness != widget.harness) {
      old.harness?.removeListener(_onData);
      widget.harness?.addListener(_onData);
    }
    _pushSettings();
    if (old.fixed != widget.fixed) {
      _lastSeq = -1;
      _onData();
    }
  }

  @override
  void dispose() {
    widget.harness?.removeListener(_onData);
    _host.dispose();
    super.dispose();
  }

  void _onMessage(Map<String, dynamic> m) {
    if (!mounted) return;
    if (m['type'] == 'ready') {
      _ready = true;
      _pushSettings();
      _onData();
    }
  }

  void _pushSettings() {
    if (!_ready) return;
    _host.run("skel.setView('${widget.view.name}');skel.setFocus(${widget.spineFocus});"
        'skel.setAmplify(${widget.amplify ? 2 : 1});skel.setLabels(${widget.labels});skel.setPaused(${!widget.active});');
  }

  void _onData() {
    final m = widget.fixed ?? widget.harness?.latest;
    if (!_ready || m == null || (widget.fixed == null && m.seq == _lastSeq)) return;
    _lastSeq = m.seq;
    double? n(double v) => v.isNaN ? null : double.parse(v.toStringAsFixed(2));
    final th = widget.thresholds ?? widget.harness?.thresholds ?? Thresholds.defaults();
    final json = jsonEncode({
      's': m.s.map(n).toList(),
      'f': m.f.map(n).toList(),
      'r': m.r.map(n).toList(),
      'ind': {for (final i in Ind.values) indKey(i): n(m.ind[i] ?? double.nan)},
      'lim': {for (final i in Ind.values) indKey(i): th.limits[i]!.toJson()},
      'sensors': widget.harness?.sensors ?? const [1, 1, 1, 1, 1],
      'state': m.state.name,
    });
    _host.run('skel.setLive($json);');
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Skeleton posed from the five sensor pods. Drag sideways to turn it.',
      child: SizedBox(height: widget.height, width: double.infinity, child: _host.build(context)),
    );
  }
}
