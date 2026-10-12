import 'dart:async';
import 'package:flutter/material.dart';
import '../core/notification/notification_helper.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/widgets.dart';
import '../models/dashboard_data.dart';
import '../models/food_item.dart';
import '../models/health_goal_cycle.dart';
import '../models/meal_log.dart';
import '../models/weekly_summary.dart';
import '../services/app_config.dart';
import '../services/auth_service.dart';
import '../services/dashboard_service.dart';
import '../services/data_events.dart';
import '../services/food_item_service.dart';
import '../services/ai_recommend_service.dart';
import '../services/health_goal_cycle_service.dart';
import '../services/meal_log_service.dart';
import '../services/storage_service.dart';
import 'backfill_section.dart';
import 'login_page.dart';
import 'meal_log_flow.dart';
import 'meal_select_sheet.dart';
import 'notifications_page.dart';
import 'serving_picker_sheet.dart';
import 'suggest_menu_page.dart';

// เก็บ flag "เคยถาม permission แจ้งเตือนแล้ว" ผ่าน StorageService (มีอยู่แล้ว
// ไม่เพิ่ม dependency ใหม่อย่าง shared_preferences) — กันถามซ้ำทุกครั้งที่
// เปิดแอป/กลับมาหน้า Dashboard ตามที่โจทย์ห้ามไว้
const _kNotificationPermissionAskedKey = 'notification_permission_asked';


class _Macros {
  final double protein;
  final double carbs;
  final double fat;
  const _Macros({this.protein = 0, this.carbs = 0, this.fat = 0});
}

class _DashboardViewData {
  final DashboardData summary;
  final List<MealLog> todayLogs;
  final _Macros macros;
  final WeeklySummaryData? weeklySummary;
  const _DashboardViewData({
    required this.summary,
    required this.todayLogs,
    required this.macros,
    this.weeklySummary,
  });
}

/// หน้าแดชบอร์ด — จุดแรกที่ผู้ใช้เห็นทุกครั้งที่เปิดแอป ต้องรู้ทันทีว่าวันนี้
/// ทานไปกี่ kcal จากเป้ากี่ kcal (ดู lib/core/theme, lib/core/widgets)
class DashboardPage extends StatefulWidget {
  final DashboardService dashboardService;
  final MealLogService mealLogService;
  final FoodItemService foodItemService;

