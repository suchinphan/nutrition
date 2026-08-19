import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// เลือกได้หลายอันจาก [options] ด้วย FilterChip — มีตัวเลือก "ไม่มี" พิเศษที่
/// เลือกแล้วล้างตัวเลือกอื่นทั้งหมด (และถูกล้างเองถ้าไปเลือกตัวอื่นต่อ) และ
/// ช่องพิมพ์ "อื่นๆ" ท้ายรายการ สำหรับกรอกเองเมื่อโรค/อาการแพ้ไม่อยู่ใน
/// [options] — พิมพ์แล้วกดปุ่ม + (หรือ Enter) เพื่อเพิ่มเป็นชิปใหม่ต่อท้าย
/// รายการ ลบออกได้ด้วยการกด x บนชิป (ผู้ใช้รายงานจริง: พิมพ์ชื่อโรคเสร็จแล้ว
/// ไม่เห็นปุ่มเพิ่ม/ไม่เห็นว่าเพิ่มสำเร็จหรือยัง)
class AppMultiSelectChip extends StatefulWidget {
  final String label;
  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  static const noneOption = 'ไม่มี';

  const AppMultiSelectChip({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<AppMultiSelectChip> createState() => _AppMultiSelectChipState();
}

class _AppMultiSelectChipState extends State<AppMultiSelectChip> {
  final _otherCtrl = TextEditingController();

  List<String> get _customEntries => widget.selected
      .where((s) => s != AppMultiSelectChip.noneOption && !widget.options.contains(s))
      .toList();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  void _addFromField() {
    final typed = _otherCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (typed.isEmpty) return;
    final canonical = widget.selected.where((s) => widget.options.contains(s)).toList();
    final merged = {..._customEntries, ...typed}.toList(); // Set กันพิมพ์ชื่อซ้ำ
    widget.onChanged([...canonical, ...merged]);
    _otherCtrl.clear();
  }

  void _removeCustomEntry(String entry) {
    final canonical = widget.selected.where((s) => widget.options.contains(s)).toList();
    final remaining = _customEntries.where((e) => e != entry).toList();
    widget.onChanged([...canonical, ...remaining]);
  }

  @override
  Widget build(BuildContext context) {
    final isNoneSelected = widget.selected.contains(AppMultiSelectChip.noneOption);
    final allOptions = [...widget.options, AppMultiSelectChip.noneOption];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: AppTextStyles.labelBold.copyWith(color: AppColors.gray900)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...allOptions.map((opt) {
              final isSelected = widget.selected.contains(opt);
              return FilterChip(
                label: Text(opt),
                selected: isSelected,
                labelStyle: AppTextStyles.bodySmall.copyWith(
                  color: isSelected ? AppColors.teal700 : AppColors.gray600,
                ),
                backgroundColor: AppColors.gray50,
                selectedColor: AppColors.teal50,
                side: BorderSide(color: isSelected ? AppColors.teal300 : AppColors.gray100),
                onSelected: (nowSelected) {
                  if (opt == AppMultiSelectChip.noneOption) {
                    _otherCtrl.clear();
                    widget.onChanged(nowSelected ? [AppMultiSelectChip.noneOption] : []);
                    return;
                  }
                  final next = [...widget.selected]..remove(AppMultiSelectChip.noneOption);
                  if (nowSelected) {
                    next.add(opt);
                  } else {
                    next.remove(opt);
                  }
                  widget.onChanged(next);
                },
              );
            }),
            // ชิปของรายการที่พิมพ์เอง (ไม่อยู่ใน options ที่กำหนดไว้ล่วงหน้า) —
            // กด x เพื่อลบ ต่างจากชิป options ด้านบนที่กดสลับเลือก/ไม่เลือกได้
            ..._customEntries.map(
              (entry) => InputChip(
                label: Text(entry),
                labelStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.teal700),
                backgroundColor: AppColors.teal50,
                side: const BorderSide(color: AppColors.teal300),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => _removeCustomEntry(entry),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _otherCtrl,
          enabled: !isNoneSelected,
          maxLength: 100,
          decoration: InputDecoration(
            hintText: 'อื่นๆ (ถ้าไม่มีในรายการด้านบน พิมพ์แล้วกด + เพื่อเพิ่ม)',
            isDense: true,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add_circle, color: AppColors.teal500),
              tooltip: 'เพิ่ม',
              onPressed: isNoneSelected ? null : _addFromField,
            ),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: isNoneSelected ? null : (_) => _addFromField(),
        ),
      ],
    );
  }
}
