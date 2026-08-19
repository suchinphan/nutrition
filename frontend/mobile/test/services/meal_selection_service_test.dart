import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/models/app_error.dart';
import 'package:frontend/models/dashboard_data.dart' show BmiStatus;
import 'package:frontend/models/meal_selection_data.dart';
import 'package:frontend/services/meal_selection_service.dart';

void main() {
  group('MockMealSelectionService.fetchPageData', () {
    test('default -> Ok with sample data', () async {
      const service = MockMealSelectionService();
      final result = await service.fetchPageData();
      result.when(
        ok: (data) {
          expect(data.healthSummary.bmi, greaterThan(0));
          expect(data.existingSelection?.meals, contains(MealSlot.breakfast));
        },
        err: (e) => fail('expected Ok, got ${e.toUserMessage()}'),
      );
    });

    test('simulateError -> Err(NetworkError)', () async {
      const service = MockMealSelectionService(simulateError: true);
      final result = await service.fetchPageData();
      result.when(
        ok: (_) => fail('expected Err'),
        err: (e) => expect(e, isA<NetworkError>()),
      );
    });

    test('simulateEmpty -> Ok with empty page data', () async {
      const service = MockMealSelectionService(simulateEmpty: true);
      final result = await service.fetchPageData();
      result.when(
        ok: (data) => expect(data.isEmpty, isTrue),
        err: (e) => fail('expected Ok, got ${e.toUserMessage()}'),
      );
    });
  });

  group('HealthSummary.bmiStatus', () {
    final cases = {
      18.0: BmiStatus.underweight,
      20.0: BmiStatus.normal,
      23.5: BmiStatus.overweight,
      27.0: BmiStatus.obese,
    };

    for (final entry in cases.entries) {
      test('bmi ${entry.key} -> ${entry.value}', () {
        final summary = HealthSummary(
          bmi: entry.key,
          caloriesGoal: 1800,
          caloriesConsumedToday: 0,
        );
        expect(summary.bmiStatus, entry.value);
      });
    }
  });

  group('HealthSummary.fromJson', () {
    test('reads calories_goal from the real GET /user/<id> shape', () {
      // ตรง shape ที่ _serialize_user_profile ใน backend/api.py ส่งจริง —
      // เดิม fromJson อ่าน key ผิดเป็น 'recommended_calories' (ไม่มีจริงใน
      // response) ทำให้ caloriesGoal เป็น 0 ค้างเสมอ
      final summary = HealthSummary.fromJson({
        'bmi': 22.4,
        'calories_goal': 1850,
        'total_calories_eaten': 620,
      });
      expect(summary.caloriesGoal, 1850);
    });
  });

  group('MealSelectionDraft', () {
    test('toJson serializes meal slots to Thai labels', () {
      const draft = MealSelectionDraft(
        meals: [MealSlot.breakfast, MealSlot.dinner],
        durationDays: 14,
      );
      expect(draft.toJson(), {
        'meal': ['เช้า', 'เย็น'],
        'duration': 14,
      });
    });

    test('totalPlanCalories multiplies daily goal by duration', () {
      const draft = MealSelectionDraft(
        meals: [MealSlot.breakfast],
        durationDays: 7,
      );
      expect(draft.totalPlanCalories(1800), 12600);
    });
  });
}
