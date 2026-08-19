import 'package:flutter/material.dart';
import '../models/dashboard_data.dart' show BmiStatus, BmiStatusLabelTh;
import '../models/meal_selection_data.dart';
import '../router/app_router.dart';
import '../services/meal_selection_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_state_view.dart';
import '../widgets/section_card.dart';

/// หน้า "เลือกมื้ออาหารและระยะเวลา" — สรุปสุขภาพ + เลือกมื้อ (เช้า/กลางวัน/
/// เย็น เลือกได้หลายอัน) + ระยะเวลา + แคลอรีที่จะได้รับ แล้วไปหน้าเลือกเมนู
///
/// รับ [service] ผ่าน constructor (DI) — สลับ Mock/Http ได้จากจุดเรียกใช้
/// โดยไม่ต้องแก้โค้ดหน้านี้ (ดู lib/router/app_router.dart)
class MealSelectionPage extends StatefulWidget {
  final MealSelectionService service;
  const MealSelectionPage({super.key, required this.service});

  @override
  State<MealSelectionPage> createState() => _MealSelectionPageState();
}

class _MealSelectionPageState extends State<MealSelectionPage> {
  late Future<MealSelectionPageData> _future;
  final Set<MealSlot> _selectedMeals = {};
  int _durationDays = 7;
  bool _submitting = false;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<MealSelectionPageData> _fetch() async {
    final result = await widget.service.fetchPageData();
    return result.when(
      ok: (data) => data,
      err: (error) => throw Exception(error.toUserMessage()),
    );
  }

  void _retry() => setState(() {
    _prefilled = false;
    _future = _fetch();
  });

  void _prefillIfNeeded(MealSelectionPageData data) {
    if (_prefilled) return;
    _prefilled = true;
    final existing = data.existingSelection;
    if (existing == null) return;
    _selectedMeals.addAll(existing.meals);
    if (existing.durationDays != null) _durationDays = existing.durationDays!;
  }

  void _toggleMeal(MealSlot slot) {
    setState(() {
      if (_selectedMeals.contains(slot)) {
        _selectedMeals.remove(slot);
      } else {
        _selectedMeals.add(slot);
      }
    });
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final draft = MealSelectionDraft(
      meals: _selectedMeals.toList(),
      durationDays: _durationDays,
    );
    final result = await widget.service.saveDraft(draft);
    if (!mounted) return;
    setState(() => _submitting = false);
    result.when(
      ok: (_) => Navigator.of(context).pushNamed(AppRoutes.mealChooseFood),
      err: (error) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toUserMessage()))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เลือกมื้ออาหารและระยะเวลา')),
      body: SafeArea(
        child: AsyncStateView<MealSelectionPageData>(
          future: _future,
          onRetry: _retry,
          isEmpty: (data) => data.isEmpty,
          empty: const _MealSelectionEmptyState(),
          builder: (context, data) {
            _prefillIfNeeded(data);
            return _MealSelectionBody(
              data: data,
              selectedMeals: _selectedMeals,
              durationDays: _durationDays,
              submitting: _submitting,
              onToggleMeal: _toggleMeal,
              onDurationChanged: (d) => setState(() => _durationDays = d),
              onSubmit: _submit,
            );
          },
        ),
      ),
    );
  }
}

/// จัดวางเนื้อหาทั้งหมด รองรับ 320dp–840dp (จำกัดความกว้างสูงสุดตรงกลางจอ
/// ไม่ให้ฟอร์มยืดกว้างเกินไปบนแท็บเล็ต)
class _MealSelectionBody extends StatelessWidget {
  final MealSelectionPageData data;
  final Set<MealSlot> selectedMeals;
  final int durationDays;
  final bool submitting;
  final ValueChanged<MealSlot> onToggleMeal;
  final ValueChanged<int> onDurationChanged;
  final VoidCallback onSubmit;

