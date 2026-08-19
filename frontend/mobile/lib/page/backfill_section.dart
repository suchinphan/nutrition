import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../models/meal_log.dart';
import '../services/auth_service.dart';
import '../services/data_events.dart';
import '../services/food_item_service.dart';
import '../services/meal_log_service.dart';
import 'meal_log_flow.dart';

bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// ช่วงวันที่กรอกย้อนหลังได้ของเป้าหมายสุขภาพที่ใช้งานอยู่ (วันแรกที่ตั้ง
/// เป้าหมาย -> วันนี้ หรือวันที่ล็อกถ้าล็อกไปแล้ว ดู health_goal_started_at/
/// health_goal_locked_until ที่ตั้งจากหน้าโปรไฟล์ "วางแผนพลังงาน") คืน null
/// ถ้ายังไม่เคยตั้งเป้าหมาย — ใช้ร่วมกันทั้ง [BackfillSection] ด้านล่างและปุ่ม
/// เลือกวันที่ของการ์ด "AI แนะนำเมนู" บน Dashboard กันคำนวณช่วงวันที่ valid
/// เพี้ยนกันสองที่ (ผู้ใช้รายงานจริง: ปุ่มเลือกวันของ AI แนะนำเมนูเดิมเปิดให้
/// ย้อนหลังได้ถึง 1 ปี ทั้งที่ควรอิงตามจำนวนวันของแผนพลังงานที่ตั้งไว้จริง)
(DateTime start, DateTime end)? healthGoalBackfillRange() {
  final auth = AuthService();
  final raw = auth.user?['health_goal_started_at']?.toString();
  if (raw == null || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  final start = DateTime(parsed.year, parsed.month, parsed.day);

  final now = DateTime.now().toUtc().add(const Duration(hours: 7));
  var end = DateTime(now.year, now.month, now.day);
  final lockedRaw = auth.user?['health_goal_locked_until']?.toString();
  final locked = lockedRaw != null ? DateTime.tryParse(lockedRaw) : null;
  if (locked != null) {
    final lockedDay = DateTime(locked.year, locked.month, locked.day);
    if (lockedDay.isBefore(end)) end = lockedDay;
  }
  if (end.isBefore(start)) return null;
  return (start, end);
}

/// การ์ด "บันทึกย้อนหลัง" — รายวันของเป้าหมายสุขภาพที่ใช้งานอยู่ (วันแรก ->
/// วันนี้) แต่ละแถวโชว์ว่ามื้อไหนยังไม่ได้กรอกบ้าง แตะแถวไหนก็เปิดกรอกย้อนหลัง
/// ของวันนั้นได้เลย ย้ายมาจาก HistoryPage เดิมให้เป็น widget แยก เพื่อใช้ซ้ำ
/// บน Dashboard ได้ด้วย (ผู้ใช้ขอ: อยากได้แบบเดียวกับหน้าประวัติมาไว้ที่
/// แดชบอร์ด) — โหลด/รีเฟรชข้อมูลของตัวเองทั้งหมด ไม่ต้องพึ่งหน้าที่เรียกใช้
class BackfillSection extends StatefulWidget {
  final MealLogService mealLogService;
  final FoodItemService foodItemService;

  const BackfillSection({
    super.key,
    required this.mealLogService,
    required this.foodItemService,
  });

  @override
  State<BackfillSection> createState() => _BackfillSectionState();
}

class _BackfillSectionState extends State<BackfillSection> {
  final AuthService _auth = AuthService();
  List<MealLog> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
    MealLogEvents.instance.addListener(_load);
    _auth.addListener(_load);
  }

  @override
  void dispose() {
    MealLogEvents.instance.removeListener(_load);
    _auth.removeListener(_load);
    super.dispose();
  }

  DateTime? get _goalStartDate => healthGoalBackfillRange()?.$1;

  DateTime get _todayBangkok {
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    return DateTime(now.year, now.month, now.day);
  }

  List<DateTime> get _backfillDays {
    final range = healthGoalBackfillRange();
    if (range == null) return const [];
    final (start, last) = range;
    final totalDays = last.difference(start).inDays + 1;
    return List.generate(totalDays, (i) => last.subtract(Duration(days: i)));
  }

  Future<void> _load() async {
    if (!_auth.isLoggedIn || _auth.isGuest) {
      if (mounted) setState(() => _logs = []);
      return;
    }
    final start = _goalStartDate;
    if (start == null) {
      if (mounted) setState(() => _logs = []);
      return;
    }
    final result = await widget.mealLogService.fetchLogs(from: start, to: _todayBangkok);
    if (!mounted) return;
    result.when(
      ok: (logs) => setState(() => _logs = logs),
      err: (_) {},
    );
  }

  // เดิมนับว่า "กรอกแล้ว" แค่เพราะมี items.isNotEmpty เฉยๆ — มื้อที่เลือกเมนู
  // ไปแล้วแต่ไม่เคยกด "ทานแล้ว" แล้วเลยเวลาของมื้อนั้นไปแล้ว (Dashboard เรียก
  // ว่า "ปล่อยค้าง"/isAbandoned) ก็ยังถูกนับว่ากรอกครบอยู่ดี ทั้งที่ Dashboard
  // เองแสดงมื้อนั้นเป็น "+ เพิ่มมื้อ..." (ยังไม่กรอก) — ผู้ใช้รายงานจริง: ยังไม่
  // ได้เลือกมื้อไหนเลยสักมื้อ แต่บันทึกย้อนหลังกลับไม่แจ้งมื้อเช้าว่าขาด ใช้
  // MealLog.isAbandoned (model กลาง) ตัวเดียวกับ Dashboard กันนิยามเพี้ยนกัน
  List<MealType> _missingMealsOn(DateTime day) {
    final loggedTypes = _logs
        .where((l) => _isSameDay(l.logDate, day) && l.items.isNotEmpty && !l.isAbandoned)
        .map((l) => l.mealType)
        .toSet();
    return MealType.values.where((t) => !loggedTypes.contains(t)).toList();
  }

  Future<void> _backfillDay(DateTime day) async {
    await startMealLogFlow(
      context,
      mealLogService: widget.mealLogService,
      foodItemService: widget.foodItemService,
      date: day,
    );
    if (mounted) await _load();
  }

  // ผู้ใช้ขอวันที่เต็มแบบ วัน/เดือน/ปี แทนเดือนย่อภาษาไทย
  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  // พับเก็บ/กางออกได้ (ผู้ใช้ขอ) — เดิมโชว์ทุกวันของเป้าหมายค้างเต็มจอตลอด
  // ยิ่งเป้าหมายยาว (เช่น 30 วัน) ยิ่งกินพื้นที่เยอะ ใช้ ExpansionTile ของ
  // Flutter เอง (ไม่สร้าง accordion เอง) แบบเดียวกับ _buildGoalCycles ใน
  // history_page.dart — ต้องห่อด้วย Material (ไม่ใช่แค่ Container) ให้
  // ListTile ภายในมีพื้นสีทึบวาด ink splash ได้จริง ไม่งั้น Flutter เตือน
  // "ListTile background color or ink splashes may be invisible"
  @override
  Widget build(BuildContext context) {
    final days = _backfillDays;
    if (days.isEmpty) return const SizedBox.shrink();
    return Material(
      color: AppColors.gray50,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Text('บันทึกย้อนหลัง', style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900)),
          subtitle: Text(
            'วันที่ 1 ถึงวันนี้ของเป้าหมายที่ใช้งานอยู่ — แตะวันไหนก็กรอกมื้อที่ยังขาดได้',
            style: AppTextStyles.caption.copyWith(color: AppColors.gray600),
          ),
          children: [for (final day in days) _buildDayRow(day)],
        ),
      ),
    );
  }

  Widget _buildDayRow(DateTime day) {
    final missing = _missingMealsOn(day);
    final dayNumber = day.difference(_goalStartDate!).inDays + 1;
    final isToday = _isSameDay(day, _todayBangkok);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _backfillDay(day),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'วันที่ $dayNumber • ${_formatDate(day)}${isToday ? ' (วันนี้)' : ''}',
                      style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: AppColors.gray900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      missing.isEmpty ? 'ครบทุกมื้อแล้ว' : 'ยังไม่ได้กรอก: ${missing.map((m) => m.labelTh).join(', ')}',
                      style: AppTextStyles.caption.copyWith(
                        color: missing.isEmpty ? AppColors.teal700 : AppColors.coral600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                missing.isEmpty ? Icons.check_circle : Icons.chevron_right,
                color: missing.isEmpty ? AppColors.teal500 : AppColors.gray400,
                size: missing.isEmpty ? 20 : 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
