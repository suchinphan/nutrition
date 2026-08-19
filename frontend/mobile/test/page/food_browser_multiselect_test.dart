import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/food_item.dart';
import 'package:frontend/models/meal_log.dart';
import 'package:frontend/models/result.dart';
import 'package:frontend/page/food_browser_page.dart';
import 'package:frontend/services/data_events.dart';
import 'package:frontend/services/food_item_service.dart';
import 'package:frontend/services/meal_log_service.dart';

final _pad = FoodItem(
  id: 1,
  categoryId: 1,
  categoryType: 'food',
  name: 'Pad Krapow',
  nameTh: 'ผัดกะเพรา',
  calories: 500,
  imageUrl: '',
  servingSizes: const [ServingSize(id: 1, unitNameTh: 'จาน', caloriesMultiplier: 1.0)],
  allergens: const [],
  allergyWarning: false,
);
final _khaoMan = FoodItem(
  id: 2,
  categoryId: 1,
  categoryType: 'food',
  name: 'Khao Man Gai',
  nameTh: 'ข้าวมันไก่',
  calories: 450,
  imageUrl: '',
  servingSizes: const [ServingSize(id: 2, unitNameTh: 'จาน', caloriesMultiplier: 1.0)],
  allergens: const [],
  allergyWarning: false,
);

class _FakeFoodItemService implements FoodItemService {
  @override
  Future<Result<List<FoodItem>>> fetchFoodItems({String? type, int? categoryId, String? search}) async =>
      Ok([_pad, _khaoMan]);
  @override
  Future<Result<FoodItem>> fetchFoodItemById(int id) async => Ok(_pad);
  @override
  Future<Result<List<FoodItem>>> fetchPopularItems({String? type, int limit = 10}) async => const Ok([]);
  @override
  Future<Result<List<String>>> fetchFoodTypes() async => const Ok(['food', 'drink', 'dessert']);
}

/// จำลอง response มาไม่เรียงลำดับ — คำขอของ filter แรก ("อาหาร") ตอบช้ากว่า
/// คำขอของ filter ที่สอง ("ของหวาน") ที่ยิงทีหลัง เพื่อทดสอบว่า _load()'s
/// generation guard ทิ้ง response เก่าที่มาถึงทีหลังจริง ไม่ทับผลลัพธ์ใหม่
class _OutOfOrderFoodItemService implements FoodItemService {
  @override
  Future<Result<List<FoodItem>>> fetchFoodItems({String? type, int? categoryId, String? search}) async {
    if (type == 'food') {
      await Future.delayed(const Duration(milliseconds: 100));
      return Ok([_pad]);
    }
    await Future.delayed(const Duration(milliseconds: 10));
    return Ok([_khaoMan]);
  }

  @override
  Future<Result<FoodItem>> fetchFoodItemById(int id) async => Ok(_pad);
  @override
  Future<Result<List<FoodItem>>> fetchPopularItems({String? type, int limit = 10}) async => const Ok([]);
  @override
  Future<Result<List<String>>> fetchFoodTypes() async => const Ok(['food', 'drink', 'dessert']);
}

class _FakeMealLogService implements MealLogService {
  @override
  Future<Result<MealLog>> addItem({required int logId, required int foodItemId, int? servingSizeId, double quantity = 1.0, bool notify = true}) async {
    // จำลองพฤติกรรมจริงของ HttpMealLogService.addItem — ยิง MealLogEvents
    // เฉพาะตอน notify=true เท่านั้น ให้เทสต์นับจำนวนครั้งที่ยิงจริงได้
    if (notify) MealLogEvents.instance.changed();
    return Ok(MealLog(id: logId, logDate: DateTime(2026, 1, 1), mealType: MealType.lunch, items: const []));
  }
  @override
  Future<Result<MealLogFetchOutcome>> getOrCreateLog({required MealType mealType, DateTime? date}) async =>
      throw UnimplementedError();
  @override
  Future<Result<List<FoodItem>>> fetchRecentItems({int limit = 5}) async => const Ok([]);
  @override
  Future<Result<List<MealLog>>> fetchLogs({DateTime? date, DateTime? from, DateTime? to}) async => const Ok([]);
  @override
  Future<Result<MealLog>> markItemEaten(int itemId, {bool notify = true}) async => throw UnimplementedError();
  @override
  Future<Result<MealLog>> undoItemEaten(int itemId) async => throw UnimplementedError();
  @override
  Future<Result<MealLog>> deleteItem(int itemId) async => throw UnimplementedError();
}

