import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/food_item.dart';
import 'package:frontend/models/meal_log.dart';
import 'package:frontend/models/result.dart';
import 'package:frontend/page/meal_select_sheet.dart';
import 'package:frontend/services/meal_log_service.dart';

MealLog _eatenLunchLog({required DateTime eatenAt}) => MealLog(
  id: 1,
  logDate: DateTime.now(),
  mealType: MealType.lunch,
  items: [
    MealLogItem(
      id: 10,
      foodItemId: 1,
      foodItemName: 'ข้าวผัดกุ้ง',
      quantity: 1,
      isEaten: true,
      eatenAt: eatenAt,
    ),
  ],
);

class _FakeMealLogService implements MealLogService {
  final MealLog Function() logProvider;
  _FakeMealLogService(this.logProvider);

  @override
  Future<Result<MealLog>> undoItemEaten(int itemId) async {
    final log = logProvider();
    return Ok(MealLog(
      id: log.id,
      logDate: log.logDate,
      mealType: log.mealType,
      items: log.items.map((i) => MealLogItem(
        id: i.id,
        foodItemId: i.foodItemId,
        foodItemName: i.foodItemName,
        quantity: i.quantity,
        isEaten: false,
      )).toList(),
    ));
  }

  @override
  Future<Result<MealLogFetchOutcome>> getOrCreateLog({required MealType mealType, DateTime? date}) async =>
      throw UnimplementedError();
  @override
  Future<Result<MealLog>> addItem({required int logId, required int foodItemId, int? servingSizeId, double quantity = 1.0, bool notify = true}) async =>
      throw UnimplementedError();
  @override
  Future<Result<MealLog>> markItemEaten(int itemId, {bool notify = true}) async => throw UnimplementedError();
  @override
  Future<Result<List<MealLog>>> fetchLogs({DateTime? date, DateTime? from, DateTime? to}) async => const Ok([]);
  @override
  Future<Result<List<FoodItem>>> fetchRecentItems({int limit = 5}) async => const Ok([]);
  @override
  Future<Result<MealLog>> deleteItem(int itemId) async => throw UnimplementedError();
}

void main() {
  testWidgets('shows "ยกเลิก" for an eaten meal within the 5-minute undo window', (tester) async {
    final log = _eatenLunchLog(eatenAt: DateTime.now().subtract(const Duration(minutes: 1)));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MealSelectSheet(
          mealLogService: _FakeMealLogService(() => log),
          todayLogs: [log],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ทานแล้ว'), findsOneWidget);
    expect(find.text('ยกเลิก'), findsOneWidget);
  });

  testWidgets('does not show "ยกเลิก" once the 5-minute window has passed', (tester) async {
    final log = _eatenLunchLog(eatenAt: DateTime.now().subtract(const Duration(minutes: 10)));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MealSelectSheet(
          mealLogService: _FakeMealLogService(() => log),
          todayLogs: [log],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ทานแล้ว'), findsOneWidget);
    expect(find.text('ยกเลิก'), findsNothing);
  });

  testWidgets('tapping "ยกเลิก" updates the sheet state without closing it', (tester) async {
    final log = _eatenLunchLog(eatenAt: DateTime.now().subtract(const Duration(minutes: 1)));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MealSelectSheet(
          mealLogService: _FakeMealLogService(() => log),
          todayLogs: [log],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();

    // หลังยกเลิก สถานะในชีทต้องเปลี่ยนเป็น "บันทึกแล้ว" (ยังไม่ทาน) ทันที
    // ไม่ต้องปิดชีทแล้วเปิดใหม่ถึงจะเห็นผล
    expect(find.text('บันทึกแล้ว'), findsOneWidget);
    expect(find.text('ทานแล้ว'), findsNothing);
    expect(find.text('ยกเลิก'), findsNothing);
  });
}
