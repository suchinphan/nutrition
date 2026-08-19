import 'package:flutter/foundation.dart';

enum MealType { breakfast, lunch, dinner }

extension MealTypeApi on MealType {
  String get apiValue => switch (this) {
    MealType.breakfast => 'breakfast',
    MealType.lunch => 'lunch',
    MealType.dinner => 'dinner',
  };

  String get labelTh => switch (this) {
    MealType.breakfast => 'เช้า',
    MealType.lunch => 'กลางวัน',
    MealType.dinner => 'เย็น',
  };
}

MealType mealTypeFromApi(String? value) => switch (value) {
  'lunch' => MealType.lunch,
  'dinner' => MealType.dinner,
  _ => MealType.breakfast,
};

/// ช่วงเวลาแต่ละมื้อ (ชั่วโมงเริ่ม, ชั่วโมงจบ ตาม Asia/Bangkok) — ต้องตรงกับ
/// backend เป๊ะ (ดู backend/page/meal_select_sheet.dart เดิม + ตรวจแล้วตรงกับ
/// kMealTimeWindows ที่ backend ใช้ล็อกมื้อ) ใช้ทั้งใน UI (ล็อกมื้อที่ผ่าน
/// เวลาแล้ว) และ NotificationHelper (ตั้งเตือนก่อนมื้อปิด 30 นาที) — จุดเดียว
/// กันสองที่ต้องแก้พร้อมกันถ้าช่วงเวลาเปลี่ยน
const Map<MealType, (int, int)> kMealTimeWindows = {
  MealType.breakfast: (5, 10),
  MealType.lunch: (10, 15),
  MealType.dinner: (15, 22),
};

/// รายการเมนูหนึ่งอันในมื้อที่บันทึกไว้ — มาจาก POST/GET /meal-logs จริง
/// (ดู backend/api.py _serialize_meal_log) หมายเหตุ: backend ส่งแค่
/// food_item_id/food_item_name/serving_size_id ไม่ได้ส่ง FoodItem/ServingSize
/// เต็มรูปแบบมาด้วย จึงเก็บเป็น id+name ตรงๆ แทนการสร้าง object ลอยๆ ที่ไม่มีข้อมูลจริง
@immutable
class MealLogItem {
  final int id;
  final int foodItemId;
  final String? foodItemName;
  final int? servingSizeId;
  final double quantity;
  final double? caloriesActual;
  final bool isEaten;
  final DateTime? eatenAt;

  const MealLogItem({
    required this.id,
    required this.foodItemId,
    this.foodItemName,
    this.servingSizeId,
    required this.quantity,
    this.caloriesActual,
    required this.isEaten,
    this.eatenAt,
  });

  factory MealLogItem.fromJson(Map<String, dynamic> json) => MealLogItem(
    id: json['id'] as int,
    foodItemId: json['food_item_id'] as int,
    foodItemName: json['food_item_name'] as String?,
    servingSizeId: json['serving_size_id'] as int?,
    quantity: (json['quantity'] as num).toDouble(),
    caloriesActual: (json['calories_actual'] as num?)?.toDouble(),
    isEaten: json['is_eaten'] == true,
    eatenAt: json['eaten_at'] != null ? DateTime.tryParse(json['eaten_at'] as String) : null,
  );

  /// ยังยกเลิก "ทานแล้ว" ได้ไหม — ภายใน 5 นาทีหลังกดเท่านั้น (ตรงกับ backend
  /// `PATCH /api/meal-log-items/<id>/undo-eaten` ที่คืน 400 EATEN_UNDO_EXPIRED
  /// หลังจากนั้น) จุดเดียวที่หน้าจอต่างๆ (Dashboard/History) เรียกใช้ร่วมกัน
  /// กันตรรกะ "5 นาที" กระจายไปคนละที่ ผู้เรียกยังต้อง rebuild เป็นระยะเอง
  /// เพราะเวลาผ่านไปเฉยๆ ไม่มี event ให้ widget รู้ตัว
  bool get canUndoEaten {
    if (!isEaten || eatenAt == null) return false;
    return DateTime.now().difference(eatenAt!) < const Duration(minutes: 5);
  }
}

/// มื้ออาหารที่บันทึกไว้ 1 มื้อ (1 วัน x 1 มื้อ ตาม UNIQUE KEY ฝั่ง backend)
/// มาจาก POST/GET /meal-logs จริง
@immutable
class MealLog {
  final int id;
  final DateTime logDate;
  final MealType mealType;
  final double? caloriesGoal;
  final List<MealLogItem> items;
  final DateTime? createdAt;

  const MealLog({
    required this.id,
    required this.logDate,
    required this.mealType,
    this.caloriesGoal,
    required this.items,
    this.createdAt,
  });

  double get totalCalories =>
      items.fold(0.0, (sum, i) => sum + (i.caloriesActual ?? 0));

