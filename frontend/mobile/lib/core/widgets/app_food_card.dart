import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'app_allergy_badge.dart';

String _emojiForCategoryType(String categoryType) => switch (categoryType) {
  'drink' => '🥤',
  'dessert' => '🍰',
  _ => '🍽️',
};

/// การ์ดเมนูอาหารมาตรฐาน — thumbnail (image_url หรือ emoji fallback ตาม
/// ประเภท), ชื่อ+แคลอรี (ของหน่วยบริโภคที่เลือก), ป้ายเตือนภูมิแพ้ (ถ้ามี),
/// trailing อิสระ (ปุ่มเลือก หรือ AppMealStatusTag) และไอคอนดาว toggle
/// รายการโปรดที่มุมขวาบน (แสดงเฉพาะเมื่อส่ง [onFavoriteToggle] มา — ไม่ส่งมา
/// ก็เหมือนเดิมทุกจุดที่ใช้อยู่แล้ว)
class AppFoodCard extends StatelessWidget {
  final String? imageUrl;
  final String categoryType; // food | drink | dessert
  final String name;
  final num? calories;
  final List<String>? allergenNames;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  const AppFoodCard({
    super.key,
    this.imageUrl,
    required this.categoryType,
    required this.name,
    this.calories,
    this.allergenNames,
    this.trailing,
    this.onTap,
    this.isFavorite = false,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Thumbnail(imageUrl: imageUrl, categoryType: categoryType),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name.isEmpty ? '-' : name,
                      style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      calories == null ? '- kcal' : '${calories!.toStringAsFixed(0)} kcal',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
                    ),
                    if (allergenNames != null && allergenNames!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      AppAllergyBadge(allergenNames: allergenNames),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );

    if (onFavoriteToggle == null) return card;

    return Stack(
      children: [
        card,
        Positioned(
          right: 4,
          top: 4,
          child: IconButton(
            onPressed: onFavoriteToggle,
            icon: Icon(
              isFavorite ? Icons.star : Icons.star_border,
              color: isFavorite ? AppColors.amber500 : AppColors.gray400,
            ),
            iconSize: 22,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final String? imageUrl;
  final String categoryType;
  const _Thumbnail({required this.imageUrl, required this.categoryType});

  @override
  Widget build(BuildContext context) {
    const size = 48.0;
    final url = imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: (url != null && url.isNotEmpty)
          ? Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _emojiFallback(),
            )
          : _emojiFallback(),
    );
  }

  Widget _emojiFallback() {
    return Container(
      width: 48,
      height: 48,
      color: AppColors.teal50,
      alignment: Alignment.center,
      child: Text(_emojiForCategoryType(categoryType), style: const TextStyle(fontSize: 22)),
    );
  }
}
