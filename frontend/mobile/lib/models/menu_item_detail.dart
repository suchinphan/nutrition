import 'package:flutter/foundation.dart';

/// รายละเอียดเมนู 1 ชิ้น — มาจาก POST /menu-info จริง (ดู backend/api.py
/// menu_info) ครอบคลุมทั้งอาหารคาว/ของหวาน/เครื่องดื่ม (group บอกว่าเป็นอันไหน)
@immutable
class MenuItemDetail {
  final String name;
  final int kcal;
  final double? protein;
  final double? carbs;
  final double? fat;
  final double? sugar;
  final double? fiber;
  final String group; // food | dessert | drink | unknown
  final String imageUrl;

  const MenuItemDetail({
    required this.name,
    required this.kcal,
    this.protein,
    this.carbs,
    this.fat,
    this.sugar,
    this.fiber,
    required this.group,
    required this.imageUrl,
  });

  bool get isKnown => group != 'unknown';

  factory MenuItemDetail.fromJson(Map<String, dynamic> json) => MenuItemDetail(
    name: json['name'] as String? ?? '',
    kcal: (json['kcal'] as num?)?.toInt() ?? 0,
    protein: (json['protein'] as num?)?.toDouble(),
    carbs: (json['carbs'] as num?)?.toDouble(),
    fat: (json['fat'] as num?)?.toDouble(),
    sugar: (json['sugar'] as num?)?.toDouble(),
    fiber: (json['fiber'] as num?)?.toDouble(),
    group: json['group'] as String? ?? 'unknown',
    imageUrl: json['image_url'] as String? ?? '',
  );
}
