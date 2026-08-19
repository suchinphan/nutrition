// =============================================================
// app_theme.dart — แปลง styles.css เป็น Flutter theme
// วางไว้ที่ lib/theme/app_theme.dart แล้วใช้:
//   MaterialApp(theme: AppTheme.light, ...)
// ต้องมี google_fonts ใน pubspec.yaml
// =============================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// สีทั้งหมด — ตรงกับ :root ใน styles.css
class AppColors {
  AppColors._();

  static const paper = Color(0xFFF7F4EC);         // --paper
  static const ink = Color(0xFF000000);           // --ink
  static const inkSoft = Color(0xFF6B6357);       // --ink-soft
  static const leaf = Color(0xFF2F5D3A);          // --leaf
  static const leafLight = Color(0xFFDCEBD9);     // --leaf-light
  static const turmeric = Color(0xFFD9A02C);      // --turmeric
  static const turmericLight = Color(0xFFF7E6BE); // --turmeric-light
  static const chili = Color(0xFFB84B32);         // --chili
  static const chiliLight = Color(0xFFF3DCD3);    // --chili-light
  static const card = Color(0xFFFFFFFF);          // --card
  static const line = Color(0xFFE7E1D2);          // --line
  static const danger = Color(0xFFC0392B);        // --danger
  static const dangerLight = Color(0xFFFBE6E2);   // --danger-light
}

/// ระยะห่าง — ตรงกับ --space-* ใน styles.css
class AppSpace {
  AppSpace._();
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
}

/// มุมโค้ง — ตรงกับ --radius-*
class AppRadius {
  AppRadius._();
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 22.0;
  static final pill = BorderRadius.circular(999);
  static final rSm = BorderRadius.circular(sm);
  static final rMd = BorderRadius.circular(md);
  static final rLg = BorderRadius.circular(lg);
}

/// เงามาตรฐาน — ตรงกับ --shadow
class AppShadow {
  AppShadow._();
  static final card = [
    BoxShadow(
      color: AppColors.ink.withValues(alpha: 0.07),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Theme หลักของแอป
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(useMaterial3: true);

    // ฟอนต์ทางการเดียวกันทั้งแอป (Noto Sans Thai) แยกด้วยน้ำหนักตามบทบาท
    final display = GoogleFonts.notoSansThai(fontWeight: FontWeight.w700); // หัวข้อ
    final body = GoogleFonts.notoSansThai();                               // เนื้อหา
    final ui = GoogleFonts.notoSansThai(fontWeight: FontWeight.w500);      // ปุ่ม/ตัวเลข/ป้าย

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.paper,

      colorScheme: const ColorScheme.light(
        primary: AppColors.leaf,
        onPrimary: Colors.white,
        primaryContainer: AppColors.leafLight,
        onPrimaryContainer: AppColors.leaf,
        secondary: AppColors.turmeric,
        secondaryContainer: AppColors.turmericLight,
        onSecondaryContainer: AppColors.turmeric,
        tertiary: AppColors.chili,
        tertiaryContainer: AppColors.chiliLight,
        onTertiaryContainer: AppColors.chili,
        surface: AppColors.card,
        onSurface: AppColors.ink,
        onSurfaceVariant: AppColors.inkSoft,
        outlineVariant: AppColors.line,
        error: AppColors.danger,
        errorContainer: AppColors.dangerLight,
      ),

      // ตรงกับ --text-* ใน styles.css
      //
      // ใช้ base.textTheme.copyWith(...) แทนการสร้าง TextTheme(...) เปล่าๆ
      // ใหม่ทั้งก้อน — เพราะพบบั๊กจริง: สร้าง TextTheme ใหม่แบบเปล่าจะ "แทนที่"
      // ทุก role ของ Typography เริ่มต้นของ Material 3 ทำให้ role ที่ไม่ได้
      // ระบุไว้ (bodyLarge, titleLarge, labelLarge ฯลฯ) กลายเป็น null หมด —
      // และ TextField ใช้ textTheme.bodyLarge เป็นสีตัวอักษรเริ่มต้นเสมอ
      // (ดู Flutter TextField source: `_m3InputStyle` -> `textTheme.bodyLarge`)
      // ผลคือทุกช่องกรอกข้อความในแอปที่ไม่ได้ตั้ง style เองตรงๆ จะได้สี null
      // (เรนเดอร์จางเกือบขาว มองไม่เห็นบนพื้นสว่าง) ตามที่เจอในหน้า login และ
      // หน้าเลือกเมนู .copyWith บน base.textTheme จะคงค่า default ของ role
      // ที่ไม่ได้ระบุไว้ (ซึ่งคำนวณจาก colorScheme.onSurface ที่ตั้งเป็น
      // AppColors.ink ไว้แล้วด้านบน) แก้ปัญหานี้ทั้งแอปในจุดเดียว
      textTheme: base.textTheme.copyWith(
        headlineSmall: display.copyWith(fontSize: 21, color: AppColors.ink),   // --text-display
        titleMedium: display.copyWith(fontSize: 16, color: AppColors.ink),     // --text-title
        bodyMedium: body.copyWith(fontSize: 13.5, color: AppColors.ink),       // --text-body
        bodySmall: body.copyWith(fontSize: 11.5, color: AppColors.inkSoft),    // --text-caption
        labelMedium: ui.copyWith(
            fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ink),  // --text-label
        // ตัวเลขสถิติใหญ่ (.stat-value)
        headlineMedium: ui.copyWith(
            fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink),
      ),

      // AppBar → .appbar
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.paper,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: display.copyWith(fontSize: 17, color: AppColors.ink),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),

      // Card → .card
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.rMd,
          side: const BorderSide(color: AppColors.line),
        ),
        margin: EdgeInsets.zero,
      ),

      // FilledButton → .btn-primary
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.leaf,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.line,
          disabledForegroundColor: AppColors.inkSoft,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
          textStyle: ui.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // TextButton → .btn-secondary
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          backgroundColor: AppColors.leafLight,
          foregroundColor: AppColors.leaf,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
          textStyle: ui.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),

      // TextField → .input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        hintStyle: body.copyWith(fontSize: 14, color: AppColors.inkSoft),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: AppRadius.rSm,
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.rSm,
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.rSm,
          borderSide: const BorderSide(color: AppColors.leaf, width: 2),
        ),
      ),

      // Chip → .chip
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.leafLight,
        labelStyle: ui.copyWith(
            fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.leaf),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      ),

      // LinearProgressIndicator → .progress-track / .progress-fill
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.turmeric,
        linearTrackColor: AppColors.line,
        linearMinHeight: 8,
      ),

      // NavigationBar → .bottomnav
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.leaf,
        indicatorColor: Colors.white.withValues(alpha: 0.15),
        labelTextStyle: WidgetStatePropertyAll(
          ui.copyWith(fontSize: 10, color: Colors.white),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : Colors.white.withValues(alpha: 0.65),
            size: 20,
          ),
        ),
      ),

      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
    );
  }
}

