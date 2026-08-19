import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../models/meal_log.dart';
import '../services/food_item_service.dart';
import '../services/meal_log_service.dart';
import 'food_browser_page.dart';
import 'meal_log_flow.dart';

// kMealTimeWindows ย้ายไปอยู่ที่ models/meal_log.dart แล้ว (ใช้ร่วมกับ
// NotificationHelper ด้วย) — import มาจากที่นั่นแทนการประกาศซ้ำในนี้ ยังใช้
// อยู่แค่เป็นข้อความอ้างอิงเวลาแนะนำใต้ชื่อมื้อ ไม่ใช้ล็อกอีกต่อไป (ผู้ใช้
// ยืนยันชัดเจน: อนุญาตกรอกมื้อไหนเวลาไหนก็ได้ รวมถึงกรอกย้อนหลังผ่าน [date])

/// Step 1 ของ flow บันทึกมื้ออาหาร — BottomSheet เลือกมื้อ เช้า/กลางวัน/เย็น
/// แสดงผลลัพธ์กลับผ่าน [showMealSelectSheet] เป็น [MealLog] ที่พร้อมใช้ต่อ
/// (สร้างใหม่ หรือดึงของเดิมที่มี log อยู่แล้ว) — [date] = null คือวันนี้
/// (ของเดิม) ระบุวันที่อื่นเพื่อกรอกย้อนหลัง (ดู history_page.dart/
/// dashboard_page.dart ปุ่ม "บันทึกย้อนหลัง")
class MealSelectSheet extends StatefulWidget {
  final MealLogService mealLogService;
  final List<MealLog> todayLogs;
  final DateTime? date;

  const MealSelectSheet({super.key, required this.mealLogService, required this.todayLogs, this.date});

  @override
  State<MealSelectSheet> createState() => _MealSelectSheetState();
}

class _MealSelectSheetState extends State<MealSelectSheet> {
  MealType? _loadingType;
  String? _error;
  // สำเนา local ที่แก้ได้ — กด "ยกเลิก" (undo-eaten) จากหน้านี้แล้วต้องเห็น
  // สถานะอัปเดตทันทีในชีทเดียวกัน ไม่ต้องปิดแล้วเปิดใหม่ (ดู _undoEaten)
  final List<MealLog> _logs = [];

  @override
  void initState() {
    super.initState();
    _logs.addAll(widget.todayLogs);
  }

  // ผู้ใช้รายงานจริง: กดเลือกเมนูที่ AI แนะนำแล้วเจอชีทนี้โดยไม่รู้ว่ากำลัง
  // บันทึกของวันไหน (โดยเฉพาะสับสนกับ flow "บันทึกย้อนหลัง" ที่ก็เปิดชีทนี้
  // เหมือนกันทุกจุด) — บอกวันที่ให้ชัดเจนทุกครั้งที่เปิดชีทนี้ ไม่ว่าจะเข้ามา
  // จากทางไหน (ปุ่ม "+ เพิ่มมื้อ", AI แนะนำเมนู, หรือบันทึกย้อนหลัง)
  String _dateLabel() {
    final d = widget.date ?? DateTime.now();
    final now = DateTime.now();
    final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
    return isToday ? 'สำหรับวันนี้' : 'บันทึกย้อนหลังสำหรับวันที่ ${d.day}/${d.month}/${d.year}';
  }

  MealLog? _existingLog(MealType type) {
    for (final log in _logs) {
      // log ว่าง (สร้างไว้ผ่าน getOrCreateLog แต่ยังไม่เคยเพิ่มเมนูเลย เช่น
      // เปิด FoodBrowserPage แล้วออกกลางทาง) ไม่นับว่า "บันทึกแล้ว" — ไม่งั้น
      // ขึ้นเครื่องหมายถูกทั้งที่ไม่มีเมนูจริง ไม่ตรงกับ dashboard_page.dart
      // (rawHasItems) ที่เช็ค items.isNotEmpty อยู่แล้ว (บั๊กที่ผู้ใช้รายงานจริง)
      if (log.mealType == type && log.items.isNotEmpty) return log;
    }
    return null;
  }

  Future<void> _select(MealType type) async {
    setState(() {
      _loadingType = type;
      _error = null;
    });
    final result = await widget.mealLogService.getOrCreateLog(mealType: type, date: widget.date);
    if (!mounted) return;
    result.when(
      ok: (outcome) => Navigator.of(context).pop(outcome.log),
      err: (error) => setState(() {
        _loadingType = null;
        _error = error.toUserMessage();
      }),
    );
  }

