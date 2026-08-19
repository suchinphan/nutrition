import 'package:flutter/foundation.dart';

enum ReportStatus { pending, replied, closed }

ReportStatus _reportStatusFromApi(String? value) => switch (value) {
  'replied' => ReportStatus.replied,
  'closed' => ReportStatus.closed,
  _ => ReportStatus.pending,
};

extension ReportStatusLabelTh on ReportStatus {
  String get labelTh => switch (this) {
    ReportStatus.pending => 'รอตรวจสอบ',
    ReportStatus.replied => 'ตอบกลับแล้ว',
    ReportStatus.closed => 'ปิดเรื่องแล้ว',
  };
}

/// ตั๋วแจ้งปัญหา/ขอปลดแบน 1 รายการ — มาจาก POST/GET /api/report_problem,
/// /api/my_reports จริง (ดู backend/models.py Report) — ไม่มี image_url/
/// ai_reply/subject/detail แบบเดิมอีกต่อไป เหลือแค่ title+message
@immutable
class Report {
  final int id;
  final String title;
  final String message;
  final ReportStatus status;
  final String? adminReply;
  final DateTime? createdAt;

  const Report({
    required this.id,
    required this.title,
    required this.message,
    required this.status,
    this.adminReply,
    this.createdAt,
  });

  factory Report.fromJson(Map<String, dynamic> json) => Report(
    id: json['id'] as int,
    title: json['title'] as String? ?? '',
    message: json['message'] as String? ?? '',
    status: _reportStatusFromApi(json['status'] as String?),
    adminReply: json['admin_reply'] as String?,
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String)
        : null,
  );
}

enum ReportSender { user, admin }

/// ข้อความ 1 รายการในบทสนทนาของ ticket — มาจาก
/// `GET/POST /api/reports/{id}/messages` จริง (ดู backend/models.py ReportMessage)
@immutable
class ReportMessage {
  final int id;
  final int reportId;
  final ReportSender sender;
  final String message;
  final DateTime? createdAt;

  const ReportMessage({
    required this.id,
    required this.reportId,
    required this.sender,
    required this.message,
    this.createdAt,
  });

  factory ReportMessage.fromJson(Map<String, dynamic> json) => ReportMessage(
    id: json['id'] as int,
    reportId: json['report_id'] as int,
    sender: json['sender_type'] == 'admin' ? ReportSender.admin : ReportSender.user,
    message: json['message'] as String? ?? '',
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String)
        : null,
  );
}

/// ผลลัพธ์ของการดึงบทสนทนา ticket — [canReply] = false เมื่อ ticket ปิดแล้ว
/// (chat กลายเป็น read-only)
@immutable
class ReportThread {
  final List<ReportMessage> messages;
  final ReportStatus status;
  final bool canReply;

  const ReportThread({required this.messages, required this.status, required this.canReply});

  factory ReportThread.fromJson(Map<String, dynamic> json) => ReportThread(
    messages: ((json['messages'] as List?) ?? [])
        .map((m) => ReportMessage.fromJson(m as Map<String, dynamic>))
        .toList(),
    status: _reportStatusFromApi(json['status'] as String?),
    canReply: json['can_reply'] as bool? ?? false,
  );
}

/// มาจาก `GET /api/reports/unread-count` จริง — [unreadReportIds] ใช้เทียบ
/// รอบก่อนหน้าว่ามี ticket ไหน "เพิ่งกลายเป็นยังไม่อ่าน" ใหม่บ้าง (ไม่ใช่แค่
/// unreadCount เพิ่มขึ้นเฉยๆ ซึ่งไม่รู้ว่าเป็น ticket ไหน)
@immutable
class UnreadReportsStatus {
  final int unreadCount;
  final List<int> unreadReportIds;

  const UnreadReportsStatus({required this.unreadCount, required this.unreadReportIds});

  factory UnreadReportsStatus.fromJson(Map<String, dynamic> json) => UnreadReportsStatus(
    unreadCount: json['unread_count'] as int? ?? 0,
    unreadReportIds: ((json['unread_report_ids'] as List?) ?? [])
        .map((e) => e as int)
        .toList(),
  );
}
