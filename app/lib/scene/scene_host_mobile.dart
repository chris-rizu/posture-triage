// Android / iOS: a three.js scene (one self-contained HTML asset) in a transparent WebView.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebSceneHost {
  WebSceneHost({required this.asset, required this.channel, required this.onMessage}) {
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(channel, onMessageReceived: (m) {
        try {
          onMessage(jsonDecode(m.message) as Map<String, dynamic>);
        } catch (_) {}
      })
      ..loadFlutterAsset(asset);
  }

  final String asset, channel;
  final void Function(Map<String, dynamic>) onMessage;
  late final WebViewController _c;

  void run(String js) => _c.runJavaScript(js).catchError((_) {});

  // horizontal drags turn the model; vertical drags still scroll the page
  static final _gestures = <Factory<OneSequenceGestureRecognizer>>{
    Factory<HorizontalDragGestureRecognizer>(HorizontalDragGestureRecognizer.new),
  };

  Widget build(BuildContext context) => WebViewWidget(controller: _c, gestureRecognizers: _gestures);

  void dispose() {}
}
