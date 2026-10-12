import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/widgets.dart';
import '../models/app_error.dart';
import '../models/health_goal_cycle.dart';
import '../models/meal_log.dart';
import '../services/auth_service.dart';
import '../services/data_events.dart';
import '../services/food_item_service.dart';
import '../services/health_goal_cycle_service.dart';
import '../services/meal_log_service.dart';
import 'backfill_section.dart';
import 'login_page.dart';
import 'meal_log_flow.dart';

const _thaiMonthsShort = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];
const _weekdayShort = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];
bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late AuthService auth;
  final MealLogService _mealLogService = createMealLogService();
  final FoodItemService _foodItemService = createFoodItemService();
  final HealthGoalCycleService _goalCycleService = createHealthGoalCycleService();

  List<MealLog> _logs = [];
  List<HealthGoalCycle> _goalCycles = [];
  bool _loading = true;
  String? _error;
  // เดิมใช้ _shownAsLoggedOut ที่ตั้งเป็น true แค่ตอน _init() เจอว่ายังไม่
  // login เท่านั้น — แต่ logout ไม่เคยเรียก _init() ใหม่ (build() ซ่อนเนื้อหา
  // ด้วย auth.isLoggedIn ตรงๆ อยู่แล้วเลยดูเหมือนใช้ได้) ผลคือ flag นี้ไม่ได้
  // ถูกตั้งตอน logout จริง พอ login เป็นคนใหม่ต่อในเซสชันเดียวกัน เงื่อนไข
  // "nowLoggedIn && _shownAsLoggedOut" เจอ false ค้างอยู่ เลยไม่ reload เลย
  // ประวัติของคนเก่าที่โหลดค้างไว้ก่อน logout จะยังค้างแสดงต่อ (บั๊กที่
  // ผู้ใช้รายงานจริง) เปลี่ยนมาเทียบสถานะ login จริงทุกครั้งแทน
  bool _wasLoggedIn = false;
  Timer? _undoLinkTicker;
  // นับ generation ของแต่ละ _loadHistory() ที่ยิงออกไป — ถ้ามีคำขอเก่าที่
  // ยังไม่เสร็จ (เช่น ตอนสลับผู้ใช้/login-logout เร็วๆ) กลับมาช้ากว่าคำขอใหม่
  // ต้องทิ้งผลลัพธ์เก่าไป ไม่งั้นข้อมูลของผู้ใช้คนก่อนจะโผล่มาทับของจริงชั่วครู่
  // (บั๊กที่ผู้ใช้รายงานจริง — เหมือน pattern เดียวกับ food_browser_page.dart)
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    auth = Provider.of<AuthService>(context, listen: false);
    // History lives inside an IndexedStack tab and is built once, so it
    // never gets a fresh initState when the user logs in/out later in the
    // same session — without this listener, a login state captured here as
    // "guest" would keep showing the guest screen forever.
    auth.addListener(_onAuthChanged);
    // มื้ออาหารอาจถูกบันทึก/ทำเครื่องหมายทานแล้วจากแท็บอื่น (เช่น Dashboard)
    // ขณะที่แท็บนี้ค้างอยู่เบื้องหลังใน IndexedStack — ฟังไว้แล้วรีเฟรชสด
    MealLogEvents.instance.addListener(_onMealLogChanged);
    // ลิงก์ "ยกเลิก" ต้องหายไปเองหลัง 5 นาทีแม้ผู้ใช้ไม่ทำอะไรเลย (ดู
    // MealLogItem.canUndoEaten) — สั่ง rebuild เป็นระยะเบาๆ พอ
    _undoLinkTicker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
    _init();
  }

  @override
  void dispose() {
    auth.removeListener(_onAuthChanged);
    MealLogEvents.instance.removeListener(_onMealLogChanged);
    _undoLinkTicker?.cancel();
    super.dispose();
  }

  void _onMealLogChanged() {
    if (!mounted || _loading) return;
    if (!auth.isLoggedIn || auth.isGuest) return;
    _loadHistory();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final nowLoggedIn = auth.isLoggedIn && !auth.isGuest;
    if (nowLoggedIn == _wasLoggedIn) return;
    _wasLoggedIn = nowLoggedIn;
    if (nowLoggedIn) {
      setState(() => _loading = true);
      _init();
    } else {
      // ล้างประวัติของ user เก่าทันทีตอน logout กันข้อมูลค้างโผล่แวบนึงถ้า
      // login คนใหม่ต่อเร็วๆ ก่อน _init() ของคนใหม่จะโหลดเสร็จ
      setState(() {
        _logs = [];
        _goalCycles = [];
      });
    }
  }

  Future<void> _init() async {
    await auth.loadToken();
    _wasLoggedIn = auth.isLoggedIn && !auth.isGuest;
    if (!auth.isLoggedIn || auth.isGuest) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    await Future.wait([_loadHistory(), _loadGoalCycles()]);
  }

  /// สรุปผลรอบเป้าหมายสุขภาพ 7 วันที่จบไปแล้ว (backend คำนวณให้ ดู
  /// _finalize_expired_goal_cycle) — ล้มเหลวได้โดยไม่กระทบประวัติมื้ออาหาร
  /// หลักของหน้านี้ เป็นแค่การ์ดเสริมด้านบน
  Future<void> _loadGoalCycles() async {
    final result = await _goalCycleService.fetchCycles();
    if (!mounted) return;
    result.when(
      ok: (cycles) => setState(() => _goalCycles = cycles),
      err: (_) {},
    );
  }

  /// วันแรก (health_goal_started_at) ของเป้าหมายที่ใช้งานอยู่ตอนนี้ — null ถ้า
  /// ยังไม่เคยตั้งเป้าหมายเลย
  DateTime? get _goalStartDate {
    final raw = auth.user?['health_goal_started_at']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  DateTime get _todayBangkok {
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    return DateTime(now.year, now.month, now.day);
  }

  // เป้าหมายแคลอรี "ปัจจุบัน" ของ user (ตัวเดียวกับที่หน้าโปรไฟล์/แดชบอร์ด
  // โชว์) — เดิมหน้านี้ใช้ log.caloriesGoal ซึ่งเป็น snapshot ตอนบันทึกมื้อ
  // นั้นๆ ถ้าค่านี้เคยถูกแก้ไข/คำนวณใหม่หลังบันทึกมื้อไปแล้ว (เช่นแก้ข้อมูล
  // ส่วนตัวหรือระบบคำนวณเป้าหมายใหม่ให้) ตัวเลขหน้าประวัติจะค้างเป็นค่าเก่า
  // ไม่ตรงกับเป้าหมายที่เลือกไว้จริงในหน้าโปรไฟล์ (ผู้ใช้รายงานจริง) ใช้ค่า
  // สดจาก auth.user แทนทุกจุดในหน้านี้ให้ตรงกันเสมอ
  double? get _currentCaloriesGoal => (auth.user?['calories_goal'] as num?)?.toDouble();

  // ช่วงวันที่ของกราฟยังอิงเป้าหมายสุขภาพปัจจุบัน ส่วนรายการประวัติแสดงทุกวันที่มีบันทึก
  DateTime get _rangeFrom => _goalStartDate ?? _todayBangkok.subtract(const Duration(days: 6));

  // ไม่ให้ยาวเกินวันหมดเขตของเป้าหมาย (health_goal_locked_until) เผื่อรอบ
  // หมดอายุไปแล้วแต่ยังไม่ได้ตั้งเป้าหมายใหม่ทับ — ไม่งั้นช่วงจะยาวขึ้นเรื่อยๆ
  // ไม่มีที่สิ้นสุดจนกว่าจะตั้งเป้าหมายใหม่
  DateTime get _rangeTo {
    if (_goalStartDate == null) return _todayBangkok;
    final lockedRaw = auth.user?['health_goal_locked_until']?.toString();
    final locked = lockedRaw != null ? DateTime.tryParse(lockedRaw) : null;
    if (locked == null) return _todayBangkok;
    final lockedDay = DateTime(locked.year, locked.month, locked.day);
    return lockedDay.isBefore(_todayBangkok) ? lockedDay : _todayBangkok;
  }

  Future<void> _loadHistory() async {
    final myGeneration = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _mealLogService.fetchLogs();
    if (!mounted || myGeneration != _loadGeneration) return;
    result.when(
      ok: (logs) {
        final sorted = [...logs]..sort((a, b) => b.logDate.compareTo(a.logDate));
        setState(() {
          _logs = sorted;
          _loading = false;
        });
      },
      err: (error) {
        if (error is AuthError) {
          Navigator.of(context, rootNavigator: true).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
          return;
        }
        setState(() {
          _loading = false;
          _error = error.toUserMessage();
        });
      },
    );
  }

  bool _isToday(DateTime logDate) {
    final nowTh = DateTime.now().toUtc().add(const Duration(hours: 7));
    return _isSameDay(logDate, nowTh);
  }

  Future<void> _markLogEaten(MealLog log) async {
    var current = log;
    for (final item in log.items.where((i) => !i.isEaten)) {
      final result = await _mealLogService.markItemEaten(item.id);
      if (!mounted) return;
      final updated = result.when(ok: (l) => l, err: (error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toUserMessage())));
        return null;
      });
      if (updated == null) return;
      current = updated;
    }
    if (!mounted) return;
    setState(() {
      final idx = _logs.indexWhere((l) => l.id == current.id);
      if (idx != -1) _logs[idx] = current;
    });
  }

  /// เดิมยกเลิกแค่ log.items.first ตัวเดียว ทั้งที่มื้อเดียวมีได้หลายเมนู —
  /// เมนูที่เหลือค้างเป็น "ทานแล้ว" ต่อไปเงียบๆ แล้วล็อกถาวรเมื่อเลย 5 นาที
  /// ของตัวเอง ทั้งที่ผู้ใช้กดยกเลิกทั้งมื้อไปแล้ว (ผู้ใช้รายงานจริง — เจอ
  /// ปัญหาเดียวกับ dashboard_page.dart/meal_select_sheet.dart) วนยกเลิกทุก
  /// เมนูที่ยังอยู่ในช่วง 5 นาที ให้สมมาตรกับตอนกด "ทานแล้ว" ทั้งมื้อ
  Future<void> _undoItemEaten(MealLog log) async {
    MealLog? latest;
    String? error;
    for (final item in log.items.where((i) => i.canUndoEaten)) {
      final result = await _mealLogService.undoItemEaten(item.id);
      result.when(
        ok: (updated) => latest = updated,
        err: (e) => error = e.toUserMessage(),
      );
    }
    if (!mounted) return;
    if (latest != null) {
      setState(() {
        final idx = _logs.indexWhere((l) => l.id == latest!.id);
        if (idx != -1) _logs[idx] = latest!;
      });
    }
    if (error != null) {
      // เผื่อ race condition เวลาไม่ตรงกันพอดี (ปุ่มยังโชว์อยู่ฝั่ง client
      // แต่ backend ถือว่าเกิน 5 นาทีไปแล้วจริง) — แจ้งเตือนสุภาพ ไม่ crash
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error!)));
    }
  }

  void _showEntryDetail(MealLog log) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'มื้อ${log.mealType.labelTh} • ${_formatDate(log.logDate)}',
                          style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900),
                        ),
                      ),
                      GestureDetector(onTap: () => Navigator.of(ctx).pop(), child: const Icon(Icons.close, size: 22)),
                    ],
                  ),
                  if (_currentCaloriesGoal != null)
                    Text(
                      'เป้าหมาย ${_currentCaloriesGoal!.toStringAsFixed(0)} kcal',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
                    ),
                  const Divider(height: 20),
                  if (log.items.isEmpty)
                    Text('ยังไม่มีเมนูในมื้อนี้', style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600))
                  else
                    ...log.items.map(
                      (it) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${it.foodItemName ?? 'เมนู #${it.foodItemId}'} '
                                '(${(it.caloriesActual ?? 0).toStringAsFixed(0)} kcal)',
                                style: AppTextStyles.bodyMedium,
                              ),
                            ),
                            AppMealStatusTag(status: it.isEaten ? AppMealStatus.eaten : AppMealStatus.planned),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day} ${_thaiMonthsShort[d.month - 1]} ${d.year}';

  Future<void> _startFirstLog() async {
    await startMealLogFlow(
      context,
      mealLogService: _mealLogService,
      foodItemService: _foodItemService,
    );
    if (mounted) _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    if (!auth.isLoggedIn || auth.isGuest) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('ประวัติ')),
        body: AppEmptyState(
          icon: Icons.lock_outline,
          title: 'ประวัติการใช้งานมีให้เฉพาะผู้ใช้ที่ล็อกอินเท่านั้น',
          ctaLabel: 'เข้าสู่ระบบ',
          onCta: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const LoginPage())),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('ประวัติ')),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([_loadHistory(), _loadGoalCycles()]),
        child: CustomScrollView(
          slivers: [
            if (_loading)
              SliverToBoxAdapter(child: _buildSkeleton())
            else if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AppErrorBanner(message: _error!, onRetry: _loadHistory),
                ),
              )
            else if (_logs.isEmpty) ...[
              if (_goalCycles.isNotEmpty) SliverToBoxAdapter(child: _buildGoalCycles()),
              SliverFillRemaining(
                hasScrollBody: false,
                child: AppEmptyState(
                  icon: Icons.receipt_long,
                  title: 'เริ่มบันทึกวันนี้เลย',
                  subtitle: 'ยังไม่มีประวัติมื้ออาหารในช่วงนี้',
                  ctaLabel: 'บันทึกมื้อแรก',
                  onCta: _startFirstLog,
                ),
              ),
            ] else ...[
              // ผู้ใช้ขอให้กราฟแท่งอยู่บนสุดเสมอ — การ์ดสรุปผลรอบเป้าหมาย
              // (สำเร็จ/ไม่สำเร็จ) เดิมอยู่บนสุดตลอด ผู้ใช้บอกว่าเกะกะ ย้ายไปไว้
              // ใต้กราฟ+บันทึกย้อนหลังแทน (ก่อนรายการมื้ออาหารรายวัน)
              SliverToBoxAdapter(child: _buildChart()),
              // ผู้ใช้ขอ: หน้าประวัติต้องบอกด้วยว่าวันไหน/มื้อไหนของรอบเป้าหมาย
              // ยังไม่ได้กรอกบ้าง — ใช้ BackfillSection ตัวเดียวกับที่ Dashboard
              // ใช้อยู่แล้ว (ดูคอมเมนต์ในไฟล์นั้น: ย้ายออกมาเป็น widget แยกเพื่อ
              // ใช้ซ้ำได้ทั้ง 2 หน้า แต่หน้านี้ไม่เคยเอากลับมาใส่จริง)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: BackfillSection(
                    mealLogService: _mealLogService,
                    foodItemService: _foodItemService,
                  ),
                ),
              ),
              if (_goalCycles.isNotEmpty) SliverToBoxAdapter(child: _buildGoalCycles()),
              _buildGroupedList(),
            ],
          ],
        ),
      ),
    );
  }

  /// การ์ดสรุปผลรอบเป้าหมายสุขภาพ 7 วันที่จบไปแล้ว — สะสมทีละรอบ (ใหม่สุด
  /// ก่อน, ดู _loadGoalCycles) ตัวเลข/ผลสำเร็จมาจาก backend ล้วนๆ
  /// (_finalize_expired_goal_cycle) หน้านี้แค่แสดงผล ไม่คำนวณเอง — ผู้ใช้บอกว่า
  /// การ์ดผลสำเร็จ/ไม่สำเร็จเกะกะ ขอย้ายไปไว้ในช่องแยกที่พับเก็บได้ (ใช้
  /// ExpansionTile ของ Flutter เอง ไม่ต้องสร้าง accordion เอง) แทนโชว์ค้าง
  /// อยู่บนหน้าตลอด
  Widget _buildGoalCycles() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        // ต้องเป็น Material (ไม่ใช่แค่ Container) ให้ ListTile ภายใน
        // ExpansionTile มีพื้นสีทึบให้วาด ink splash ทับได้จริง — Container
        // เฉยๆ ทำให้ Flutter เตือน "ListTile background color or ink
        // splashes may be invisible" ทุกครั้งที่แตะขยาย/ย่อ (ผู้ใช้รายงานจริง)
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            title: Text(
              'ดูประวัติเป้าหมายสำเร็จหรือไม่',
              style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900),
            ),
            children: _goalCycles.map(_buildGoalCycleCard).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildGoalCycleCard(HealthGoalCycle cycle) {
    final percent = (cycle.successRatio * 100).round();
    final color = cycle.isSuccess ? AppColors.teal700 : AppColors.coral600;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cycle.isSuccess ? AppColors.teal50 : AppColors.coral50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  // เดิม hardcode "ครบ 7 วัน" ตอนที่ยังล็อกเป้าหมายตายตัว 7
                  // วันเสมอ — ตอนนี้ระยะเวลากำหนดเองได้ (ดูปุ่ม "คำนวณ" ในกล่อง
                  // วางแผนพลังงานหน้าโปรไฟล์) คำนวณจำนวนวันจริงจาก period แทน
                  'ครบ ${cycle.periodEnd.difference(cycle.periodStart).inDays + 1} วัน • เป้าหมาย${cycle.healthGoal}',
                  style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(cycle.isSuccess ? Icons.check_circle : Icons.cancel, color: color, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    cycle.isSuccess ? 'สำเร็จ' : 'ไม่สำเร็จ',
                    style: AppTextStyles.bodySmall.copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatDate(cycle.periodStart)} - ${_formatDate(cycle.periodEnd)}',
            style: AppTextStyles.caption.copyWith(color: AppColors.gray600),
          ),
          const SizedBox(height: 6),
          Text(
            'บันทึกมื้ออาหารไป ${cycle.mealsLogged} จาก ${cycle.mealsAvailable} มื้อที่มีให้เลือก ($percent%)',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray900),
          ),
          if (cycle.weightStart != null && cycle.weightEnd != null) ...[
            const SizedBox(height: 2),
            Text(
              'น้ำหนัก ${cycle.weightStart!.toStringAsFixed(1)} -> ${cycle.weightEnd!.toStringAsFixed(1)} กก.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray900),
            ),
          ],
          if (cycle.mealsOverQuota > 0) ...[
            const SizedBox(height: 2),
            Text(
              'กินเกินโควตาต่อมื้อไป ${cycle.mealsOverQuota} มื้อ',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.coral600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: List.generate(5, (_) => const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: AppSkeletonLoader(variant: AppSkeletonVariant.listItem),
      ))),
    );
  }

  Widget _buildChart() {
    final byDay = <DateTime, List<MealLog>>{};
    for (final log in _logs) {
      final key = DateTime(log.logDate.year, log.logDate.month, log.logDate.day);
      byDay.putIfAbsent(key, () => []).add(log);
    }
    final from = _rangeFrom;
    final to = _rangeTo;
    final totalDays = to.difference(from).inDays + 1;
    // เดิมซ่อนกราฟไปเลยตอนมีข้อมูลแค่วันเดียว (วันแรกของเป้าหมายที่เพิ่ง
    // เริ่ม) — ผู้ใช้ยืนยันว่าอยากเห็นกราฟเสมอตั้งแต่วันแรก แม้จะมีแค่แท่ง
    // เดียวก็ตาม (ตัวกราฟเองไม่ยืดเต็มความกว้างแบบผิดสัดส่วนแล้ว ดู
    // AppBarChart._kMinChartSlots) เลยเอาเงื่อนไขซ่อนออก
    final points = List.generate(totalDays, (i) {
      final day = from.add(Duration(days: i));
      final dayLogs = byDay[day] ?? const <MealLog>[];
      final planned = _currentCaloriesGoal ?? 0.0;
      final eaten = dayLogs.fold(
        0.0,
        (s, l) => s + l.items.where((it) => it.isEaten).fold(0.0, (s2, it) => s2 + (it.caloriesActual ?? 0)),
      );
      return AppBarChartPoint(
        // ผู้ใช้ขอชื่อวัน (จันทร์-อาทิตย์) กลับมาด้วย ไม่ใช่มีแค่ตัวเลข —
        // ใช้ชื่อย่อ (จ/อ/พ/...) แทนชื่อเต็ม เพราะพื้นที่ใต้แท่งแคบมากตอนมี
        // หลายสิบแท่ง (แผน 30 วัน) ชื่อเต็มจะล้นทับกันเอง — เคยลองใส่ปีคู่กัน
        // แบบเต็ม "dd/mm/yyyy" ไปแล้ว (ทั้งแบบตัดบรรทัดอัตโนมัติและตัดเอง)
        // แต่ 11 แท่งขึ้นไปแต่ละช่องแคบเกินกว่าจะพอสำหรับแม้แต่ "dd/mm" ที่เติม
        // เลข 0 นำหน้า (04/08 กว้างพอๆ กับช่องเอง แทบไม่เหลือช่องไฟ ยังชิดกัน
        // อยู่ดี — ผู้ใช้รายงานจริง) ตัดเลข 0 นำหน้าออก (4/8 แทน 04/08) แคบลง
        // จริงเฉลี่ย ~1-2 ตัวอักษรต่อวัน เหลือที่ให้มีช่องไฟระหว่างวันได้ ปีเต็ม
        // ยังดูได้จาก tooltip ตอนแตะเหมือนเดิม (tooltipLabel ด้านล่าง)
        label: _weekdayShort[day.weekday % 7],
        sublabel: '${day.day}/${day.month}',
        value: eaten,
        backgroundValue: planned,
        muted: eaten <= 0,
        tooltipLabel: _formatDate(day),
      );
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.gray50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ผู้ใช้ขอให้หัวข้อบอกจำนวนวันของเป้าหมายที่เลือกไว้ตรงๆ (เช่น
            // "แผนเป้าหมายสุขภาพ 30 วัน") แทนประโยคยาวเดิม
            Text(
              _goalStartDate != null ? 'แผนเป้าหมายสุขภาพ $totalDays วัน' : 'แคลอรี $totalDays วันย้อนหลัง',
              textAlign: TextAlign.center,
              style: AppTextStyles.labelBold.copyWith(color: AppColors.gray900),
            ),
            const SizedBox(height: 16),
            AppBarChart(height: 100, points: points),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedList() {
    final byDay = <DateTime, List<MealLog>>{};
    for (final log in _logs) {
      final key = DateTime(log.logDate.year, log.logDate.month, log.logDate.day);
      byDay.putIfAbsent(key, () => []).add(log);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    const mealOrder = [MealType.breakfast, MealType.lunch, MealType.dinner];

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final day = days[index];
          final dayLogs = [...byDay[day]!]
            ..sort((a, b) => mealOrder.indexOf(a.mealType).compareTo(mealOrder.indexOf(b.mealType)));
          final dayEaten = dayLogs.fold(
            0.0,
            (s, l) => s + l.items.where((it) => it.isEaten).fold(0.0, (s2, it) => s2 + (it.caloriesActual ?? 0)),
          );
          // caloriesGoal ของแต่ละมื้อเป็นแค่ snapshot ตอนบันทึกมื้อนั้น — เดิม
          // บวกรวมทุกมื้อในวันเดียวกัน ทำให้วันที่บันทึกครบ 3 มื้อ เป้าหมาย
          // กลายเป็น 3 เท่าของจริง แล้วต่อให้แก้เป็นเอาค่าเดียวก็ยังค้างเป็น
          // ค่าเก่าถ้าเป้าหมายถูกคำนวณใหม่หลังบันทึกมื้อนั้นไปแล้ว (ผู้ใช้
          // รายงานจริง: 525/2096 ไม่ตรงกับที่โปรไฟล์โชว์ 1815) ใช้ค่าเป้าหมาย
          // ปัจจุบันสดจาก auth.user แทนไปเลย ตรงกับหน้าโปรไฟล์/แดชบอร์ดเสมอ
          final dayGoal = _currentCaloriesGoal ?? 0.0;

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isSameDay(day, DateTime.now().toUtc().add(const Duration(hours: 7)))
                          ? 'วันนี้ • ${_formatDate(day)}'
                          : _formatDate(day),
                      style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900),
                    ),
                    Text(
                      '${dayEaten.toStringAsFixed(0)} / ${dayGoal.toStringAsFixed(0)} kcal',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...dayLogs.map((log) => _buildMealCard(log)),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
        childCount: days.length,
      ),
    );
  }

  Widget _buildMealCard(MealLog log) {
    final allEaten = log.items.isNotEmpty && log.items.every((it) => it.isEaten);
    final canMarkEaten = log.items.any((it) => !it.isEaten) && _isToday(log.logDate);
    final firstName = log.items.isEmpty ? null : log.items.first.foodItemName;
    final extraCount = log.items.length - 1;
    final name = firstName == null
        ? 'มื้อ${log.mealType.labelTh}'
        : 'มื้อ${log.mealType.labelTh} • $firstName${extraCount > 0 ? ' และอีก $extraCount รายการ' : ''}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppFoodCard(
        categoryType: 'food',
        name: name,
        calories: log.totalCalories,
        onTap: () => _showEntryDetail(log),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AppMealStatusTag(status: allEaten ? AppMealStatus.eaten : AppMealStatus.planned),
            // เดิมเช็ค items.any(canUndoEaten) (เวลาของเมนูใดเมนูหนึ่งเอง)
            // เปลี่ยนเป็นเช็คทั้งมื้อ (isSealed) ให้สอดคล้องกับ Dashboard
            // (ผู้ใช้รายงานจริง)
            if (allEaten && !log.isSealed)
              TextButton(
                onPressed: () => _undoItemEaten(log),
                style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text('ยกเลิก', style: AppTextStyles.caption.copyWith(color: AppColors.coral600)),
              ),
            if (canMarkEaten) ...[
              const SizedBox(height: 6),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _markLogEaten(log),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.teal500, borderRadius: BorderRadius.circular(8)),
                  child: const Text('ทานแล้ว', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
