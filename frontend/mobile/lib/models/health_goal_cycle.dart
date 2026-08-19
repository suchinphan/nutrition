import 'package:flutter/foundation.dart';

/// ผลรอบเป้าหมายสุขภาพ 7 วันที่จบไปแล้ว — มาจาก GET /api/user/health-goal-cycles
/// จริง (ดู backend/models.py HealthGoalCycle) 1 รอบต่อ 1 ครั้งที่ตั้งเป้าหมาย
/// แล้วครบ 7 วัน คำนวณครั้งเดียวฝั่ง backend ไม่ใช่ค่าที่คำนวณสดในแอป
@immutable
class HealthGoalCycle {
  final int id;
  final String healthGoal;
  final int? caloriesGoal;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int mealsLogged;
  final int mealsAvailable;
  // จำนวนมื้อในรอบนี้ที่กินเกินโควตาต่อมื้อ (calories_goal/3) — เดิม cap นี้
  // บล็อกการบันทึกมื้ออาหารจริง ผู้ใช้ขอให้เอาข้อจำกัดออกแล้วเก็บไว้สรุปผล
  // ตอนจบรอบแทน (ดู backend api._finalize_expired_goal_cycle)
  final int mealsOverQuota;
  final double successRatio;
  final bool isSuccess;

  const HealthGoalCycle({
    required this.id,
    required this.healthGoal,
    required this.caloriesGoal,
    required this.periodStart,
    required this.periodEnd,
    required this.mealsLogged,
    required this.mealsAvailable,
    required this.mealsOverQuota,
    required this.successRatio,
    required this.isSuccess,
  });

  factory HealthGoalCycle.fromJson(Map<String, dynamic> json) => HealthGoalCycle(
    id: json['id'] as int,
    healthGoal: json['health_goal'] as String,
    caloriesGoal: (json['calories_goal'] as num?)?.toInt(),
    periodStart: DateTime.parse(json['period_start'] as String),
    periodEnd: DateTime.parse(json['period_end'] as String),
    mealsLogged: json['meals_logged'] as int,
    mealsAvailable: json['meals_available'] as int,
    mealsOverQuota: (json['meals_over_quota'] as num?)?.toInt() ?? 0,
    successRatio: (json['success_ratio'] as num).toDouble(),
    isSuccess: json['is_success'] as bool,
  );
}
