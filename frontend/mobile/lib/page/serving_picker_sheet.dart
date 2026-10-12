import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/app_allergy_badge.dart';
import '../models/food_item.dart';
import '../models/meal_log.dart';

/// เมนู+ขนาด+จำนวนที่เลือกไว้ ยังไม่ยิง backend — แค่ค่าที่ FoodBrowserPage
/// เก็บสะสมไว้ในตะกร้าก่อนกด "ยืนยัน" รวดเดียว (ดู FoodBrowserPage._confirm)
class ServingChoice {
  final FoodItem item;
  final ServingSize? servingSize;
  final double quantity;
  const ServingChoice({required this.item, required this.servingSize, required this.quantity});

  double get calories => (item.calories ?? 0) * (servingSize?.caloriesMultiplier ?? 1.0) * quantity;
}

/// Step 3 — เลือกขนาดเสิร์ฟ + จำนวน แล้วคืนค่ากลับไปให้ FoodBrowserPage เก็บ
/// ลงตะกร้า (ไม่ยิง backend ตรงนี้แล้ว — เลือกได้หลายเมนูก่อนค่อยยืนยันทีเดียว)
class ServingPickerSheet extends StatefulWidget {
  final FoodItem item;
  final MealLog mealLog;

  const ServingPickerSheet({super.key, required this.item, required this.mealLog});

  @override
  State<ServingPickerSheet> createState() => _ServingPickerSheetState();
}

