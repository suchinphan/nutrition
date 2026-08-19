import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

/// ThemeData กลางของแอป (design system ใหม่) — ประกอบจาก [AppColors] และ
/// [AppTextStyles] เท่านั้น ห้ามเติมค่าสี/ขนาดตัวอักษรดิบ (magic value) ที่นี่
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.gray50,

      colorScheme: const ColorScheme.light(
        primary: AppColors.teal500,
        onPrimary: Colors.white,
        primaryContainer: AppColors.teal50,
        onPrimaryContainer: AppColors.teal700,
        secondary: AppColors.amber500,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.amber50,
        onSecondaryContainer: AppColors.amber500,
        surface: Colors.white,
        onSurface: AppColors.gray900,
        onSurfaceVariant: AppColors.gray600,
        outline: AppColors.gray100,
        outlineVariant: AppColors.gray100,
        error: AppColors.coral400,
        onError: Colors.white,
        errorContainer: AppColors.coral50,
        onErrorContainer: AppColors.coral600,
      ),

      // ใช้ .copyWith บน base.textTheme แทนสร้าง TextTheme ใหม่เปล่าๆ — สร้าง
      // ใหม่ทั้งก้อนจะทำให้ role ที่ไม่ได้ระบุ (เช่น bodyLarge ที่ TextField
      // ใช้เป็นสีตัวอักษรเริ่มต้น) กลายเป็น null ไปด้วย
      textTheme: base.textTheme.copyWith(
        headlineSmall: AppTextStyles.headingLarge.copyWith(color: AppColors.gray900),
        titleLarge: AppTextStyles.headingMedium.copyWith(color: AppColors.gray900),
        titleMedium: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900),
        bodyLarge: AppTextStyles.bodyLarge.copyWith(color: AppColors.gray900),
        bodyMedium: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray900),
        bodySmall: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
        labelSmall: AppTextStyles.caption,
        labelLarge: AppTextStyles.labelBold.copyWith(color: AppColors.gray900),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.gray50,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: AppTextStyles.headingMedium.copyWith(color: AppColors.gray900),
        iconTheme: const IconThemeData(color: AppColors.gray900),
      ),

      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.gray100, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray400),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gray100),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gray100),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.teal500, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.coral400),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.coral400, width: 2),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.teal500,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.gray100,
          disabledForegroundColor: AppColors.gray400,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: AppTextStyles.labelBold.copyWith(color: Colors.white),
        ),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.teal500,
        unselectedItemColor: AppColors.gray400,
        selectedLabelStyle: AppTextStyles.caption,
        unselectedLabelStyle: AppTextStyles.caption,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.teal500,
        foregroundColor: Colors.white,
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.teal500,
        linearTrackColor: AppColors.gray100,
        linearMinHeight: 8,
      ),

      dividerTheme: const DividerThemeData(color: AppColors.gray100, thickness: 0.5, space: 1),
    );
  }
}
