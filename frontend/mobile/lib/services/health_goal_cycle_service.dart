import '../models/health_goal_cycle.dart';
import '../models/result.dart';
import 'auth_service.dart';
import 'typed_api_client.dart';

/// สัญญา (interface) ของ service ผลรอบเป้าหมายสุขภาพ 7 วัน — คุย
/// /api/user/health-goal-cycles จริง (backend finalize ให้เองตอนรอบหมดอายุ)
abstract class HealthGoalCycleService {
  Future<Result<List<HealthGoalCycle>>> fetchCycles();

  /// ปิด dialog สรุปผล 7 วันไปแล้ว — กันโผล่ซ้ำทุกครั้งที่เปิดหน้าหลัก (ดู
  /// DashboardData.goalCycleResult)
  Future<Result<void>> acknowledge(int cycleId);
}

class HttpHealthGoalCycleService implements HealthGoalCycleService {
  final TypedApiClient _client;
  const HttpHealthGoalCycleService(this._client);

  @override
  Future<Result<List<HealthGoalCycle>>> fetchCycles() {
    return _client.getJson<List<HealthGoalCycle>>(
      '/api/user/health-goal-cycles',
      decode: (json) => ((json as Map<String, dynamic>)['cycles'] as List)
          .map((c) => HealthGoalCycle.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<Result<void>> acknowledge(int cycleId) => _client.postJson<void>(
    '/api/user/health-goal-cycles/$cycleId/ack',
    decode: (_) {},
  );
}

HealthGoalCycleService createHealthGoalCycleService() {
  final client = TypedApiClient(tokenProvider: () => AuthService().token);
  return HttpHealthGoalCycleService(client);
}
