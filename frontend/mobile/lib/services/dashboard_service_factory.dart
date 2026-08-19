import 'auth_service.dart';
import 'dashboard_service.dart';
import 'typed_api_client.dart';
import '../models/dashboard_data.dart';

/// เลือก implementation ของ [DashboardService] ตอน build โดยไม่ต้องแก้โค้ด —
/// รัน `flutter run --dart-define=USE_MOCK_DASHBOARD=true` เพื่อบังคับกลับไป
/// ใช้ mock (เช่น ตอนพัฒนา UI โดยไม่มี backend รันอยู่)
///
/// อัปเดต: backend มี endpoint `GET /api/dashboard` จริงแล้ว (ดู
/// docs/api_contract.md + backend/api.py) จึง default เป็น HTTP จริงแทน mock
DashboardService createDashboardService() {
  const useMock = bool.fromEnvironment(
    'USE_MOCK_DASHBOARD',
    defaultValue: false,
  );
  if (useMock) return const MockDashboardService();
  final client = TypedApiClient(tokenProvider: () => AuthService().token);
  return HttpDashboardService(client);
}

/// เรียก [createDashboardService] แล้วแกะ [Result] ให้กลับเป็น Future ที่
/// throw ตอน Err — ให้ DashboardPage ที่ยังใช้ DashboardFetcher แบบ
/// FutureBuilder ทำงานได้โดยไม่ต้องแก้ dashboard_page.dart
Future<DashboardData> fetchDashboardData() {
  return createDashboardService().fetchDashboard('demo-user').then(
        (result) => result.when(
          ok: (data) => data,
          err: (error) => throw Exception(error.toUserMessage()),
        ),
      );
}