// =============================================================
// Widget ช่วยที่ใช้บ่อย (ตรงกับ component ใน CSS)
// =============================================================

/// .card-hero — การ์ดพื้นเขียวเข้มสำหรับ hero/summary
class HeroCard extends StatelessWidget {
  final Widget child;
  const HeroCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.leaf,
        borderRadius: AppRadius.rLg,
      ),
      child: child,
    );
  }
}

/// .chip พร้อมเลือกโทนสี
enum ChipTone { leaf, turmeric, chili, danger }

class ToneChip extends StatelessWidget {
  final String label;
  final ChipTone tone;
  const ToneChip(this.label, {super.key, this.tone = ChipTone.leaf});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      ChipTone.leaf => (AppColors.leafLight, AppColors.leaf),
      ChipTone.turmeric => (AppColors.turmericLight, AppColors.turmeric),
      ChipTone.chili => (AppColors.chiliLight, AppColors.chili),
      ChipTone.danger => (AppColors.dangerLight, AppColors.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.pill),
      child: Text(
        label,
        style: GoogleFonts.prompt(
            fontSize: 12, fontWeight: FontWeight.w500, color: fg),
      ),
    );
  }
}

/// .tile — แถวรายการมีไอคอนซ้าย (ใช้แทน ListTile ให้ตรงดีไซน์)
class AppTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final ChipTone tone;
  final Widget? trailing;
  final VoidCallback? onTap;

  const AppTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tone = ChipTone.leaf,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      ChipTone.leaf => (AppColors.leafLight, AppColors.leaf),
      ChipTone.turmeric => (AppColors.turmericLight, AppColors.turmeric),
      ChipTone.chili => (AppColors.chiliLight, AppColors.chili),
      ChipTone.danger => (AppColors.dangerLight, AppColors.danger),
    };
    return Material(
      color: AppColors.card,
      borderRadius: AppRadius.rMd,
      child: InkWell(
        borderRadius: AppRadius.rMd,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: AppRadius.rMd,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration:
                    BoxDecoration(color: bg, borderRadius: AppRadius.rSm),
                child: Icon(icon, size: 20, color: fg),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.inkSoft)),
                  ],
                ),
              ),
              trailing ??
                  const Icon(Icons.chevron_right,
                      color: AppColors.inkSoft, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// .stat-value + .stat-label — ช่องสถิติใน dashboard
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Widget? footer; // เช่น Text delta หรือ ToneChip
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: AppRadius.rMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: GoogleFonts.prompt(
                      fontSize: 22, fontWeight: FontWeight.w600)),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(unit!, style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
          if (footer != null) ...[const SizedBox(height: 4), footer!],
        ],
      ),
    );
  }
}
