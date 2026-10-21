// Fallback for platforms without a web view (unit tests): an empty box.
import 'package:flutter/widgets.dart';

class WebSceneHost {
  WebSceneHost({required this.asset, required this.channel, required this.onMessage});
  final String asset, channel;
  final void Function(Map<String, dynamic>) onMessage;
  void run(String js) {}
  Widget build(BuildContext context) => const SizedBox.expand();
  void dispose() {}
}
