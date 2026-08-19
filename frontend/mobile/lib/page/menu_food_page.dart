import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
// removed import of main.dart to avoid circular import
import '../models/menu_item_detail.dart';
import '../services/api_loader.dart';
import '../services/auth_service.dart';

class MenuFoodPage extends StatefulWidget {
  const MenuFoodPage({super.key});

  @override
  State<MenuFoodPage> createState() => _MenuFoodPageState();
}

/// หมวดหมู่ที่เลือกได้ในหน้านี้ พร้อมไอคอนประจำหมวด
const Map<String, IconData> _categoryIcons = {
  'โปรตีน': Icons.egg_alt_outlined,
  'ผักและผลไม้': Icons.eco_outlined,
  'คาร์โบไฮเดรต': Icons.rice_bowl_outlined,
  'เครื่องดื่ม': Icons.local_cafe_outlined,
};

class _MenuFoodPageState extends State<MenuFoodPage> {
  final Color primaryGreen = AppColors.leaf;

  // รายการเมนูเต็มต่อหมวด โหลดจาก backend จริงผ่าน ApiLoader
  final Map<String, List<String>> _items = {
    for (final k in _categoryIcons.keys) k: <String>[],
  };
  bool _loading = true;

  String _selectedCategory = 'โปรตีน';
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadMenus();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> _flatten(Map<String, Set<String>>? m) {
    if (m == null) return [];
    final all = <String>{};
    for (final s in m.values) {
      all.addAll(s);
    }
    final list = all.toList()..sort();
    return list;
  }

  Future<void> _loadMenus() async {
    try {
      final protein = await ApiLoader.loadProteinMenus();
      final veg = await ApiLoader.loadVegetableMenus();
      final carb = await ApiLoader.loadCarbMenus();
      final healthy = await ApiLoader.loadHealthyDrinks();
      final weightloss = await ApiLoader.loadWeightLossDrinks();
      final energy = await ApiLoader.loadEnergyDrinks();

      if (!mounted) return;
      setState(() {
        _items['โปรตีน'] = _flatten(protein);
        _items['ผักและผลไม้'] = _flatten(veg);
        _items['คาร์โบไฮเดรต'] = _flatten(carb);
        _items['เครื่องดื่ม'] = {...healthy, ...weightloss, ...energy}.toList()
          ..sort();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openDetail(String name) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MenuDetailSheet(
        name: name,
        icon: _categoryIcons[_selectedCategory]!,
        primaryGreen: primaryGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allItems = _items[_selectedCategory] ?? [];
    final filtered = _query.isEmpty
        ? allItems
        : allItems
              .where((n) => n.toLowerCase().contains(_query))
              .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Icon(Icons.arrow_back, color: primaryGreen, size: 26),
                  ),
                  const Expanded(child: SizedBox()),
                  const Text(
                    'เมนูอาหาร',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                  Builder(
                    builder: (_) {
                      final auth = AuthService();
                      String idText = 'Guest';
                      if (auth.isLoggedIn && auth.user != null) {
                        final uname =
                            auth.user!['username'] ??
                            auth.user!['name'] ??
                            (auth.user!['id']?.toString() ?? '—');
                        idText = uname.toString();
                      }
                      return Text(idText, style: const TextStyle(color: Colors.black));
                    },
                  ),
                ],
              ),
            ),
            // หมวดหมู่ + ค้นหา
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(labelText: 'หมวดหมู่'),
                    items: _categoryIcons.keys
                        .map(
                          (k) => DropdownMenuItem(
                            value: k,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_categoryIcons[k], size: 18, color: primaryGreen),
                                const SizedBox(width: 8),
                                Text(k),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _selectedCategory = v;
                        _searchCtrl.clear();
                        _query = '';
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'ค้นหาเมนูใน $_selectedCategory...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setState(() {
                                _searchCtrl.clear();
                                _query = '';
                              }),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // รายการเมนู (เฉพาะหมวดที่เลือก + ผลค้นหา)
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? Center(
                      child: Text(
                        allItems.isEmpty
                            ? 'ไม่พบเมนูในหมวดนี้'
                            : 'ไม่พบเมนูที่ตรงกับ "$_query"',
                        style: const TextStyle(color: AppColors.inkSoft),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => _MenuItemCard(
                        icon: _categoryIcons[_selectedCategory]!,
                        name: filtered[i],
                        primaryGreen: primaryGreen,
                        onTap: () => _openDetail(filtered[i]),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.check, color: Colors.white, size: 20),
                  label: const Text(
                    'ตกลง',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      // bottomNavigationBar เดิมถูกลบออก — ซ้ำกับ NavigationBar ใหม่ใน
      // RootShell (main.dart) ที่เป็น bottom nav หลักของแอปแล้ว (ปุ่ม
      // ค้นหา/เมนู ของเดิมเป็น onPressed: () {} เปล่าๆ ไม่ทำอะไรอยู่แล้วด้วย)
    );
  }
}

/// การ์ดเมนู 1 รายการ — กดแล้วเปิดดูรายละเอียดเต็ม (ดู _MenuDetailSheet)
class _MenuItemCard extends StatelessWidget {
  final IconData icon;
  final String name;
  final Color primaryGreen;
  final VoidCallback onTap;

  const _MenuItemCard({
    required this.icon,
    required this.name,
    required this.primaryGreen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: primaryGreen, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.inkSoft, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// bottom sheet แสดงรายละเอียดเต็มของเมนู 1 ชิ้น — ดึงจาก
/// ApiLoader.loadMenuDetail (POST /menu-info จริง)
class _MenuDetailSheet extends StatefulWidget {
  final String name;
  final IconData icon;
  final Color primaryGreen;

  const _MenuDetailSheet({
    required this.name,
    required this.icon,
    required this.primaryGreen,
  });

  @override
  State<_MenuDetailSheet> createState() => _MenuDetailSheetState();
}

class _MenuDetailSheetState extends State<_MenuDetailSheet> {
  late final Future<MenuItemDetail?> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiLoader.loadMenuDetail(widget.name);
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
      child: FutureBuilder<MenuItemDetail?>(
        future: _future,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState != ConnectionState.done;
          final detail = snapshot.data;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: widget.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(widget.icon, color: widget.primaryGreen),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (detail == null)
                const Text(
                  'ไม่พบรายละเอียดเพิ่มเติมของเมนูนี้ในระบบ',
                  style: TextStyle(color: AppColors.inkSoft),
                )
              else ...[
                _detailRow('แคลอรี', '${detail.kcal} kcal'),
                if (detail.protein != null)
                  _detailRow('โปรตีน', '${detail.protein!.toStringAsFixed(1)} g'),
                if (detail.carbs != null)
                  _detailRow('คาร์โบไฮเดรต', '${detail.carbs!.toStringAsFixed(1)} g'),
                if (detail.fat != null)
                  _detailRow('ไขมัน', '${detail.fat!.toStringAsFixed(1)} g'),
                if (detail.sugar != null)
                  _detailRow('น้ำตาล', '${detail.sugar!.toStringAsFixed(1)} g'),
                if (detail.fiber != null)
                  _detailRow('ใยอาหาร', '${detail.fiber!.toStringAsFixed(1)} g'),
              ],
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
