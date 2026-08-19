import '../models/result.dart';
import '../models/weight_log.dart';
import 'auth_service.dart';
import 'typed_api_client.dart';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// สัญญา (interface) ของ service น้ำหนักย้อนหลัง — คุย /api/weight-logs จริง
abstract class WeightLogService {
  Future<Result<List<WeightLogEntry>>> fetchWeightLogs({int days = 30});

  /// บันทึกน้ำหนักวันนี้ (หรือวันที่ระบุ) — backend upsert เองถ้ามีของวัน
  /// เดียวกันอยู่แล้ว ไม่ error 409 แบบ meal_logs
  Future<Result<WeightLogEntry>> logWeight({required double weight, DateTime? loggedAt});
}

class HttpWeightLogService implements WeightLogService {
  final TypedApiClient _client;
  const HttpWeightLogService(this._client);

  @override
  Future<Result<List<WeightLogEntry>>> fetchWeightLogs({int days = 30}) {
    return _client.getJson<List<WeightLogEntry>>(
      '/api/weight-logs?days=$days',
      decode: (json) => ((json as Map<String, dynamic>)['weight_logs'] as List)
          .map((w) => WeightLogEntry.fromJson(w as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<Result<WeightLogEntry>> logWeight({required double weight, DateTime? loggedAt}) {
    return _client.postJson<WeightLogEntry>(
      '/api/weight-logs',
      body: {
        'weight': weight,
        if (loggedAt != null) 'logged_at': _ymd(loggedAt),
      },
      decode: (json) => WeightLogEntry.fromJson(json as Map<String, dynamic>),
    );
  }
}

WeightLogService createWeightLogService() {
  final client = TypedApiClient(tokenProvider: () => AuthService().token);
  return HttpWeightLogService(client);
}