  const DashboardPage({
    super.key,
    required this.dashboardService,
    required this.mealLogService,
    required this.foodItemService,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  _DashboardViewData? _data;
  bool _loading = true;
  bool _hasError = false;
  final HealthGoalCycleService _goalCycleService = createHealthGoalCycleService();
  final AiRecommendService _aiRecommendService = createAiRecommendService();
  // null = วันนี้ — ผู้ใช้รายงานจริง: กดเมนูที่ AI แนะนำแล้วอยากเลือกบันทึก
  // ย้อนหลังได้เหมือน BackfillSection ไม่ใช่ล็อกไว้ที่วันนี้เสมอ
  DateTime? _aiRecommendDate;
  Timer? _undoLinkTicker;
  late String _lastAuthSignature;

  // เดิม _onAuthChanged() สั่ง _retry() ทุกครั้งที่ AuthService.notifyListeners()
  // ยิง ไม่ว่าจะเกี่ยวกับ login state จริงๆ หรือไม่ (เช่น ProfilePage._init
  // เรียก refreshProfile()/saveUser() ตอนซิงค์โปรไฟล์ก็ยิง notifyListeners()
  // เหมือนกัน) พอทุกแท็บใน IndexedStack init พร้อมกันตอนแอปเพิ่งเปิด แต่ละ
  // ครั้งที่ AuthService เปลี่ยนแบบไม่เกี่ยวกับ Dashboard เลยก็ทำให้ Dashboard
  // รีเซ็ตเป็น skeleton แล้วยิง fetch ใหม่ถี่ๆ เห็นเป็นจอกะพริบ (บั๊กที่
  // ผู้ใช้รายงานจริง — ยังเหลืออยู่แม้ loadToken() จะข้ามการอ่านซ้ำแล้ว)
  // เทียบ signature (login state + user id + เป้าหมายสุขภาพ/calories_goal)
  // ก่อน ไม่เปลี่ยนจริงไม่ต้อง retry — เดิมเทียบแค่ login state+uid ทำให้
  // เปลี่ยนเป้าหมายสุขภาพจากหน้าโปรไฟล์ (uid เดิม ยัง login อยู่ ไม่เปลี่ยน)
  // ไม่ทำให้ signature ต่างกันเลย Dashboard เลยไม่ retry/รีเฟรชเลย (บั๊กที่
  // ผู้ใช้รายงานจริง: "เป้าหมาย" กับ kcal เป้าที่หน้าหลักไม่ตรงกับที่เพิ่ง
  // บันทึกไว้ในหน้าโปรไฟล์ — ค้างค่าตั้งแต่ครั้งก่อนหน้า)
  // ผู้ใช้รายงานจริง: แก้ "แพ้อาหาร" เป็นไข่ที่หน้าโปรไฟล์แล้วกลับมาหน้าหลัก
  // โดยไม่ pull-to-refresh เอง การ์ด "AI แนะนำเมนู" ยังค้างเสนอเมนูที่มีไข่
  // อยู่ (backend กรอง allergen ออกจากคำแนะนำอยู่แล้วจริงๆ แค่ฝั่งนี้ไม่เคย
  // ยิงขอใหม่) เพราะ signature เดิมเทียบแค่ login state/health_goal/
  // calories_goal ไม่เทียบ food_allergies/chronic_diseases เลย ทั้งที่สอง
  // ค่านี้กำหนดผลการแนะนำเมนูโดยตรง (ดู health_calc.score_food_candidate)
  // เพิ่มเข้ามาให้ _onAuthChanged เห็นการเปลี่ยนแปลงแล้วสั่ง _retry() ให้เอง
  String _authSignature() {
    final auth = AuthService();
    final loggedIn = auth.isLoggedIn && !auth.isGuest;
    final u = auth.user;
    final uid = u?['id']?.toString() ?? '';
    final healthGoal = u?['health_goal']?.toString() ?? '';
    final caloriesGoal = u?['calories_goal']?.toString() ?? '';
    final allergies = u?['food_allergies']?.toString() ?? '';
    final diseases = u?['chronic_diseases']?.toString() ?? '';
    return '$loggedIn:$uid:$healthGoal:$caloriesGoal:$allergies:$diseases';
  }

  @override
  void initState() {
    super.initState();
    _lastAuthSignature = _authSignature();
    _refresh();
    // ลิงก์ "ยกเลิก" ต้องหายไปเองหลัง 5 นาทีแม้ผู้ใช้ไม่ทำอะไรเลย (แค่เวลา
    // ผ่านไปเฉยๆ ไม่มี event ให้ rebuild) — สั่ง rebuild เป็นระยะเบาๆ พอ ไม่ต้อง
    // นับถอยหลังเป็นวินาทีจริงจัง (ตามที่กำหนด)
    _undoLinkTicker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
    // Dashboard เป็น root ของแท็บ "หน้าหลัก" ที่ค้างอยู่ใน IndexedStack ตลอด
    // — ถ้าผู้ใช้ทานแล้ว/บันทึกมื้อจากที่อื่น (เช่น History) ตอน Dashboard
    // ไม่ได้ active ต้องรีเฟรชสดเมื่อกลับมาเห็นโดยไม่ต้องรอ pull-to-refresh
    MealLogEvents.instance.addListener(_onMealLogChanged);
    // ชื่อ/เป้าหมาย/calories_goal ที่แก้จากหน้าโปรไฟล์ (หรือรูปโปรไฟล์ที่
    // อัปโหลดใหม่) ก็ต้องสะท้อนที่ header และตัวเลข kcal ของ Dashboard ทันที
    // เหมือนกัน — AuthService.notifyListeners() ไม่ผูกกับ MealLogEvents จึง
    // ต้องฟังแยกอีกตัว ไม่งั้นข้อมูลโปรไฟล์ที่แสดงจะค้างอยู่ค่าตอนโหลดครั้งแรก
    AuthService().addListener(_onAuthChanged);
    // ขอ permission แจ้งเตือนครั้งแรกตรงนี้ (ถึงหน้า Dashboard หลัง login
    // สำเร็จ) — ไม่ใช่ทันทีตอนเปิดแอปครั้งแรกซึ่งจะดูรุกล้ำเกินไป รอให้ build
    // เฟรมแรกเสร็จก่อนค่อยโชว์ dialog กันชนกับตอนหน้ากำลัง build อยู่
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskNotificationPermission());
  }

  Future<void> _maybeAskNotificationPermission() async {
    if (!mounted) return;
    if (!AuthService().isLoggedIn || AuthService().isGuest) return;

    final storage = StorageService();
    final asked = await storage.read(key: _kNotificationPermissionAskedKey);
    if (asked == 'true' || !mounted) return;

    final wantsToEnable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เปิดการแจ้งเตือน'),
        content: const Text(
          'เปิดการแจ้งเตือนเพื่อ (1) เตือนก่อนช่วงเวลาบันทึกมื้ออาหารจะปิด '
          'และ (2) แจ้งทันทีที่แอดมินตอบข้อความที่คุณแจ้งไว้',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('ไว้ทีหลัง')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('เปิดการแจ้งเตือน')),
        ],
      ),
    );

    // ถามครั้งเดียวพอไม่ว่าจะตอบยังไง (รวมถึงปิด dialog เฉยๆ) — ถ้าปฏิเสธ
    // permission ระบบจริง badge ในแอปยังทำงานได้ปกติ แค่ไม่มี system
    // notification โผล่ (ดู NotificationHelper)
    await storage.write(key: _kNotificationPermissionAskedKey, value: 'true');
    if (wantsToEnable == true) {
      await NotificationHelper.requestPermission();
    }
  }

  @override
  void dispose() {
    MealLogEvents.instance.removeListener(_onMealLogChanged);
    AuthService().removeListener(_onAuthChanged);
    _undoLinkTicker?.cancel();
    super.dispose();
  }

  void _onMealLogChanged() {
    if (!mounted) return;
    _retry();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final sig = _authSignature();
    if (sig == _lastAuthSignature) return;
    _lastAuthSignature = sig;
    _retry();
  }

  void _retry() => _refresh();

  /// โหลด/รีเฟรชข้อมูลแดชบอร์ด — เดิมทุกครั้งที่เรียก (ผ่าน _retry, ทั้งจาก
  /// MealLogEvents/auth เปลี่ยน/บันทึกมื้อ) จะเซ็ต Future ใหม่ให้ FutureBuilder
  /// ซึ่งโชว์ _buildSkeleton() ทับทั้งหน้าระหว่างรอเสมอ ไม่ใช่แค่โล่งวูบ แต่
  /// unmount ทุก widget ใต้ ListView ไปด้วย (widget เดิมที่ตำแหน่งนั้นเป็น
  /// AppSkeletonLoader คนละ type กับของจริง Flutter เลย dispose State เก่า
  /// ทิ้งแล้วสร้างใหม่ทุกครั้งที่ข้อมูลโหลดเสร็จ) — พอ _AiRecommendSection
  /// เก็บ state เอง (ตะกร้า/มื้อที่กำลังเลือกจาก AI แนะนำเมนู) เรื่องนี้กลาย
  /// เป็นบั๊กจริง: เลือกเมนู AI แนะนำ -> เปิด MealSelectSheet (เรียก
  /// getOrCreateLog ซึ่งยิง MealLogEvents.changed() เสมอ) -> หน้าหลักรีเฟรช
  /// กลางอากาศ -> _AiRecommendSectionState โดน dispose ทิ้งระหว่างทาง ->
  /// โค้ดที่เหลือ (fetch food item / เปิด ServingPickerSheet) เจอ mounted
  /// เป็น false แล้วเงียบๆ หยุดทำงาน (ผู้ใช้รายงานจริง: เลือกมื้อแล้วไม่มี
  /// อะไรเกิดขึ้นเลย เด้งกลับมาหน้าหลักเฉยๆ) — ตอนนี้โชว์ skeleton แค่ตอน
  /// โหลดครั้งแรกที่ยังไม่เคยมีข้อมูล (_data == null) ส่วนรีเฟรชพื้นหลังที่
  /// มีข้อมูลอยู่แล้วแค่สลับ _data เงียบๆ ไม่ทุบทั้ง widget tree ทิ้ง
  Future<void> _refresh() async {
    if (_data == null) setState(() => _loading = true);
    try {
      final data = await _load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _hasError = false;
      });
      await _maybeShowGoalCycleResult(data);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // มีข้อมูลเก่าอยู่แล้ว (รีเฟรชพื้นหลังพลาด) แค่คงของเดิมไว้เงียบๆ
        // ไม่ทุบทั้งหน้าเป็น error banner — โชว์ banner เฉพาะตอนไม่มีข้อมูล
        // ให้แสดงเลยเท่านั้น (โหลดครั้งแรกพลาด)
        if (_data == null) _hasError = true;
      });
    }
  }

  /// รอบเป้าหมายสุขภาพ 7 วันเพิ่งหมดอายุและยังไม่เคยเห็น (ดู
  /// DashboardData.goalCycleResult / backend get_dashboard_summary) — เด้ง
  /// dialog สรุปผลทันทีที่เปิดหน้าหลัก แล้วรับทราบกันโผล่ซ้ำรอบถัดไป
  Future<void> _maybeShowGoalCycleResult(_DashboardViewData data) async {
    final cycle = data.summary.goalCycleResult;
    if (cycle == null || !mounted) return;
    final percent = (cycle.successRatio * 100).round();
    final days = cycle.periodEnd.difference(cycle.periodStart).inDays + 1;
    final overDailyQuota = !cycle.isSuccess && cycle.dailyQuotaExcessPercent > 0;
    final overDailyQuotaPercent = cycle.dailyQuotaExcessPercent.round();
    final weightSupported = cycle.weightDelta != null &&
        ((cycle.healthGoal == 'ลดน้ำหนัก' && cycle.weightDelta! < 0) ||
            (cycle.healthGoal == 'เพิ่มน้ำหนัก' && cycle.weightDelta! > 0) ||
            (cycle.healthGoal == 'รักษาน้ำหนัก' && cycle.weightDelta!.abs() <= 1.0));
    final weightSummary = cycle.weightStart != null && cycle.weightEnd != null
        ? _weightResultText(cycle)
        : 'ยังไม่มีข้อมูลน้ำหนักเพียงพอสำหรับยืนยันผล';
    final mealSummary = 'บันทึกมื้ออาหารครบ ${cycle.mealsLogged} จาก ${cycle.mealsAvailable} มื้อที่มีให้เลือก ($percent%)';
    final isOverQuotaButWeightOnTarget = cycle.dailyQuotaExcessPercent > 0 && weightSupported;
    final overQuotaLabel = cycle.healthGoal == 'ลดน้ำหนัก'
        ? 'กินเกินแต่ลดน้ำหนัก'
        : cycle.healthGoal == 'เพิ่มน้ำหนัก'
            ? 'กินเกินแต่เพิ่มน้ำหนัก'
            : 'กินเกินแต่ยังอยู่ในช่วงรักษาน้ำหนัก';
    final failureReason = cycle.successRatio < 0.6
      ? 'เป้าหมายไม่สำเร็จ (ต่ำกว่า 60%)'
      : 'เป้าหมายไม่สำเร็จ';
    final statusText = cycle.isSuccess
      ? '$mealSummary\nเป้าหมายสำเร็จ\n${isOverQuotaButWeightOnTarget ? '$overQuotaLabel: $weightSummary' : weightSummary}'
      : '$mealSummary\n$failureReason\n${overDailyQuota ? 'กินเกินโควตารายวัน $overDailyQuotaPercent%\n' : ''}$weightSummary';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      // ต้องกด "รับทราบ" เท่านั้นถึงจะปิดได้ — เดิม barrierDismissible: false
      // กันแค่แตะข้างนอก ปุ่ม/ท่าทางย้อนกลับ (Android back) ยังหลุดออกได้อยู่
      // (ผู้ใช้ยืนยันชัดเจน: ต้องค้างไว้จนกว่าจะกดปุ่มตกลงเท่านั้น)
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(
            cycle.isSuccess
                ? 'สำเร็จ!'
                : 'เป้าหมายไม่สำเร็จ',
          ),
          content: Text(
            'ครบ $days วันของเป้าหมาย${cycle.healthGoal}แล้ว\n$statusText',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('รับทราบ')),
          ],
        ),
      ),
    );
    await _goalCycleService.acknowledge(cycle.id);
  }

  String _weightResultText(HealthGoalCycle cycle) {
    final start = cycle.weightStart!.toStringAsFixed(1);
    final end = cycle.weightEnd!.toStringAsFixed(1);
    final delta = (cycle.weightEnd ?? 0.0) - (cycle.weightStart ?? 0.0);
    final deltaText = delta.abs().toStringAsFixed(1);

    if (cycle.healthGoal == 'ลดน้ำหนัก') {
      if (delta < 0) {
        return 'น้ำหนักเป้าหมายลดลงจาก $start กก. เป็น $end กก. (ลดลง $deltaText กก.)';
      }
      return 'น้ำหนักเป้าหมาย $start กก. → น้ำหนักล่าสุด $end กก. (เพิ่มขึ้น $deltaText กก.)';
    }
    if (cycle.healthGoal == 'เพิ่มน้ำหนัก') {
      if (delta > 0) {
        return 'น้ำหนักเป้าหมายเพิ่มขึ้นจาก $start กก. เป็น $end กก. (เพิ่มขึ้น $deltaText กก.)';
      }
      return 'น้ำหนักเป้าหมาย $start กก. → น้ำหนักล่าสุด $end กก. (ลดลง $deltaText กก.)';
    }
    if (cycle.healthGoal == 'รักษาน้ำหนัก' && delta.abs() <= 1.0) {
      final changeText = delta > 0 ? 'เพิ่มขึ้น' : 'ลดลง';
      return 'น้ำหนักเป้าหมายรักษาอยู่ที่ $start กก. → $end กก. ($changeText $deltaText กก.)';
    }
    final changeText = delta > 0 ? 'เพิ่มขึ้น' : 'ลดลง';
    return 'น้ำหนักเป้าหมาย $start กก. → น้ำหนักล่าสุด $end กก. (ไม่สอดคล้องกับเป้าหมายที่เลือก: $changeText $deltaText กก.)';
  }

  Future<_DashboardViewData> _load() async {
    // guest ไม่มี token เลย (saveGuest() ไม่เคยเรียก saveToken) — ทุก endpoint
    // ที่เรียกด้านล่างนี้ต้องใช้ Authorization: Bearer เสมอ (ดู
    // _require_auth_user() ฝั่ง backend) ยิงไปก็ 401 ทุกครั้ง เดิมปล่อยให้
    // throw แล้วโชว์ error banner ถาวรที่กด "ลองใหม่" ไม่มีทางสำเร็จ — เช็ค
    // ตรงนี้ก่อนยิง network เลย คืนค่าว่างเปล่าแทน ให้ build() ตัดสินใจโชว์
    // ป้ายชวนเข้าสู่ระบบแบบเดียวกับ ProfilePage/HistoryPage
    if (!AuthService().isLoggedIn || AuthService().isGuest) {
      return const _DashboardViewData(
        summary: DashboardData(
          caloriesConsumed: 0,
          caloriesPlanned: 0,
          caloriesGoal: 0,
          meals: [],
          weightKg: 0,
          bmi: 0,
          bmiStatus: BmiStatus.normal,
          last7Days: [],
          shortcuts: [],
        ),
        todayLogs: [],
        macros: _Macros(),
      );
    }

    final userId = AuthService().user?['id']?.toString() ?? '';
    final summaryResult = await widget.dashboardService.fetchDashboard(userId);
    final summary = summaryResult.when(
      ok: (d) => d,
      err: (e) => throw Exception(e.toUserMessage()),
    );

    final logsResult = await widget.mealLogService.fetchLogs(date: DateTime.now());
    final todayLogs = logsResult.when(ok: (l) => l, err: (_) => <MealLog>[]);

    final macros = await _computeMacros(todayLogs);

    // สรุปรายสัปดาห์เป็นการ์ดเสริม ไม่ใช่ข้อมูลหลักของหน้า — พลาดแล้วแค่ไม่
    // โชว์การ์ดนี้ ไม่ทำให้ทั้งหน้าล้มเหลวไปด้วย (ต่างจาก fetchDashboard หลัก
    // ด้านบนที่ throw ตรงๆ เพราะเป็นข้อมูลหลักที่ขาดไม่ได้)
    final weeklySummaryResult = await widget.dashboardService.fetchWeeklySummary();
    final weeklySummary = weeklySummaryResult.when(ok: (w) => w, err: (_) => null);

    return _DashboardViewData(
      summary: summary,
      todayLogs: todayLogs,
      macros: macros,
      weeklySummary: weeklySummary,
    );
  }

  /// รวมโปรตีน/คาร์บ/ไขมันของเมนูที่ is_eaten=1 วันนี้ — meal_log_items เก็บ
  /// แค่ calories_actual ไม่มี macro แยก จึงต้องดึงรายละเอียด food_item มา
  /// สเกลตามสัดส่วนแคลอรีจริงที่ทาน (calories_actual / calories มาตรฐาน)
  Future<_Macros> _computeMacros(List<MealLog> logs) async {
    final cache = <int, FoodItem?>{};
    double protein = 0, carbs = 0, fat = 0;

    for (final log in logs) {
      for (final item in log.items) {
        if (!item.isEaten) continue;
        var foodItem = cache[item.foodItemId];
        if (!cache.containsKey(item.foodItemId)) {
          final result = await widget.foodItemService.fetchFoodItemById(item.foodItemId);
          foodItem = result.when(ok: (f) => f, err: (_) => null);
          cache[item.foodItemId] = foodItem;
        }
        if (foodItem == null || (foodItem.calories ?? 0) <= 0) continue;
        final scale = (item.caloriesActual ?? 0) / foodItem.calories!;
        protein += (foodItem.proteinG ?? 0) * scale;
        carbs += (foodItem.carbsG ?? 0) * scale;
        fat += (foodItem.fatG ?? 0) * scale;
      }
    }
    return _Macros(protein: protein, carbs: carbs, fat: fat);
  }

  Future<void> _addMeal(MealType type) async {
    await startMealLogFlow(
      context,
      mealLogService: widget.mealLogService,
      foodItemService: widget.foodItemService,
      preFilledMealType: type,
    );
    if (mounted) _retry();
  }

  /// แตะแถวมื้อที่มีเมนูอยู่แล้วบน Dashboard — เปิดชีทเดียวกับที่ "+ บันทึก"
  /// ใช้ตอนแตะมื้อที่บันทึกแล้ว (ดู meal_select_sheet.dart:_manageExisting)
  /// เดิม Dashboard โชว์ได้แค่ "เมนูแรก และอีก N รายการ" เฉยๆ ไม่มีทางแตะดู
  /// รายการที่เหลือ/ลบเมนูที่เลือกผิดจากตรงนี้เลย (ผู้ใช้รายงานจริง)
  Future<void> _manageMeal(MealLog log) async {
    await showManageMealSheet(
      context,
      mealLogService: widget.mealLogService,
      foodItemService: widget.foodItemService,
      log: log,
    );
    if (mounted) _retry();
  }

  /// ปุ่ม "บันทึกเลย" ตอน dashboard ยังว่างเปล่า (ยังไม่มีมื้อไหนถูกบันทึกวันนี้
  /// เลย) — ต้องให้เลือกมื้อก่อนเสมอผ่าน MealSelectSheet (preFilledMealType:
  /// null) ห้าม auto-pick มื้อปัจจุบันแทนเงียบๆ เหมือนเดิม เพราะผู้ใช้ไม่เคย
  /// กดยืนยันว่าจะบันทึกมื้อไหนจริงๆ (บั๊กที่เจอจริง: กดปุ่มนี้แล้วโดดไปเลือก
  /// เมนูอาหารได้เลยทั้งที่ยังไม่ได้เลือกมื้อ)
  Future<void> _startQuickLog() async {
    await startMealLogFlow(
      context,
      mealLogService: widget.mealLogService,
      foodItemService: widget.foodItemService,
    );
    if (mounted) _retry();
  }

  /// เปิด date picker มาตรฐานของ Flutter ให้เลือกวันที่จะบันทึกเมนูที่ AI
  /// แนะนำ — จำกัดช่วงตาม [healthGoalBackfillRange] (วันแรกที่ตั้งเป้าหมาย ->
  /// วันนี้/วันที่ล็อก) เดียวกับที่ BackfillSection ใช้ทุกประการ ผู้ใช้รายงาน
  /// จริงว่าเดิมเปิดให้ย้อนหลังได้ถึง 1 ปีลอยๆ ไม่อิงกับแผนพลังงาน (เป้าหมาย
  /// น้ำหนัก+จำนวนวัน) ที่ตั้งไว้จากหน้าโปรไฟล์เลย เลือกวันนี้เอง = เคลียร์
  /// กลับเป็น null (ของเดิม)
  Future<void> _pickAiRecommendDate() async {
    final range = healthGoalBackfillRange();
    if (range == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังไม่ได้ตั้งเป้าหมายสุขภาพ จึงยังบันทึกย้อนหลังไม่ได้')),
      );
      return;
    }
    final (start, end) = range;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _aiRecommendDate ?? end,
      firstDate: start,
      lastDate: end,
    );
    if (picked == null || !mounted) return;
    final isToday = picked.year == now.year && picked.month == now.month && picked.day == now.day;
    setState(() => _aiRecommendDate = isToday ? null : DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _markMealEaten(MealLog log) async {
    // notify: false ในลูป — มื้อนี้มีหลายเมนูได้แล้ว (ดู backend/api.py
    // meal_log_items ที่เลิกล็อกไว้แค่ 1 รายการ/มื้อ) กดทานแล้วทีเดียวยิง
    // MealLogEvents ซ้ำกันหลายรอบไม่จำเป็น เอาแค่ครั้งเดียวพอหลัง loop จบ
    // (เจอจริงจากเคส FoodBrowserPage ยืนยันหลายเมนูรวด — ดู food_browser_page.dart._confirm)
    var anySucceeded = false;
    for (final item in log.items.where((i) => !i.isEaten)) {
      final result = await widget.mealLogService.markItemEaten(item.id, notify: false);
      if (result.isOk) anySucceeded = true;
    }
    if (anySucceeded) MealLogEvents.instance.changed();
    if (mounted) _retry();
  }

  /// เดิมยกเลิกแค่ log.items.first ตัวเดียว (ดูปุ่ม "ยกเลิก" ใน _mealRow) ทั้ง
  /// ที่มื้อเดียวมีได้หลายเมนู (FoodBrowserPage ยืนยันหลายเมนูรวดเดียวได้) —
  /// กด "ทานแล้ว" มาร์กครบทุกเมนูในมื้อ (ดู _markMealEaten) แต่กด "ยกเลิก" กลับ
  /// คืนสถานะให้แค่เมนูแรก เมนูที่เหลือค้างเป็น "ทานแล้ว" ต่อไปเงียบๆ พอเลย 5
  /// นาทีของตัวมันเองก็ล็อกถาวรทั้งที่ผู้ใช้กดยกเลิกไปแล้ว (ผู้ใช้รายงานจริง)
  /// วนยกเลิกทุกเมนูที่ยังอยู่ในช่วง 5 นาที ให้สมมาตรกับ _markMealEaten
  Future<void> _undoMealEaten(MealLog log) async {
    String? error;
    var anySucceeded = false;
    for (final item in log.items.where((i) => i.canUndoEaten)) {
      final result = await widget.mealLogService.undoItemEaten(item.id);
      result.when(
        ok: (_) => anySucceeded = true,
        err: (e) => error = e.toUserMessage(),
      );
    }
    if (!mounted) return;
    if (anySucceeded) _retry();
    if (error != null) {
      // เผื่อ race condition เวลาไม่ตรงกันพอดี (ปุ่มยังโชว์อยู่ฝั่ง client
      // แต่ backend ถือว่าเกิน 5 นาทีไปแล้วจริง) — แจ้งเตือนสุภาพ ไม่ crash
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error!)));
    }
  }

  /// วันนี้ "ปิด" แล้วหรือยัง — ถึง 22:00 (เวลาที่มื้อเย็นปิดรับตาม
  /// kMealTimeWindows) หรือมื้อเย็นถูกกดทานแล้วและยืนยันแล้วเกิน 5 นาที
  /// (พ้นช่วง undo — ดู MealLogItem.canUndoEaten) เงื่อนไขไหนจริงก่อนก็ล็อก
  /// ทันที ไม่ต้องรอทั้งคู่ — ใช้ตัดสินทั้งซ่อนปุ่ม "+ เพิ่มมื้อ" ที่เหลือ
  /// และโชว์การ์ดสรุปผลวันนี้ทันที (แทนที่จะรอแค่ dinner_logged จาก backend
  /// ซึ่งเป็นจริงตั้งแต่สร้าง meal_log มื้อเย็น ไม่สนว่ากดทานแล้วหรือยัง)
  bool _isDayLocked(List<MealLog> todayLogs) {
    final nowBangkok = DateTime.now().toUtc().add(const Duration(hours: 7));
    // อ่านชั่วโมงปิดมื้อเย็นจาก kMealTimeWindows ตรงๆ แทน hardcode 22 ซ้ำ —
    // เดิม comment ด้านบนอ้างถึง kMealTimeWindows เป็น source of truth อยู่
    // แล้วแต่โค้ดจริงไม่ได้อ่านค่าจากตรงนั้น (บั๊กที่เจอจริง — ถูกต้องเพราะ
    // บังเอิญเลขตรงกันตอนนี้ แต่จะไม่ตามกันถ้า kMealTimeWindows เปลี่ยนในอนาคต)
    if (nowBangkok.hour >= kMealTimeWindows[MealType.dinner]!.$2) return true;

    MealLog? dinner;
    for (final log in todayLogs) {
      if (log.mealType == MealType.dinner) {
        dinner = log;
        break;
      }
    }
    if (dinner == null || dinner.items.isEmpty) return false;
    final allEaten = dinner.items.every((i) => i.isEaten);
    // เดิมเช็ค items.any(canUndoEaten) (เวลาของเมนูใดเมนูหนึ่งเอง) — ใช้
    // dinner.isSealed (ยึดเวลาทานแล้วครั้งแรกสุดของมื้อ) แทน ให้สอดคล้องกับ
    // จุดอื่นทั้งหมดที่แก้ไปแล้ว (ผู้ใช้รายงานจริง)
    return allEaten && dinner.isSealed;
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    if (!auth.isLoggedIn || auth.isGuest) {
      // เดิมใช้ AppEmptyState ตัวกลาง (ไอคอนเทา 56px แบบเดียวกับหน้า error
      // ทั่วไป) ผู้ใช้บอกว่าดูโล่งเกินไป/ไม่มีเอกลักษณ์ — ทำโลโก้เฉพาะหน้านี้
      // เอง (วงกลมไล่เฉด + เงานุ่มๆ) แทน ยังคงเว้นที่โล่งรอบๆ ตามที่ผู้ใช้
      // ขอไว้ ไม่ได้ยัดองค์ประกอบเพิ่ม แค่ทำของเดิมให้ดูมีระดับขึ้น
      return Scaffold(
        backgroundColor: AppColors.gray50,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.teal500, AppColors.teal700],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.teal500.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.monitor_heart_rounded, color: Colors.white, size: 46),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'เข้าสู่ระบบเพื่อดูแดชบอร์ดของคุณ',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ติดตามแคลอรี มื้ออาหาร และความคืบหน้าในแต่ละวัน',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray600),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.teal500,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('เข้าสู่ระบบ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.gray50,
      body: SafeArea(
        child: Builder(
          builder: (context) {
            if (_loading && _data == null) {
              return _buildSkeleton();
            }
            if (_hasError && _data == null) {
              return Column(
                children: [
                  const SizedBox(height: 8),
                  AppErrorBanner(message: 'โหลดข้อมูลแดชบอร์ดไม่สำเร็จ', onRetry: _retry),
                ],
              );
            }
            final data = _data!;
            if (data.summary.isEmpty) {
              // เดิมโชว์แค่ AppEmptyState ตัวเดียวเต็มจอ ไม่มี _Header() เลย —
              // พอยังไม่บันทึกมื้อแรก หน้าเลยดูเหมือนคนละหน้ากับตอนมีข้อมูล
              // (ไม่มีชื่อ/รูปโปรไฟล์/กระดิ่งแจ้งเตือนให้กดเลย) ผู้ใช้บอกว่า
              // ยังดูโล่งไป — คง _Header() ไว้ด้านบนเสมอ แล้วทำการ์ดชวนบันทึก
              // มื้อแรกให้มีลูกเล่นแบบเดียวกับหน้า login (วงกลมไล่เฉด+เงา)
              // แทนไอคอนเทาแบนๆ เดิม
              //
              // ผู้ใช้รายงานจริง: บัญชีสมัครใหม่ (ยังไม่เคยบันทึกมื้อเลย ->
              // isEmpty=true) ไม่เห็นการ์ด "AI แนะนำเมนู" เลย ทั้งที่เพิ่งกรอก
              // ข้อมูลส่วนตัว+เป้าหมายสุขภาพเสร็จหมาดๆ — นี่คือช่วงที่ AI ช่วย
              // ได้มากที่สุด (ให้เลือกมื้อแรกได้เลยแทนที่จะต้องไล่ค้นหาเมนูเอง
              // ผ่านปุ่ม "บันทึกเลย") เดิมโชว์แค่ตอน isEmpty=false เพราะฝัง
              // เงื่อนไขไว้ที่ data.aiRecommendations (มาจาก endpoint เดียวกับ
              // dashboard summary) แต่ AI recommend เป็น endpoint แยกที่ไม่
              // ผูกกับว่ามีมื้อบันทึกไว้หรือยัง เปลี่ยนจาก Expanded+Center
              // (การ์ดชวนบันทึกมื้อแรกใบเดียว) เป็น ListView ปกติ ใส่การ์ด AI
              // แนะนำเมนูต่อจาก header ก่อนการ์ดชวนบันทึกมื้อแรก
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _Header(),
                    const SizedBox(height: 16),
                    // ผู้ใช้รายงานจริง: หน้าแดชบอร์ดตอนยังไม่บันทึกมื้อแรก
                    // (isEmpty) โชว์แค่ชื่อเป้าหมายสุขภาพที่ header ("เป้าหมาย:
                    // รักษาน้ำหนัก") แต่ไม่มีตัวเลข kcal เป้าหมายให้เห็นเลย —
                    // caloriesGoal มาจากโปรไฟล์ตรงๆ ไม่ต้องรอมีมื้อบันทึกก่อน
                    // (isEmpty เช็คแค่ caloriesConsumed/caloriesPlanned/
                    // last7Days ไม่เกี่ยวกับ caloriesGoal เลย) โชว์
                    // _CalorieHeroCard เดียวกับหน้าที่มีข้อมูลแล้วได้เลย
                    _CalorieHeroCard(summary: data.summary),
                    const SizedBox(height: 16),
                    // ผู้ใช้ยืนยัน: การ์ดชวนบันทึกมื้อแรกอยู่บนสุด (เห็นทันที
                    // ไม่ต้องเลื่อน) ส่วน AI แนะนำเมนูอยู่ถัดลงมาด้านล่าง
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.gray100),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [AppColors.teal500, AppColors.teal700],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.teal500.withValues(alpha: 0.35),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.restaurant_menu_rounded, color: Colors.white, size: 40),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'เริ่มบันทึกมื้อแรกของคุณ',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'บันทึกมื้ออาหารเพื่อดูสรุปแคลอรีที่นี่',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray600),
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: 220,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () => _startQuickLog(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.teal500,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text('บันทึกเลย', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _AiRecommendSection(
                      // key รวม _lastAuthSignature ด้วย (ดูคอมเมนต์เต็มที่
                      // จุดใช้งานอีกจุดด้านล่าง) กันการ์ดนี้ค้างแนะนำเมนูที่มี
                      // สารก่อภูมิแพ้ที่เพิ่งบันทึกเพิ่มจากหน้าโปรไฟล์
                      key: ValueKey('$_aiRecommendDate|$_lastAuthSignature'),
                      aiRecommendService: _aiRecommendService,
                      mealLogService: widget.mealLogService,
                      foodItemService: widget.foodItemService,
                      selectedDate: _aiRecommendDate,
                      onPickDate: _pickAiRecommendDate,
                      onSaved: _retry,
                    ),
                    const SizedBox(height: 16),
                    // ผู้ใช้รายงานจริง: บัญชีที่ยังไม่เคยบันทึกมื้อเลย (isEmpty)
                    // ไม่เห็นกล่อง "บันทึกย้อนหลัง" เลย ทั้งที่อาจตั้งเป้าหมาย
                    // สุขภาพไปแล้วหลายวันก่อนหน้า (health_goal_started_at ไม่ได้
                    // ผูกกับ isEmpty) — เดิมมีแค่ branch ที่ไม่ว่างเท่านั้นที่ใส่
                    // ไว้ BackfillSection เองเช็ค/ซ่อนตัวเองอยู่แล้วถ้ายังไม่เคย
                    // ตั้งเป้าหมาย (คืน SizedBox.shrink ดู backfill_section.dart)
                    // ใส่ตรงนี้ได้เลยไม่ต้องมี logic เพิ่ม
                    BackfillSection(
                      mealLogService: widget.mealLogService,
                      foodItemService: widget.foodItemService,
                    ),
                    const SizedBox(height: 16),
                    const _SuggestMenuEntry(),
                  ],
                ),
              );
            }
            final dayLocked = _isDayLocked(data.todayLogs);
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _Header(),
                  const SizedBox(height: 16),
                  _CalorieHeroCard(summary: data.summary),
                  if (data.summary.overLimit) ...[
                    const SizedBox(height: 12),
                    const _OverLimitWarning(),
                  ],
                  if (data.weeklySummary != null) ...[
                    const SizedBox(height: 16),
                    _WeeklySummaryCard(summary: data.weeklySummary!),
                  ],
                  const SizedBox(height: 16),
                  _MacroRow(macros: data.macros),
                  const SizedBox(height: 16),
                  _WeeklyChartCard(days: data.summary.last7Days),
                  const SizedBox(height: 16),
                  _TodayMealsSection(
                    todayLogs: data.todayLogs,
                    onAddMeal: _addMeal,
                    onMarkEaten: _markMealEaten,
                    onUndoEaten: _undoMealEaten,
                    onManage: _manageMeal,
                  ),
                  const SizedBox(height: 16),
                  _AiRecommendSection(
                    // key เปลี่ยนตาม selectedDate หรือ _lastAuthSignature —
                    // บังคับ Flutter สร้าง state ใหม่ (initState ยิงคำแนะนำ
                    // ใหม่ + ล้างตะกร้าที่ค้างอยู่) ตอน (1) ผู้ใช้เปลี่ยนวันที่
                    // จะบันทึกย้อนหลัง กันตะกร้าเดิมค้างอ้างอิง MealLog ของ
                    // วันที่เก่าไปแล้ว หรือ (2) แพ้อาหาร/โรคประจำตัว/เป้าหมาย
                    // สุขภาพเปลี่ยนจากหน้าโปรไฟล์ — ผู้ใช้รายงานจริง: เพิ่ม
                    // "ไข่" เป็นอาหารที่แพ้แล้วกดบันทึก กลับมาหน้าหลักการ์ดนี้
                    // ยังแนะนำ "ข้าวไข่ดาว" ค้างอยู่เหมือนเดิม เพราะ
                    // _AiRecommendSectionState ยิง fetch ครั้งเดียวตอน
                    // initState เท่านั้น ไม่เคยฟัง auth signature เปลี่ยนเอง
                    // (ต่างจาก _DashboardPageState._onAuthChanged ที่ฟังอยู่
                    // แล้วแต่แค่ทำให้ widget นี้ rebuild เฉยๆ ไม่ได้สั่งให้มัน
                    // fetch ใหม่) — ผูก key กับ _lastAuthSignature ตัวเดียวกับ
                    // ที่ _onAuthChanged ใช้เทียบอยู่แล้วเลย ไม่ต้องเพิ่ม
                    // listener ใหม่ซ้ำซ้อน
                    key: ValueKey('$_aiRecommendDate|$_lastAuthSignature'),
                    aiRecommendService: _aiRecommendService,
                    mealLogService: widget.mealLogService,
                    foodItemService: widget.foodItemService,
                    selectedDate: _aiRecommendDate,
                    onPickDate: _pickAiRecommendDate,
                    onSaved: _retry,
                  ),
                  const SizedBox(height: 16),
                  BackfillSection(
                    mealLogService: widget.mealLogService,
                    foodItemService: widget.foodItemService,
                  ),
                  const SizedBox(height: 16),
                  const _SuggestMenuEntry(),
                  if (dayLocked) ...[
                    const SizedBox(height: 16),
                    _DailySummaryCard(summary: data.summary),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        AppSkeletonLoader(variant: AppSkeletonVariant.profileHeader),
        SizedBox(height: 16),
        AppSkeletonLoader(variant: AppSkeletonVariant.card),
        SizedBox(height: 16),
        AppSkeletonLoader(variant: AppSkeletonVariant.card),
        SizedBox(height: 16),
        AppSkeletonLoader(variant: AppSkeletonVariant.listItem),
        AppSkeletonLoader(variant: AppSkeletonVariant.listItem),
        AppSkeletonLoader(variant: AppSkeletonVariant.listItem),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final u = auth.user ?? {};
    final name = (u['name']?.toString().trim().isNotEmpty == true)
        ? u['name'].toString()
        : (u['username']?.toString() ?? 'ผู้ใช้');
    final fullName = [u['name'], u['surname']]
        .where((p) => p != null && p.toString().trim().isNotEmpty)
        .join(' ');
    final goalLabel = (u['health_goal']?.toString().trim().isNotEmpty == true)
        ? u['health_goal'].toString()
        : '-';
    final avatarPath = u['avatar_url']?.toString();
    final avatarUrl = (avatarPath != null && avatarPath.isNotEmpty) ? '${getApiBase()}$avatarPath' : null;

    return Row(
      children: [
        AppAvatarInitials(name: fullName.isNotEmpty ? fullName : name, size: 44, imageUrl: avatarUrl),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('สวัสดี, $name', style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900)),
              Text('เป้าหมาย: $goalLabel', style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600)),
            ],
          ),
        ),
        // ไอคอนแจ้งเตือน — เดิมกดแล้วขึ้นแค่ SnackBar ลอยๆ หายไปเอง ผู้ใช้
        // อยากได้หน้าเต็มจอที่ดูย้อนหลังได้จริง (ผู้ใช้รายงานจริง) เปิด
        // NotificationsPage แทน — ยังไม่มีระบบเก็บประวัติแจ้งเตือนจริงจัง
        // (ดูคอมเมนต์ในไฟล์นั้น) เลยยังโชว์แค่ empty state แต่โครงเต็มจอพร้อม
        // ใช้ทันทีที่มีของจริงมาเสียบ
        IconButton(
          icon: const Icon(Icons.notifications_none, color: AppColors.gray600),
          onPressed: () {
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => const NotificationsPage()),
            );
          },
        ),
      ],
    );
  }
}