  /// มื้อ "ปิดสนิท" แล้วหรือยัง — อิงเวลาที่เมนู "แรก" ของมื้อนี้ถูกกดทานแล้ว
  /// ไม่ใช่เมนูล่าสุด (เดิมเช็คว่ามีเมนูไหนยังไม่เกิน 5 นาทีของตัวมันเองบ้าง
  /// ไหม ทำให้เพิ่มเมนูใหม่แล้วกดทานแล้วอีกรอบได้นาฬิกาใหม่ทุกครั้ง เลื่อนวัน
  /// ปิดมื้อออกไปเรื่อยๆ ไม่มีที่สิ้นสุด — ผู้ใช้รายงานจริง) ตรงกับ backend's
  /// _meal_is_sealed() เป๊ะ — คุมแค่ "เพิ่มเมนูใหม่ได้ไหม" ไม่กระทบสิทธิ์แก้ไข/
  /// ลบ/ยกเลิกทานแล้วของแต่ละเมนูที่ยังอิงเวลาของตัวเอง (ดู canUndoEaten)
  bool get isSealed {
    final eatenAts = items.where((i) => i.isEaten && i.eatenAt != null).map((i) => i.eatenAt!);
    if (eatenAts.isEmpty) return false;
    final earliest = eatenAts.reduce((a, b) => a.isBefore(b) ? a : b);
    return DateTime.now().difference(earliest) > const Duration(minutes: 5);
  }

  /// มื้อที่เลือกเมนูไปแล้วแต่ไม่เคยกด "ทานแล้ว" เลย แล้วเลยช่วงเวลาของมื้อ
  /// นั้นไปแล้ว (วันนี้เช็คตามชั่วโมงปัจจุบันเทียบ kMealTimeWindows, วันที่
  /// ผ่านไปแล้วถือว่าเลยเวลาเสมอ) — ถือว่า "ยังไม่เคยกรอก" จริงๆ ย้ายมาไว้ที่
  /// model กลางจุดเดียว เดิม Dashboard (_TodayMealsSection) มีนิยามนี้ของ
  /// ตัวเองแยกต่างหาก ส่วน BackfillSection เช็คแค่ items.isNotEmpty เฉยๆ ไม่รู้
  /// จักแนวคิด "ปล่อยค้าง" นี้เลย ทำให้มื้อที่เลือกเมนูค้างไว้ไม่ยืนยันทานแล้ว
  /// Dashboard นับว่ายังไม่กรอก แต่บันทึกย้อนหลังกลับนับว่ากรอกครบแล้ว
  /// (ผู้ใช้รายงานจริง) ใช้ getter เดียวกันทั้งคู่กันเพี้ยนกันอีก
  bool get isAbandoned {
    final hasItems = items.isNotEmpty;
    final allEaten = hasItems && items.every((i) => i.isEaten);
    if (!hasItems || allEaten) return false;
    final window = kMealTimeWindows[mealType]!;
    // เพิ่มเมนูตอนที่เลยเวลาของมื้อนั้นไปแล้วเอง (บันทึกย้อนหลัง/นอกเวลาโดย
    // ตั้งใจ ผ่านปุ่ม "+ เพิ่มมื้อ" ที่เปิดให้กรอกได้ทุกเวลา) ไม่ถือว่า
    // "ปล่อยค้าง" เพราะไม่เคยมีโอกาสกดทานแล้วในช่วงเวลานั้นเลยด้วยซ้ำ ต่างจาก
    // มื้อที่เลือกไว้ตอนอยู่ในช่วงเวลาแล้วปล่อยผ่านไปเฉยๆ (ผู้ใช้รายงานจริง:
    // เพิ่งเลือกเมนูมื้อเช้าตอนหกโมงเย็น แต่ Dashboard ถือว่า "ยังไม่เคยกรอก"
    // ทันที ทั้งที่เพิ่งบันทึกไปหมาดๆ) — created_at เป็นเวลากรุงเทพฯ naive
    // ตรงตัวจาก backend (get_thailand_time()) ใช้ปีเดือนวัน/ชั่วโมงตรงๆ ได้
    // เลยไม่ต้องแปลง timezone ซ้ำ
    final created = createdAt;
    if (created != null &&
        created.year == logDate.year &&
        created.month == logDate.month &&
        created.day == logDate.day &&
        created.hour >= window.$2) {
      return false;
    }
    final nowBangkok = DateTime.now().toUtc().add(const Duration(hours: 7));
    final today = DateTime(nowBangkok.year, nowBangkok.month, nowBangkok.day);
    final logDay = DateTime(logDate.year, logDate.month, logDate.day);
    if (logDay.isBefore(today)) return true;
    if (logDay.isAfter(today)) return false;
    return nowBangkok.hour >= window.$2;
  }

  factory MealLog.fromJson(Map<String, dynamic> json) => MealLog(
    id: json['id'] as int,
    logDate: DateTime.parse(json['log_date'] as String),
    mealType: mealTypeFromApi(json['meal_type'] as String?),
    caloriesGoal: (json['calories_goal'] as num?)?.toDouble(),
    items: ((json['items'] as List?) ?? const [])
        .map((i) => MealLogItem.fromJson(i as Map<String, dynamic>))
        .toList(),
    createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
  );
}
