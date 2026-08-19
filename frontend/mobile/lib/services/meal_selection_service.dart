import '../models/app_error.dart';
import '../models/meal_selection_data.dart';
import '../models/result.dart';
import 'auth_service.dart';
import 'typed_api_client.dart';

/// สัญญา (interface) ของ service หน้า "เลือกมื้ออาหารและระยะเวลา"
abstract class MealSelectionService {
  Future<Result<MealSelectionPageData>> fetchPageData();
  Future<Result<bool>> saveDraft(MealSelectionDraft draft);
}

/// implementation จริง — ยิง GET ไปหา backend จริงที่มีอยู่แล้ว 2 endpoint:
///   - `GET /user/<id>`             → BMI/เป้าแคลอรี (ดู backend/models.py)
///   - GET /user_selections/current → การเลือกที่มีอยู่แล้ว (ถ้ามี)
class HttpMealSelectionService implements MealSelectionService {
  final TypedApiClient _client;
  final AuthService _auth;
  HttpMealSelectionService(this._client, {AuthService? auth})
    : _auth = auth ?? AuthService();

  @override
  Future<Result<MealSelectionPageData>> fetchPageData() async {
    final userId = _auth.user?['id']?.toString();
    if (userId == null || userId.isEmpty) {
      return const Err(AuthError());
    }

    final summaryResult = await _client.getJson<HealthSummary>(
      '/user/$userId',
      decode: (json) => HealthSummary.fromJson(json as Map<String, dynamic>),
    );
    if (summaryResult is Err<HealthSummary>) {
      return Err(summaryResult.error);
    }
    final summary = (summaryResult as Ok<HealthSummary>).value;

    final existingResult = await _client.getJson<ExistingMealSelection?>(
      '/user_selections/current',
      decode: (json) {
        final sel = (json as Map<String, dynamic>)['user_selection'];
        return sel == null
            ? null
            : ExistingMealSelection.fromJson(sel as Map<String, dynamic>);
      },
    );
    final existing = existingResult is Ok<ExistingMealSelection?>
        ? existingResult.value
        : null;

    return Ok(
      MealSelectionPageData(healthSummary: summary, existingSelection: existing),
    );
  }

  @override
  Future<Result<bool>> saveDraft(MealSelectionDraft draft) async {
    // หมายเหตุสำคัญ: ยัง "ไม่" ยิง POST /save-selection จริงจากหน้านี้
    // endpoint นั้นต้องการ food_type_id/category_id/menu_id ฯลฯ ที่มาจาก
    // ขั้นตอน "เลือกเมนู" ถัดไปด้วย (ดู backend/api.py save_selection และ
    // การไหลจริงใน choose_your_meal_and_duration.dart._saveSelectionOnline
    // ที่ถูกเรียกก็ต่อเมื่อมี food ids ครบแล้วเท่านั้น) ถ้ายิง POST ตรงนี้
    // ด้วยฟิลด์อาหารว่างๆ จะสร้างแถว UserSelection ที่ไม่สมบูรณ์และอาจ
    // ล็อกผู้ใช้แบบผิดๆ ในฐานข้อมูลจริง
    //
    // จึง "stage" ค่าไว้ที่ AuthService.tempSelections แทน — เป็นพื้นที่เก็บ
    // จริงของผู้ใช้ที่ล็อกอินอยู่ (ไม่ใช่ mock) ให้ขั้นตอนเลือกเมนูถัดไปรวม
    // กับ food ids แล้วค่อย POST ครั้งเดียวให้ครบ ตรงกับสถาปัตยกรรมเดิมของแอป
    try {
      final merged = <String, dynamic>{
        ...?_auth.tempSelections,
        ...draft.toJson(),
      };
      _auth.setTempSelections(merged);
      return const Ok(true);
    } catch (_) {
      return const Err(NetworkError());
    }
  }
}

/// mock — ข้อมูลตัวอย่างสมจริงเป็นภาษาไทย สำหรับพัฒนา UI ก่อน/ไม่มีเน็ต
class MockMealSelectionService implements MealSelectionService {
  final bool simulateError;
  final bool simulateEmpty;
  const MockMealSelectionService({
    this.simulateError = false,
    this.simulateEmpty = false,
  });

  @override
  Future<Result<MealSelectionPageData>> fetchPageData() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (simulateError) return const Err(NetworkError());
    if (simulateEmpty) {
      return const Ok(
        MealSelectionPageData(
          healthSummary: HealthSummary(
            bmi: 0,
            caloriesGoal: 0,
            caloriesConsumedToday: 0,
          ),
        ),
      );
    }
    return const Ok(
      MealSelectionPageData(
        healthSummary: HealthSummary(
          bmi: 22.4,
          caloriesGoal: 1850,
          caloriesConsumedToday: 620,
        ),
        existingSelection: ExistingMealSelection(
          meals: [MealSlot.breakfast, MealSlot.lunch],
          durationDays: 14,
          planCaloriesGoal: 1850,
          isLocked: false,
        ),
      ),
    );
  }

  @override
  Future<Result<bool>> saveDraft(MealSelectionDraft draft) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (simulateError) return const Err(NetworkError());
    return const Ok(true);
  }
}
