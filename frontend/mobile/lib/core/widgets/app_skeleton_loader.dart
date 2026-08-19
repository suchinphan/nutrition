import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum AppSkeletonVariant { card, listItem, profileHeader }

/// Skeleton loader พร้อม shimmer animation (sweep gradient เอง ไม่พึ่ง
/// package ภายนอก) — ใช้แสดงระหว่างรอ API response ก่อนมีข้อมูลจริง
class AppSkeletonLoader extends StatefulWidget {
  final AppSkeletonVariant variant;
  const AppSkeletonLoader({super.key, this.variant = AppSkeletonVariant.card});

  @override
  State<AppSkeletonLoader> createState() => _AppSkeletonLoaderState();
}

class _AppSkeletonLoaderState extends State<AppSkeletonLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final t = _controller.value;
            return LinearGradient(
              colors: const [AppColors.gray100, Colors.white, AppColors.gray100],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(-1 - t * 2, 0),
              end: Alignment(1 - t * 2, 0),
            ).createShader(bounds);
          },
          child: _buildSkeletonShape(),
        );
      },
    );
  }

  Widget _buildSkeletonShape() {
    switch (widget.variant) {
      case AppSkeletonVariant.listItem:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              _box(width: 48, height: 48, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _box(width: double.infinity, height: 14, radius: 4),
                    const SizedBox(height: 6),
                    _box(width: 80, height: 12, radius: 4),
                  ],
                ),
              ),
            ],
          ),
        );
      case AppSkeletonVariant.profileHeader:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _box(width: 64, height: 64, radius: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _box(width: 140, height: 18, radius: 4),
                    const SizedBox(height: 8),
                    _box(width: 100, height: 14, radius: 4),
                  ],
                ),
              ),
            ],
          ),
        );
      case AppSkeletonVariant.card:
        return _box(width: double.infinity, height: 96, radius: 12);
    }
  }

  Widget _box({required double width, required double height, required double radius}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.gray100, borderRadius: BorderRadius.circular(radius)),
    );
  }
}
