import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// การ์ดพื้นขาวขอบบาง (ตรงกับ .card ใน styles.css) พร้อมหัวข้อทางเลือก
///
/// app_theme.dart มี HeroCard (พื้นเขียวเข้ม) และ StatCard (label/value/unit)
/// อยู่แล้ว แต่ยังไม่มี widget กลางสำหรับ "การ์ดขาว + หัวข้อ + เนื้อหาอิสระ"
/// (เช่น กราฟ, รายการ) จึงเพิ่มตัวนี้ กันไม่ให้แต่ละหน้าคัดลอก
/// BoxDecoration(color: AppColors.card, border, borderRadius) ซ้ำกันเอง
class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  const SectionCard({super.key, this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: AppRadius.rMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpace.sm),
          ],
          child,
        ],
      ),
    );
  }
}
