# =========================
# Standardized error response format — ใช้ร่วมกันทั้ง api.py และ
# admin/admin_routes.py (แยกไฟล์ต่างหากกัน circular import ระหว่างสองโมดูล)
#
# ทุก error ต้องคืนรูปแบบเดียวกันเสมอ:
#   { "is_error": true, "error": "ข้อความ", "code": "MACHINE_CODE",
#     "message": "ข้อความ", "detail": {...} }
#
# หมายเหตุ: ตาม spec เดิมต้องการ "error": true (boolean ล้วน) แต่โค้ด Flutter
# ที่มีอยู่แล้วหลายหน้า (login_page.dart, register_page.dart, profile_page.dart)
# เช็ค `if (j['error'] != null) msg = j['error'].toString()` — boolean true ก็
# "!= null" เหมือนกัน จะทำให้ UI โชว์คำว่า "true" แทนข้อความจริง เนื่องจาก prompt
# นี้ห้ามแตะ Flutter จึงคง "error" เป็น string ข้อความเดิมไว้ (backward-compatible)
# แล้วเพิ่ม "is_error" เป็น boolean ใหม่ต่างหากสำหรับโค้ดที่อยากเช็คแบบ
# machine-readable จริงๆ (เช่น React admin) — ตัดสินใจร่วมกับผู้ใช้แล้ว
# =========================
from flask import jsonify

ERROR_STATUS_DEFAULTS = {
    400: 'VALIDATION_ERROR',
    401: 'UNAUTHORIZED',
    403: 'FORBIDDEN',
    404: 'NOT_FOUND',
    405: 'METHOD_NOT_ALLOWED',
    409: 'CONFLICT',
    429: 'RATE_LIMITED',
    500: 'SERVER_ERROR',
}


def error_response(message, status=400, code=None, detail=None):
    """สร้าง error response รูปแบบมาตรฐาน — ใช้แทน jsonify({'error': ...}), status ทุกที่"""
    body = {
        'is_error': True,
        'error': message,
        'code': code or ERROR_STATUS_DEFAULTS.get(status, 'ERROR'),
        'message': message,
    }
    if detail is not None:
        body['detail'] = detail
    return jsonify(body), status
