import 'auth_service.dart';
import 'meal_selection_service.dart';
import 'typed_api_client.dart';

/// เลือก implementation ของ [MealSelectionService] ตอน build โดยไม่ต้องแก้
/// โค้ด — รัน `flutter run --dart-define=USE_MOCK_MEAL_SELECTION=true` เพื่อ
/// บังคับกลับไปใช้ mock (เช่น ตอนพัฒนา UI โดยไม่มี backend รันอยู่) ค่า
/// เริ่มต้นคือยิง HTTP จริงเหมือน dashboard_service_factory.dart (เดิม
/// comment นี้เขียนสลับกับโค้ดจริง — บอกว่า default เป็น mock ทั้งที่โค้ด
/// จริง defaultValue: false คือ HTTP จริง แก้ comment ให้ตรงโค้ด)
MealSelectionService createMealSelectionService() {
  const useMock = bool.fromEnvironment(
    'USE_MOCK_MEAL_SELECTION',
    defaultValue: false,
  );
  if (useMock) return const MockMealSelectionService();
  final client = TypedApiClient(tokenProvider: () => AuthService().token);
  return HttpMealSelectionService(client);
}
