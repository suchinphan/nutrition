import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/widgets.dart';
import '../models/food_item.dart';
import '../models/meal_log.dart';
import '../services/data_events.dart';
import '../services/favorite_service.dart';
import '../services/food_item_service.dart';
import '../services/meal_log_service.dart';
import 'serving_picker_sheet.dart';

// อาหาร/เครื่องดื่ม/ของหวาน built-in มีป้ายกำกับภาษาไทยตายตัว หัวข้อที่
// แอดมินเพิ่มเองใช้ชื่อที่พิมพ์ไว้ตรงๆ เป็นป้ายกำกับ (ดู _loadFoodTypes)
const _builtinTypeLabels = {'food': 'อาหาร', 'drink': 'เครื่องดื่ม', 'dessert': 'ของหวาน'};

const _defaultTypeFilters = [
  (label: 'ทั้งหมด', value: null),
  (label: 'อาหาร', value: 'food'),
  (label: 'เครื่องดื่ม', value: 'drink'),
  (label: 'ของหวาน', value: 'dessert'),
];

/// Step 2 — ค้นหา/เลือกเมนูสำหรับมื้อที่กำลังบันทึก (มาจาก [MealSelectSheet])
class FoodBrowserPage extends StatefulWidget {
  final MealLog mealLog;
  final FoodItemService foodItemService;
  final MealLogService mealLogService;

  const FoodBrowserPage({
    super.key,
    required this.mealLog,
    required this.foodItemService,
    required this.mealLogService,
  });

  @override
  State<FoodBrowserPage> createState() => _FoodBrowserPageState();
}

class _FoodBrowserPageState extends State<FoodBrowserPage> {
  late MealLog _log;
  String? _typeFilter;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  final FavoriteService _favoriteService = createFavoriteService();

  bool _loading = true;
  String? _error;
  List<FoodItem> _items = [];
  // สลับ filter ถี่ๆ ยิง _load() ซ้อนกันได้ (เช่นแตะ "อาหาร" แล้วรีบแตะ
  // "ของหวาน" ก่อนคำขอแรกตอบกลับ) — ถ้า response เก่ามาถึงทีหลัง response
  // ใหม่ (เครือข่ายมาไม่เรียงลำดับ) ต้องทิ้งของเก่า ไม่งั้น setState ทับ
  // _items ที่ถูกต้องด้วยข้อมูลของ filter ที่ไม่ได้เลือกอยู่แล้ว
  int _loadGeneration = 0;

  // ตะกร้า — เลือกได้หลายเมนูก่อนกด "ยืนยัน" รวดเดียว (ไม่ยิง backend ทีละ
  // เมนูเหมือนเดิมที่ล็อกไว้แค่ 1 รายการ/มื้อ)
  final List<ServingChoice> _selections = [];
  bool _confirming = false;

  double get _totalCalories => _selections.fold(0.0, (sum, c) => sum + c.calories);

  // แถว "รายการโปรด"/"ล่าสุด" บนสุด — โหลดแยกจากรายการหลัก ไม่ใช้ _loading/
  // _error ร่วมกัน (พังจุดเดียวไม่ทำให้ทั้งหน้าใช้งานไม่ได้)
  List<FoodItem> _favorites = [];
  List<FoodItem> _recentItems = [];
  List<FoodItem> _popularItems = [];
  Set<int> _favoriteIds = {};

  // ผู้ใช้รายงานจริง: แอดมินเพิ่มหัวข้อใหม่ (เช่น "ผลไม้") ในหน้าแอดมินแล้ว
  // แต่แท็บนี้ hardcode ไว้แค่ 3 ค่า ฝั่งผู้ใช้เลยไม่เห็นเลย — ดึงจาก
  // GET /api/food-types แทน เก็บ 3 หัวข้อ built-in ไว้เป็นค่าเริ่มต้นกัน
  // แท็บว่างตอนเปิดหน้าครั้งแรก/เน็ตช้า พอโหลดเสร็จค่อยแทนที่ด้วยของจริง
  var _typeFilters = _defaultTypeFilters;

  @override
  void initState() {
    super.initState();
    _log = widget.mealLog;
    _load();
    unawaited(_loadFavorites());
    unawaited(_loadRecentItems());
    unawaited(_loadPopularItems());
    unawaited(_loadFoodTypes());
  }

