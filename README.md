# NutritionalHealth — Setup

โปรเจคมี 3 ส่วน:
- `backend/` — Python (Flask) API + MySQL
- `frontend/admin/` — React (Vite) แผงควบคุมแอดมิน
- `frontend/mobile/` — Flutter แอปมือถือ

ทำตามลำดับ: **backend ก่อนเสมอ** (อีก 2 ส่วนเรียก API จาก backend)

---

## 1) Backend (Python)

**ต้องมี:** Python 3.13, MySQL 8+

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate          # Windows
pip install -r requirements.txt
```

**ตั้งค่า config** — คัดลอกไฟล์ `.example` แล้วใส่ค่าจริง (ไฟล์จริงไม่ต้อง commit):

| ไฟล์ตัวอย่าง | ไฟล์จริงที่ต้องสร้าง | ใส่อะไร |
|---|---|---|
| `config.json.example` | `config.json` | `GEMINI_API_KEY` |
| `mysql_config.example.json` | `mysql_config.json` | user/password/host/port/database |
| `image_providers.example.json` | `image_providers.json` | Google/Unsplash/Pexels API keys |

สร้างไฟล์ `.env` ใน `backend/` เอง (ต้องมีตัวแปรเหล่านี้ — ดึงจาก `os.environ.get(...)` ในโค้ดจริง):
```
SECRET_KEY=
JWT_SECRET_KEY=
ADMIN_SECRET=
MYSQL_HOST=
MYSQL_PORT=
MYSQL_USER=
MYSQL_PASS=
MYSQL_DB=
DB_PATH=
FLASK_ENV=development
TOKEN_TTL_DAYS=
GOOGLE_API_KEY=
GOOGLE_CX=
UNSPLASH_ACCESS_KEY=
PEXELS_API_KEY=
GROQ_API_KEY=
GROQ_MODEL=
```

**สร้างฐานข้อมูล:**
```bash
mysql -u root -p < create_db_and_user.sql
mysql -u root -p <database_name> < mysql_schema.sql
```

**รัน:**
```bash
python api.py
```
รันที่ `http://localhost:5000` (debug=True — แก้โค้ดแล้ว auto-reload)

---

## 2) Admin panel (React + Vite)

**ต้องมี:** Node.js 20+

```bash
cd frontend/admin
npm install
npm run dev
```

มีไฟล์ `.env.development` อยู่แล้ว (`VITE_API_BASE_URL=http://localhost:5000`) — แก้ให้ตรง backend จริงถ้าไม่ได้รันที่ localhost:5000

---

## 3) Mobile app (Flutter)

**ต้องมี:** Flutter SDK (Dart `^3.9.2` ขึ้นไป)

```bash
cd frontend/mobile
flutter pub get
```

เปิดใช้ desktop ครั้งแรก (ถ้ายังไม่เคย):
```bash
flutter config --enable-windows-desktop
```

**รัน:**
```bash
flutter run -d windows      # หรือ -d chrome, หรือ device/emulator อื่น
```

**dart-define ที่มีผล** (ปกติไม่ต้องใส่ — ค่า default ชี้ backend จริงอยู่แล้วที่ `localhost:5000`):
```bash
--dart-define=API_URL=http://localhost:5000        # เปลี่ยน backend URL
--dart-define=USE_MOCK_DASHBOARD=true              # บังคับกลับไปใช้ mock data
--dart-define=USE_MOCK_MEAL_SELECTION=true         # เหมือนกัน (หน้าเลือกมื้ออาหาร)
```

**รันเทส:**
```bash
flutter test
flutter test integration_test/meal_selection_test.dart -d windows
```

---

## ลำดับรันตอน dev

1. `backend`: `python api.py` (ค้างไว้)
2. `frontend/admin`: `npm run dev` (ถ้าต้องใช้แผงแอดมิน)
3. `frontend/mobile`: `flutter run -d windows`
