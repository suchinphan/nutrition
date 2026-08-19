import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// ครอบ [Future] ด้วย 4 สถานะมาตรฐาน: loading / error(+retry) / empty / success
/// สร้างเพื่อไม่ต้องเขียน FutureBuilder + UI error/empty เองซ้ำทุกหน้า
/// (ทุกหน้าต้องมี 4 สถานะนี้ตามกติกาโปรเจค) — ใช้ซ้ำได้กับทุกหน้าที่โหลดข้อมูล
/// ตัวอย่างการใช้งาน: ดู lib/page/dashboard_page.dart
class AsyncStateView<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback onRetry;
  final bool Function(T data)? isEmpty;
  final Widget? loading;
  final Widget? empty;
  final String errorMessage;

  const AsyncStateView({
    super.key,
    required this.future,
    required this.builder,
    required this.onRetry,
    this.isEmpty,
    this.loading,
    this.empty,
    this.errorMessage = 'โหลดข้อมูลไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return loading ?? const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState(message: errorMessage, onRetry: onRetry);
        }
        final data = snapshot.data as T;
        if (empty != null && isEmpty != null && isEmpty!(data)) {
          return empty!;
        }
        return builder(context, data);
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.dangerLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                color: AppColors.danger,
                size: 28,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่'),
            ),
          ],
        ),
      ),
    );
  }
}