  /// ยกเลิก "ทานแล้ว" ได้ภายใน 5 นาที — endpoint เดียวกับที่ Dashboard/History
  /// ใช้ (undo-eaten) เพิ่มเข้ามาที่นี่ด้วยเพื่อให้สถานะ "sync" กัน ไม่ใช่ว่า
  /// หน้านี้ล็อกถาวรทันทีที่เลือกเมนู ทั้งที่ Dashboard/History ยังยกเลิกได้
  ///
  /// เดิมยกเลิกแค่ items.first ตัวเดียว ทั้งที่มื้อเดียวมีได้หลายเมนู — เมนูที่
  /// เหลือค้างเป็น "ทานแล้ว" ต่อไปเงียบๆ แล้วล็อกถาวรเมื่อเลย 5 นาทีของตัวเอง
  /// ทั้งที่ผู้ใช้กดยกเลิกทั้งมื้อไปแล้ว (ผู้ใช้รายงานจริง) วนยกเลิกทุกเมนูที่
  /// ยังอยู่ในช่วง 5 นาที ให้สมมาตรกับตอนกด "ทานแล้ว" ที่มาร์กครบทุกเมนู
  Future<void> _undoEaten(MealLog log) async {
    MealLog? latest;
    String? error;
    for (final item in log.items.where((i) => i.canUndoEaten)) {
      final result = await widget.mealLogService.undoItemEaten(item.id);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error!)));
    }
  }

  /// เดิมมื้อที่บันทึกเมนูไปแล้วแก้ไขไม่ได้อีกเลย ไม่มีทางลบ/เปลี่ยนเมนูที่
  /// เลือกผิด (บั๊กที่ผู้ใช้รายงานจริง) เปิด sheet ย่อยให้ลบเมนูที่ไม่ต้องการ
  /// ออก แล้วเลือกใหม่ต่อได้ (ผ่าน `DELETE /meal-log-items/<id>` ที่เพิ่มมาคู่กัน)
  Future<void> _manageExisting(MealLog log) async {
    final action = await showModalBottomSheet<_ManageMealAction>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ManageMealSheet(mealLogService: widget.mealLogService, log: log),
    );
    if (!mounted || action == null) return;
    setState(() {
      final idx = _logs.indexWhere((l) => l.id == action.log.id);
      if (idx != -1) _logs[idx] = action.log;
    });
    if (action.addMore) Navigator.of(context).pop(action.log);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('เลือกมื้ออาหาร', style: AppTextStyles.headingMedium.copyWith(color: AppColors.gray900)),
          const SizedBox(height: 4),
          Text(_dateLabel(), style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600)),
          const SizedBox(height: 16),
          if (_error != null) ...[
            Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.coral600)),
            const SizedBox(height: 12),
          ],
          for (final type in MealType.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MealOptionTile(
                type: type,
                existingLog: _existingLog(type),
                loading: _loadingType == type,
                onTap: () => _select(type),
                onUndoEaten: _undoEaten,
                onManage: (log) => _manageExisting(log),
              ),
            ),
        ],
      ),
    );
  }
}

class _MealOptionTile extends StatelessWidget {
  final MealType type;
  final MealLog? existingLog;
  final bool loading;
  final VoidCallback onTap;
  final ValueChanged<MealLog> onUndoEaten;
  final ValueChanged<MealLog> onManage;

