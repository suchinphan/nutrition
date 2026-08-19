import 'package:flutter/foundation.dart';
import 'dashboard_data.dart' show BmiStatus;

/// มื้ออาหาร — ใช้แทนสตริง "เช้า+กลางวัน+เย็น" เดิม ด้วยค่า enum ที่เลือก
/// ได้หลายอันอิสระต่อกัน (ตรงกับดีไซน์ใหม่ที่ให้กดเลือกทีละมื้อ ไม่ใช่เลือก
/// จากชุดคอมโบสำเร็จรูปแบบหน้าเดิม)
enum MealSlot { breakfast, lunch, dinner }

extension MealSlotLabel on MealSlot {
  String get labelTh => switch (this) {
    MealSlot.breakfast => 'เช้า',
    MealSlot.lunch => 'กลางวัน',
    MealSlot.dinner => 'เย็น',
  };

  /// ค่าที่ backend เข้าใจ (ตรงกับ _decode_meal_list ใน backend/models.py
  /// ที่รองรับทั้ง JSON list ของสตริงไทยเหล่านี้ หรือสตริงคั่นด้วย "+")
  String get apiValue => labelTh;
}

MealSlot? mealSlotFromApiValue(String? value) => switch (value?.trim()) {
  'เช้า' => MealSlot.breakfast,
  'กลางวัน' => MealSlot.lunch,
  'เย็น' => MealSlot.dinner,
  _ => null,
};

/// สรุปสุขภาพของผู้ใช้ — มาจาก `GET /user/<id>` จริง (ดู backend/models.py
/// User.to_dict()) เอาแค่ 3 ฟิลด์ที่หน้านี้ต้องใช้
@immutable
class HealthSummary {
  final double bmi;
  final double caloriesGoal; // calories_goal
  final double caloriesConsumedToday; // total_calories_eaten

  const HealthSummary({
    required this.bmi,
    required this.caloriesGoal,
    required this.caloriesConsumedToday,
  });

  /// คำนวณสถานะ BMI เองจากตัวเลข (เกณฑ์เอเชีย: <18.5/<23/<25/>=25) แทนการ
  /// อ่านฟิลด์ bmi_status ที่ backend ส่งมาตรงๆ — เพราะตรวจ backend/api.py
  /// จริงแล้วพบว่ามีโค้ด 2 จุดผลิตข้อความสถานะ BMI เป็นคนละชุดกัน
  /// ('ท้วม/น้ำหนักเกิน' vs 'น้ำหนักเกินมาตรฐาน' ฯลฯ) ไม่นิ่งพอจะ parse ตรงๆ
  BmiStatus get bmiStatus {
    if (bmi <= 0) return BmiStatus.normal;
    if (bmi < 18.5) return BmiStatus.underweight;
    if (bmi < 23) return BmiStatus.normal;
    if (bmi < 25) return BmiStatus.overweight;
    return BmiStatus.obese;
  }

  factory HealthSummary.fromJson(Map<String, dynamic> json) => HealthSummary(
    bmi: (json['bmi'] as num?)?.toDouble() ?? 0,
    caloriesGoal: (json['calories_goal'] as num?)?.toDouble() ?? 0,
    caloriesConsumedToday:
        (json['total_calories_eaten'] as num?)?.toDouble() ?? 0,
  );
}

/// การเลือกมื้อ/ระยะเวลาที่มีอยู่แล้ว (ถ้าเคยเลือกไว้และยังไม่หมดอายุ) —
/// มาจาก GET /user_selections/current จริง (ดู backend/api.py
/// get_current_user_selection) ใช้ prefill ฟอร์มและบอกว่าถูกล็อกอยู่หรือไม่
@immutable
class ExistingMealSelection {
  final List<MealSlot> meals;
  final int? durationDays;
  final int? planCaloriesGoal;
  final bool isLocked; // is_fulllock จาก backend

  const ExistingMealSelection({
    required this.meals,
    required this.durationDays,
    required this.planCaloriesGoal,
    required this.isLocked,
  });

  factory ExistingMealSelection.fromJson(Map<String, dynamic> json) {
    final rawMeal = json['meal'];
    final meals = <MealSlot>[];
    if (rawMeal is List) {
      for (final m in rawMeal) {
        final slot = mealSlotFromApiValue(m?.toString());
        if (slot != null) meals.add(slot);
      }
    } else if (rawMeal is String && rawMeal.isNotEmpty) {
      for (final part in rawMeal.split('+')) {
        final slot = mealSlotFromApiValue(part);
        if (slot != null) meals.add(slot);
      }
    }
    return ExistingMealSelection(
      meals: meals,
      durationDays: (json['duration'] as num?)?.toInt(),
      planCaloriesGoal: (json['plan_calories_goal'] as num?)?.toInt(),
      isLocked: json['is_fulllock'] == true,
    );
  }
}

/// ข้อมูลรวมของหน้า "เลือกมื้ออาหารและระยะเวลา"
@immutable
class MealSelectionPageData {
  final HealthSummary healthSummary;
  final ExistingMealSelection? existingSelection;

  const MealSelectionPageData({
    required this.healthSummary,
    this.existingSelection,
  });

  /// ยังไม่มีข้อมูลสุขภาพเลย (ผู้ใช้ยังไม่กรอกข้อมูลส่วนตัว/BMI มาก่อน)
  bool get isEmpty =>
      healthSummary.bmi <= 0 && healthSummary.caloriesGoal <= 0;
}

/// ร่างการเลือกมื้อ/ระยะเวลาที่ผู้ใช้กำลังกรอกอยู่ในหน้านี้
@immutable
class MealSelectionDraft {
  final List<MealSlot> meals;
  final int durationDays;

  const MealSelectionDraft({required this.meals, required this.durationDays});

  /// แคลอรีรวมที่จะได้รับตลอดช่วงเวลาที่เลือก (เป้าหมาย/วัน x จำนวนวัน)
  int totalPlanCalories(double dailyGoal) =>
      (dailyGoal * durationDays).round();

  Map<String, dynamic> toJson() => {
    'meal': meals.map((m) => m.apiValue).toList(),
    'duration': durationDays,
  };
}
