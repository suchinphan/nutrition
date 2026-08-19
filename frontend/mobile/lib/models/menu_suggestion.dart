import 'package:flutter/foundation.dart';

enum SubmissionStatus { pending, approved, rejected }

SubmissionStatus _statusFromApi(String? value) => switch (value) {
  'approved' => SubmissionStatus.approved,
  'rejected' => SubmissionStatus.rejected,
  _ => SubmissionStatus.pending,
};

extension SubmissionStatusLabelTh on SubmissionStatus {
  String get labelTh => switch (this) {
    SubmissionStatus.pending => 'รอตรวจสอบ',
    SubmissionStatus.approved => 'อนุมัติแล้ว',
    SubmissionStatus.rejected => 'ถูกปฏิเสธ',
  };
}

/// ข้อเสนอเมนูใหม่ 1 รายการที่ผู้ใช้ส่งไป — มาจาก GET /api/my_submissions จริง
/// (ดู backend/models.py Submission) ให้ผู้ใช้เช็คได้เองว่าแอดมินอนุมัติ/
/// ปฏิเสธหรือยัง (เดิมส่งไปแล้วไม่มีทางรู้ผลเลย)
@immutable
class MenuSuggestion {
  final int id;
  final String nameTh;
  final String? nameEn;
  final String itemType;
  final String? detail;
  final SubmissionStatus status;
  final String? reviewNote;
  final DateTime? createdAt;

  const MenuSuggestion({
    required this.id,
    required this.nameTh,
    this.nameEn,
    required this.itemType,
    this.detail,
    required this.status,
    this.reviewNote,
    this.createdAt,
  });

  factory MenuSuggestion.fromJson(Map<String, dynamic> json) => MenuSuggestion(
    id: json['id'] as int,
    nameTh: json['name_th'] as String? ?? '',
    nameEn: json['name_en'] as String?,
    itemType: json['item_type'] as String? ?? 'food',
    detail: json['detail'] as String?,
    status: _statusFromApi(json['status'] as String?),
    reviewNote: json['review_note'] as String?,
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String)
        : null,
  );
}
