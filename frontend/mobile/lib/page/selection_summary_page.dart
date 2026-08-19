import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'history_page.dart';

/// Read-only confirmation screen shown right after choose_food_type_page.dart
/// successfully saves the user's meal/food/drink selection. Replaces the old
/// calculate1/2/3_page.dart + Show_food_items_page.dart chain, which
/// duplicated this same summary across three extra screens and issued extra
/// /save-selection calls. The save already happened before this page is
/// shown — this page does not call the backend, it only displays what was
/// just saved and hands off to History.
class SelectionSummaryPage extends StatelessWidget {
  final String meal;
  final int duration;
  final String foodName;
  final String dessertName;
  final String drinkName;
  final int totalCalories;

  const SelectionSummaryPage({
    super.key,
    required this.meal,
    required this.duration,
    required this.foodName,
    required this.dessertName,
    required this.drinkName,
    required this.totalCalories,
  });

  static const Color _accentGreen = AppColors.leaf;

  Widget _buildItemRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _accentGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _accentGreen, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                const SizedBox(height: 2),
                Text(
                  value.isNotEmpty ? value : '-',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F8F6),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'สรุปรายการที่เลือก',
          style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: _accentGreen, size: 22),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'บันทึกรายการเรียบร้อยแล้ว',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildItemRow(Icons.schedule, 'มื้ออาหาร / ระยะเวลา', '${meal.isNotEmpty ? meal : '-'} · $duration วัน'),
                    _buildItemRow(Icons.restaurant_menu, 'เมนูอาหาร', foodName),
                    _buildItemRow(Icons.icecream_outlined, 'ของหวาน', dessertName),
                    _buildItemRow(Icons.local_cafe_outlined, 'เครื่องดื่ม', drinkName),
                    _buildItemRow(Icons.local_fire_department_outlined, 'แคลอรีรวม', '$totalCalories kcal'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => HistoryPage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.history, color: Colors.white, size: 20),
                  label: const Text(
                    'ส่งไปยังประวัติ',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