class _CalorieHeroCard extends StatelessWidget {
  final DashboardData summary;
  const _CalorieHeroCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    // ทานเกินเป้าวันนี้แล้ว -> การ์ดเปลี่ยนเป็นสีแดง (coral) แทนเขียวปกติ
    // ให้เห็นชัดตั้งแต่แวบแรกโดยไม่ต้องอ่านตัวเลข
    final bgColor = summary.overLimit ? AppColors.coral400 : AppColors.teal500;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${summary.caloriesConsumed.toStringAsFixed(0)} kcal',
                style: AppTextStyles.headingLarge.copyWith(color: Colors.white, fontSize: 32),
              ),
              if (summary.overLimit) ...[
                const SizedBox(width: 8),
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'จากเป้า ${thousands(summary.caloriesGoal.round())} kcal วันนี้',
            style: AppTextStyles.bodyMedium.copyWith(color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 16),
          AppCalorieBar(
            eaten: summary.caloriesConsumed.round(),
            planned: summary.caloriesPlanned.round(),
            goal: summary.caloriesGoal.round(),
            showLabel: false,
            trackColor: Colors.white.withValues(alpha: 0.25),
            plannedColor: summary.overLimit ? AppColors.coral200 : AppColors.teal100,
            eatenColor: Colors.white.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 8),
          Text(
            'วางแผนไว้ ${thousands(summary.caloriesPlanned.round())} kcal',
            style: AppTextStyles.caption.copyWith(color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }
}

/// แบนเนอร์เตือนตอนทานเกินเป้าวันนี้แล้ว — โชว์ต่อจากการ์ดแคลอรีสีแดงทันที
/// ไม่ใช่แค่เปลี่ยนสีเฉยๆ ต้องมีข้อความเตือนชัดเจนตามที่ขอ
class _OverLimitWarning extends StatelessWidget {
  const _OverLimitWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppColors.coral50, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.coral600, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'คุณทานอาหารเกินขีดจำกัดแล้ว โปรดระมัดระวังการเลือกกินอาหารในวันถัดไป',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.coral600),
            ),
          ),
        ],
      ),
    );
  }
}

