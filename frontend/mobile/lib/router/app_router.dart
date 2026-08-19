import 'package:flutter/material.dart';
import '../page/categories_page.dart';
import '../page/change_password_page.dart';
import '../page/choose_food_type_page.dart';
import '../page/class_food_page.dart';
import '../page/choose_a_health_goal.dart';
import '../page/coming_soon_page.dart';
import '../page/dashboard_page.dart';
import '../page/history_page.dart';
import '../page/menu_food_page.dart';
import '../page/profile_page.dart';
import '../page/register_login_page.dart';
import '../page/report_problem_page.dart';
import '../page/search_page.dart';
import '../page/show_bmi_and_suggested_calories.dart';
import '../services/dashboard_service_factory.dart';
import '../services/food_item_service.dart';
import '../services/meal_log_service.dart';

// =============================================================================
// Routing tree ของแอป (Navigator 1.0 / named routes)
//
// ตรวจ pubspec.yaml แล้วไม่พบ go_router จึงใช้ named routes (onGenerateRoute)
// ตามที่ระบุไว้เป็นทางเลือกสำรอง — ชื่อ route ทุกเส้นตั้งเป็น const string
// ใน [AppRoutes] ด้านล่าง เผื่ออนาคตต้องรองรับ deep link จริง (uni_links/
// app_links) ก็ผูกกับชื่อ route พวกนี้ได้ทันทีโดยไม่ต้องแก้จุดอื่น
//
//   /                          [✅ ผูกแล้ว] MainScreen — grid หน้าแรก
//   │  (root ของ tab "หน้าหลัก" ใน RootShell — ผูกที่ main.dart โดยตรง
//   │   ไม่ได้อยู่ใน _builders ด้านล่าง กันไม่ให้ app_router.dart ต้อง
//   │   import main.dart กลับ เกิด circular import — onGenerateRoute คืน
//   │   null สำหรับ "/" โดยตั้งใจ ดูคอมเมนต์ที่ onGenerateRoute ด้านล่าง)
//   │
//   ├─ /dashboard              [✅ ผูกแล้ว] DashboardPage (mock data)
//   │  ├─ /class-food          [✅ ผูกแล้ว] ClassFoodPage      (shortcut)
//   │  ├─ /history             [✅ ผูกแล้ว] HistoryPage        (shortcut)
//   │  └─ /personal-info       [✅ ผูกแล้ว] PersonalInformationPage (shortcut)
//   │
//   /search                    [✅ ผูกแล้ว] SearchPage   — bottom nav "ค้นหา"
//   /categories                [✅ ผูกแล้ว] CategoriesPage — bottom nav "เมนู"
//   /history                   [✅ ผูกแล้ว] HistoryPage  — bottom nav "ประวัติ"
//                              (root ของ tab "ประวัติ" ใน RootShell)
//   /class-food                [✅ ผูกแล้ว] ClassFoodPage
//   /menu-food                 [✅ ผูกแล้ว] MenuFoodPage
//   /personal-info             [✅ ผูกแล้ว] PersonalInformationPage
//   /meal/select               [✅ ผูกแล้ว] MealSelectionPage (ใหม่ — แทนที่
//                              choose_your_meal_and_duration.dart เดิมที่จุด
//                              เข้าแบบ "เริ่มใหม่" ทั้งหมด — ไฟล์เดิมถูกลบแล้ว
//                              (ยืนยันว่าไม่มีจุด import ไหนเรียกใช้เลยในทั้ง
//                              repo ก่อนลบ — ดู BUG_REPORT.md BUG-032)
//
//   /meal/choose-food          [✅ ผูกแล้ว] ChooseFoodTypePage — ปลายทางของ
//                              ปุ่ม "หน้าถัดไป" ใน MealSelectionPage
//                              (หน้านี้ไม่รับ constructor parameter เลย —
//                              จัดการ id ที่เลือกเองภายใน state จึงผูกเป็น
//                              named route ตรงๆ ได้ ต่างจาก
//                              ChooseYourMealAndDurationPage เดิม)
//   /health-goal               [✅ ผูกแล้ว] ChooseAHealthGoal (userId มี default)
//   /bmi                       [✅ ผูกแล้ว] ShowBMIAndSuggestedCalories (ทุก
//                              parameter มี default เป็น '' หมด)
//   /report-problem            [✅ ผูกแล้ว] ReportProblemPage
//   /login                     [✅ ผูกแล้ว] RegisterLoginPage
//   /change-password           [✅ ผูกแล้ว] ChangePasswordPage (parameter
//                              ทั้งหมดเป็น nullable/optional)
//
//   ---- ตั้งใจไม่ implement เป็น named route (ตกไปที่ ComingSoonPage) ----
//   /meal/summary              [🚧 ตั้งใจไม่ผูก] SelectionSummaryPage — ทุก
//                              constructor parameter เป็น `required` หมด
//                              (meal, duration, foodName, dessertName,
//                              drinkName, totalCalories) คือชื่อ/แคลอรีของ
//                              เมนูที่ผู้ใช้เพิ่งเลือกจริง ไม่มีค่า default ที่
//                              สมเหตุสมผล จะใส่ค่าว่างๆ ไปก็แค่ทำให้ดูเหมือน
//                              หน้าพัง ไม่ใช่ทำให้หน้าใช้งานได้จริง
//                              หน้านี้ "เชื่อมจริง" อยู่แล้วในโค้ดเดิม —
//                              choose_food_type_page.dart:1539 push
//                              SelectionSummaryPage(...) พร้อมข้อมูลจริงตอน
//                              ผู้ใช้เลือกเมนูเสร็จ ที่ไม่ได้ผูกคือแค่ route
//                              ชื่อ `/meal/summary` แบบ deep-link ทั่วไปที่ไม่
//                              มี context จะเอาข้อมูลมาจากไหน
//
// งานนี้ผูกทุก route ที่ปลายทางสร้างได้โดยไม่ต้องพกพารามิเตอร์เฉพาะ (ทุก
// constructor field มี default/nullable) เหลือแค่ /meal/summary ที่ตั้งใจ
// ไม่ผูกตามเหตุผลข้างบน — ส่วน route ที่เดิมเปิดผ่าน MaterialPageRoute ตรงๆ
// จากหน้าอื่นในแอป (เช่น flow เลือกเมนู/สรุปรายการ) ยังคงเปิดแบบเดิม ไม่กระทบ
// =============================================================================

