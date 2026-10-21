import 'package:flutter/material.dart';

import '../core/indicators.dart';
import '../core/score.dart';
import '../core/protocol.dart';
import '../device/harness.dart';

/// Design tokens. The palette comes from kinesiology tape and clinic walls.
class Tok {
  static const wall = Color(0xFFE9EEEA); // page background
  static const panel = Color(0xFFFBFCFB); // cards
  static const ink = Color(0xFF1D2A33); // text
  static const inkSoft = Color(0xFF51606B); // secondary text
  static const line = Color(0xFFC9D3CD); // dividers
  static const blue = Color(0xFF1668C7); // tape blue: primary actions
  static const pink = Color(0xFFE4467C); // tape pink: harness, highlights
  static const healthy = Color(0xFF2F8F5B);
  static const monitor = Color(0xFFC98A06);
  static const refer = Color(0xFFC8323C);
  static const font = 'Atkinson';
}

Color riskColor(Risk? r) => switch (r) {
      Risk.healthy => Tok.healthy,
      Risk.monitor => Tok.monitor,
      Risk.refer => Tok.refer,
      null => Tok.inkSoft,
    };

String fmtDeg(double? v, {int digits = 1}) =>
    (v == null || v.isNaN) ? '—' : '${v.toStringAsFixed(digits)}°';

ThemeData buildTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Tok.blue,
    onPrimary: Colors.white,
    secondary: Tok.pink,
    onSecondary: Colors.white,
    tertiary: Tok.pink,
    onTertiary: Colors.white,
    error: Tok.refer,
    onError: Colors.white,
    surface: Tok.wall,
    onSurface: Tok.ink,
    onSurfaceVariant: Tok.inkSoft,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Tok.panel,
    surfaceContainer: Tok.panel,
    surfaceContainerHigh: Color(0xFFDDE5E0),
    surfaceContainerHighest: Color(0xFFD3DDD7),
    outline: Tok.line,
    outlineVariant: Tok.line,
  );
  // Type scale (px): 13 / 15 / 17 / 20 / 28 / 44, one family, regular and bold.
  const text = TextTheme(
    displayMedium: TextStyle(fontSize: 44, height: 1.05, fontWeight: FontWeight.w700, letterSpacing: -0.8),
    headlineMedium: TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleLarge: TextStyle(fontSize: 20, height: 1.25, fontWeight: FontWeight.w700),
    titleMedium: TextStyle(fontSize: 17, height: 1.3, fontWeight: FontWeight.w700),
    bodyLarge: TextStyle(fontSize: 17, height: 1.45),
    bodyMedium: TextStyle(fontSize: 15, height: 1.45),
    bodySmall: TextStyle(fontSize: 13, height: 1.4),
    labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: Tok.font,
    textTheme: text.apply(bodyColor: Tok.ink, displayColor: Tok.ink),
    scaffoldBackgroundColor: Tok.wall,
    dividerTheme: const DividerThemeData(color: Tok.line, space: 1, thickness: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: Tok.wall,
      foregroundColor: Tok.ink,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: Tok.font, fontSize: 20, fontWeight: FontWeight.w700, color: Tok.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: Tok.font, fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        foregroundColor: Tok.ink,
        side: const BorderSide(color: Tok.ink, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: Tok.font, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Tok.blue,
        textStyle: const TextStyle(fontFamily: Tok.font, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Tok.panel,
      selectedColor: const Color(0xFFD6E4F5),
      secondarySelectedColor: const Color(0xFFD6E4F5),
      labelStyle: const TextStyle(fontFamily: Tok.font, fontSize: 15, color: Tok.ink),
      secondaryLabelStyle: const TextStyle(fontFamily: Tok.font, fontSize: 15, color: Tok.ink),
      checkmarkColor: Tok.blue,
      side: const BorderSide(color: Tok.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? Tok.ink : Tok.panel),
        foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? Colors.white : Tok.ink),
        side: const WidgetStatePropertyAll(BorderSide(color: Tok.line)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: Tok.font, fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Tok.panel,
      indicatorColor: const Color(0xFFD6E4F5),
      height: 66,
      labelTextStyle: WidgetStateProperty.resolveWith((st) => TextStyle(
          fontFamily: Tok.font, fontSize: 12.5, fontWeight: st.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w400,
          color: st.contains(WidgetState.selected) ? Tok.ink : Tok.inkSoft)),
      iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(color: st.contains(WidgetState.selected) ? Tok.blue : Tok.inkSoft)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? Colors.white : Tok.inkSoft),
      trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? Tok.blue : Tok.line),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Tok.ink,
      contentTextStyle: TextStyle(fontFamily: Tok.font, fontSize: 15, color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tok.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tok.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tok.blue, width: 2)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Tok.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Tok.panel),
  );
}

