import 'dart:typed_data';
import '../models/result.dart';
import 'auth_service.dart';
import 'typed_api_client.dart';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// ผลของ [ExportService.exportHistory] — ไบต์ไฟล์ + ชื่อไฟล์ที่ควรใช้บันทึก
class ExportedFile {
  final Uint8List bytes;
  final String fileName;
  const ExportedFile({required this.bytes, required this.fileName});
}

/// สัญญาของ service ดาวน์โหลดประวัติการกิน — คุย GET /api/export/history จริง
abstract class ExportService {
  Future<Result<ExportedFile>> exportHistory({
    required String format,
    DateTime? from,
    DateTime? to,
  });
}

class HttpExportService implements ExportService {
  final TypedApiClient _client;
  const HttpExportService(this._client);

  @override
  Future<Result<ExportedFile>> exportHistory({
    required String format,
    DateTime? from,
    DateTime? to,
  }) async {
    final params = <String, String>{
      'format': format,
      if (from != null) 'from': _ymd(from),
      if (to != null) 'to': _ymd(to),
    };
    final query = Uri(queryParameters: params).query;
    final result = await _client.getBytes('/api/export/history?$query');
    return result.when(
      ok: (bytes) => Ok(ExportedFile(bytes: bytes, fileName: 'history.$format')),
      err: (error) => Err(error),
    );
  }
}

ExportService createExportService() {
  final client = TypedApiClient(tokenProvider: () => AuthService().token);
  return HttpExportService(client);
}