/// ประกอบตัวเลขดิบจาก WeeklySummaryData เป็นประโยคไทยที่เข้าใจง่าย — โทน
/// ให้กำลังใจเสมอ ไม่ตัดสิน/ตำหนิแม้ตัวเลขจะต่ำ (ตามที่กำหนด)
List<String> _composeWeeklySummarySentences(WeeklySummaryData d) {
  final lines = <String>[];
  final totalTracked = d.daysOnTarget + d.daysOverGoal + d.daysUnderGoal;

  if (totalTracked > 0) {
    if (d.daysOnTarget >= 5) {
      lines.add('สัปดาห์นี้คุณอยู่ในเป้า ${d.daysOnTarget} ใน 7 วัน เยี่ยมมากเลย!');
    } else if (d.daysOnTarget >= 3) {
      lines.add('สัปดาห์นี้คุณอยู่ในเป้า ${d.daysOnTarget} ใน 7 วัน ทำได้ดีแล้ว ลองต่อยอดกันอีกนิด');
    } else if (d.daysOnTarget > 0) {
      lines.add('สัปดาห์นี้คุณอยู่ในเป้า ${d.daysOnTarget} ใน 7 วัน เริ่มต้นได้ดีแล้ว ลองปรับเพิ่มอีกหน่อยในสัปดาห์หน้านะ');
    } else {
      lines.add('สัปดาห์นี้ยังไม่มีวันที่ตรงเป้าเป๊ะ ไม่เป็นไรเลย ลองเริ่มใหม่ได้ทุกมื้อ');
    }
  }

  if (d.streakDaysLogged >= 2) {
    lines.add('บันทึกต่อเนื่อง ${d.streakDaysLogged} วันแล้ว สู้ๆ ต่อไปนะ!');
  } else if (d.streakDaysLogged == 1) {
    lines.add('บันทึกไปแล้ว 1 วัน เริ่มต้นดีมาก มาบันทึกต่อกันพรุ่งนี้นะ');
  }

  if (d.mostFrequentCategory != null && d.mostFrequentCategory!.isNotEmpty) {
    lines.add('เมนูที่คุณเลือกบ่อยที่สุดสัปดาห์นี้คือ "${d.mostFrequentCategory}"');
  }

  return lines;
}

