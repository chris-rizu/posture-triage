import 'package:flutter/material.dart';

import 'data/record_store.dart';
import 'data/records.dart';
import 'device/harness.dart';
import 'ui/common.dart';
import 'ui/shell.dart';

void main() {
  runApp(PostureTriageApp(harness: Harness(), records: Records(RecordStore.create())));
}

class PostureTriageApp extends StatelessWidget {
  const PostureTriageApp({super.key, required this.harness, required this.records});
  final Harness harness;
  final Records records;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Buko',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        themeMode: ThemeMode.light,
        home: AppShell(harness: harness, records: records),
      );
}
