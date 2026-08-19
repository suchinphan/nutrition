import 'package:flutter/material.dart';
import '../app_categories.dart';
import '../theme/app_theme.dart';

/// รายการหมวดหมู่ทั้งหมด — ปลายทางของปุ่ม "เมนู" ใน bottom nav
/// (แทนที่ modal bottom sheet เดิม ด้วยหน้าเต็มที่ผลักผ่าน root navigator
/// เสมอ กันปัญหา overlay ถูกซ่อนเวลาเปิดจาก tab อื่นที่ไม่ใช่ "หน้าหลัก")
class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = buildAppCategories();
    return Scaffold(
      appBar: AppBar(title: const Text('หมวดหมู่ทั้งหมด')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpace.md),
          itemCount: categories.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
          itemBuilder: (context, i) {
            final c = categories[i];
            return AppTile(
              icon: c['icon'] as IconData,
              title: c['label'] as String,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => c['page'] as Widget)),
            );
          },
        ),
      ),
    );
  }
}
