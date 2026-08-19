/// ข้อผิดพลาดที่ service layer อาจคืนกลับมา แยกเป็นชนิดย่อยให้ UI แยก handle ได้
/// (เช่น AuthError อาจต้องพาไปหน้า login, ServerError อาจโชว์ปุ่ม "ลองใหม่")
sealed class AppError {
  const AppError();

  /// ข้อความภาษาไทยสำหรับแสดงผลตรงๆ ให้ผู้ใช้ (ไม่ใช่ debug message)
  String toUserMessage();
}

/// เชื่อมต่อเครือข่ายไม่ได้ / timeout / DNS ล้มเหลว ฯลฯ
final class NetworkError extends AppError {
  const NetworkError();

  @override
  String toUserMessage() =>
      'เชื่อมต่อเครือข่ายไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่อีกครั้ง';
}

/// เซิร์ฟเวอร์ตอบกลับด้วย status code ที่ไม่ใช่ 2xx (ไม่รวม 401/403 ซึ่งจัดเป็น AuthError)
final class ServerError extends AppError {
  final int code;
  final String message;
  const ServerError(this.code, this.message);

  @override
  String toUserMessage() {
    // [message] คือข้อความที่ TypedApiClient._extractMessage ดึงจาก
    // json['message']/json['error'] มาแล้ว (backend ทุก endpoint คืน
    // {error, code, message, ...} ตาม error_response() เหมือนกันหมด) — ใช้
    // ข้อความจริงจาก server เสมอถ้ามี (เช่น EATEN_UNDO_EXPIRED: "เกินเวลาที่จะ
    // ยกเลิกได้แล้ว (5 นาที)") แทนข้อความทั่วไปที่ไม่บอกอะไรเลย เหมือน pattern
    // เดียวกับ ConflictError ด้านล่าง
    if (message.isNotEmpty) return message;
    return 'เซิร์ฟเวอร์ขัดข้อง (รหัส $code) กรุณาลองใหม่อีกครั้ง';
  }
}

/// แปลง response body เป็นโมเดลไม่สำเร็จ (JSON ผิดรูปแบบ/ฟิลด์ไม่ตรง)
final class ParseError extends AppError {
  const ParseError();

  @override
  String toUserMessage() => 'ข้อมูลที่ได้รับจากเซิร์ฟเวอร์ไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง';
}

/// ไม่ได้เข้าสู่ระบบ หรือ token หมดอายุ/ไม่ถูกต้อง (401/403)
final class AuthError extends AppError {
  const AuthError();

  @override
  String toUserMessage() => 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่อีกครั้ง';
}

/// 409 — สถานะปัจจุบันไม่อนุญาตให้ทำรายการนี้ (มื้อนี้บันทึกไปแล้ว,
/// ticket ปิดแล้ว, เปลี่ยนเป้าหมายยังไม่ครบ 7 วัน ฯลฯ) — [body] คือ JSON ที่
/// decode แล้วจาก response ตรงๆ ให้ผู้เรียกดึงข้อมูลเดิมออกมาใช้ต่อได้ (เช่น
/// meal_log ที่มีอยู่แล้ว) โดยไม่ต้องยิงซ้ำ
final class ConflictError extends AppError {
  final dynamic body;
  const ConflictError(this.body);

  @override
  String toUserMessage() {
    // backend ทุก endpoint ใหม่คืน {error, code, message, ...} ตาม
    // error_response() แบบเดียวกันหมด — ใช้ message จริงจาก server แทนข้อความ
    // ตายตัวเรื่องมื้ออาหารที่ใช้ผิดบริบทได้ตั้งแต่มี endpoint 409 อื่นเพิ่มมา
    // (ticket ปิด, ล็อกเป้าหมาย, ล็อกเมนูที่เลือกแล้ว)
    try {
      final b = body;
      if (b is Map && b['message'] is String && (b['message'] as String).isNotEmpty) {
        return b['message'] as String;
      }
      if (b is Map && b['error'] is String && (b['error'] as String).isNotEmpty) {
        return b['error'] as String;
      }
    } catch (_) {}
    return 'ทำรายการนี้ไม่ได้ในตอนนี้';
  }
}
