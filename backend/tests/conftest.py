"""Shared fixtures for all backend tests — same disposable-test-user pattern
used throughout this project's live-curl testing and test_e2e_flow.py:
create via /register, run the test against the real dev DB (no mocks, no
rollback sandbox), delete everything the user could have created in
teardown so no test data survives between runs.
"""
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# _check_admin_secret()/admin_required() ไม่มี default secret ฝังในซอร์สโค้ด
# แล้ว (แก้ BUG-001 — เดิม fallback เป็น '12345678zA*' ซึ่งเป็นช่องโหว่ความ
# ปลอดภัยถ้า deploy จริงลืมตั้งค่าเอง) เทสต์ที่ยิง request ผ่าน X-Admin-Secret
# header (ดู test_new_features.py) จึงต้องตั้ง env var นี้เองตรงๆ ก่อน request
# แรก ไม่พึ่ง default จากโค้ดจริงอีกต่อไป
os.environ.setdefault('ADMIN_SECRET', '12345678zA*')

from contextlib import contextmanager
from datetime import datetime

import pytest

import api as api_module
from api import app, db, limiter
from models import (
    User, MealLog, MealLogItem, ProfileAuditLog, WeightLog, UserFavoriteFood,
    UserConsent, Report, ReportMessage, Submission,
)

PASSWORD = 'Test1234!'

# POST /meal-logs ตอนนี้เช็คช่วงเวลาจริงของแต่ละมื้อ (ดู api.MEAL_TIME_WINDOWS)
# เทสต์ที่ยิง endpoint นี้เลยต้องปลอมนาฬิกาเซิร์ฟเวอร์ให้อยู่ในช่วงของมื้อนั้น
# ไม่งั้นผลเทสต์จะสุ่มพัง/ผ่านตามเวลาจริงที่รันจริง — patch แค่ในช่วง `with`
# เท่านั้น ไม่ใช่ทั้งเทสต์ เพราะโค้ดอื่นในเทสต์เดียวกัน (เช่น undo-eaten 5 นาที)
# ยังต้องใช้เวลาจริงเทียบกันเองอยู่
_MEAL_WINDOW_HOUR = {'breakfast': 7, 'lunch': 12, 'dinner': 18}


@contextmanager
def freeze_meal_window(meal_type, hour=None):
    # hour override lets a test pretend it's outside meal_type's window (e.g.
    # to assert the 403 MEAL_WINDOW_CLOSED rejection) instead of only ever
    # freezing to a time that's inside it. Keeps the real *date* — only the
    # hour is faked — since log_date defaults to get_thailand_time().date()
    # and later requests (e.g. dashboard) compare against the real today
    # once this patch is reverted; a fake date here would make the log
    # invisible to any unpatched code later in the same test.
    original = api_module.get_thailand_time
    if hour is None:
        hour = _MEAL_WINDOW_HOUR[meal_type]
    today = original().date()
    api_module.get_thailand_time = lambda: datetime(today.year, today.month, today.day, hour, 0)
    try:
        yield
    finally:
        api_module.get_thailand_time = original


@pytest.fixture
def client():
    app.config['TESTING'] = True
    # ปิด rate limit ตอนรันเทสต์ — ทุก request มาจาก IP เดียวกัน (test client)
    # ทั้งสวีท ถ้าไม่ปิด /register (5 ครั้ง/นาที) จะโดนบล็อกตั้งแต่ test_user
    # fixture ตัวที่ 6 เป็นต้นไป ทำให้เทสต์ error ด้วย 429 ทั้งที่ฟีเจอร์ที่
    # ทดสอบจริงไม่มีปัญหาอะไรเลย ต้องตั้งที่ limiter.enabled ตรงๆ (ไม่ใช่
    # app.config['RATELIMIT_ENABLED']) เพราะ Limiter.init_app() อ่านค่านั้น
    # แค่ครั้งเดียวตอน api.py ถูก import (ก่อน fixture นี้รันอีก) ตั้ง config
    # ทีหลังจึงไม่มีผล ไม่กระทบ rate limit จริงตอน production เพราะรีเซ็ต
    # กลับ True ตอนจบทุกเทสต์
    limiter.enabled = False
    with app.test_client() as c:
        yield c
    limiter.enabled = True