/// การ์ดสรุปรายสัปดาห์แบบข้อความ — ดึงจาก GET /api/dashboard/weekly-summary
/// แล้วประกอบเป็นประโยคไทยฝั่ง client เอง (backend ส่งแค่ตัวเลขดิบ)
class _WeeklySummaryCard extends StatelessWidget {
  final WeeklySummaryData summary;
  const _WeeklySummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final sentences = _composeWeeklySummarySentences(summary);
    if (sentences.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: AppColors.teal500),
              const SizedBox(width: 8),
              Text('สรุปรายสัปดาห์', style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900)),
            ],
          ),
          const SizedBox(height: 10),
          for (final s in sentences)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(s, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray900)),
            ),
        ],
      ),
    );
  }
}

// อาหาร/เครื่องดื่ม/ของหวาน built-in มีป้ายกำกับภาษาไทยตายตัว หัวข้อที่
// แอดมินเพิ่มเองใช้ชื่อที่พิมพ์ไว้ตรงๆ เป็นป้ายกำกับ (identifier ขึ้นต้น _ เป็น
// library-private ใน Dart — ก็อปมาจาก food_browser_page.dart ตรงๆ ไม่ได้
// import ข้ามไฟล์ ซ้ำแค่ 3 คู่ ไม่คุ้มแยกไฟล์ constants ใหม่)
const _builtinTypeLabels = {'food': 'อาหาร', 'drink': 'เครื่องดื่ม', 'dessert': 'ของหวาน'};

