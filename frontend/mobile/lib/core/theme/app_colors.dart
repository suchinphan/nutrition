import 'package:flutter/material.dart';

/// Single source of truth ของสีทั้งแอป — ห้าม hardcode Color(...) นอกไฟล์นี้
/// (ดู lib/core/theme/app_theme.dart ที่ประกอบเป็น ThemeData และ
/// lib/core/widgets/* ที่ใช้ชุดนี้ทั้งหมด)
class AppColors {
  AppColors._();

  // Primary (สีหลักของแอป — สุขภาพ ธรรมชาติ)
  static const teal900 = Color(0xFF04342C);
  static const teal700 = Color(0xFF0F6E56);
  static const teal500 = Color(0xFF1D9E75); // ใช้บ่อยที่สุด (primary)
  static const teal300 = Color(0xFF5DCAA5);
  static const teal100 = Color(0xFF9FE1CB);
  static const teal50 = Color(0xFFE1F5EE);

  // Amber (แคลอรี / พลังงาน)
  static const amber500 = Color(0xFFEF9F27);
  static const amber100 = Color(0xFFFAC775);
  static const amber50 = Color(0xFFFAEEDA);

  // Coral (คำเตือน แพ้อาหาร)
  static const coral600 = Color(0xFF993C1D);
  static const coral400 = Color(0xFFD85A30);
  static const coral200 = Color(0xFFF0997B);
  static const coral50 = Color(0xFFFAECE7);

  // Blue (ข้อมูล โปรตีน)
  static const blue600 = Color(0xFF185FA5);
  static const blue400 = Color(0xFF378ADD);
  static const blue50 = Color(0xFFE6F1FB);

  // Neutral
  static const gray900 = Color(0xFF2C2C2A);
  static const gray600 = Color(0xFF5F5E5A);
  static const gray400 = Color(0xFF888780);
  static const gray100 = Color(0xFFD3D1C7);
  static const gray50 = Color(0xFFF1EFE8);
}
