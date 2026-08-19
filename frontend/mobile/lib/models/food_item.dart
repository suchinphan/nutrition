import 'package:flutter/foundation.dart';

/// ขนาดเสิร์ฟหนึ่งแบบของเมนู (เล็ก/กลาง/ใหญ่ ฯลฯ) — มาจาก GET /api/food-items
/// (ดู backend/models.py ServingSize)
@immutable
class ServingSize {
  final int id;
  final String unitNameTh;
  final double caloriesMultiplier;
  final double? gramsApprox;

  const ServingSize({
    required this.id,
    required this.unitNameTh,
    required this.caloriesMultiplier,
    this.gramsApprox,
  });

  factory ServingSize.fromJson(Map<String, dynamic> json) => ServingSize(
    id: json['id'] as int,
    unitNameTh: (json['unit_name_th'] as String?) ?? (json['unit_name'] as String? ?? ''),
    caloriesMultiplier: (json['calories_multiplier'] as num).toDouble(),
    gramsApprox: (json['grams_approx'] as num?)?.toDouble(),
  );
}

/// เมนูอาหาร/เครื่องดื่ม/ของหวานหนึ่งรายการ — รวมจาก food_items ตาราง (แทน
/// FoodMenu/DrinkMenu/DessertMenu เดิม 3 ชุด) มาจาก GET /api/food-items จริง
/// (ดู backend/api.py _serialize_food_item)
@immutable
class FoodItem {
  final int id;
  final int categoryId;
  final String categoryType; // food | drink | dessert
  final String name;
  final String? nameTh;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;
  final double? sugarG;
  final String imageUrl;
  final List<ServingSize> servingSizes;
  final List<String> allergens;
  final bool allergyWarning;
  final String? diseaseWarningReason;
  final int? swapFoodId;
  final String? upgradeTips;

  const FoodItem({
    required this.id,
    required this.categoryId,
    required this.categoryType,
    required this.name,
    this.nameTh,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
    this.sugarG,
    required this.imageUrl,
    required this.servingSizes,
    required this.allergens,
    required this.allergyWarning,
    this.diseaseWarningReason,
    this.swapFoodId,
    this.upgradeTips,
  });

  /// ชื่อไทยถ้ามี ไม่งั้น fallback ไปชื่ออังกฤษ — ใช้แสดงผลใน UI
  String get displayName => (nameTh != null && nameTh!.isNotEmpty) ? nameTh! : name;

  /// serving size ที่ถือเป็นค่าเริ่มต้น (multiplier = 1.0) ถ้าไม่มีให้ใช้ตัวแรก
  ServingSize? get defaultServingSize {
    if (servingSizes.isEmpty) return null;
    for (final s in servingSizes) {
      if (s.caloriesMultiplier == 1.0) return s;
    }
    return servingSizes.first;
  }

  factory FoodItem.fromJson(Map<String, dynamic> json) => FoodItem(
    id: json['id'] as int,
    categoryId: json['category_id'] as int,
    categoryType: json['category_type'] as String? ?? 'food',
    name: json['name'] as String? ?? '',
    nameTh: json['name_th'] as String?,
    calories: (json['calories'] as num?)?.toDouble(),
    proteinG: (json['protein_g'] as num?)?.toDouble(),
    carbsG: (json['carbs_g'] as num?)?.toDouble(),
    fatG: (json['fat_g'] as num?)?.toDouble(),
    fiberG: (json['fiber_g'] as num?)?.toDouble(),
    sugarG: (json['sugar_g'] as num?)?.toDouble(),
    imageUrl: json['image_url'] as String? ?? '',
    servingSizes: ((json['serving_sizes'] as List?) ?? const [])
        .map((s) => ServingSize.fromJson(s as Map<String, dynamic>))
        .toList(),
    allergens: ((json['allergens'] as List?) ?? const [])
        .map((a) => a.toString())
        .toList(),
    allergyWarning: json['allergy_warning'] == true,
    diseaseWarningReason: json['disease_warning_reason'] as String?,
    swapFoodId: json['swap_food_id'] as int?,
    upgradeTips: json['upgrade_tips'] as String?,
  );
}
