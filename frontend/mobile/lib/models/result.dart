import 'app_error.dart';

/// ผลลัพธ์แบบ success/error อย่างชัดเจน — บังคับให้ผู้เรียกจัดการ error
/// แทนการปล่อยให้ exception ดิบหลุดขึ้นไปถึง UI (ดู typed_api_client.dart)
sealed class Result<T> {
  const Result();

  /// จับคู่ผลลัพธ์ให้ครบทั้งสองกรณี (คล้าย fold ใน Either)
  R when<R>({
    required R Function(T value) ok,
    required R Function(AppError error) err,
  }) {
    final self = this;
    return switch (self) {
      Ok<T>() => ok(self.value),
      Err<T>() => err(self.error),
    };
  }

  bool get isOk => this is Ok<T>;
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

final class Err<T> extends Result<T> {
  final AppError error;
  const Err(this.error);
}