const _defaultAiCategories = [
  (label: 'อาหาร', value: 'food'),
  (label: 'เครื่องดื่ม', value: 'drink'),
  (label: 'ของหวาน', value: 'dessert'),
];

/// การ์ด "AI แนะนำเมนู" แบบ inline บน Dashboard ตรงๆ (เดิมทำเป็นการ์ดทางเข้า
/// หน้าแยกแบบ _SuggestMenuEntry ด้านล่าง แต่ผู้ใช้ยืนยันว่าอยากเห็นผลลัพธ์
/// ทันทีโดยไม่ต้องกดออกจากหน้าหลัก — เอาหน้าแยกออก ใช้การ์ดนี้แสดง top 3
/// ที่ backend คำนวณมาให้แล้วตรงๆ)
///
/// ผู้ใช้รายงานจริง: เดิมมีแค่หมวด "อาหาร" ให้ดู (hardcode category: 'food'
/// ตอนยิง /api/ai/recommend) ไม่มีทางเห็นเครื่องดื่ม/ของหวานที่ AI แนะนำเลย
/// — เพิ่มแท็บสลับหมวด (เหมือน _typeFilters ใน food_browser_page.dart) ยิง
/// คำขอใหม่ตามหมวดที่เลือกในนี้เอง (ไม่ต้องรีโหลดทั้งแดชบอร์ด)
///
/// ผู้ใช้รายงานจริงอีกเคส: เดิมแตะเมนูที่ AI แนะนำแล้วบันทึกลง backend ทันที
/// ทีละเมนู เลือกได้แค่ 1 เมนู/ครั้ง พอสลับหมวดไปเลือกอีกเมนู (เช่น อาหาร
/// แล้วต่อด้วยเครื่องดื่ม) เมนูแรกที่เพิ่งบันทึกไปหายไปจากที่เลือกไว้แล้ว
/// เหมือนต้องเลือกทีละมื้อแยกกัน — เก็บลงตะกร้า (_cart) ก่อนเหมือน
/// FoodBrowserPage ทุกประการ เลือกข้ามหมวดได้เท่าที่ต้องการแล้วกด "บันทึก"
/// รวดเดียว (มื้อเดียวกันทั้งตะกร้า — เลือกมื้อแค่ครั้งแรกที่แตะเมนู)
class _AiRecommendSection extends StatefulWidget {
  final AiRecommendService aiRecommendService;
  final MealLogService mealLogService;
  final FoodItemService foodItemService;
  final DateTime? selectedDate;
  final VoidCallback onPickDate;
  final VoidCallback onSaved;
  const _AiRecommendSection({
    super.key,
    required this.aiRecommendService,
    required this.mealLogService,
    required this.foodItemService,
    required this.selectedDate,
    required this.onPickDate,
    required this.onSaved,
  });

  @override
  State<_AiRecommendSection> createState() => _AiRecommendSectionState();
}

class _AiRecommendSectionState extends State<_AiRecommendSection> {
  String _category = 'food';
  bool _loading = true;
  String? _error;
  List<AiRecommendation> _items = [];
  // true เมื่อ backend บอกว่าหมวดนี้ไม่ควรแนะนำเลยสำหรับโรคประจำตัวที่ผู้ใช้มี
  // (เช่นเบาหวานกับของหวาน) — โชว์เหตุผลแทนลิสต์เมนู/ข้อความ "ยังไม่มีเมนูแนะนำ"
  bool _blocked = false;
  String? _blockedReason;
  // สลับหมวดถี่ๆ ยิง _load() ซ้อนกันได้เหมือนกับ FoodBrowserPage — ต้องทิ้ง
  // response ของหมวดที่ไม่ได้เลือกอยู่แล้วถ้ามันตอบกลับมาทีหลัง
  int _loadGeneration = 0;
  final Map<String, List<AiRecommendation>> _categorySeed = {};