@pytest.fixture
def test_user(client):
    suffix = uuid.uuid4().hex[:8]
    username = f'e2e_{suffix}'
    email = f'e2e_{suffix}@example.com'
    resp = client.post('/register', json={
        'username': username, 'password': PASSWORD, 'confirm_password': PASSWORD, 'email': email,
    })
    assert resp.status_code == 201, resp.get_json()
    body = resp.get_json()
    user_id = body['user_id']
    # /register คืน authToken มาให้เลย — ใช้ตัวนี้แทนการยิง /login แยกต่างหาก
    # ในทุกเทสต์ (ที่ rate-limit ไว้แค่ 5 ครั้ง/นาที/IP ดู api.py:1083-1084)
    # เทสต์หลายไฟล์/หลายเคสที่ล็อกอินซ้ำๆ ในโปรเซสเดียวกันจะโดน 429 ถ้าไปเรียก
    # /login จริงทุกครั้ง
    token = body['authToken']

    yield {'username': username, 'email': email, 'user_id': user_id, 'token': token}

    with app.app_context():
        u = User.query.get(user_id)
        if u is None:
            return
        # เดิมเป็น delete statement เรียงกันตรงๆ ไม่มี try/except — ถ้าอันใด
        # อันหนึ่งกลางทางล้ม (เช่น FK constraint ที่ไม่คาดคิด) รายการหลังจาก
        # นั้นรวมถึงตัว user เองจะไม่ถูกลบเลย ทิ้ง test user ค้างใน DB จริง
        # (บั๊กที่เจอจริง — ยังไม่เคยเกิดจริงในทางปฏิบัติปัจจุบัน แต่เป็นความ
        # เสี่ยงแฝง) ห่อแต่ละขั้นด้วย try/except ให้พยายามลบต่อแม้ขั้นก่อน
        # หน้าล้ม จบด้วยการลบ user เสมอ
        def _safe(fn):
            # commit ทันทีหลังแต่ละขั้นสำเร็จ ไม่รวมเป็น transaction เดียวกัน
            # ทั้งหมด — ถ้าไม่ commit แยก แล้วขั้นถัดไป rollback จะลบผลลัพธ์
            # ของขั้นก่อนหน้าที่สำเร็จไปแล้วทิ้งไปด้วย (rollback คืนค่าทั้ง
            # session ไม่ใช่แค่ statement ล่าสุด)
            try:
                fn()
                db.session.commit()
            except Exception:
                db.session.rollback()

        _safe(lambda: [MealLogItem.query.filter_by(meal_log_id=log.id).delete()
                        for log in MealLog.query.filter_by(user_id=u.id).all()])
        _safe(lambda: MealLog.query.filter_by(user_id=u.id).delete())
        _safe(lambda: ProfileAuditLog.query.filter_by(user_id=u.id).delete())
        _safe(lambda: WeightLog.query.filter_by(user_id=u.id).delete())
        _safe(lambda: UserFavoriteFood.query.filter_by(user_id=u.id).delete())
        _safe(lambda: UserConsent.query.filter_by(user_id=u.id).delete())
        _safe(lambda: Submission.query.filter_by(user_id=u.id).delete())

        def _delete_report_messages():
            for report in Report.query.filter_by(user_id=u.id).all():
                ReportMessage.query.filter_by(report_id=report.id).delete()
        _safe(_delete_report_messages)
        _safe(lambda: Report.query.filter_by(user_id=u.id).delete())

        try:
            db.session.delete(u)
            db.session.commit()
        except Exception:
            db.session.rollback()