/// ชื่อ route ทั้งหมด — ใช้ constant string เพื่อกัน typo และเตรียมไว้
/// สำหรับ deep link ในอนาคต (แม้ยังไม่มี intent-filter/universal link จริง)
class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const search = '/search';
  static const history = '/history';
  static const categories = '/categories';
  static const dashboard = '/dashboard';
  static const classFood = '/class-food';
  static const menuFood = '/menu-food';
  static const personalInfo = '/personal-info';
  static const mealChooseFood = '/meal/choose-food';
  static const healthGoal = '/health-goal';
  static const bmi = '/bmi';
  static const reportProblem = '/report-problem';
  static const login = '/login';

  // ตั้งใจไม่มี builder จริง — ดูเหตุผลในไดอะแกรมด้านบน (ต้องพก selection
  // state ที่เพิ่งเลือกจริง ไม่มีค่า default ที่สมเหตุสมผล) เรียกแล้วจะได้
  // ComingSoonPage
  static const mealSummary = '/meal/summary';
  static const changePassword = '/change-password';
}

/// แปลงชื่อ route -> หน้าจริง ใช้ร่วมกันทั้ง root [Navigator] ของแอปและ
/// nested [Navigator] ของแต่ละ tab ใน RootShell (ดู main.dart)
///
/// ไม่รวม [AppRoutes.home] ไว้ในนี้โดยตั้งใจ — MainScreen ประกาศอยู่ใน
/// main.dart ถ้า import มาที่นี่จะเกิด circular import (main.dart ก็ต้อง
/// import ไฟล์นี้เพื่อใช้ AppRoutes/AppRouter เช่นกัน) จึงให้ tab "หน้าหลัก"
/// ใน RootShell ผูก AppRoutes.home กับ MainScreen เองโดยตรงแทน
class AppRouter {
  AppRouter._();

  static final Map<String, WidgetBuilder> _builders = {
    AppRoutes.search: (_) => const SearchPage(),
    AppRoutes.categories: (_) => const CategoriesPage(),
    AppRoutes.history: (_) => HistoryPage(),
    AppRoutes.dashboard: (_) => DashboardPage(
      dashboardService: createDashboardService(),
      mealLogService: createMealLogService(),
      foodItemService: createFoodItemService(),
    ),
    AppRoutes.classFood: (_) => ClassFoodPage(),
    AppRoutes.menuFood: (_) => MenuFoodPage(),
    AppRoutes.personalInfo: (_) => const ProfilePage(),
    AppRoutes.mealChooseFood: (_) => const ChooseFoodTypePage(),
    AppRoutes.healthGoal: (_) => const ChooseAHealthGoal(),
    AppRoutes.bmi: (_) => const ShowBMIAndSuggestedCalories(),
    AppRoutes.reportProblem: (_) => const ReportProblemPage(),
    AppRoutes.login: (_) => const RegisterLoginPage(),
    AppRoutes.changePassword: (_) => const ChangePasswordPage(),
  };

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    // AppRoutes.home ("/") ต้อง return null ตรงนี้ (ไม่ใช่ ComingSoonPage)
    // เพราะ Flutter สร้าง route ให้ "/" เป็นขั้นแรกเสมอเมื่อ initialRoute ของ
    // Navigator มีความยาวมากกว่า 1 ตัวอักษร (ดู
    // Navigator.defaultGenerateInitialRoutes ที่ split path เป็นหลาย route)
    // เช่น tab "ประวัติ" ใน RootShell ใช้ initialRoute: '/history' — ถ้าคืน
    // ComingSoonPage("/") ตรงนี้แทน null มันจะถูกดันไปแอบอยู่ใต้ HistoryPage
    // ในสแตกเดียวกัน โผล่มาให้เห็นตอนกด back จาก HistoryPage (บั๊กที่เจอจริง)
    if (settings.name == AppRoutes.home) {
      return null;
    }
    final builder = _builders[settings.name];
    if (builder != null) {
      return MaterialPageRoute(builder: builder, settings: settings);
    }
    return MaterialPageRoute(
      builder: (_) => ComingSoonPage(routeName: settings.name ?? 'ไม่ทราบชื่อหน้า'),
      settings: settings,
    );
  }
}
