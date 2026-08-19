import 'package:flutter/material.dart';
import 'health_goal_cycle.dart';

/// สถานะการกรอกมื้ออาหารแต่ละมื้อในวันนี้ — backend ใหม่ (GET /dashboard/summary)
/// ส่งแค่ logged/pending (ไม่มี missed อีกต่อไป เพราะไม่มีแนวคิด "ล็อกตารางมื้อ"
/// แบบ UserSelection เดิมแล้ว)
enum MealStatus { pending, done }

@immutable
class MealCheckItem {
  final String label; // เช้า / กลางวัน / เย็น (แปลจาก meal_type ฝั่งแอป)
  final MealStatus status;
  const MealCheckItem({required this.label, required this.status});

  factory MealCheckItem.fromJson(Map<String, dynamic> json) => MealCheckItem(
    label: _mealTypeLabelTh(json['meal_type'] as String?),
    status: json['status'] == 'logged' ? MealStatus.done : MealStatus.pending,
  );
}

String _mealTypeLabelTh(String? value) => switch (value) {
  'breakfast' => 'เช้า',
  'lunch' => 'กลางวัน',
  'dinner' => 'เย็น',
  _ => value ?? '',
};

/// แคลอรีของ 1 วัน ใช้กับกราฟ 7 วันย้อนหลัง
@immutable
class DailyCalorie {
  final DateTime date;
  final double consumedKcal;
  final double goalKcal;
  const DailyCalorie({
    required this.date,
    required this.consumedKcal,
    required this.goalKcal,
  });

  bool get isOverGoal => consumedKcal > goalKcal;
}

enum BmiStatus { underweight, normal, overweight, obese }

extension BmiStatusLabelTh on BmiStatus {
  String get labelTh => switch (this) {
    BmiStatus.underweight => 'น้ำหนักต่ำกว่าเกณฑ์',
    BmiStatus.normal => 'ปกติ',
    BmiStatus.overweight => 'น้ำหนักเกิน',
    BmiStatus.obese => 'อ้วน',
  };
}

BmiStatus _bmiStatusFromJson(String? value) => switch (value) {
  'ผอม' => BmiStatus.underweight,
  'ท้วม/น้ำหนักเกิน' => BmiStatus.overweight,
  'อ้วน' => BmiStatus.obese,
  _ => BmiStatus.normal,
};

/// เมนูลัดหนึ่งรายการ แสดงผ่าน AppTile
@immutable
class ShortcutItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const ShortcutItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
}

/// ข้อมูลทั้งหมดของหน้าแดชบอร์ด — ไม่ผูกกับ mock หรือ API ใดโดยเฉพาะ
/// ผู้เรียกใช้ (ดู lib/services/dashboard_service_factory.dart) เป็นผู้ประกอบข้อมูลนี้ขึ้นมา
@immutable
class DashboardData {
  final double caloriesConsumed; // eaten_calories
  final double caloriesPlanned; // planned_calories (รวมที่ยังไม่กดทานแล้ว)
  final double caloriesGoal;
  final List<MealCheckItem> meals;

  final double weightKg;
  final double bmi;
  final BmiStatus bmiStatus;

  final List<DailyCalorie> last7Days; // เรียงเก่า -> ใหม่ ควรมี 7 รายการ
  final List<ShortcutItem> shortcuts;

  // ทานเกิน calories_goal วันนี้แล้ว — การ์ดแคลอรีเปลี่ยนเป็นสีแดง + เตือน
  final bool overLimit;
  // มื้อเย็นถูกบันทึกแล้ว (มี meal_log ของมื้อเย็นวันนี้) — โชว์การ์ดสรุปผล
  // การกินท้ายวันได้ (รายละเอียดการคำนวณ kcal เชิงลึกรอ prompt ถัดไป)
  final bool dinnerLogged;

  // รอบเป้าหมายสุขภาพ 7 วันที่เพิ่งหมดอายุ (22:00 ของวันที่ 7) และผู้ใช้ยัง
  // ไม่เคยเห็น dialog สรุปผล — null ถ้าไม่มี (ยังไม่ครบ 7 วัน หรือรับทราบไป
  // แล้ว) ดู backend api.get_dashboard_summary
  final HealthGoalCycle? goalCycleResult;

  const DashboardData({
    required this.caloriesConsumed,
    required this.caloriesPlanned,
    required this.caloriesGoal,
    required this.meals,
    required this.weightKg,
    required this.bmi,
    required this.bmiStatus,
    required this.last7Days,
    required this.shortcuts,
    this.overLimit = false,
    this.dinnerLogged = false,
    this.goalCycleResult,
  });

  /// ยังไม่มีการบันทึกอะไรเลยวันนี้ (และไม่มีประวัติ 7 วัน) — ใช้ตัดสินสถานะ empty
  bool get isEmpty =>
      caloriesConsumed == 0 &&
      caloriesPlanned == 0 &&
      last7Days.every((d) => d.consumedKcal == 0);

  /// รับ JSON จาก GET /dashboard/summary จริง — [shortcuts] ไม่ได้มาจาก
  /// backend เพราะเป็น UI-only field (ผูก IconData/VoidCallback ของ Flutter
  /// โดยตรง ไม่ serializable) ผู้เรียกใช้ต้องเติมเองฝั่งแอปหลัง fetch
  ///
  /// หมายเหตุ: schema ใหม่ตัด weight_delta_kg/sodium/sugar ออกจาก backend
  /// แล้ว (ไม่มีตารางเก็บประวัติน้ำหนัก/เกลือ/น้ำตาลย้อนหลัง) จึงไม่มีในโมเดลนี้
  /// อีกต่อไป — สถิติ 2 ช่องนั้นถูกถอดออกจากหน้าแดชบอร์ดไปด้วย
  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final goal = (json['calories_goal'] as num).toDouble();
    return DashboardData(
      caloriesConsumed: (json['eaten_calories'] as num).toDouble(),
      caloriesPlanned: (json['planned_calories'] as num).toDouble(),
      caloriesGoal: goal,
      meals: (json['meals'] as List)
          .map((m) => MealCheckItem.fromJson(m as Map<String, dynamic>))
          .toList(),
      weightKg: (json['weight_kg'] as num).toDouble(),
      bmi: (json['bmi'] as num).toDouble(),
      bmiStatus: _bmiStatusFromJson(json['bmi_status'] as String?),
      last7Days: (json['last_7_days'] as List)
          .map(
            (d) => DailyCalorie(
              date: DateTime.parse((d as Map<String, dynamic>)['date'] as String),
              consumedKcal: (d['eaten_calories'] as num).toDouble(),
              goalKcal: goal,
            ),
          )
          .toList(),
      shortcuts: const [],
      overLimit: json['over_limit'] as bool? ?? false,
      dinnerLogged: json['dinner_logged'] as bool? ?? false,
      goalCycleResult: json['goal_cycle_result'] != null
          ? HealthGoalCycle.fromJson(json['goal_cycle_result'] as Map<String, dynamic>)
          : null,
    );
  }
}