  const _MealOptionTile({
    required this.type,
    required this.existingLog,
    required this.loading,
    required this.onTap,
    required this.onUndoEaten,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final window = kMealTimeWindows[type]!;
    final timeLabel = '${window.$1.toString().padLeft(2, '0')}:00-${window.$2.toString().padLeft(2, '0')}:00';
    final isLogged = existingLog != null;
    // เลือกเมนูของมื้อนี้ไปแล้วเลือก "มื้อใหม่" ซ้ำไม่ได้ (409 ที่ backend
    // กันไว้จริง) แต่ยังต้องแก้ไข/ลบเมนูที่เลือกผิดได้ — เดิมล็อกทั้งแตะเลย
    // ไม่มีทางกลับไปหน้าเลือกเมนูอีกต่อไป (บั๊กที่ผู้ใช้รายงานจริง) ตอนนี้
    // isLogged เปิดให้แตะเพื่อ "จัดการเมนู" แทนที่จะล็อกเฉยๆ — ไม่ล็อกตามช่วง
    // เวลาอีกต่อไป (ผู้ใช้ยืนยันชัดเจน: กรอกมื้อไหนเวลาไหนก็ได้เต็มที่)
    final isLocked = isLogged;

    // ทานแล้วหรือยัง + ยกเลิกได้ไหม (มื้อนี้ยังไม่ปิดสนิท) — เดิมเช็ค
    // items.any(canUndoEaten) (เวลาของเมนูใดเมนูหนึ่งเอง) เปลี่ยนเป็นเช็ค
    // ทั้งมื้อ (isSealed) ให้สอดคล้องกับ Dashboard/History (ผู้ใช้รายงานจริง)
    final items = existingLog?.items ?? const [];
    final allEaten = items.isNotEmpty && items.every((i) => i.isEaten);
    final canUndo = allEaten && !(existingLog?.isSealed ?? false);

    return Material(
        color: isLogged ? AppColors.teal50 : AppColors.gray50,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: loading
              ? null
              : isLogged
                  ? () => onManage(existingLog!)
                  : (isLocked ? null : onTap),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(type.labelTh, style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900)),
                      const SizedBox(height: 2),
                      Text(timeLabel, style: AppTextStyles.caption),
                    ],
                  ),
                ),
                if (loading)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else if (isLogged) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        allEaten ? Icons.check_circle : Icons.check_circle_outline,
                        color: AppColors.teal500,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(allEaten ? 'ทานแล้ว' : 'บันทึกแล้ว',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.teal700)),
                    ],
                  ),
                  if (canUndo) ...[
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () => onUndoEaten(existingLog!),
                      style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: Text('ยกเลิก', style: AppTextStyles.caption.copyWith(color: AppColors.coral600)),
                    ),
                  ],
                  // ไอคอนดินสอ = ยังแก้ไขเมนูของมื้อนี้ได้อยู่ — เดิมโชว์ค้าง
                  // เสมอไม่ว่าจะล็อกไปแล้วหรือยัง (ผู้ใช้รายงานจริง: เกิน 5
                  // นาทีระบบล็อกถูกต้องแล้ว แต่ไอคอนดินสอยังค้างอยู่เหมือนแก้
                  // ได้) ผูกกับ isSealed ตัวเดียวกับที่คุม "เพิ่มเมนูใหม่ได้
                  // ไหม" อยู่แล้ว — ยังไม่ครบ 5 นาทีจากที่กดทานแล้วครั้งแรก
                  // (หรือยังไม่เคยกดทานแล้วเลย) ถึงจะโชว์
                  if (!(existingLog?.isSealed ?? false)) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_outlined, color: AppColors.gray400, size: 18),
                  ],
                ]
                else
                  const Icon(Icons.chevron_right, color: AppColors.gray400),
              ],
            ),
          ),
        ),
      );
  }
}

/// ผลลัพธ์จาก [_ManageMealSheet] — [log] คือ MealLog ล่าสุดหลังลบ (ถ้ามี),
/// [addMore] บอกว่าผู้ใช้กด "+ เลือกเมนูเพิ่ม" ต้องเปิด FoodBrowserPage ต่อ
class _ManageMealAction {
  final MealLog log;
  final bool addMore;
  const _ManageMealAction({required this.log, required this.addMore});
}

/// จัดการเมนูของมื้อที่บันทึกไปแล้ว — ลบรายการที่เลือกผิด/ไม่ต้องการออกได้
/// (ผ่าน `DELETE /meal-log-items/<id>`) แล้วเลือกเมนูใหม่เพิ่มได้ต่อ — เดิม
/// มื้อที่มีเมนูแล้วแก้ไขไม่ได้อีกเลย (บั๊กที่ผู้ใช้รายงานจริง)
class _ManageMealSheet extends StatefulWidget {
  final MealLogService mealLogService;
  final MealLog log;
  const _ManageMealSheet({required this.mealLogService, required this.log});

  @override
  State<_ManageMealSheet> createState() => _ManageMealSheetState();
}

class _ManageMealSheetState extends State<_ManageMealSheet> {
  late MealLog _log = widget.log;
  int? _deletingId;

