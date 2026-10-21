// Browser build: a three.js scene in a same-origin iframe.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

int _nextId = 0;

class WebSceneHost {
  WebSceneHost({required this.asset, required this.channel, required this.onMessage}) {
    _viewType = 'scene-${_nextId++}';
    _frame = web.HTMLIFrameElement()
      ..src = 'assets/$asset'
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.background = 'transparent'
      ..setAttribute('allowtransparency', 'true');
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _frame);
    _listener = ((web.MessageEvent e) {
      if (e.source != _frame.contentWindow) return;
      final data = e.data;
      if (data == null) return;
      final key = channel == 'SkelHost' ? 'skel' : 'buko';
      final msg = (data as JSObject).getProperty<JSAny?>(key.toJS);
      if (msg == null) return;
      final s = web.window.getProperty<JSObject>('JSON'.toJS).callMethod<JSString>('stringify'.toJS, msg).toDart;
      onMessage(jsonDecode(s) as Map<String, dynamic>);
    }).toJS;
    web.window.addEventListener('message', _listener);
  }

  final String asset, channel;
  final void Function(Map<String, dynamic>) onMessage;
  late final String _viewType;
  late final web.HTMLIFrameElement _frame;
  late final JSFunction _listener;

  void run(String js) {
    final w = _frame.contentWindow;
    if (w == null) return;
    try {
      (w as JSObject).callMethod('eval'.toJS, js.toJS);
    } catch (_) {}
  }

  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);

  void dispose() => web.window.removeEventListener('message', _listener);
}
