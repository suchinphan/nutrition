import '../models/app_error.dart';
import '../models/dashboard_data.dart';
import '../models/result.dart';
import '../models/weekly_summary.dart';
import 'typed_api_client.dart';

/// สัญญา (interface) ของ service ที่ดึงข้อมูลแดชบอร์ด แยกจาก implementation
/// เพื่อสลับ mock/HTTP ได้โดยไม่ต้องแก้โค้ด UI (ดู dashboard_service_factory.dart)
abstract class DashboardService {
  Future<Result<DashboardData>> fetchDashboard(String userId);

  /// สรุปภาพรวม 7 วันล่าสุดสำหรับประกอบเป็นประโยคไทย (การ์ด "สรุปรายสัปดาห์"
  /// บน DashboardPage) — แยก endpoint จาก fetchDashboard เพราะเป็นข้อมูลคนละ
  /// scope กัน (วันนี้ vs 7 วันย้อนหลัง) ไม่อยากให้ endpoint หลักช้าลงเพราะ
  /// ต้องรวมทุกอย่างในคำขอเดียว
  Future<Result<WeeklySummaryData>> fetchWeeklySummary();
}

/// implementation จริงที่ยิง HTTP ไปหา backend ผ่าน [TypedApiClient]
/// ดู docs/api_contract.md สำหรับรูปแบบ JSON ที่ endpoint นี้ต้องคืน
///
/// หมายเหตุ: [userId] รับไว้ตาม interface ที่กำหนด แต่ไม่ได้ฝังใน URL — backend
/// Flask ที่มีอยู่แล้ว (backend/api.py) ระบุตัวผู้ใช้จาก Authorization: Bearer
/// token เพียงอย่างเดียวเสมอ (ดู /api/check_main_page_summary เป็นตัวอย่าง)
/// ไม่มี endpoint ไหนฝัง user id ไว้ใน path เลย จึงตาม convention เดิมของ
/// โปรเจคนี้แทนที่จะสร้าง RESTful path ใหม่แบบ `/api/users/<id>/...`
class HttpDashboardService implements DashboardService {
  final TypedApiClient _client;
  const HttpDashboardService(this._client);

  @override
  Future<Result<DashboardData>> fetchDashboard(String userId) {
    return _client.getJson<DashboardData>(
      '/api/dashboard',
      decode: (json) => DashboardData.fromJson(json as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<WeeklySummaryData>> fetchWeeklySummary() {
    return _client.getJson<WeeklySummaryData>(
      '/api/dashboard/weekly-summary',
      decode: (json) => WeeklySummaryData.fromJson(json as Map<String, dynamic>),
    );
  }
}

/// mock implementation — เดิมมีโค้ดสร้างข้อมูลตัวอย่างซ้ำกัน 3 ฟังก์ชัน
/// ในหน้าต่างๆ รวมเป็นแหล่งเดียวที่นี่ เรียกผ่าน createDashboardService()
/// (ดู services/dashboard_service_factory.dart) เมื่อรันด้วย
/// --dart-define=USE_MOCK_DASHBOARD=true
class MockDashboardService implements DashboardService {
  /// จำลอง error ทุกครั้งที่เรียก (สำหรับทดสอบสถานะ error/retry)
  final bool simulateError;

  /// จำลองผู้ใช้ที่ยังไม่มีข้อมูลบันทึกวันนี้ (สำหรับทดสอบสถานะ empty)
  final bool simulateEmpty;

  const MockDashboardService({
    this.simulateError = false,
    this.simulateEmpty = false,
  });

  @override
  Future<Result<DashboardData>> fetchDashboard(String userId) async {
    await Future.delayed(const Duration(milliseconds: 900));
    if (simulateError) return const Err(NetworkError());
    return Ok(simulateEmpty ? _emptyData() : _sampleData());
  }

  @override
  Future<Result<WeeklySummaryData>> fetchWeeklySummary() async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (simulateError) return const Err(NetworkError());
    if (simulateEmpty) {
      return const Ok(WeeklySummaryData(
        daysOnTarget: 0,
        daysOverGoal: 0,
        daysUnderGoal: 0,
        avgEatenCalories: 0,
        streakDaysLogged: 0,
      ));
    }
    return const Ok(WeeklySummaryData(
      daysOnTarget: 4,
      daysOverGoal: 2,
      daysUnderGoal: 1,
      avgEatenCalories: 1830,
      streakDaysLogged: 5,
      mostFrequentCategory: 'อาหารจานเดียว',
    ));
  }

  DashboardData _sampleData() {
    final today = DateTime.now();
    const sampleConsumed = [
      1750.0,
      1890.0,
      2100.0,
      1600.0,
      2250.0,
      1980.0,
      1400.0,
    ];
    return DashboardData(
      caloriesConsumed: 1400,
      caloriesPlanned: 1650,
      caloriesGoal: 2000,
      meals: const [
        MealCheckItem(label: 'เช้า', status: MealStatus.done),
        MealCheckItem(label: 'กลางวัน', status: MealStatus.done),
        MealCheckItem(label: 'เย็น', status: MealStatus.pending),
      ],
      weightKg: 65.2,
      bmi: 22.4,
      bmiStatus: BmiStatus.normal,
      last7Days: List.generate(
        7,
        (i) => DailyCalorie(
          date: today.subtract(Duration(days: 6 - i)),
          consumedKcal: sampleConsumed[i],
          goalKcal: 2000,
        ),
      ),
      shortcuts: const [], // เมนูลัดเป็น UI-only ประกอบที่ฝั่งหน้าจอ ไม่ใช่ที่นี่
    );
  }

  DashboardData _emptyData() {
    final today = DateTime.now();
    return DashboardData(
      caloriesConsumed: 0,
      caloriesPlanned: 0,
      caloriesGoal: 2000,
      meals: const [
        MealCheckItem(label: 'เช้า', status: MealStatus.pending),
        MealCheckItem(label: 'กลางวัน', status: MealStatus.pending),
        MealCheckItem(label: 'เย็น', status: MealStatus.pending),
      ],
      weightKg: 0,
      bmi: 0,
      bmiStatus: BmiStatus.normal,
      last7Days: List.generate(
        7,
        (i) => DailyCalorie(
          date: today.subtract(Duration(days: 6 - i)),
          consumedKcal: 0,
          goalKcal: 2000,
        ),
      ),
      shortcuts: const [],
    );
  }
}