  const _MealSelectionBody({
    required this.data,
    required this.selectedMeals,
    required this.durationDays,
    required this.submitting,
    required this.onToggleMeal,
    required this.onDurationChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedMeals.isNotEmpty;
    final totalCalories = MealSelectionDraft(
      meals: selectedMeals.toList(),
      durationDays: durationDays,
    ).totalPlanCalories(data.healthSummary.caloriesGoal);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HealthSummarySection(summary: data.healthSummary),
              const SizedBox(height: AppSpace.lg),
              Text(
                'เลือกมื้ออาหาร',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpace.sm),
              _MealChipsRow(selected: selectedMeals, onToggle: onToggleMeal),
              const SizedBox(height: AppSpace.lg),
              DropdownButtonFormField<int>(
                initialValue: durationDays,
                decoration: const InputDecoration(labelText: 'ระยะเวลา'),
                items: const [7, 14, 30]
                    .map((d) => DropdownMenuItem(value: d, child: Text('$d วัน')))
                    .toList(),
                onChanged: (d) {
                  if (d != null) onDurationChanged(d);
                },
              ),
              const SizedBox(height: AppSpace.lg),
              _CalorieInfoBox(
                mealCount: selectedMeals.length,
                totalCalories: totalCalories,
              ),
              const SizedBox(height: AppSpace.lg),
              _NextButton(
                enabled: hasSelection,
                submitting: submitting,
                onPressed: onSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// SectionCard "สรุปสุขภาพ" — BMI, เป้าแคลอรี/วัน, ได้รับจริง + ToneChip สถานะ
class _HealthSummarySection extends StatelessWidget {
  final HealthSummary summary;
  const _HealthSummarySection({required this.summary});

  static ChipTone _toneFor(BmiStatus s) => switch (s) {
    BmiStatus.normal => ChipTone.leaf,
    BmiStatus.underweight || BmiStatus.overweight => ChipTone.turmeric,
    BmiStatus.obese => ChipTone.chili,
  };

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'สรุปสุขภาพ',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'BMI',
                  value: summary.bmi.toStringAsFixed(1),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'เป้าแคลอรี/วัน',
                  value: '${summary.caloriesGoal.toStringAsFixed(0)} kcal',
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'ได้รับจริง',
                  value:
                      '${summary.caloriesConsumedToday.toStringAsFixed(0)} kcal',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          ToneChip(
            summary.bmiStatus.labelTh,
            tone: _toneFor(summary.bmiStatus),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.labelMedium),
      ],
    );
  }
}

/// แถวชิปเลือกมื้ออาหาร เช้า/กลางวัน/เย็น — เลือกได้หลายอันอิสระต่อกัน
class _MealChipsRow extends StatelessWidget {
  final Set<MealSlot> selected;
  final ValueChanged<MealSlot> onToggle;
  const _MealChipsRow({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: MealSlot.values
          .map(
            (slot) => _MealChip(
              slot: slot,
              selected: selected.contains(slot),
              onTap: () => onToggle(slot),
            ),
          )
          .toList(),
    );
  }
}

/// ชิปเดียว — AnimatedContainer เปลี่ยนสี + AnimatedScale ขยาย 1.03 ตอนเลือก
class _MealChip extends StatelessWidget {
  final MealSlot slot;
  final bool selected;
  final VoidCallback onTap;
  const _MealChip({
    required this.slot,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Semantics(
          button: true,
          selected: selected,
          label: selected ? '${slot.labelTh} เลือกแล้ว' : slot.labelTh,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedScale(
              scale: selected ? 1.03 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.leafLight : AppColors.card,
                  borderRadius: AppRadius.rMd,
                  border: Border.all(
                    color: selected ? AppColors.leaf : AppColors.line,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Text(
                  slot.labelTh,
                  style: TextStyle(
                    color: selected ? AppColors.leaf : AppColors.ink,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// กล่องข้อมูล (turmericLight) สรุปแคลอรีรวมตามมื้อ/ระยะเวลาที่เลือก
class _CalorieInfoBox extends StatelessWidget {
  final int mealCount;
  final int totalCalories;
  const _CalorieInfoBox({required this.mealCount, required this.totalCalories});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.turmericLight,
        borderRadius: AppRadius.rMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.turmeric, size: 20),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              mealCount == 0
                  ? 'เลือกมื้ออาหารเพื่อดูแคลอรีที่จะได้รับ'
                  : 'คุณจะได้รับพลังงานรวมประมาณ $totalCalories kcal ตลอดช่วงที่เลือก',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// ปุ่ม "หน้าถัดไป" — disabled + tooltip บอกเหตุผลเมื่อยังไม่เลือกมื้อ,
/// แสดง spinner เล็กๆ ตอน submit
class _NextButton extends StatelessWidget {
  final bool enabled;
  final bool submitting;
  final VoidCallback onPressed;
  const _NextButton({
    required this.enabled,
    required this.submitting,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: enabled && !submitting ? onPressed : null,
      child: submitting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text('หน้าถัดไป'),
    );
    if (enabled) return button;
    return Tooltip(message: 'กรุณาเลือกมื้ออาหารอย่างน้อย 1 มื้อ', child: button);
  }
}

class _MealSelectionEmptyState extends StatelessWidget {
  const _MealSelectionEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.assignment_outlined,
              size: 56,
              color: AppColors.inkSoft,
            ),
            const SizedBox(height: AppSpace.md),
            Text('ยังไม่มีข้อมูลสุขภาพ', style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpace.xs),
            Text(
              'กรุณากรอกข้อมูลส่วนตัวก่อนเพื่อคำนวณ BMI และเป้าแคลอรี',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