class _ServingPickerSheetState extends State<ServingPickerSheet> {
  ServingSize? _selectedSize;
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    _selectedSize = widget.item.defaultServingSize;
  }

  double get _totalCalories =>
      (widget.item.calories ?? 0) * (_selectedSize?.caloriesMultiplier ?? 1.0) * _quantity;

  // kcal ของขนาดที่เลือก 1 หน่วย (ไม่คูณจำนวน) — ใช้อธิบายในกล่อง "รายละเอียด"
  double get _selectedSizeCalories =>
      (widget.item.calories ?? 0) * (_selectedSize?.caloriesMultiplier ?? 1.0);

  String get _selectedSizeLabel =>
      (_selectedSize?.unitNameTh.isNotEmpty ?? false) ? _selectedSize!.unitNameTh : 'ขนาดนี้';

  void _adjustQuantity(int delta) {
    setState(() {
      _quantity = (_quantity + delta).clamp(1, 5);
    });
  }

  void _add() {
    Navigator.of(context).pop(
      ServingChoice(item: widget.item, servingSize: _selectedSize, quantity: _quantity.toDouble()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
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
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: (item.imageUrl.isNotEmpty)
                    ? Image.network(
                        item.imageUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _emojiBox(item.categoryType),
                      )
                    : _emojiBox(item.categoryType),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.displayName.isEmpty ? '-' : item.displayName,
                  style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900),
                ),
              ),
            ],
          ),
          // เดิมจุดนี้ (ขั้นตอนยืนยันเพิ่มเมนูจริงก่อนบันทึก) ไม่มีการเตือน
          // แพ้อาหารเลย ทั้งที่ FoodBrowserPage's list มี item.allergyWarning
          // อยู่แล้ว (บั๊กที่เจอจริง — BUG-002 กรณี b) เพิ่ม badge เดียวกับ
          // ที่ AppFoodCard ใช้ แสดงเฉพาะตอนเมนูนี้ตรงกับที่ผู้ใช้แพ้จริง
          // (allergyWarning) ไม่ใช่แค่มี allergen อะไรก็แสดง
          if (item.allergyWarning) ...[
            const SizedBox(height: 12),
            AppAllergyBadge(allergenNames: [
              ...item.allergens,
              if (item.diseaseWarningReason != null) item.diseaseWarningReason!,
            ]),
          ],
          const SizedBox(height: 20),
          if (item.servingSizes.isNotEmpty) ...[
            Text('ขนาด', style: AppTextStyles.labelBold.copyWith(color: AppColors.gray900)),
            const SizedBox(height: 8),
            Row(
              children: item.servingSizes.map((s) {
                final selected = _selectedSize?.id == s.id;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.unitNameTh.isEmpty ? '-' : s.unitNameTh),
                      selected: selected,
                      onSelected: (_) => setState(() => _selectedSize = s),
                    ),
                  ),
                );
              }).toList(),
            ),
            // ผู้ใช้ขอ: ตัดส่วนเทียบเกณฑ์จาน/เส้นผ่านศูนย์กลาง/จำนวนคนกิน/
            // ประเภทเมนูออก (เอาไปทดลองแล้วไม่เข้ากับทุกเมนู เช่นเครื่องดื่ม
            // "แก้วกลาง" ไปเทียบเป็นมาตรฐาน "จาน" มันแปลก) เหลือแค่กรัม+kcal
            // จริงของเมนูนั้นพอ
            if (_selectedSize?.gramsApprox != null) ...[
              const SizedBox(height: 14),
              Text('รายละเอียด', style: AppTextStyles.labelBold.copyWith(color: AppColors.gray900)),
              const SizedBox(height: 6),
              Text(
                item.categoryType == 'drink'
                    ? '$_selectedSizeLabel ปริมาณเครื่องดื่ม ประมาณ ${_selectedSize!.gramsApprox!.toStringAsFixed(0)} มิลลิลิตร '
                        'ให้พลังงานประมาณ ${_selectedSizeCalories.toStringAsFixed(0)} kcal'
                    : '$_selectedSizeLabel มีปริมาณอาหาร ประมาณ ${_selectedSize!.gramsApprox!.toStringAsFixed(0)} กรัม '
                        'ให้พลังงานประมาณ ${_selectedSizeCalories.toStringAsFixed(0)} kcal',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600, height: 1.4),
              ),
            ],
            const SizedBox(height: 20),
          ],
          Text('จำนวน', style: AppTextStyles.labelBold.copyWith(color: AppColors.gray900)),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _quantity > 1 ? () => _adjustQuantity(-1) : null,
              ),
              Text(_quantity.toString(), style: AppTextStyles.headingSmall),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _quantity < 5 ? () => _adjustQuantity(1) : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.amber50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'รวม ${_totalCalories.toStringAsFixed(0)} kcal',
              style: AppTextStyles.headingSmall.copyWith(color: AppColors.amber500),
            ),
          ),
          const SizedBox(height: 16),
          // เดิมแค่โชว์ badge เตือนเฉยๆ แต่ปุ่มกดเพิ่มยังกดได้ปกติ (ตั้งใจไว้
          // แบบนั้นตอนแรก — ดู comment ที่ backend api.py's _serialize_food_item
          // "200 พร้อม flag เตือน ไม่ใช่ error") ผู้ใช้ขอเปลี่ยนเป็นบล็อกจริง
          // สำหรับเมนูที่ตรงกับสิ่งที่แพ้ ปิดปุ่มไปเลยไม่ให้กดเพิ่มได้
          if (item.allergyWarning)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'ไม่สามารถเพิ่มเมนูนี้ได้ — มีส่วนผสมที่คุณแพ้/ต้องเลี่ยง',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.coral600),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: item.allergyWarning ? null : _add,
              child: Text('เพิ่มลงมื้อ${widget.mealLog.mealType.labelTh}'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emojiBox(String categoryType) {
    final emoji = switch (categoryType) {
      'drink' => '🥤',
      'dessert' => '🍰',
      _ => '🍽️',
    };
    return Container(
      width: 56,
      height: 56,
      color: AppColors.teal50,
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 24)),
    );
  }
}

/// เปิด [ServingPickerSheet] แบบ modal bottom sheet — คืน [ServingChoice] ที่
/// เลือกไว้ (ยังไม่บันทึกลง backend) หรือ null ถ้าผู้ใช้ปิดโดยไม่ได้เลือก
Future<ServingChoice?> showServingPickerSheet(
  BuildContext context, {
  required FoodItem item,
  required MealLog mealLog,
}) {
  return showModalBottomSheet<ServingChoice>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ServingPickerSheet(item: item, mealLog: mealLog),
  );
}
