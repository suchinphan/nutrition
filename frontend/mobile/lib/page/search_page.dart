import 'package:flutter/material.dart';
import '../app_categories.dart';
import '../theme/app_theme.dart';

/// หน้าค้นหาแยกต่างหาก — ปลายทางของปุ่ม "ค้นหา" ใน bottom nav
/// (ค้นหาแบบพิมพ์ในกล่องค้นหาบน grid หน้าแรกยังใช้งานได้ตามเดิม แยกจากกัน
/// หน้านี้ไม่ผูกกับ tab persistence — เป็นแค่หน้าที่ผลักผ่าน root navigator)
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  late final List<Map<String, dynamic>> _all;
  late List<Map<String, dynamic>> _filtered;

  @override
  void initState() {
    super.initState();
    _all = buildAppCategories();
    _filtered = _all;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all
                .where((c) => (c['label'] as String).toLowerCase().contains(q))
                .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'ค้นหาหมวดหมู่...',
            border: InputBorder.none,
          ),
        ),
      ),
      body: SafeArea(
        child: _filtered.isEmpty
            ? Center(
                child: Text(
                  'ไม่พบผลการค้นหา',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpace.md),
                itemCount: _filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
                itemBuilder: (context, i) {
                  final c = _filtered[i];
                  return AppTile(
                    icon: c['icon'] as IconData,
                    title: c['label'] as String,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => c['page'] as Widget),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