  // ตะกร้าเมนูที่ AI แนะนำ — เลือกข้ามหมวดได้ก่อนกด "บันทึก" รวดเดียว
  // (ดูคอมเมนต์บนคลาส) ทุกเมนูในตะกร้าลงมื้อเดียวกัน (_cartLog)
  MealLog? _cartLog;
  final List<ServingChoice> _cart = [];
  bool _saving = false;

  // ผู้ใช้รายงานจริง: แอดมินเพิ่มหัวข้อใหม่แล้วแท็บนี้ยังไม่เห็น เหมือนกับ
  // _typeFilters ใน FoodBrowserPage — ดึงจาก GET /api/food-types แทนเช่นกัน
  // (ดึงครั้งเดียวตอนเปิดแอป ไม่ poll ซ้ำ — ผู้ใช้ขอกลับมาแบบเดิม)
  var _categories = _defaultAiCategories;

  double get _cartTotal => _cart.fold(0.0, (sum, c) => sum + c.calories);

  String get _dateLabel {
    final d = widget.selectedDate;
    if (d == null) return 'วันนี้';
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(_loadCategories());
  }

  Future<void> _loadCategories() async {
    final result = await widget.foodItemService.fetchFoodTypes();
    if (!mounted) return;
    result.when(
      ok: (types) => setState(() {
        _categories = [for (final t in types) (label: _builtinTypeLabels[t] ?? t, value: t)];
      }),
      err: (_) {},
    );
  }

  Future<void> _load({bool randomize = false}) async {
    final myGeneration = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _blocked = false;
      _blockedReason = null;
    });
    final result = await widget.aiRecommendService.fetchRecommendations(
      category: _category,
      limit: 5,
      date: widget.selectedDate,
      randomize: randomize,
    );
    if (!mounted || myGeneration != _loadGeneration) return;
    result.when(
      ok: (r) {
        final fetched = List<AiRecommendation>.from(r.items);
        _categorySeed[_category] = fetched;

        setState(() {
          _items = fetched;
          _blocked = r.blocked;
          _blockedReason = r.blockedReason;
          _loading = false;
        });
      },
      err: (e) => setState(() {
        _loading = false;
        _error = e.toUserMessage();
      }),
    );
  }

  void _randomizeCurrentMenu() {
    final seeded = _categorySeed[_category] ?? _items;
    if (seeded.isEmpty) return;
    _load(randomize: true);
  }

  void _selectCategory(String value) {
    if (_category == value) return;
    setState(() => _category = value);
    if (_categorySeed.containsKey(_category)) {
      setState(() => _items = List<AiRecommendation>.from(_categorySeed[_category]!));
      return;
    }
    _load();
  }

  /// แตะเมนูในการ์ด — ใช้ flow เดียวกับ FoodBrowserPage (เลือกมื้อ -> เลือก
  /// ขนาดเสิร์ฟ -> เก็บลงตะกร้า) แค่ข้าม step ค้นหา/เลือกเมนูเองเพราะ AI
  /// เลือกเมนูให้แล้ว — เลือกมื้อ ([_cartLog]) แค่ครั้งแรกที่ตะกร้ายังว่าง
  /// เมนูถัดไปที่แตะเพิ่มจะลงมื้อเดียวกันอัตโนมัติไม่ต้องเลือกซ้ำ
  Future<void> _addToCart(AiRecommendation rec) async {
    if (!hasCompleteProfileAndGoal()) {
      await showIncompleteProfileDialog(context);
      return;
    }

    var log = _cartLog;
    if (log == null) {
      final date = widget.selectedDate;
      final logsResult = await widget.mealLogService.fetchLogs(date: date ?? DateTime.now());
      if (!mounted) return;
      final todayLogs = logsResult.when(ok: (l) => l, err: (_) => const <MealLog>[]);

      log = await showMealSelectSheet(
        context,
        mealLogService: widget.mealLogService,
        todayLogs: todayLogs,
        date: date,
      );
      if (log == null || !mounted) return;
    }

    final itemResult = await widget.foodItemService.fetchFoodItemById(rec.foodItemId);
    if (!mounted) return;
    final item = itemResult.when(
      ok: (i) => i,
      err: (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toUserMessage())));
        return null;
      },
    );
    if (item == null) return;

    final choice = await showServingPickerSheet(context, item: item, mealLog: log);
    if (choice == null || !mounted) return;
    setState(() {
      _cartLog = log;
      _cart.add(choice);
    });
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart.removeAt(index);
      if (_cart.isEmpty) _cartLog = null;
    });
  }

  /// ยิง `POST /meal-logs/<id>/items` ทีละรายการตามลำดับในตะกร้า — เหมือนกับ
  /// FoodBrowserPage._confirm ทุกประการ (notify: false ในลูป ยิง
  /// MealLogEvents ทีเดียวหลังจบ กันถล่ม dev server ตอนยืนยันหลายเมนูรวด)
  Future<void> _saveCart() async {
    final log = _cartLog;
    if (log == null || _cart.isEmpty) return;
    setState(() => _saving = true);
    final remaining = <ServingChoice>[];
    String? error;
    var anySucceeded = false;
    for (final choice in _cart) {
      final result = await widget.mealLogService.addItem(
        logId: log.id,
        foodItemId: choice.item.id,
        servingSizeId: choice.servingSize?.id,
        quantity: choice.quantity,
        notify: false,
      );
      result.when(
        ok: (_) => anySucceeded = true,
        err: (e) {
          error = e.toUserMessage();
          remaining.add(choice);
        },
      );
    }
    if (anySucceeded) MealLogEvents.instance.changed();
    if (!mounted) return;
    setState(() {
      _cart
        ..clear()
        ..addAll(remaining);
      if (_cart.isEmpty) _cartLog = null;
      _saving = false;
    });
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error!)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกเมนูที่เลือกแล้ว')));
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: AppColors.teal500),
              const SizedBox(width: 8),
              Expanded(
                child: Text('AI แนะนำเมนู', style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900)),
              ),
              // ผู้ใช้รายงานจริง: อยากเลือกบันทึกเมนูที่ AI แนะนำย้อนหลังได้
              // ด้วย ไม่ใช่ล็อกไว้ที่วันนี้เสมอ — แตะเพื่อเปิด date picker
              // มาตรฐาน (ดู _pickAiRecommendDate ใน DashboardPage)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: _loading ? null : _randomizeCurrentMenu,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('เปลี่ยนเมนู', style: AppTextStyles.caption),
                  ),
                  TextButton.icon(
                    onPressed: widget.onPickDate,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.calendar_today, size: 14),
                    label: Text(_dateLabel, style: AppTextStyles.caption),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _categories
                  .map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(c.label),
                        selected: _category == c.value,
                        onSelected: (_) => _selectCategory(c.value),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: AppSkeletonLoader(variant: AppSkeletonVariant.listItem),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.coral600)),
            )
          else if (_blocked)
            // โรคประจำตัวห้ามทั้งหมวด (เช่นเบาหวานกับของหวาน) — ใช้โทนคอรัล
            // เดียวกับคำเตือนแพ้อาหารทั้งแอป (ดู AppColors.coral50 comment)
            // ไม่ใช่แค่ข้อความเทาเฉยๆ เพราะเป็นคำเตือนด้านสุขภาพที่ต้องสังเกตเห็น
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.coral50, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.health_and_safety_outlined, color: AppColors.coral600, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _blockedReason ?? 'ไม่แนะนำเมนูหมวดนี้สำหรับโรคประจำตัวของคุณ',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.coral600),
                    ),
                  ),
                ],
              ),
            )
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('ยังไม่มีเมนูแนะนำในหมวดนี้', style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600)),
            )
          else
            for (final rec in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppFoodCard(
                  imageUrl: rec.imageUrl,
                  categoryType: _category,
                  name: rec.menuName,
                  calories: rec.calories,
                  onTap: () => _addToCart(rec),
                ),
              ),
          if (_cart.isNotEmpty) ...[
            const Divider(height: 20),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _cart.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final choice = _cart[i];
                  return Chip(
                    key: ObjectKey(choice),
                    label: Text(
                      '${choice.item.displayName} (${choice.calories.toStringAsFixed(0)} kcal)',
                      style: AppTextStyles.caption,
                    ),
                    onDeleted: () => _removeFromCart(i),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'รวม ${_cartTotal.toStringAsFixed(0)} kcal (${_cart.length} รายการ)',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray900, fontWeight: FontWeight.w600),
                  ),
                ),
                ElevatedButton(
                  onPressed: _saving ? null : _saveCart,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(88, 40)),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('บันทึก'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// ทางเข้าหน้าเสนอเมนูใหม่ — backend/หน้าแอดมิน ("ข้อเสนอเมนู") มีระบบตรวจ
/// ข้อเสนออยู่แล้ว แต่ฝั่งผู้ใช้ไม่เคยมีทางส่งเข้ามาได้เลย (ผู้ใช้รายงานจริง)
/// วางไว้ที่หน้าหลัก/แดชบอร์ดตามที่ผู้ใช้ยืนยันว่าเหมาะกว่าหน้าอื่น
class _SuggestMenuEntry extends StatelessWidget {
  const _SuggestMenuEntry();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.gray50,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => const SuggestMenuPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.teal50, shape: BoxShape.circle),
                child: const Icon(Icons.add_circle_outline, color: AppColors.teal700, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('เสนอเมนูใหม่', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: AppColors.gray900)),
                    Text('อยากให้แอดมินเพิ่มเมนูอะไร บอกเราได้เลย', style: AppTextStyles.caption.copyWith(color: AppColors.gray600)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.gray400),
            ],
          ),
        ),
      ),
    );
  }
}