/// Level name in its colour, with a small dot.
class RiskTag extends StatelessWidget {
  const RiskTag(this.risk, {super.key});
  final Risk? risk;

  @override
  Widget build(BuildContext context) {
    final c = riskColor(risk);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(risk == null ? 'No result' : riskTitle(risk!),
          style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 14)),
    ]);
  }
}

/// One line of device status: battery, calibration, the five sensors.
class HarnessStatusBar extends StatelessWidget {
  const HarnessStatusBar(this.h, {super.key});
  final Harness h;

  @override
  Widget build(BuildContext context) {
    final pct = batteryPercent(h.batteryMv);
    final sensors = h.sensors;
    final missing = [for (var i = 0; i < 5; i++) if (i < sensors.length && sensors[i] == 0) 'IMU${i + 1}'];
    const soft = TextStyle(color: Tok.inkSoft, fontSize: 14);
    Widget item(IconData i, String t, {Color color = Tok.inkSoft}) => Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 17, color: color),
            const SizedBox(width: 5),
            Text(t, style: soft.copyWith(color: color)),
          ]),
        );
    return Wrap(runSpacing: 6, children: [
      item(pct < 0 ? Icons.power : (pct < 20 ? Icons.battery_alert : Icons.battery_std),
          pct < 0 ? 'USB power' : 'Battery $pct%', color: pct >= 0 && pct < 20 ? Tok.refer : Tok.inkSoft),
      item(h.calibrated ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          h.calibrated ? 'Calibrated' : 'Not calibrated', color: h.calibrated ? Tok.healthy : Tok.monitor),
      item(Icons.sensors, missing.isEmpty ? '5 of 5 sensors' : '${missing.join(', ')} not responding',
          color: missing.isEmpty ? Tok.inkSoft : Tok.refer),
      if (h.isDemo || h.simulated) item(Icons.science_outlined, h.isDemo ? 'Demo' : 'Simulated sensors', color: Tok.pink),
    ]);
  }
}

/// Sentence-case heading for a group of content.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 28, 0, 10),
        child: Text(text, style: Theme.of(context).textTheme.titleLarge),
      );
}

/// A tappable row in a list: icon, title, one line of explanation, chevron.
class NavRow extends StatelessWidget {
  const NavRow({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap, this.trailing});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          Icon(icon, color: Tok.ink, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.titleMedium),
              const SizedBox(height: 2),
              Text(subtitle, style: t.bodySmall?.copyWith(color: Tok.inkSoft)),
            ]),
          ),
          trailing ?? const Icon(Icons.chevron_right, color: Tok.inkSoft),
        ]),
      ),
    );
  }
}

/// A light raised panel; used sparingly for the one thing on a screen that needs grouping.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.color = Tok.panel});
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(22)),
        child: child,
      );
}

void showSnack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(text)));


/// A white card: the basic container of the tabbed screens.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Tok.panel,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

/// Title with an optional action on the right ("View all").
class CardHeader extends StatelessWidget {
  const CardHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (action != null)
            InkWell(
              onTap: onAction,
              child: Row(children: [
                Text(action!, style: const TextStyle(color: Tok.inkSoft, fontSize: 14)),
                const Icon(Icons.chevron_right, size: 18, color: Tok.inkSoft),
              ]),
            ),
        ]),
      );
}

/// Pill with the level in plain words.
class LevelChip extends StatelessWidget {
  const LevelChip(this.risk, {super.key, this.text});
  final Risk? risk;
  final String? text;
  @override
  Widget build(BuildContext context) {
    final c = riskColor(risk);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
      child: Text(text ?? (risk == null ? 'Incomplete' : levelPhrase(risk!)),
          style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}

String shortDate(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${m[d.month - 1]} ${d.day}, ${d.year}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}
