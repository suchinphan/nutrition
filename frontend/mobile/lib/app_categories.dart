import 'package:flutter/material.dart';
import 'page/class_food_page.dart';
import 'page/dashboard_page.dart';
import 'page/history_page.dart';
import 'page/menu_food_page.dart';
import 'page/profile_page.dart';
import 'services/dashboard_service_factory.dart';
import 'services/food_item_service.dart';
import 'services/meal_log_service.dart';

/// รายการหมวดหมู่หลักของแอป — เดิมประกาศซ้ำอยู่ในตัว MainScreen เท่านั้น
/// ตอนนี้แยกออกมาให้ MainScreen (grid หน้าแรก + ค้นหาแบบพิมพ์), SearchPage
/// และ CategoriesPage ใช้ข้อมูลชุดเดียวกัน ไม่ต้องประกาศซ้ำ 3 ที่
///
/// หมายเหตุ: การกดจากหน้านี้ (SearchPage/CategoriesPage) ไปหน้า
/// "เลือกมื้ออาหารและระยะเวลา" จะ**ไม่ผ่าน**การตรวจสอบข้อมูลส่วนตัว/เป้าหมาย
/// สุขภาพก่อน (ต่างจาก grid หน้าแรกที่มี `_canOpenMealPage` คอยกัน) เพราะเป็น
/// การตัดขอบเขตงานนี้ที่โฟกัสที่ routing/back-button ไม่ใช่การย้าย business
/// logic การ gate สิทธิ์ — ถ้าต้องการให้ตรวจสอบเหมือนกันทุกทางเข้า แจ้งได้
List<Map<String, dynamic>> buildAppCategories() => [
  {
    'label': 'แดชบอร์ด',
    'page': DashboardPage(
      dashboardService: createDashboardService(),
      mealLogService: createMealLogService(),
      foodItemService: createFoodItemService(),
    ),
    'asset': null,
    'icon': Icons.dashboard_outlined,
  },
  {
    'label': 'คลาสอาหาร',
    'page': ClassFoodPage(),
    'asset': 'assets/images/คลาสอาหาร.jpg',
    'icon': Icons.restaurant_menu,
  },
  {
    'label': 'เมนูอาหาร',
    'page': MenuFoodPage(),
    'asset': 'assets/images/เมนูอาหาร.jpg',
    'icon': Icons.menu_book,
  },
  {
    'label': 'ประวัติการกรอกข้อมูล',
    'page': HistoryPage(),
    'asset': 'assets/images/ประวัติการกรอกข้อมูล.png',
    'icon': Icons.receipt_long,
  },
  {
    'label': 'ตั้งค่าข้อมูลส่วนตัว',
    'page': const ProfilePage(),
    'asset': 'assets/images/การกรอกข้อมูล.jpg',
    'icon': Icons.person_outline,
  },
];