/// สรุปผลการกินท้ายวัน — โชว์เมื่อมื้อเย็นถูกบันทึกแล้ว (dinner_logged)
/// รายละเอียดการคำนวณ kcal เชิงลึก (เช่น macro breakdown ของวันนั้นๆ)
/// รอ prompt ถัดไปตามที่ผู้ใช้แจ้งไว้ — ตอนนี้สรุปจากตัวเลขที่มีอยู่แล้วก่อน
class _DailySummaryCard extends StatelessWidget {
  final DashboardData summary;
  const _DailySummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final overLimit = summary.overLimit;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.nightlight_round, size: 18, color: AppColors.gray600),
              const SizedBox(width: 8),
              Text('สรุปผลการกินวันนี้', style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'ทานไปทั้งหมด ${thousands(summary.caloriesConsumed.round())} kcal จากเป้า ${thousands(summary.caloriesGoal.round())} kcal',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: overLimit ? AppColors.coral50 : AppColors.teal50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              overLimit
                  ? 'เกินเป้าไป ${thousands((summary.caloriesConsumed - summary.caloriesGoal).round())} kcal'
                  : 'อยู่ในเป้าหมาย (เหลืออีก ${thousands((summary.caloriesGoal - summary.caloriesConsumed).round())} kcal)',
              style: AppTextStyles.bodySmall.copyWith(
                color: overLimit ? AppColors.coral600 : AppColors.teal700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  final _Macros macros;
  const _MacroRow({required this.macros});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppNutrientChip(label: 'โปรตีน', value: macros.protein, unit: 'g', color: AppColors.blue600),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AppNutrientChip(label: 'คาร์บ', value: macros.carbs, unit: 'g', color: AppColors.amber500),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AppNutrientChip(label: 'ไขมัน', value: macros.fat, unit: 'g', color: AppColors.coral600),
        ),
      ],
    );
  }
}

class _WeeklyChartCard extends StatelessWidget {
  final List<DailyCalorie> days;
  const _WeeklyChartCard({required this.days});

  static const _weekdayShort = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('แคลอรี 7 วันย้อนหลัง', style: AppTextStyles.labelBold.copyWith(color: AppColors.gray900)),
            const SizedBox(height: 8),
            AppBarChart(
              height: 80,
              points: days
                  .map(
                    (d) => AppBarChartPoint(
                      label: _weekdayShort[d.date.weekday % 7],
                      value: d.consumedKcal,
                      muted: d.consumedKcal <= 0,
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayMealsSection extends StatelessWidget {
  final List<MealLog> todayLogs;
  final ValueChanged<MealType> onAddMeal;
  final ValueChanged<MealLog> onMarkEaten;
  final ValueChanged<MealLog> onUndoEaten;
  final ValueChanged<MealLog> onManage;

  const _TodayMealsSection({
    required this.todayLogs,
    required this.onAddMeal,
    required this.onMarkEaten,
    required this.onUndoEaten,
    required this.onManage,
  });

  MealLog? _logFor(MealType type) {
    for (final log in todayLogs) {
      if (log.mealType == type) return log;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('มื้อวันนี้', style: AppTextStyles.labelBold.copyWith(color: AppColors.gray900)),
            const SizedBox(height: 8),
            for (final type in MealType.values) _mealRow(context, type),
          ],
        ),
      ),
    );
  }

  Widget _mealRow(BuildContext context, MealType type) {
    final log = _logFor(type);
    final rawHasItems = log != null && log.items.isNotEmpty;
    final rawAllEaten = rawHasItems && log.items.every((i) => i.isEaten);
    // มื้อที่เลือกเมนูไปแล้วแต่ไม่เคยกด "ทานแล้ว" เลย พอเลยเวลาของมื้อนั้น
    // ไปแล้ว (เข้าสู่ช่วงมื้อถัดไป/ปิดรับแล้ว) ให้ถือว่ามื้อนั้น "ยังไม่เคย
    // กรอก" ไปเลยทันที แทนที่จะค้างโชว์เมนูที่เลือกไว้เฉยๆ โดยไม่มีใครยืนยัน
    // ว่าทานจริง (ผู้ใช้ขอมาตรงๆ) — ส่วนมื้อที่กดทานแล้วแล้วนับว่าสำเร็จ
    // เสมอไม่ว่าเวลาจะผ่านไปแค่ไหน ไม่โดนกฎนี้กระทบ
    // ย้ายนิยาม "ปล่อยค้าง" ไปเป็น MealLog.isAbandoned (model กลาง) แล้ว —
    // BackfillSection ใช้ตัวเดียวกันด้วย กันสองที่นิยาม "มื้อนี้เสร็จหรือยัง"
    // เพี้ยนกันเอง (ผู้ใช้รายงานจริง)
    final abandoned = log != null && log.isAbandoned;
    final hasItems = rawHasItems && !abandoned;
    final allEaten = hasItems && rawAllEaten;
    // เดิมโชว์แค่ log.items.first.foodItemName เฉยๆ — เลือกหลายเมนูในมื้อ
    // เดียว (FoodBrowserPage เลือกหลายอย่างแล้วยืนยันรวดเดียวได้) ชื่อมื้อจะ
    // เห็นแค่เมนูแรกเมนูเดียว ทั้งที่ kcal รวม (log.totalCalories ด้านล่าง)
    // นับครบทุกเมนูอยู่แล้ว (ผู้ใช้รายงานจริง) ต่อท้ายด้วยจำนวนที่เหลือแทน
    final mealItemsLabel = hasItems
        ? (log.items.length > 1
            ? '${log.items.first.foodItemName ?? '-'} และอีก ${log.items.length - 1} รายการ'
            : (log.items.first.foodItemName ?? '-'))
        : null;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasItems ? AppColors.teal500 : AppColors.gray100,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(type.labelTh, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray900)),
          ),
          Expanded(
            child: hasItems
                ? Text(
                    mealItemsLabel ?? '-',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : const SizedBox.shrink(),
          ),
          if (!hasItems)
            // มื้อที่ยังไม่ได้เลือกเมนูต้องกดเพิ่มได้เสมอ ไม่ว่าจะเวลาไหน
            // ของวันหรือมื้อเย็นทานไปแล้วหรือยัง — ตรงกับ "บันทึกย้อนหลัง"
            // ที่ไม่ล็อกช่วงเวลาอยู่แล้ว (ผู้ใช้รายงานจริง)
            TextButton(
              onPressed: () => onAddMeal(type),
              child: Text('+ เพิ่มมื้อ${type.labelTh}'),
            )
          else ...[
            Text(
              '${log.totalCalories.toStringAsFixed(0)} kcal',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
            ),
            const SizedBox(width: 8),
            if (allEaten) ...[
              const AppMealStatusTag(status: AppMealStatus.eaten),
              // เดิมเช็ค items.any(canUndoEaten) (เวลาของเมนูใดเมนูหนึ่งเอง)
              // ทำให้ถ้ามีเมนูที่เพิ่งทานสดๆ ปนอยู่ ปุ่มยกเลิกยังโชว์ทั้งที่
              // มื้อปิดสนิทไปแล้วจากเมนูอื่น (ผู้ใช้รายงานจริง — backend
              // undo-eaten ก็เช็คระดับมื้อแล้วเหมือนกัน ดู _meal_is_sealed)
              if (!log.isSealed)
                TextButton(
                  onPressed: () => onUndoEaten(log),
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text('ยกเลิก', style: AppTextStyles.caption.copyWith(color: AppColors.coral600)),
                ),
            ] else
              TextButton(
                onPressed: () => onMarkEaten(log),
                child: const Text('ทานแล้ว'),
              ),
          ],
        ],
      ),
    );

    // แตะดูรายละเอียด/จัดการมื้อได้เฉพาะมื้อที่มีเมนูแล้วเท่านั้น — มื้อว่าง
    // ไม่มีอะไรให้ดู แค่ปุ่ม "+ เพิ่มมื้อ" ของตัวเองอยู่แล้ว (อยู่ใน [row])
    if (!hasItems) return row;
    return InkWell(
      onTap: () => onManage(log),
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}