  Future<void> _loadFoodTypes() async {
    final result = await widget.foodItemService.fetchFoodTypes();
    if (!mounted) return;
    result.when(
      ok: (types) => setState(() {
        _typeFilters = [
          (label: 'ทั้งหมด', value: null),
          for (final t in types) (label: _builtinTypeLabels[t] ?? t, value: t),
        ];
      }),
      err: (_) {},
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final myGeneration = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.foodItemService.fetchFoodItems(
      type: _typeFilter,
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
    );
    if (!mounted || myGeneration != _loadGeneration) return;
    result.when(
      ok: (items) => setState(() {
        _items = items;
        _loading = false;
      }),
      err: (error) => setState(() {
        _loading = false;
        _error = error.toUserMessage();
      }),
    );
  }

  Future<void> _loadFavorites() async {
    final result = await _favoriteService.fetchFavorites();
    if (!mounted) return;
    result.when(
      ok: (items) => setState(() {
        _favorites = items;
        _favoriteIds = items.map((i) => i.id).toSet();
      }),
      // เงียบไว้ — แถวนี้เป็นของเสริม ถ้าโหลดพลาดแค่ไม่โชว์แถว ไม่ต้องบล็อก
      // การเลือกเมนูหลักที่ต้องทำงานได้เสมอ
      err: (_) {},
    );
  }

  Future<void> _loadRecentItems() async {
    final result = await widget.mealLogService.fetchRecentItems(limit: 5);
    if (!mounted) return;
    result.when(
      ok: (items) => setState(() => _recentItems = items),
      err: (_) {},
    );
  }

  /// นับสะสมตลอดกาลจากผู้ใช้ทุกคน — ต้องโหลดใหม่ทุกครั้งที่สลับแท็บ
  /// (อาหาร/เครื่องดื่ม/ของหวาน) เพราะยอดนิยมของแต่ละประเภทไม่เหมือนกัน
  Future<void> _loadPopularItems() async {
    final result = await widget.foodItemService.fetchPopularItems(type: _typeFilter, limit: 5);
    if (!mounted) return;
    result.when(
      ok: (items) => setState(() => _popularItems = items),
      err: (_) {},
    );
  }

  Future<void> _toggleFavorite(FoodItem item) async {
    final isFav = _favoriteIds.contains(item.id);
    // อัปเดต UI ทันที (optimistic) — ไม่ต้องรอ network ก่อนเห็นดาวเปลี่ยนสี
    setState(() {
      if (isFav) {
        _favoriteIds.remove(item.id);
        _favorites.removeWhere((i) => i.id == item.id);
      } else {
        _favoriteIds.add(item.id);
        _favorites = [item, ..._favorites];
      }
    });
    final result = isFav
        ? await _favoriteService.removeFavorite(item.id)
        : await _favoriteService.addFavorite(item.id);
    if (!mounted) return;
    result.when(
      ok: (_) {},
      err: (error) {
        // ยิงไม่สำเร็จ — revert กลับสถานะเดิม กันหน้าตาไม่ตรงกับ backend จริง
        setState(() {
          if (isFav) {
            _favoriteIds.add(item.id);
            _favorites = [item, ..._favorites];
          } else {
            _favoriteIds.remove(item.id);
            _favorites.removeWhere((i) => i.id == item.id);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toUserMessage())));
      },
    );
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _openServingPicker(FoodItem item) async {
    // ปิดคีย์บอร์ดก่อนเปิด modal เสมอ — ถ้าช่องค้นหายัง focus อยู่ตอนแตะเมนู
    // (พิมพ์ค้นหาแล้วแตะเลือกทันทีโดยไม่ปิดคีย์บอร์ดก่อน) คีย์บอร์ดที่กำลัง
    // จะปิดกับ sheet ที่กำลังจะเปิดจะแย่งกันปรับ viewInsets ในเฟรมเดียวกันบน
    // เครื่องจริง (เจอจริง — RenderBox ที่พังทุกครั้งมี _RenderInputPadding
    // ของ TextField ช่องค้นหาอยู่ในสายเสมอ) — widget test จำลอง race นี้
    // ไม่ได้เพราะ test binding จัดการ focus transition ตอน push route แบบ
    // synchronous ในเฟรมเดียว ไม่เหมือนคีย์บอร์ดจริงที่ animate หลายเฟรม
    FocusScope.of(context).unfocus();
    final choice = await showServingPickerSheet(context, item: item, mealLog: _log);
    if (!mounted || choice == null) return;
    setState(() => _selections.add(choice));
  }

  void _removeSelection(int index) {
    setState(() => _selections.removeAt(index));
  }

  /// ยิง `POST /meal-logs/<id>/items` ทีละรายการตามลำดับที่เลือกไว้ในตะกร้า —
  /// รายการที่พลาดจะยังค้างอยู่ในตะกร้าให้กดยืนยันใหม่ได้ ไม่ต้องเลือกซ้ำ
  /// ตั้งแต่ต้น ส่วนรายการที่สำเร็จแล้วก็ถูกบันทึกจริงไปแล้ว ไม่หายไปไหน
  ///
  /// [notify: false] ทุกครั้งใน loop — ปกติ addItem() ยิง
  /// MealLogEvents.changed() ทุกครั้งที่สำเร็จ ให้ Dashboard/History (ที่ค้าง
  /// อยู่ใน IndexedStack ตลอด) รีเฟรชสด แต่เลือกมาหลายเมนูรวดเดียวจะยิงรีเฟรช
  /// ซ้อนกันหลายรอบจนถล่ม dev server เอง (เจอจริง — ยืนยัน 5 เมนูรวด ทำให้
  /// request ค้าง/connection หลุด) เลย notify แค่ครั้งเดียวหลัง loop จบ
  Future<void> _confirm() async {
    setState(() => _confirming = true);
    final remaining = <ServingChoice>[];
    String? error;
    var anySucceeded = false;
    for (final choice in _selections) {
      final result = await widget.mealLogService.addItem(
        logId: _log.id,
        foodItemId: choice.item.id,
        servingSizeId: choice.servingSize?.id,
        quantity: choice.quantity,
        notify: false,
      );
      result.when(
        ok: (log) {
          _log = log;
          anySucceeded = true;
        },
        err: (e) {
          error = e.toUserMessage();
          remaining.add(choice);
        },
      );
    }
    if (anySucceeded) MealLogEvents.instance.changed();
    if (!mounted) return;
    setState(() {
      _selections
        ..clear()
        ..addAll(remaining);
      _confirming = false;
    });
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error!)));
      return;
    }
    Navigator.of(context).pop(_log);
  }

  void _showSwapInfo(FoodItem item) {
    final swapId = item.swapFoodId;
    if (swapId == null) return;
    final swapItem = _items.where((i) => i.id == swapId).firstOrNull;
    FocusScope.of(context).unfocus();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('เมนูทดแทนแนะนำ'),
        content: Text(
          swapItem != null
              ? '${swapItem.displayName} (${swapItem.calories?.toStringAsFixed(0) ?? '-'} kcal)'
                '${item.upgradeTips != null && item.upgradeTips!.isNotEmpty ? '\n\n${item.upgradeTips}' : ''}'
              : item.upgradeTips ?? 'ไม่พบรายละเอียดเมนูทดแทนในหมวดนี้',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ปิด')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('บันทึกมื้อ${_log.mealType.labelTh}')),
      // เดิม search+chips+quick-access เป็น Column แข็งอยู่นอก Expanded ก่อน
      // _buildBody() — พอ bottomNavigationBar (แถบตะกร้า) สูงขึ้นจากการเพิ่ม
      // แถว "บันทึกไปแล้ว" ก่อนหน้านี้ พื้นที่ body ที่เหลือแคบลง หน้าจอเตี้ยๆ
      // เลย overflow (เจอจริง — RenderFlex overflow 6px) รวมทุกอย่างเป็น
      // scrollable เดียว (CustomScrollView) แทน ไม่มีทาง overflow อีกไม่ว่า
      // จอจะเตี้ยแค่ไหน เพราะทุกส่วนเลื่อนไปด้วยกันได้หมด
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'ค้นหาเมนู...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                _load();
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _typeFilters
                          .map(
                            (f) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(f.label),
                                selected: _typeFilter == f.value,
                                onSelected: (_) {
                                  setState(() => _typeFilter = f.value);
                                  _load();
                                  unawaited(_loadPopularItems());
                                },
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildQuickAccessRows()),
          const SliverToBoxAdapter(child: Divider(height: 1)),
          ..._buildBodySlivers(),
        ],
      ),
      bottomNavigationBar: SafeArea(child: _buildSelectionBar()),
    );
  }

  /// ลบเมนูที่บันทึกไปแล้วของมื้อนี้ (ตัวเดียวกับที่ _ManageMealSheet ใช้) —
  /// เรียกตรงจากชิปในแถบล่างสุดของหน้านี้เลย ไม่ต้องเปิดชีท "จัดการมื้อ" แยก
  Future<void> _deleteLoggedItem(MealLogItem item) async {
    final result = await widget.mealLogService.deleteItem(item.id);
    if (!mounted) return;
    result.when(
      ok: (updated) => setState(() => _log = updated),
      err: (error) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toUserMessage())),
      ),
    );
  }

  /// แถบล่างสุด — เดิมโชว์เฉพาะตะกร้าเมนูใหม่ที่ยังไม่ยืนยัน (_selections)
  /// ซ่อนไปเลยถ้ายังไม่เลือกอะไรใหม่ ทำให้เมนูที่บันทึก/ยืนยันไปแล้วของมื้อนี้
  /// (_log.items — ยังแก้ไข/ลบได้อยู่ภายใน 5 นาทีตามกฎ undo-eaten เดียวกับ
  /// Dashboard) ไม่มีทางเห็นเลยจนกว่าจะเลือกเมนูใหม่อีกอันก่อน (ผู้ใช้รายงาน
  /// จริง) ตอนนี้โชว์รายการที่บันทึกไปแล้วเป็นแถวแยกด้านบนเสมอ ไม่ต้องรอ
  /// เลือกอะไรใหม่ก่อน — ลบได้ถ้ายังอยู่ในช่วงแก้ไข (🗑️) ล็อกถ้าเลยแล้ว (🔒)
  Widget _buildSelectionBar() {
    if (_selections.isEmpty && _log.items.isEmpty) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_log.items.isNotEmpty) ...[
            Text('บันทึกไปแล้ว', style: AppTextStyles.caption.copyWith(color: AppColors.gray600)),
            const SizedBox(height: 4),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _log.items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final item = _log.items[i];
                  // เดิมเช็คแค่ item.canUndoEaten (เวลาของเมนูนี้เอง) — เมนูที่
                  // เพิ่งทานสดๆ ยังโชว์ลบได้ทั้งที่มื้อปิดสนิทไปแล้วจากเมนูอื่น
                  // (ผู้ใช้รายงานจริง) ต้องเช็คทั้งมื้อ (_log.isSealed) ด้วย
                  final canEdit = !item.isEaten || !_log.isSealed;
                  return Chip(
                    key: ValueKey('logged-${item.id}'),
                    avatar: canEdit ? null : const Icon(Icons.lock_outline, size: 14),
                    label: Text(
                      '${item.foodItemName ?? "เมนู #${item.foodItemId}"} '
                      '(${(item.caloriesActual ?? 0).toStringAsFixed(0)} kcal)',
                      style: AppTextStyles.caption,
                    ),
                    onDeleted: canEdit ? () => _deleteLoggedItem(item) : null,
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_selections.isNotEmpty) ...[
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _selections.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final choice = _selections[i];
                  return Chip(
                    key: ObjectKey(choice),
                    label: Text(
                      '${choice.item.displayName} (${choice.calories.toStringAsFixed(0)} kcal)',
                      style: AppTextStyles.caption,
                    ),
                    onDeleted: () => _removeSelection(i),
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
                    'รวม ${_totalCalories.toStringAsFixed(0)} kcal (${_selections.length} รายการ)',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray900, fontWeight: FontWeight.w600),
                  ),
                ),
                ElevatedButton(
                  onPressed: _confirming ? null : _confirm,
                  // ธีมกลางของแอป (core/theme/app_theme.dart) ตั้ง minimumSize
                  // เป็น Size.fromHeight(48) = กว้างเท่า Infinity ไว้ให้ปุ่มเต็ม
                  // ความกว้างเป็นค่าเริ่มต้นทั้งแอป (ปุ่มอื่นๆ ส่วนใหญ่อยู่เดี่ยวๆ
                  // เต็มแถวจริง) แต่ปุ่มนี้อยู่ใน Row ข้าง Expanded — รับ
                  // minWidth: infinity ไม่ได้ ต้อง override ให้กว้างจำกัดเอง
                  // (เจอจริง — "BoxConstraints forces an infinite width" ชี้ตรง
                  // มาที่ปุ่มนี้ก่อนจะแก้)
                  style: ElevatedButton.styleFrom(minimumSize: const Size(88, 40)),
                  child: _confirming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('ยืนยัน'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// แถว "รายการโปรด"/"ล่าสุด" บนสุด — ซ่อนไปเลยถ้าว่างทั้งคู่ (user ใหม่ยัง
  /// ไม่เคยบันทึกอะไรเลย) กันดูรกเกินไปสำหรับ section ย่อย
  Widget _buildQuickAccessRows() {
    if (_favorites.isEmpty && _recentItems.isEmpty && _popularItems.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_favorites.isNotEmpty) _buildQuickAccessRow('รายการโปรด', _favorites),
          if (_recentItems.isNotEmpty) _buildQuickAccessRow('ล่าสุด', _recentItems),
          if (_popularItems.isNotEmpty) _buildQuickAccessRow('เมนูยอดนิยม', _popularItems),
        ],
      ),
    );
  }

  Widget _buildQuickAccessRow(String title, List<FoodItem> items) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(title, style: AppTextStyles.labelBold.copyWith(color: AppColors.gray900)),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 96,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                return Padding(
                  key: ValueKey(item.id),
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 240,
                    // แตะแล้วไปหน้าเลือกขนาด/ยืนยันทันที ข้าม step ค้นหา —
                    // ใช้ตัวเลือกขนาดเริ่มต้นของเมนูนั้น (เหมือนแตะจากลิสต์หลัก)
                    child: AppFoodCard(
                      imageUrl: item.imageUrl,
                      categoryType: item.categoryType,
                      name: item.displayName.isEmpty ? '-' : item.displayName,
                      calories: item.calories,
                      onTap: () => _openServingPicker(item),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// คืนเป็น sliver list (ใช้กับ CustomScrollView ใน build()) แทนการคืน
  /// ListView/Widget เดี่ยวๆ แบบเดิม — ให้เนื้อหาส่วนนี้เลื่อนรวมเป็นเนื้อ
  /// เดียวกับ header (search/chips/quick-access) ด้านบน กัน overflow ตอนจอเตี้ย
  List<Widget> _buildBodySlivers() {
    if (_loading) {
      return [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, _) => const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: AppSkeletonLoader(variant: AppSkeletonVariant.listItem),
              ),
              childCount: 5,
            ),
          ),
        ),
      ];
    }
    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: AppErrorBanner(message: _error!, onRetry: _load),
          ),
        ),
      ];
    }
    if (_items.isEmpty) {
      final keyword = _searchCtrl.text.trim();
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: AppEmptyState(
            icon: Icons.search_off,
            title: keyword.isEmpty ? 'ไม่พบเมนูในหมวดนี้' : "ไม่พบเมนู '$keyword'",
            ctaLabel: 'ล้างการค้นหา',
            onCta: () {
              _searchCtrl.clear();
              setState(() => _typeFilter = null);
              _load();
              unawaited(_loadPopularItems());
            },
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final item = _items[i];
              final hasWarning = item.allergyWarning;
              return Container(
                key: ValueKey(item.id),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: hasWarning
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.coral400, width: 1.5),
                      )
                    : null,
                child: Column(
                  children: [
                    AppFoodCard(
                      imageUrl: item.imageUrl,
                      categoryType: item.categoryType,
                      name: item.displayName.isEmpty ? '-' : item.displayName,
                      calories: item.calories,
                      allergenNames: [
                        ...item.allergens,
                        if (item.diseaseWarningReason != null) item.diseaseWarningReason!,
                      ],
                      trailing: const Icon(Icons.chevron_right, color: AppColors.gray400),
                      onTap: () => _openServingPicker(item),
                      isFavorite: _favoriteIds.contains(item.id),
                      onFavoriteToggle: () => _toggleFavorite(item),
                    ),
                    if (hasWarning && item.swapFoodId != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, right: 8),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => _showSwapInfo(item),
                            child: const Text('ดูเมนูทดแทน'),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
            childCount: _items.length,
          ),
        ),
      ),
    ];
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
