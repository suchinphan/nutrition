import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// หน้า placeholder สำหรับ route ที่ยังไม่มี widget จริง (ดู app_router.dart)
/// แสดงแค่ AppBar + ข้อความ "กำลังพัฒนา" ตามที่กำหนด
class ComingSoonPage extends StatelessWidget {
  final String routeName;
  const ComingSoonPage({super.key, required this.routeName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(routeName)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.construction,
                size: 56,
                color: AppColors.inkSoft,
              ),
              const SizedBox(height: AppSpace.md),
              Text('กำลังพัฒนา', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpace.xs),
              Text(
                'หน้านี้ ($routeName) ยังไม่พร้อมใช้งาน',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
