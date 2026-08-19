# API Contract — Dashboard Summary

รูปแบบ JSON ที่ Flutter app (`lib/services/dashboard_service.dart` →
`HttpDashboardService`) คาดหวังจาก backend สำหรับหน้าแดชบอร์ด
(`lib/page/dashboard_page.dart`, โมเดลอยู่ที่ `lib/models/dashboard_data.dart`)

## ⚠️ สิ่งที่พบจากการตรวจโค้ด backend จริง (สำคัญ ต้องแจ้งทีม)

โจทย์ตั้งต้นสมมติว่า backend เป็น FastAPI/Django รันที่ `localhost:8000` แต่จาก
การอ่าน `backend/api.py` จริง พบว่า:

- **เป็น Flask ไม่ใช่ FastAPI/Django** (`app = Flask(__name__)`)
- **รันที่ port 5000** ไม่ใช่ 8000 (`app.run(..., port=5000)`)
- **ไม่มี endpoint ไหนฝัง user id ไว้ใน URL path เลย** — ทุก endpoint ที่ต้อง
  ยืนยันตัวตน (เช่น `/api/check_main_page_summary`) ระบุผู้ใช้จาก
  `Authorization: Bearer <token>` เพียงอย่างเดียว (lookup `User` จาก
  `password_token` ที่ตรงกับ token ใน header) แล้วดึง `user.id` ฝั่งเซิร์ฟเวอร์เอง
- **รูปแบบ error response ที่ใช้จริงคือ `{"error": "ข้อความ"}`** ไม่ใช่
  `{"message": ...}` (เช่น `{'error': 'authorization required'}`,
  `{'error': 'invalid or expired token'}`)

ฝั่ง Flutter (`TypedApiClient`) รองรับทั้งสองคีย์ (`message` และ `error`) อยู่แล้ว
จึงไม่กระทบโค้ด แต่ **แนะนำให้ทีม backend ยึด `{"error": "..."}` ต่อไปเพื่อความ
สม่ำเสมอ**

**อัปเดต:** แก้ค่า default ของ `--dart-define=API_URL` fallback ใน
`lib/services/typed_api_client.dart` แล้วให้ตรงกับ port 5000 จริง (ตรงกับ
`getApiBase()` ที่ `lib/services/app_config.dart` ใช้อยู่ทั่วทั้งแอป) ไม่ต้อง
ส่ง `--dart-define` เพิ่มเพื่อชี้ port ให้ถูกอีกต่อไป

## Endpoint

```
GET /api/dashboard
Authorization: Bearer <jwt_token>   (จำเป็น)
```

ตาม convention เดิมของโปรเจค **ไม่ต้องส่ง user id ใน path หรือ query** —
backend ระบุผู้ใช้จาก token ในการ header เอง (เหมือน `/api/check_main_page_summary`
ที่มีอยู่แล้ว)

### Response 200 OK

```json
{
  "calories_consumed": 1400.0,
  "calories_goal": 2000.0,
  "meals": [
    { "label": "เช้า", "status": "done" },
    { "label": "กลางวัน", "status": "done" },
    { "label": "เย็น", "status": "pending" }
  ],
  "weight_kg": 65.2,
  "weight_delta_kg": -0.3,
  "bmi": 22.4,
  "bmi_status": "normal",
  "sodium_mg": 1450.0,
  "sodium_goal_mg": 2000.0,
  "sugar_g": 28.0,
  "sugar_goal_g": 50.0,
  "last_7_days": [
    { "date": "2026-07-13", "consumed_kcal": 1750.0, "goal_kcal": 2000.0 },
    { "date": "2026-07-14", "consumed_kcal": 1890.0, "goal_kcal": 2000.0 },
    { "date": "2026-07-15", "consumed_kcal": 2100.0, "goal_kcal": 2000.0 },
    { "date": "2026-07-16", "consumed_kcal": 1600.0, "goal_kcal": 2000.0 },
    { "date": "2026-07-17", "consumed_kcal": 2250.0, "goal_kcal": 2000.0 },
    { "date": "2026-07-18", "consumed_kcal": 1980.0, "goal_kcal": 2000.0 },
    { "date": "2026-07-19", "consumed_kcal": 1400.0, "goal_kcal": 2000.0 }
  ]
}
```

