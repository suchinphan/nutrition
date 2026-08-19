import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// วงกลม avatar — โชว์รูปจริงถ้ามี [imageUrl] (URL เต็ม พร้อม cache-busting
/// ผ่าน key ของผู้เรียกถ้าต้องการ) ไม่งั้น fallback เป็นวงกลมอักษรย่อจากชื่อ
/// เหมือนเดิม (ยังไม่มีรูป หรือโหลดรูปไม่สำเร็จ)
class AppAvatarInitials extends StatelessWidget {
  final String name;
  final double size;
  final String? imageUrl;

  const AppAvatarInitials({super.key, required this.name, this.size = 40, this.imageUrl});

  String get _initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Widget _initialsCircle() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.teal500, shape: BoxShape.circle),
      child: Text(
        _initials,
        style: AppTextStyles.headingSmall.copyWith(color: Colors.white, fontSize: size * 0.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) return _initialsCircle();
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _initialsCircle(),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _initialsCircle(),
      ),
    );
  }
}
