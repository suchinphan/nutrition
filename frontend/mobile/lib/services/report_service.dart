import '../models/report.dart';
import '../models/result.dart';
import 'auth_service.dart';
import 'typed_api_client.dart';

/// สัญญา (interface) ของ service แจ้งปัญหา/ขอปลดแบน — ticket schema ใหม่
/// (title+message เท่านั้น ไม่มี image_url/ai_reply แบบเดิมแล้ว) พร้อม thread
/// แชทแยกต่างหาก (ReportMessage) สำหรับคุยไปมาจนกว่าแอดมินจะปิดเรื่อง
abstract class ReportService {
  Future<Result<Report>> submitReportProblem({required String title, required String message});

  /// scope: 'open' (ค่าเริ่มต้น — เฉพาะที่ยังไม่ปิด, ใช้ในหน้าโปรไฟล์)
  /// หรือ 'closed' (เฉพาะที่ปิดแล้ว, ใช้ในหน้าประวัติ)
  Future<Result<List<Report>>> fetchMyReports({String scope = 'open'});

  Future<Result<ReportThread>> fetchMessages(int reportId);
  Future<Result<ReportMessage>> sendMessage(int reportId, String message);

  Future<Result<bool>> submitUnbanRequest({
    required String message,
    String? username,
    String? email,
    String? password,
  });

  /// จำนวน ticket ที่มีข้อความจากแอดมินที่ยังไม่อ่าน — ใช้กับ badge บน
  /// bottom nav (ดู core/notification/notification_helper.dart)
  Future<Result<UnreadReportsStatus>> fetchUnreadCount();

  /// เรียกตอนเปิดหน้า ticket ใดๆ — mark ว่าอ่านข้อความจากแอดมินล่าสุดแล้ว
  Future<Result<void>> markReportRead(int reportId);
}

class HttpReportService implements ReportService {
  final TypedApiClient _client;
  const HttpReportService(this._client);

  @override
  Future<Result<Report>> submitReportProblem({required String title, required String message}) {
    return _client.postJson<Report>(
      '/api/report_problem',
      body: {'title': title, 'message': message},
      decode: (json) => Report.fromJson((json as Map<String, dynamic>)['report'] as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<List<Report>>> fetchMyReports({String scope = 'open'}) {
    return _client.getJson<List<Report>>(
      '/api/my_reports?scope=$scope',
      decode: (json) => ((json as Map<String, dynamic>)['reports'] as List)
          .map((r) => Report.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<Result<ReportThread>> fetchMessages(int reportId) {
    return _client.getJson<ReportThread>(
      '/api/reports/$reportId/messages',
      decode: (json) => ReportThread.fromJson(json as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<ReportMessage>> sendMessage(int reportId, String message) {
    return _client.postJson<ReportMessage>(
      '/api/reports/$reportId/messages',
      body: {'message': message},
      decode: (json) => ReportMessage.fromJson(json as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<bool>> submitUnbanRequest({
    required String message,
    String? username,
    String? email,
    String? password,
  }) {
    return _client.postJson<bool>(
      '/api/request_unban',
      body: {
        'message': message,
        if (username != null) 'username': username,
        if (email != null) 'email': email,
        if (password != null) 'password': password,
      },
      decode: (_) => true,
    );
  }

  @override
  Future<Result<UnreadReportsStatus>> fetchUnreadCount() {
    return _client.getJson<UnreadReportsStatus>(
      '/api/reports/unread-count',
      decode: (json) => UnreadReportsStatus.fromJson(json as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<void>> markReportRead(int reportId) {
    return _client.patchJson<void>(
      '/api/reports/$reportId/mark-read',
      decode: (_) {},
    );
  }
}

ReportService createReportService() {
  final client = TypedApiClient(tokenProvider: () => AuthService().token);
  return HttpReportService(client);
}