### ชนิดข้อมูลของแต่ละฟิลด์

| ฟิลด์ | ชนิด | หมายเหตุ |
|---|---|---|
| `calories_consumed` | number | แคลอรีที่กินไปวันนี้ |
| `calories_goal` | number | เป้าหมายแคลอรีวันนี้ (ต้อง > 0) |
| `meals[].label` | string | ชื่อมื้อ (เช้า/กลางวัน/เย็น) |
| `meals[].status` | string enum | หนึ่งใน `"pending"` \| `"done"` \| `"missed"` เท่านั้น ค่าอื่นถือเป็น `pending` |
| `weight_kg` | number | น้ำหนักล่าสุด |
| `weight_delta_kg` | number | ผลต่างจากการชั่งครั้งก่อน (ค่าลบ = ลดลง, บวก = เพิ่มขึ้น) |
| `bmi` | number | ค่า BMI |
| `bmi_status` | string enum | หนึ่งใน `"underweight"` \| `"normal"` \| `"overweight"` \| `"obese"` ค่าอื่นถือเป็น `normal` |
| `sodium_mg` | number | โซเดียมที่กินไปวันนี้ (mg) |
| `sodium_goal_mg` | number | เป้าหมายโซเดียม/วัน (mg) |
| `sugar_g` | number | น้ำตาลที่กินไปวันนี้ (g) |
| `sugar_goal_g` | number | เป้าหมายน้ำตาล/วัน (g) |
| `last_7_days[].date` | string | รูปแบบ ISO-8601 `YYYY-MM-DD` เรียง **เก่า → ใหม่** ต้องมี **7 รายการพอดี** |
| `last_7_days[].consumed_kcal` | number | แคลอรีที่กินของวันนั้น |
| `last_7_days[].goal_kcal` | number | เป้าหมายแคลอรีของวันนั้น |

**หมายเหตุสำคัญ:** ไม่มีฟิลด์ `shortcuts` ใน contract นี้ — เมนูลัดหน้าแดชบอร์ด
(ไอคอน + navigation) เป็นข้อมูลฝั่ง Flutter app ล้วนๆ (ผูกกับ `IconData`/
`VoidCallback` ของ Flutter โดยตรง) ไม่ serializable เป็น JSON จึงไม่ต้องส่งมา

ถ้าผู้ใช้ยังไม่มีข้อมูลบันทึกวันนี้เลย ให้คืน `calories_consumed: 0` และ
`last_7_days` ที่ `consumed_kcal` เป็น 0 ทุกวัน (ฝั่งแอปจะตีความว่าเป็นสถานะ
"ยังไม่มีข้อมูล" และแสดง empty state แทน — ดู `DashboardData.isEmpty`)

### Response 401 / 403 — Unauthorized

```json
{ "error": "invalid or expired token" }
```

ฝั่งแอปจะ map เป็น `AuthError` (ข้อความ "เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่อีกครั้ง")

### Response 4xx/5xx อื่นๆ — Server Error

```json
{ "error": "คำอธิบาย error สั้นๆ" }
```

ฝั่งแอปจะ map เป็น `ServerError(code, message)` และแสดงปุ่ม "ลองใหม่"

## Checklist สำหรับทีม backend

- [ ] เพิ่ม route `GET /api/dashboard` ใน `backend/api.py` (รูปแบบเดียวกับ
      `/api/check_main_page_summary` — อ่าน user จาก Bearer token, ไม่รับ
      user id ทาง path/query)
- [ ] `last_7_days` ต้องมี **7 รายการเสมอ** แม้บางวันไม่มีข้อมูล (ใส่ 0)
- [ ] ตัวเลขทั้งหมดเป็น JSON number (ไม่ใช่ string) — ฝั่งแอป parse ด้วย
      `(json['x'] as num).toDouble()` ถ้าส่งเป็น string จะเป็น `ParseError`
- [ ] `meals[].status` และ `bmi_status` ต้องเป็นค่าตรงตามที่ระบุเป๊ะๆ
      (case-sensitive, lowercase) ค่าที่ไม่ตรงจะถูกปัดเป็นค่า default
      อย่างเงียบๆ (ไม่ error) — ถ้าต้องการ error ชัดเจนกว่านี้แจ้งได้
