import 'package:flutter/foundation.dart';

/// น้ำหนัก 1 วัน — มาจาก GET/POST /api/weight-logs จริง (ดู backend/models.py
/// WeightLog) หนึ่งแถวต่อหนึ่งวัน (backend upsert ถ้าบันทึกซ้ำวันเดียวกัน)
@immutable
class WeightLogEntry {
  final int id;
  final double weight;
  final DateTime loggedAt;
  final DateTime? createdAt;

  const WeightLogEntry({
    required this.id,
    required this.weight,
    required this.loggedAt,
    this.createdAt,
  });

  factory WeightLogEntry.fromJson(Map<String, dynamic> json) => WeightLogEntry(
    id: json['id'] as int,
    weight: (json['weight'] as num).toDouble(),
    loggedAt: DateTime.parse(json['logged_at'] as String),
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String)
        : null,
  );
}