  Future<void> _delete(MealLogItem item) async {
    setState(() => _deletingId = item.id);
    final result = await widget.mealLogService.deleteItem(item.id);
    if (!mounted) return;
    result.when(
      ok: (updated) => setState(() {
        _log = updated;
        _deletingId = null;
      }),
      err: (error) {
        setState(() => _deletingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toUserMessage())),
        );
      },
    );
  }

  // มื้อนี้ "ปิด" แล้วหรือยัง — ดู MealLog.isSealed (ยึดเวลาทานแล้วครั้งแรกสุด
  // ของมื้อนี้ ไม่ใช่ล่าสุด กันเพิ่มเมนูใหม่มาร์กทานแล้วเรื่อยๆ แล้วนาฬิกา
  // รีเซ็ตใหม่ทุกครั้ง เลื่อนวันปิดมื้อไม่มีที่สิ้นสุด — ผู้ใช้รายงานจริง)
  bool get _mealLocked => _log.isSealed;

  @override
  Widget build(BuildContext context) {
    final mealLocked = _mealLocked;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('จัดการมื้อ${_log.mealType.labelTh}', style: AppTextStyles.headingMedium.copyWith(color: AppColors.gray900)),
          const SizedBox(height: 16),
          if (_log.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('ยังไม่มีเมนูในมื้อนี้', style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600)),
            )
          else
            ..._log.items.map((item) {
              // รายการที่ยังไม่กดทานแล้ว หรือกดแล้วแต่มื้อนี้ยังไม่ปิดสนิท ยัง
              // แก้ได้ปกติ — เดิมเช็คแค่ item.canUndoEaten (เวลาของเมนูนี้เอง)
              // เมนูที่เพิ่งทานสดๆ จะยังโชว์ลบได้ทั้งที่มื้อปิดสนิทไปแล้วจาก
              // เมนูอื่น (ผู้ใช้รายงานจริง) ต้องเช็คทั้งมื้อ (_log.isSealed)
              final canEditItem = !item.isEaten || !_log.isSealed;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.foodItemName ?? 'เมนู #${item.foodItemId}'} '
                        '(${(item.caloriesActual ?? 0).toStringAsFixed(0)} kcal)',
                        style: AppTextStyles.bodyMedium,
                      ),
                    ),
                    if (_deletingId == item.id)
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    else if (canEditItem)
                      IconButton(
                        onPressed: () => _delete(item),
                        icon: const Icon(Icons.delete_outline, color: AppColors.coral600),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(Icons.lock_outline, color: AppColors.gray400, size: 20),
                      ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 12),
          if (!mealLocked)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(_ManageMealAction(log: _log, addMore: true)),
                child: const Text('+ เลือกเมนูเพิ่ม'),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(_ManageMealAction(log: _log, addMore: false)),
              child: const Text('เสร็จสิ้น'),
            ),
          ),
        ],
      ),
    );
  }
}

/// เปิด [MealSelectSheet] แบบ modal bottom sheet — คืน [MealLog] ที่เลือก/
/// สร้างแล้ว หรือ null ถ้าผู้ใช้ปิดโดยไม่ได้เลือก
Future<MealLog?> showMealSelectSheet(
  BuildContext context, {
  required MealLogService mealLogService,
  required List<MealLog> todayLogs,
  DateTime? date,
}) {
  return showModalBottomSheet<MealLog>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => MealSelectSheet(mealLogService: mealLogService, todayLogs: todayLogs, date: date),
  );
}

/// เปิด [_ManageMealSheet] ตรงๆ โดยไม่ต้องผ่าน [MealSelectSheet] ก่อน — เดิม
/// เข้าถึงได้ทางเดียวคือกดปุ่ม "+ บันทึก" แล้วแตะมื้อที่บันทึกแล้วในชีทเลือก
/// มื้อ ทำให้ Dashboard ("มื้อวันนี้") ที่โชว์แค่ "เมนูแรก และอีก N รายการ"
/// ไม่มีทางแตะดูรายการที่เหลือได้เลย (ผู้ใช้รายงานจริง) ใช้ตัวนี้ให้แถวมื้อ
/// บน Dashboard แตะเปิดดู/จัดการได้ตรงๆ เหมือนกันเป๊ะ — กด "+ เลือกเมนูเพิ่ม"
/// ในชีทก็เปิด [FoodBrowserPage] ต่อให้เอง (ปกติ [MealSelectSheet] เป็นคน
/// เปิดให้ ที่นี่ไม่มี MealSelectSheet ห่ออยู่เลยต้องทำเอง)
Future<void> showManageMealSheet(
  BuildContext context, {
  required MealLogService mealLogService,
  required FoodItemService foodItemService,
  required MealLog log,
}) async {
  final action = await showModalBottomSheet<_ManageMealAction>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ManageMealSheet(mealLogService: mealLogService, log: log),
  );
  if (action == null || !action.addMore || !context.mounted) return;
  // เดิมเปิด FoodBrowserPage ตรงนี้ทันทีโดยไม่เช็คข้อมูลโปรไฟล์เลย ต่างจาก
  // startMealLogFlow() ที่เช็คก่อนเสมอ — ทางเข้านี้ (แตะมื้อที่มีเมนูอยู่แล้ว
  // บน Dashboard -> "+ เลือกเมนูเพิ่ม") เลยเลือกอาหารเพิ่มได้ทั้งที่ข้อมูล
  // ส่วนตัว/เป้าหมายสุขภาพยังไม่ครบ (ผู้ใช้รายงานจริง) ใช้เงื่อนไขเดียวกัน
  if (!hasCompleteProfileAndGoal()) {
    await showIncompleteProfileDialog(context);
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FoodBrowserPage(
        mealLog: action.log,
        foodItemService: foodItemService,
        mealLogService: mealLogService,
      ),
    ),
  );
}