void main() {
  testWidgets('select two food items in a row without crashing', (tester) async {
    final mealLog = MealLog(id: 1, logDate: DateTime(2026, 1, 1), mealType: MealType.lunch, items: const []);
    await tester.pumpWidget(MaterialApp(
      // ต้องใช้ธีมจริงของแอป ไม่ใช่ default ของ Flutter — บั๊ก "BoxConstraints
      // forces an infinite width" ที่เจอจริงมาจาก core/theme/app_theme.dart
      // ตั้ง ElevatedButton minimumSize เป็น Size.fromHeight(48) (กว้าง
      // infinity) ทั้งแอป ธีม default ของ Flutter ไม่มีค่านี้ จึงไม่มีทาง
      // reproduce บั๊กนี้ได้เลยถ้าไม่ใช้ธีมจริง
      theme: AppTheme.light,
      home: FoodBrowserPage(
        mealLog: mealLog,
        foodItemService: _FakeFoodItemService(),
        mealLogService: _FakeMealLogService(),
      ),
    ));
    await tester.pumpAndSettle();

    // แตะเมนูแรก
    await tester.tap(find.text('ผัดกะเพรา'));
    await tester.pumpAndSettle();
    expect(find.text('เพิ่มลงมื้อกลางวัน'), findsOneWidget);

    // กดเพิ่มลงตะกร้า
    await tester.tap(find.text('เพิ่มลงมื้อกลางวัน'));
    await tester.pumpAndSettle();

    // แตะเมนูที่สอง — จุดที่ผู้ใช้รายงานว่า popup ไม่ขึ้น/error แดง
    await tester.tap(find.text('ข้าวมันไก่'));
    await tester.pumpAndSettle();
    expect(find.text('เพิ่มลงมื้อกลางวัน'), findsOneWidget);
  });

  testWidgets('tap the same food item twice in a row', (tester) async {
    final mealLog = MealLog(id: 1, logDate: DateTime(2026, 1, 1), mealType: MealType.lunch, items: const []);
    await tester.pumpWidget(MaterialApp(
      // ต้องใช้ธีมจริงของแอป ไม่ใช่ default ของ Flutter — บั๊ก "BoxConstraints
      // forces an infinite width" ที่เจอจริงมาจาก core/theme/app_theme.dart
      // ตั้ง ElevatedButton minimumSize เป็น Size.fromHeight(48) (กว้าง
      // infinity) ทั้งแอป ธีม default ของ Flutter ไม่มีค่านี้ จึงไม่มีทาง
      // reproduce บั๊กนี้ได้เลยถ้าไม่ใช้ธีมจริง
      theme: AppTheme.light,
      home: FoodBrowserPage(
        mealLog: mealLog,
        foodItemService: _FakeFoodItemService(),
        mealLogService: _FakeMealLogService(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ผัดกะเพรา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มลงมื้อกลางวัน'));
    await tester.pumpAndSettle();

    // เมนูเดิมอีกครั้ง (ตอนนี้ตะกร้ามี "ผัดกะเพรา" อยู่แล้ว 1 รายการ ซึ่งโชว์
    // เป็น Chip ในแถบล่างด้วย ชื่อซ้ำกับใน list หลัก)
    await tester.tap(find.text('ผัดกะเพรา').first);
    await tester.pumpAndSettle();
    expect(find.text('เพิ่มลงมื้อกลางวัน'), findsOneWidget);
  });

  testWidgets('remove an item from the cart tray via chip delete', (tester) async {
    final mealLog = MealLog(id: 1, logDate: DateTime(2026, 1, 1), mealType: MealType.lunch, items: const []);
    await tester.pumpWidget(MaterialApp(
      // ต้องใช้ธีมจริงของแอป ไม่ใช่ default ของ Flutter — บั๊ก "BoxConstraints
      // forces an infinite width" ที่เจอจริงมาจาก core/theme/app_theme.dart
      // ตั้ง ElevatedButton minimumSize เป็น Size.fromHeight(48) (กว้าง
      // infinity) ทั้งแอป ธีม default ของ Flutter ไม่มีค่านี้ จึงไม่มีทาง
      // reproduce บั๊กนี้ได้เลยถ้าไม่ใช้ธีมจริง
      theme: AppTheme.light,
      home: FoodBrowserPage(
        mealLog: mealLog,
        foodItemService: _FakeFoodItemService(),
        mealLogService: _FakeMealLogService(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ผัดกะเพรา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มลงมื้อกลางวัน'));
    await tester.pumpAndSettle();

    // ลบรายการในตะกร้าผ่านปุ่ม x ของ Chip
    final deleteIcon = find.descendant(of: find.byType(Chip), matching: find.byIcon(Icons.cancel));
    expect(deleteIcon, findsOneWidget);
    await tester.tap(deleteIcon);
    await tester.pumpAndSettle();
  });

  testWidgets('add items then confirm', (tester) async {
    final mealLog = MealLog(id: 1, logDate: DateTime(2026, 1, 1), mealType: MealType.lunch, items: const []);
    await tester.pumpWidget(MaterialApp(
      // ต้องใช้ธีมจริงของแอป ไม่ใช่ default ของ Flutter — บั๊ก "BoxConstraints
      // forces an infinite width" ที่เจอจริงมาจาก core/theme/app_theme.dart
      // ตั้ง ElevatedButton minimumSize เป็น Size.fromHeight(48) (กว้าง
      // infinity) ทั้งแอป ธีม default ของ Flutter ไม่มีค่านี้ จึงไม่มีทาง
      // reproduce บั๊กนี้ได้เลยถ้าไม่ใช้ธีมจริง
      theme: AppTheme.light,
      home: FoodBrowserPage(
        mealLog: mealLog,
        foodItemService: _FakeFoodItemService(),
        mealLogService: _FakeMealLogService(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ผัดกะเพรา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มลงมื้อกลางวัน'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();
  });

  testWidgets('confirming a multi-item cart fires MealLogEvents once, not once per item', (tester) async {
    final mealLog = MealLog(id: 1, logDate: DateTime(2026, 1, 1), mealType: MealType.lunch, items: const []);
    var notifyCount = 0;
    void onChanged() => notifyCount++;
    MealLogEvents.instance.addListener(onChanged);
    addTearDown(() => MealLogEvents.instance.removeListener(onChanged));

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: FoodBrowserPage(
        mealLog: mealLog,
        foodItemService: _FakeFoodItemService(),
        mealLogService: _FakeMealLogService(),
      ),
    ));
    await tester.pumpAndSettle();

    // เลือก 2 เมนูลงตะกร้าก่อนยืนยัน
    await tester.tap(find.text('ผัดกะเพรา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มลงมื้อกลางวัน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ข้าวมันไก่'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มลงมื้อกลางวัน'));
    await tester.pumpAndSettle();

    notifyCount = 0; // เอาแค่ที่เกิดขึ้นระหว่าง "ยืนยัน" เท่านั้น
    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();

    // 2 เมนูในตะกร้า ต้องยิง MealLogEvents แค่ 1 ครั้งหลัง loop จบ ไม่ใช่ 2
    // ครั้งตามจำนวนเมนู (ไม่งั้น Dashboard/History ที่ค้างใน IndexedStack จะ
    // รีเฟรชซ้อนกันจนถล่ม dev server — เจอจริงตอนยืนยัน 5 เมนูรวด)
    expect(notifyCount, 1);
  });

  testWidgets('tap food card while favorite toggle is in flight', (tester) async {
    final mealLog = MealLog(id: 1, logDate: DateTime(2026, 1, 1), mealType: MealType.lunch, items: const []);
    await tester.pumpWidget(MaterialApp(
      // ต้องใช้ธีมจริงของแอป ไม่ใช่ default ของ Flutter — บั๊ก "BoxConstraints
      // forces an infinite width" ที่เจอจริงมาจาก core/theme/app_theme.dart
      // ตั้ง ElevatedButton minimumSize เป็น Size.fromHeight(48) (กว้าง
      // infinity) ทั้งแอป ธีม default ของ Flutter ไม่มีค่านี้ จึงไม่มีทาง
      // reproduce บั๊กนี้ได้เลยถ้าไม่ใช้ธีมจริง
      theme: AppTheme.light,
      home: FoodBrowserPage(
        mealLog: mealLog,
        foodItemService: _FakeFoodItemService(),
        mealLogService: _FakeMealLogService(),
      ),
    ));
    await tester.pumpAndSettle();

    // แตะดาวก่อน (ยิง network request ค้างอยู่เพราะไม่มี server จริงใน test)
    await tester.tap(find.byIcon(Icons.star_border).first);
    await tester.pump(const Duration(milliseconds: 20));
    // แล้วรีบแตะการ์ดเมนูทันทีก่อน request ด้านบนจะตอบกลับ
    await tester.tap(find.text('ผัดกะเพรา'));
    await tester.pumpAndSettle();
    expect(find.text('เพิ่มลงมื้อกลางวัน'), findsOneWidget);
  });

  testWidgets('stale out-of-order type-filter response is discarded, not applied', (tester) async {
    final mealLog = MealLog(id: 1, logDate: DateTime(2026, 1, 1), mealType: MealType.lunch, items: const []);
    await tester.pumpWidget(MaterialApp(
      // ต้องใช้ธีมจริงของแอป ไม่ใช่ default ของ Flutter — บั๊ก "BoxConstraints
      // forces an infinite width" ที่เจอจริงมาจาก core/theme/app_theme.dart
      // ตั้ง ElevatedButton minimumSize เป็น Size.fromHeight(48) (กว้าง
      // infinity) ทั้งแอป ธีม default ของ Flutter ไม่มีค่านี้ จึงไม่มีทาง
      // reproduce บั๊กนี้ได้เลยถ้าไม่ใช้ธีมจริง
      theme: AppTheme.light,
      home: FoodBrowserPage(
        mealLog: mealLog,
        foodItemService: _OutOfOrderFoodItemService(),
        mealLogService: _FakeMealLogService(),
      ),
    ));
    await tester.pumpAndSettle();

    // แตะ "อาหาร" (ตอบช้า 100ms) แล้วรีบแตะ "ของหวาน" (ตอบเร็ว 10ms) ก่อน
    // คำขอแรกจะตอบกลับ — ผลลัพธ์สุดท้ายต้องเป็นของ "ของหวาน" (คลิกล่าสุด)
    // ไม่ใช่ "อาหาร" ที่ตอบมาทีหลังแต่เป็น response เก่ากว่า
    await tester.tap(find.text('อาหาร'));
    await tester.pump(const Duration(milliseconds: 5));
    await tester.tap(find.text('ของหวาน'));
    await tester.pumpAndSettle();

    expect(find.text('ข้าวมันไก่'), findsOneWidget);
    expect(find.text('ผัดกะเพรา'), findsNothing);
  });

  testWidgets('tap food card while the search field still has keyboard focus', (tester) async {
    final mealLog = MealLog(id: 1, logDate: DateTime(2026, 1, 1), mealType: MealType.lunch, items: const []);
    await tester.pumpWidget(MaterialApp(
      // ต้องใช้ธีมจริงของแอป ไม่ใช่ default ของ Flutter — บั๊ก "BoxConstraints
      // forces an infinite width" ที่เจอจริงมาจาก core/theme/app_theme.dart
      // ตั้ง ElevatedButton minimumSize เป็น Size.fromHeight(48) (กว้าง
      // infinity) ทั้งแอป ธีม default ของ Flutter ไม่มีค่านี้ จึงไม่มีทาง
      // reproduce บั๊กนี้ได้เลยถ้าไม่ใช้ธีมจริง
      theme: AppTheme.light,
      home: FoodBrowserPage(
        mealLog: mealLog,
        foodItemService: _FakeFoodItemService(),
        mealLogService: _FakeMealLogService(),
      ),
    ));
    await tester.pumpAndSettle();

    // แตะช่องค้นหาให้ focus (คีย์บอร์ดเปิด) แล้วพิมพ์บางอย่าง แต่ "ไม่" กด
    // ปิดคีย์บอร์ดก่อนแตะเมนู — จำลองพฤติกรรมจริงที่ผู้ใช้ค้นหาแล้วแตะเลือก
    // เมนูจากผลลัพธ์ทันทีโดยคีย์บอร์ดยังค้างอยู่
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'กะเพรา');
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.testTextInput.isVisible, isTrue, reason: 'ช่องค้นหาต้อง focus/คีย์บอร์ดเปิดอยู่ก่อนแตะเมนู');

    // หมายเหตุ: widget test พิสูจน์ race condition จริง (คีย์บอร์ด animate
    // ปิดพร้อม sheet เปิดในเฟรมเดียวกันบนเครื่องจริง) ไม่ได้ เพราะ test
    // binding จัดการ focus transition ตอน push route แบบ synchronous เทสต์
    // นี้เช็คได้แค่ว่า flow ยังทำงานถูกต้องเมื่อช่องค้นหามี focus ค้างอยู่
    await tester.tap(find.text('ผัดกะเพรา'));
    await tester.pumpAndSettle();
    expect(find.text('เพิ่มลงมื้อกลางวัน'), findsOneWidget);
  });

  testWidgets('selecting an item over the old per-meal cap shows no quota warning and stays confirmable', (tester) async {
    // เดิมมี cap ต่อมื้อ (calories_goal/3) ทั้งเตือน UI และบล็อกจริงฝั่ง
    // server — ผู้ใช้ขอให้เอาออกทั้งคู่ หยิบเท่าไรก็ได้ ไม่มีคำเตือนโควตา
    // อีกต่อไป (ดู HealthGoalCycle.mealsOverQuota สำหรับสรุปผลตอนจบรอบแทน)
    // calories_goal 900 -> cap เดิม = 300 kcal, ข้าวมันไก่ 450 kcal เกินแน่ๆ
    final mealLog = MealLog(id: 1, logDate: DateTime(2026, 1, 1), mealType: MealType.lunch, caloriesGoal: 900, items: const []);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: FoodBrowserPage(
        mealLog: mealLog,
        foodItemService: _FakeFoodItemService(),
        mealLogService: _FakeMealLogService(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ข้าวมันไก่'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มลงมื้อกลางวัน'));
    await tester.pumpAndSettle();

    expect(find.textContaining('เกินโควตา'), findsNothing);
    expect(find.textContaining('เหลือโควตา'), findsNothing);
    expect(find.text('ยืนยัน'), findsOneWidget);
  });
}
