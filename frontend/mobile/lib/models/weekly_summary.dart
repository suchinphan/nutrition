import 'package:flutter/foundation.dart';

/// สรุปภาพรวม 7 วันล่าสุด — มาจาก GET /api/dashboard/weekly-summary จริง
/// (ดู backend/api.py dashboard_weekly_summary) เอาไปประกอบเป็นประโยคไทย
/// ฝั่ง client เอง (ไม่ใช่ backend ส่งข้อความสำเร็จรูปมา)
@immutable
class WeeklySummaryData {
  final int daysOnTarget;
  final int daysOverGoal;
  final int daysUnderGoal;
  final double avgEatenCalories;
  final int streakDaysLogged;
  final String? mostFrequentCategory;

  const WeeklySummaryData({
    required this.daysOnTarget,
    required this.daysOverGoal,
    required this.daysUnderGoal,
    required this.avgEatenCalories,
    required this.streakDaysLogged,
    this.mostFrequentCategory,
  });

  factory WeeklySummaryData.fromJson(Map<String, dynamic> json) => WeeklySummaryData(
    daysOnTarget: json['days_on_target'] as int? ?? 0,
    daysOverGoal: json['days_over_goal'] as int? ?? 0,
    daysUnderGoal: json['days_under_goal'] as int? ?? 0,
    avgEatenCalories: (json['avg_eaten_calories'] as num?)?.toDouble() ?? 0,
    streakDaysLogged: json['streak_days_logged'] as int? ?? 0,
    mostFrequentCategory: json['most_frequent_category'] as String?,
  );
}
