import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/food_item.dart';
import 'package:frontend/models/meal_log.dart';
import 'package:frontend/models/result.dart';
import 'package:frontend/page/food_browser_page.dart';
import 'package:frontend/page/meal_select_sheet.dart';
import 'package:frontend/services/food_item_service.dart';
import 'package:frontend/services/meal_log_service.dart';

MealLog _breakfastLogWithThreeItems() => MealLog(
  id: 1,
  logDate: DateTime.now(),
  mealType: MealType.breakfast,
  caloriesGoal: 1990,
  items: const [
    MealLogItem(id: 10, foodItemId: 1, foodItemName: 'ข้าวเหนียวมะม่วง', quantity: 1, caloriesActual: 433, isEaten: true),
    MealLogItem(id: 11, foodItemId: 2, foodItemName: 'วุ้นตาล', quantity: 1, caloriesActual: 140, isEaten: true),
    MealLogItem(id: 12, foodItemId: 3, foodItemName: 'นมถั่วเหลือง', quantity: 1, caloriesActual: 79, isEaten: true),
  ],
);

class _FakeMealLogService implements MealLogService {
  @override
  Future<Result<MealLog>> deleteItem(int itemId) async => throw UnimplementedError();
  @override
  Future<Result<MealLog>> undoItemEaten(int itemId) async => throw UnimplementedError();
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
}

class _FakeFoodItemService implements FoodItemService {
  @override
  Future<Result<List<FoodItem>>> fetchFoodItems({String? type, int? categoryId, String? search}) async => const Ok([]);
  @override
  Future<Result<FoodItem>> fetchFoodItemById(int id) async => throw UnimplementedError();
  @override
  Future<Result<List<FoodItem>>> fetchPopularItems({String? type, int limit = 10}) async => const Ok([]);
  @override
  Future<Result<List<String>>> fetchFoodTypes() async => const Ok(['food', 'drink', 'dessert']);
}

void main() {
  testWidgets('showManageMealSheet lists every item in the meal, not just the first', (tester) async {
    // เดิม Dashboard โชว์ label แค่เมนูแรก ("ข้าวเหนียวมะม่วง") ผู้ใช้กด
    // เข้าไปดูรายละเอียดไม่ได้เลย — ตอนนี้แตะแถวมื้อแล้วเปิด showManageMealSheet
    // ต้องเห็นครบทั้ง 3 เมนูที่บันทึกไว้จริง
    final log = _breakfastLogWithThreeItems();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showManageMealSheet(
              context,
              mealLogService: _FakeMealLogService(),
              foodItemService: _FakeFoodItemService(),
              log: log,
            ),
            child: const Text('เปิดจัดการมื้อ'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('เปิดจัดการมื้อ'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ข้าวเหนียวมะม่วง'), findsOneWidget);
    expect(find.textContaining('วุ้นตาล'), findsOneWidget);
    expect(find.textContaining('นมถั่วเหลือง'), findsOneWidget);
  });

  testWidgets('meal eaten over 5 minutes ago shows no delete buttons and no add-more button', (tester) async {
    // ผู้ใช้รายงานจริง: มื้อที่ทานไปแล้วเกิน 5 นาที (undo-eaten ล็อกไปแล้ว)
    // แต่ชีทจัดการมื้อยังโชว์ปุ่มลบให้กดได้อยู่ — ต้องกลายเป็นดูอย่างเดียว
    final log = MealLog(
      id: 1,
      logDate: DateTime.now(),
      mealType: MealType.breakfast,
      items: [
        MealLogItem(
          id: 10,
          foodItemId: 1,
          foodItemName: 'ข้าวเหนียวมะม่วง',
          quantity: 1,
          caloriesActual: 433,
          isEaten: true,
          eatenAt: DateTime.now().subtract(const Duration(minutes: 10)),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showManageMealSheet(
              context,
              mealLogService: _FakeMealLogService(),
              foodItemService: _FakeFoodItemService(),
              log: log,
            ),
            child: const Text('เปิดจัดการมื้อ'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('เปิดจัดการมื้อ'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('+ เลือกเมนูเพิ่ม'), findsNothing);
    expect(find.textContaining('แก้ไขไม่ได้อีก'), findsOneWidget);
  });

  testWidgets('meal eaten within 5 minutes still shows delete and add-more buttons', (tester) async {
    final log = MealLog(
      id: 1,
      logDate: DateTime.now(),
      mealType: MealType.breakfast,
      items: [
        MealLogItem(
          id: 10,
          foodItemId: 1,
          foodItemName: 'ข้าวเหนียวมะม่วง',
          quantity: 1,
          caloriesActual: 433,
          isEaten: true,
          eatenAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showManageMealSheet(
              context,
              mealLogService: _FakeMealLogService(),
              foodItemService: _FakeFoodItemService(),
              log: log,
            ),
            child: const Text('เปิดจัดการมื้อ'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('เปิดจัดการมื้อ'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.text('+ เลือกเมนูเพิ่ม'), findsOneWidget);
  });

  testWidgets('add-more with incomplete profile shows the profile dialog, not FoodBrowserPage', (tester) async {
    // เดิม "+ เลือกเมนูเพิ่ม" เปิด FoodBrowserPage ตรงๆ โดยไม่เช็คข้อมูล
    // โปรไฟล์เลย ต่างจากทางเข้าอื่นๆ ที่ผ่าน startMealLogFlow() ซึ่งเช็คเสมอ —
    // AuthService() เป็น singleton ที่ยังไม่เคย login ในเทสนี้ (user == null)
    // จำลองสถานะ "ข้อมูลโปรไฟล์ยังไม่ครบ" ได้พอดี
    final log = MealLog(
      id: 1,
      logDate: DateTime.now(),
      mealType: MealType.breakfast,
      items: [
        MealLogItem(
          id: 10,
          foodItemId: 1,
          foodItemName: 'ข้าวเหนียวมะม่วง',
          quantity: 1,
          caloriesActual: 433,
          isEaten: true,
          eatenAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showManageMealSheet(
              context,
              mealLogService: _FakeMealLogService(),
              foodItemService: _FakeFoodItemService(),
              log: log,
            ),
            child: const Text('เปิดจัดการมื้อ'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('เปิดจัดการมื้อ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ เลือกเมนูเพิ่ม'));
    await tester.pumpAndSettle();

    expect(find.text('ข้อมูลยังไม่ครบ'), findsOneWidget);
    expect(find.byType(FoodBrowserPage), findsNothing);
  });
}
