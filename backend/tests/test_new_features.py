"""Coverage for every feature actually implemented across Prompt 1-4 of this
project (weight_logs, favorites, ticket unread-count, CSV import, undo-eaten,
consents) — optional items that were never built (export PDF/CSV UI polish,
etc. on the client side) are intentionally not covered here since there is no
corresponding backend behavior to test. Same disposable-test-user pattern as
test_e2e_flow.py (fixtures now shared via conftest.py): every row this file
writes belongs to one /register'd user deleted in teardown.

Admin-only endpoints (CSV import, admin reply) authenticate via the
X-Admin-Secret header (see backend/admin/admin_routes.py:_check_admin_secret)
rather than a session login, matching how they were live-verified with curl
during development.
"""
import io
import os
import sys
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from api import app, db, _meal_is_sealed
from conftest import PASSWORD, freeze_meal_window
from health_calc import calc_age, calc_calories_goal, calc_calories_goal_custom, calc_tdee
from models import (
    Allergen, FoodCategory, FoodItem, HealthGoalCycle, MealLog, MealLogItem,
    User, UserConsent, get_thailand_time,
)

ADMIN_SECRET = os.environ.get('ADMIN_SECRET', '12345678zA*')
ADMIN_HEADERS = {'X-Admin-Secret': ADMIN_SECRET}


def _login(client, test_user):
    # ใช้ token จาก /register ตรงๆ (ดู conftest.py) แทนยิง /login ซ้ำทุกเทสต์
    # กันโดน rate limit "5 per minute" ของ /login เวลารันหลายเทสต์รวดในโปรเซส
    # เดียวกัน — พฤติกรรม auth ที่ทดสอบจริงคือ Bearer token เดียวกันกับที่
    # /login คืนกลับมาอยู่แล้ว (ทั้งคู่ผูกกับ users.password_token เดียวกัน)
    return {'Authorization': f'Bearer {test_user["token"]}'}


def _first_food_item(client, auth):
    resp = client.get('/api/food-items', headers=auth)
    assert resp.status_code == 200
    items = resp.get_json()['items']
    assert len(items) > 0, 'food_items table is empty — cannot exercise this test'
    return items[0]


# =========================
# WEIGHT LOGS
# =========================

def test_weight_log_same_day_upserts_instead_of_duplicating(client, test_user):
    auth = _login(client, test_user)

    resp = client.post('/api/weight-logs', json={'weight': 70}, headers=auth)
    assert resp.status_code == 200, resp.get_json()
    first_id = resp.get_json()['id']

    # บันทึกซ้ำวันเดียวกัน (ไม่ส่ง logged_at = default วันนี้) ด้วยน้ำหนักใหม่
    resp = client.post('/api/weight-logs', json={'weight': 72.5}, headers=auth)
    assert resp.status_code == 200, resp.get_json()
    assert resp.get_json()['id'] == first_id, 'บันทึกซ้ำวันเดียวกันต้อง update แถวเดิม ไม่สร้างแถวใหม่'
    assert resp.get_json()['weight'] == 72.5

    resp = client.get('/api/weight-logs?days=30', headers=auth)
    assert resp.status_code == 200
    rows = resp.get_json()['weight_logs']
    assert len(rows) == 1, f'ควรมีแค่ 1 แถวสำหรับวันนี้ ได้ {len(rows)} แถว'
    assert rows[0]['weight'] == 72.5


def test_weight_log_syncs_users_weight_to_latest_logged_date_not_last_write(client, test_user):
    auth = _login(client, test_user)
    today = get_thailand_time().date()

    # เขียนของ "วันนี้" ก่อน แล้วค่อย backfill ของ "เมื่อวาน" ทีหลัง (เขียนทีหลัง
    # แต่วันที่เก่ากว่า) — users.weight ต้องยังคงเป็นค่าของวันนี้ ไม่ใช่ค่าที่
    # POST ล่าสุด (นี่คือเหตุผลที่ _sync_user_weight_to_latest_log ต้อง query
    # หา logged_at ล่าสุดเอง แทนที่จะเชื่อว่า "ล่าสุดที่ POST มา = ล่าสุดตามวันที่")
    resp = client.post('/api/weight-logs', json={'weight': 65}, headers=auth)
    assert resp.status_code == 200, resp.get_json()

    yesterday = (today - timedelta(days=1)).isoformat()
    resp = client.post('/api/weight-logs', json={'weight': 200, 'logged_at': yesterday}, headers=auth)
    assert resp.status_code == 200, resp.get_json()

    resp = client.get(f'/user/{test_user["user_id"]}', headers=auth)
    assert resp.status_code == 200
    assert resp.get_json()['weight'] == 65, (
        'users.weight ต้องตรงกับ logged_at ล่าสุด (วันนี้=65) ไม่ใช่ค่าที่ POST ล่าสุด (backfill เมื่อวาน=200)'
    )


def test_weight_log_rejects_out_of_range_and_non_numeric(client, test_user):
    auth = _login(client, test_user)

    resp = client.post('/api/weight-logs', json={'weight': 'abc'}, headers=auth)
    assert resp.status_code == 400
    assert resp.get_json()['code'] == 'VALIDATION_ERROR'

    resp = client.post('/api/weight-logs', json={'weight': 501}, headers=auth)
    assert resp.status_code == 400
    assert resp.get_json()['code'] == 'VALIDATION_ERROR'


# =========================
# FAVORITES + RECENT ITEMS
# =========================

def test_favorite_toggle_is_idempotent(client, test_user):
    auth = _login(client, test_user)
    item = _first_food_item(client, auth)

    resp = client.post(f'/api/favorites/{item["id"]}', headers=auth)
    assert resp.status_code == 200, resp.get_json()
    # กดซ้ำ (ดาวกดซ้ำ) ต้องไม่ error, ไม่สร้างแถวซ้ำ (PK คู่ user_id+food_item_id)
    resp = client.post(f'/api/favorites/{item["id"]}', headers=auth)
    assert resp.status_code == 200, resp.get_json()

    resp = client.get('/api/favorites', headers=auth)
    assert resp.status_code == 200
    ids = [i['id'] for i in resp.get_json()['items']]
    assert ids.count(item['id']) == 1, 'กดดาวซ้ำต้องไม่ทำให้เมนูซ้ำในรายการโปรด'

    # ลบซ้ำ (ลบทั้งที่ไม่มีอยู่แล้วรอบสอง) ก็ต้องไม่ error เช่นกัน
    resp = client.delete(f'/api/favorites/{item["id"]}', headers=auth)
    assert resp.status_code == 200, resp.get_json()
    resp = client.delete(f'/api/favorites/{item["id"]}', headers=auth)
    assert resp.status_code == 200, resp.get_json()

    resp = client.get('/api/favorites', headers=auth)
    assert resp.get_json()['items'] == []


def test_recent_items_has_no_duplicate_food_items(client, test_user):
    auth = _login(client, test_user)
    item = _first_food_item(client, auth)

    # บันทึกเมนูเดิมซ้ำใน 2 มื้อที่ต่างกัน (เช้า/กลางวัน) — recent-items ต้อง
    # dedupe เหลือรายการเดียว ไม่ใช่โผล่ 2 ครั้งตามจำนวนมื้อที่เลือกมันไป
    for meal_type in ('breakfast', 'lunch'):
        with freeze_meal_window(meal_type):
            resp = client.post('/meal-logs', json={'meal_type': meal_type}, headers=auth)
        assert resp.status_code in (200, 201), resp.get_json()
        log_id = resp.get_json()['id']
        resp = client.post(f'/meal-logs/{log_id}/items', json={'food_item_id': item['id'], 'quantity': 1}, headers=auth)
        assert resp.status_code == 201, resp.get_json()

    resp = client.get('/api/meal-logs/recent-items?limit=5', headers=auth)
    assert resp.status_code == 200
    recent_ids = [i['id'] for i in resp.get_json()['items']]
    assert recent_ids.count(item['id']) == 1, f'เมนู {item["id"]} ถูกเลือก 2 มื้อ แต่ recent-items ต้อง dedupe เหลือ 1'


# =========================
# MEAL TIME WINDOW (ปิดรับนอกช่วงเวลาของมื้อนั้น — ล็อกฝั่ง server จริง ไม่ใช่
# แค่ UI, ดู api.MEAL_TIME_WINDOWS)
# =========================

def test_meal_log_rejected_outside_its_time_window(client, test_user):
    auth = _login(client, test_user)

    # เวลา 23:00 อยู่นอกช่วงของทั้ง 3 มื้อ (breakfast 05-10, lunch 10-15,
    # dinner 15-22) — ต้องโดนบล็อก 403 ไม่ใช่สร้าง log ผ่านไปได้
    with freeze_meal_window('dinner', hour=23):
        resp = client.post('/meal-logs', json={'meal_type': 'dinner'}, headers=auth)
    assert resp.status_code == 403, resp.get_json()
    assert resp.get_json().get('code') == 'MEAL_WINDOW_CLOSED'


def test_meal_log_accepted_inside_its_time_window(client, test_user):
    auth = _login(client, test_user)

    with freeze_meal_window('breakfast'):
        resp = client.post('/meal-logs', json={'meal_type': 'breakfast'}, headers=auth)
    assert resp.status_code in (200, 201), resp.get_json()


# =========================
# HEALTH GOAL CYCLE (สรุปผล 7 วัน — ดู api._finalize_expired_goal_cycle)
# =========================

def test_health_goal_locked_until_aligns_to_day7_dinner_close(client, test_user):
    auth = _login(client, test_user)
    resp = client.post(f'/user/{test_user["user_id"]}', json={
        'gender': 'ชาย', 'date_of_birth': '1996-01-01',
        'weight': 65, 'height': 170, 'activity_level': 'ไม่ออกกำลัง',
    }, headers=auth)
    assert resp.status_code == 200, resp.get_json()

    today = get_thailand_time().date()
    resp = client.post('/api/user/health-goal', json={'health_goal': 'ลดน้ำหนัก'}, headers=auth)
    assert resp.status_code == 200, resp.get_json()

    # ตั้งวันนี้เป็น "วันที่ 1" — ต้องปลดล็อกได้ตอน 22:00 ของ "วันที่ 7"
    # (วันนี้ + 6 วัน) ไม่ใช่ now+7*24 ชม.ตรงๆ ที่อาจจบกลางดึก/กลางมื้อ
    locked_until = datetime.fromisoformat(resp.get_json()['health_goal_locked_until'])
    expected_day7 = today + timedelta(days=6)
    assert locked_until.date() == expected_day7
    assert (locked_until.hour, locked_until.minute) == (22, 0)


def test_calories_goal_refreshes_when_activity_level_changes_mid_cycle(client, test_user):
    # เดิม calories_goal คำนวณแค่ครั้งเดียวตอน POST /api/user/health-goal แล้ว
    # ค้างค่าไว้จนครบล็อก 7 วัน แม้ผู้ใช้จะมาเปลี่ยน activity_level ที่หน้า
    # โปรไฟล์ (POST /user/<id>) ก็ตาม (บั๊กที่เจอจริง) — เทสต์นี้ยืนยันว่า
    # POST /user/<id> คำนวณ calories_goal ใหม่ให้ทันทีเมื่อ activity_level
    # เปลี่ยนและ user มี health_goal ตั้งไว้แล้ว โดยไม่ต้องรอครบรอบล็อก
    auth = _login(client, test_user)
    dob = '1996-01-01'
    resp = client.post(f'/user/{test_user["user_id"]}', json={
        'gender': 'ชาย', 'date_of_birth': dob,
        'weight': 65, 'height': 170, 'activity_level': 'ไม่ออกกำลัง',
    }, headers=auth)
    assert resp.status_code == 200, resp.get_json()

    resp = client.post('/api/user/health-goal', json={'health_goal': 'รักษาน้ำหนัก'}, headers=auth)
    assert resp.status_code == 200, resp.get_json()
    calories_before = resp.get_json()['calories_goal']

    age = calc_age(datetime.fromisoformat(dob).date())
    expected_before = calc_calories_goal(
        calc_tdee(65, 170, age, 'ชาย', 'ไม่ออกกำลัง'), 'รักษาน้ำหนัก', 'ชาย'
    )
    assert calories_before == expected_before

    # เปลี่ยนแค่ activity_level ที่หน้าโปรไฟล์ (ไม่แตะ health_goal/weight_goal เลย)
    resp = client.post(f'/user/{test_user["user_id"]}', json={
        'activity_level': 'ออกกำลังกายหนักมากเป็นนักกีฬา',
    }, headers=auth)
    assert resp.status_code == 200, resp.get_json()
    calories_after = resp.get_json()['calories_goal']

    expected_after = calc_calories_goal(
        calc_tdee(65, 170, age, 'ชาย', 'ออกกำลังกายหนักมากเป็นนักกีฬา'), 'รักษาน้ำหนัก', 'ชาย'
    )
    assert calories_after == expected_after
    assert calories_after > calories_before  # กิจกรรมหนักขึ้นมาก -> เป้าแคลอรีต้องสูงขึ้นตาม

    # GET ต้องเห็นค่าที่อัปเดตแล้วเหมือนกัน (ไม่ใช่แค่ response ของ POST เอง)
    resp = client.get(f'/user/{test_user["user_id"]}', headers=auth)
    assert resp.status_code == 200, resp.get_json()
    assert resp.get_json()['calories_goal'] == expected_after


def test_calories_goal_custom_plan_refreshes_with_custom_formula_on_weight_change(client, test_user):
    # ผู้ใช้รายงานจริง: ตั้งเป้าหมายจากกล่อง "วางแผนพลังงาน" (มี
    # target_weight/days ผูกอยู่) แล้วมาแก้น้ำหนัก/ส่วนสูง/กิจกรรมที่หน้า
    # โปรไฟล์ — calories_goal ที่ POST /user/<id> คำนวณใหม่ให้ ต้องใช้สูตร
    # calc_calories_goal_custom (ตาม target_weight/days) เหมือนตอนบันทึกเป้าหมาย
    # ครั้งแรก ไม่ใช่ตกไปใช้สูตร ±500 เดิมที่ไม่รู้จัก target_weight เลย
    auth = _login(client, test_user)
    dob = '1996-01-01'
    resp = client.post(f'/user/{test_user["user_id"]}', json={
        'gender': 'ชาย', 'date_of_birth': dob,
        'weight': 75, 'height': 170, 'activity_level': 'ไม่ออกกำลัง',
    }, headers=auth)
    assert resp.status_code == 200, resp.get_json()

    resp = client.post(
        '/api/user/health-goal',
        json={'health_goal': 'ลดน้ำหนัก', 'target_weight': 60, 'days': 30},
        headers=auth,
    )
    assert resp.status_code == 200, resp.get_json()

    # เปลี่ยนกิจกรรม (ไม่แตะ target_weight/days) — TDEE เปลี่ยน แต่แผนเดิมยังอยู่
    resp = client.post(f'/user/{test_user["user_id"]}', json={
        'activity_level': 'ออกกำลังกายหนักมากเป็นนักกีฬา',
    }, headers=auth)
    assert resp.status_code == 200, resp.get_json()

    age = calc_age(datetime.fromisoformat(dob).date())
    tdee_after = calc_tdee(75, 170, age, 'ชาย', 'ออกกำลังกายหนักมากเป็นนักกีฬา')
    expected_after = calc_calories_goal_custom(tdee_after, 75, 60, 30, 'ชาย')
    assert resp.get_json()['calories_goal'] == expected_after
    # เป้าหมายน้ำหนัก/จำนวนวันของแผนเดิมต้องไม่ถูกแตะ
    assert resp.get_json()['health_goal_target_weight'] == 60
    assert resp.get_json()['health_goal_target_days'] == 30


def test_health_goal_cycle_finalizes_once_when_expired(client, test_user):
    auth = _login(client, test_user)
    resp = client.post(f'/user/{test_user["user_id"]}', json={
        'gender': 'ชาย', 'date_of_birth': '1996-01-01',
        'weight': 65, 'height': 170, 'activity_level': 'ไม่ออกกำลัง',
    }, headers=auth)
    assert resp.status_code == 200, resp.get_json()

    resp = client.post('/api/user/health-goal', json={'health_goal': 'รักษาน้ำหนัก'}, headers=auth)
    assert resp.status_code == 200, resp.get_json()

    item = _first_food_item(client, auth)

    with app.app_context():
        user = User.query.get(test_user['user_id'])
        # จำลองว่ารอบ 7 วันหมดอายุไปเมื่อกี้นี้ แทนรอจริง 7 วัน — ต้องตั้ง
        # health_goal_started_at เองด้วย เพราะตอนนี้ locked_until ไม่ใช่
        # started_at+7 วันตรงๆ อีกต่อไป (ปัดไปที่ 22:00 ของวันที่ 7 แล้ว)
        # _finalize_expired_goal_cycle เลยใช้ started_at เป็นตัวตั้ง period_start
        locked_until = get_thailand_time().replace(tzinfo=None) - timedelta(minutes=1)
        period_start = locked_until - timedelta(days=7)
        user.health_goal_locked_until = locked_until
        user.health_goal_started_at = period_start
        db.session.commit()

        # บันทึก+กดทานแล้ว 2 มื้อ (เช้า, กลางวัน) ของวันกลางๆ รอบ — ตั้งใจ
        # เลี่ยงขอบเขตวันแรก/วันสุดท้ายที่อาจโดน clip เพื่อให้ผลลัพธ์แน่นอน
        mid_day = (period_start + timedelta(days=3)).date()
        for meal_type in ('breakfast', 'lunch'):
            log = MealLog(user_id=user.id, log_date=mid_day, meal_type=meal_type, calories_goal=user.calories_goal)
            db.session.add(log)
            db.session.flush()
            db.session.add(MealLogItem(
                meal_log_id=log.id, food_item_id=item['id'], quantity=1,
                calories_actual=100, protein_actual=1, carbs_actual=1, fat_actual=1,
                is_eaten=True,
            ))
        db.session.commit()

    resp = client.get('/api/user/health-goal-cycles', headers=auth)
    assert resp.status_code == 200, resp.get_json()
    cycles = resp.get_json()['cycles']
    assert len(cycles) == 1, f'ควรสรุปผลได้ 1 รอบ ได้ {len(cycles)} รอบ'
    cycle = cycles[0]
    assert cycle['meals_logged'] == 2
    assert cycle['meals_available'] >= 2
    expected_ratio = cycle['meals_logged'] / cycle['meals_available']
    assert abs(cycle['success_ratio'] - expected_ratio) < 1e-6
    assert cycle['is_success'] == (cycle['success_ratio'] >= 0.6)

    # เรียกซ้ำต้องไม่สร้างแถวซ้ำ (idempotent ผ่าน UNIQUE user_id+period_end)
    resp2 = client.get('/api/user/health-goal-cycles', headers=auth)
    assert len(resp2.get_json()['cycles']) == 1


def test_health_goal_cycle_counts_meals_over_quota(client, test_user):
    # เดิม cap ต่อมื้อ (calories_goal/3) บล็อกการบันทึกจริง — เอาข้อจำกัดออก
    # แล้ว (ดู test_meal_log_item_allowed_when_exceeds_one_third_daily_goal)
    # แทนที่ด้วยการนับสรุปตอนจบรอบว่ากินเกินโควตาไปกี่มื้อ
    auth = _login(client, test_user)
    resp = client.post(f'/user/{test_user["user_id"]}', json={
        'gender': 'ชาย', 'date_of_birth': '1996-01-01',
        'weight': 65, 'height': 170, 'activity_level': 'ไม่ออกกำลัง',
    }, headers=auth)
    assert resp.status_code == 200, resp.get_json()

    resp = client.post('/api/user/health-goal', json={'health_goal': 'รักษาน้ำหนัก'}, headers=auth)
    assert resp.status_code == 200, resp.get_json()

    item = _first_food_item(client, auth)

    with app.app_context():
        user = User.query.get(test_user['user_id'])
        user.calories_goal = 900  # -> cap ต่อมื้อ = 300 kcal
        locked_until = get_thailand_time().replace(tzinfo=None) - timedelta(minutes=1)
        period_start = locked_until - timedelta(days=7)
        user.health_goal_locked_until = locked_until
        user.health_goal_started_at = period_start
        db.session.commit()

        mid_day = (period_start + timedelta(days=3)).date()
        # มื้อเช้า: 100 kcal อยู่ในโควตา (cap 300) — ไม่นับเกิน
        log_ok = MealLog(user_id=user.id, log_date=mid_day, meal_type='breakfast', calories_goal=user.calories_goal)
        db.session.add(log_ok)
        db.session.flush()
        db.session.add(MealLogItem(
            meal_log_id=log_ok.id, food_item_id=item['id'], quantity=1,
            calories_actual=100, protein_actual=1, carbs_actual=1, fat_actual=1, is_eaten=True,
        ))
        # มื้อกลางวัน: 400 kcal เกินโควตา (cap 300) — ต้องนับเป็น 1 มื้อที่เกิน
        log_over = MealLog(user_id=user.id, log_date=mid_day, meal_type='lunch', calories_goal=user.calories_goal)
        db.session.add(log_over)
        db.session.flush()
        db.session.add(MealLogItem(
            meal_log_id=log_over.id, food_item_id=item['id'], quantity=1,
            calories_actual=400, protein_actual=1, carbs_actual=1, fat_actual=1, is_eaten=True,
        ))
        db.session.commit()

    resp = client.get('/api/user/health-goal-cycles', headers=auth)
    assert resp.status_code == 200, resp.get_json()
    cycles = resp.get_json()['cycles']
    assert len(cycles) == 1
    assert cycles[0]['meals_logged'] == 2
    assert cycles[0]['meals_over_quota'] == 1


def test_dashboard_shows_goal_cycle_result_until_acknowledged(client, test_user):
    auth = _login(client, test_user)
    resp = client.post(f'/user/{test_user["user_id"]}', json={
        'gender': 'ชาย', 'date_of_birth': '1996-01-01',
        'weight': 65, 'height': 170, 'activity_level': 'ไม่ออกกำลัง',
    }, headers=auth)
    assert resp.status_code == 200, resp.get_json()
    resp = client.post('/api/user/health-goal', json={'health_goal': 'ลดน้ำหนัก'}, headers=auth)
    assert resp.status_code == 200, resp.get_json()

    with app.app_context():
        user = User.query.get(test_user['user_id'])
        # ไม่บันทึกมื้อไหนเลยตลอด 7 วัน — คาดว่าได้ is_success=False
        locked_until = get_thailand_time().replace(tzinfo=None) - timedelta(minutes=1)
        user.health_goal_locked_until = locked_until
        user.health_goal_started_at = locked_until - timedelta(days=7)
        db.session.commit()

    # เปิดหน้าหลักครั้งแรกหลังรอบหมดอายุ — ต้องเห็นผลสรุปทันที ไม่ต้องรอ
    # เข้าโปรไฟล์/ประวัติเอง
    resp = client.get('/api/dashboard', headers=auth)
    assert resp.status_code == 200, resp.get_json()
    result = resp.get_json()['goal_cycle_result']
    assert result is not None
    assert result['health_goal'] == 'ลดน้ำหนัก'
    assert result['is_success'] is False
    cycle_id = result['id']

    # ยังไม่กด "รับทราบ" — เปิดหน้าหลักซ้ำต้องยังเห็นผลเดิม ไม่หายไปเอง
    resp2 = client.get('/api/dashboard', headers=auth)
    assert resp2.get_json()['goal_cycle_result']['id'] == cycle_id

    # กด "รับทราบ" แล้ว — เปิดหน้าหลักอีกครั้งต้องไม่เห็นอีก
    resp3 = client.post(f'/api/user/health-goal-cycles/{cycle_id}/ack', headers=auth)
    assert resp3.status_code == 200, resp3.get_json()
    resp4 = client.get('/api/dashboard', headers=auth)
    assert resp4.get_json()['goal_cycle_result'] is None


# =========================
# MULTI-ITEM MEAL LOGS (FoodBrowserPage เลือกหลายเมนูแล้วยืนยันรวดเดียว)
# =========================

def test_meal_log_accepts_multiple_items_in_one_meal(client, test_user):
    auth = _login(client, test_user)
    items = client.get('/api/food-items', headers=auth).get_json()['items']
    assert len(items) >= 2, 'ต้องมีอย่างน้อย 2 เมนูเพื่อทดสอบเพิ่มหลายรายการ'

    with freeze_meal_window('lunch'):
        resp = client.post('/meal-logs', json={'meal_type': 'lunch'}, headers=auth)
    assert resp.status_code in (200, 201), resp.get_json()
    log_id = resp.get_json()['id']

    # เพิ่มเมนูที่ 1 — เดิมล็อกไม่ให้เพิ่มอีกหลังจากนี้ (409 MEAL_ITEM_LOCKED)
    resp = client.post(f'/meal-logs/{log_id}/items', json={'food_item_id': items[0]['id'], 'quantity': 1}, headers=auth)
    assert resp.status_code == 201, resp.get_json()

    # เพิ่มเมนูที่ 2 — ต้องสำเร็จ ไม่ใช่ 409 อีกต่อไป
    resp = client.post(f'/meal-logs/{log_id}/items', json={'food_item_id': items[1]['id'], 'quantity': 1}, headers=auth)
    assert resp.status_code == 201, resp.get_json()
    body = resp.get_json()
    assert len(body['items']) == 2, 'มื้อเดียวต้องเก็บได้ 2 รายการ ไม่ถูกปฏิเสธรายการที่สอง'
    assert {i['food_item_id'] for i in body['items']} == {items[0]['id'], items[1]['id']}


# =========================
# TICKET UNREAD COUNT
# =========================

def test_unread_count_increases_after_admin_reply_and_decreases_after_mark_read(client, test_user):
    auth = _login(client, test_user)

    resp = client.post('/api/report_problem', json={'title': 'ทดสอบ', 'message': 'ทดสอบ unread count'}, headers=auth)
    assert resp.status_code == 201, resp.get_json()
    report_id = resp.get_json()['report']['id']

    resp = client.get('/api/reports/unread-count', headers=auth)
    assert resp.status_code == 200
    assert resp.get_json()['unread_count'] == 0, 'ยังไม่มีแอดมินตอบ ต้องยังไม่มี unread'

    resp = client.post('/admin/reply', json={'report_id': report_id, 'message': 'รับเรื่องแล้ว'}, headers=ADMIN_HEADERS)
    assert resp.status_code == 200, resp.get_json()

    resp = client.get('/api/reports/unread-count', headers=auth)
    assert resp.status_code == 200
    body = resp.get_json()
    assert body['unread_count'] == 1, 'แอดมินตอบแล้วต้องนับเป็น unread 1 เรื่อง'
    assert report_id in body['unread_report_ids']

    resp = client.patch(f'/api/reports/{report_id}/mark-read', headers=auth)
    assert resp.status_code == 200, resp.get_json()

    resp = client.get('/api/reports/unread-count', headers=auth)
    assert resp.get_json()['unread_count'] == 0, 'mark-read แล้วต้องลด unread กลับเป็น 0'


# =========================
# CSV IMPORT (admin)
# =========================

def _csv_upload(client, content, dry_run):
    data = {'file': (io.BytesIO(content.encode('utf-8')), 'import.csv')}
    return client.post(
        f'/admin/food-items/import?dry_run={"true" if dry_run else "false"}',
        data=data,
        headers=ADMIN_HEADERS,
        content_type='multipart/form-data',
    )


def test_csv_import_dry_run_does_not_write_to_db(client):
    csv_content = (
        'name,name_th,category_name,calories,protein_g,carbs_g,fat_g,fiber_g,sugar_g,image_url\r\n'
        'Pytest Dry Run Item,ทดสอบ dry run,pytest_dry_run_category,100,5,10,2,,,\r\n'
    )
    with app.app_context():
        before_items = FoodItem.query.count()
        before_cats = FoodCategory.query.count()

    resp = _csv_upload(client, csv_content, dry_run=True)
    assert resp.status_code == 200, resp.get_json()
    body = resp.get_json()
    assert body['dry_run'] is True
    assert body['would_create_count'] == 1
    assert body['error_count'] == 0
    assert body['results'][0]['status'] == 'would_create'
    assert 'pytest_dry_run_category' in body['new_categories']

    with app.app_context():
        assert FoodItem.query.count() == before_items, 'dry_run ต้องไม่เขียน FoodItem ลง DB จริง'
        assert FoodCategory.query.count() == before_cats, 'dry_run ต้องไม่สร้างหมวดหมู่ใหม่จริง'


def test_csv_import_commit_separates_success_and_error_rows_correctly(client):
    csv_content = (
        'name,name_th,category_name,calories,protein_g,carbs_g,fat_g,fiber_g,sugar_g,image_url\r\n'
        'Pytest Commit Valid Item,ทดสอบสำเร็จ,pytest_commit_category,150,8,15,3,,,\r\n'
        ',ทดสอบไม่มีชื่อ,pytest_commit_category,120,4,10,2,,,\r\n'
        'Pytest Commit Bad Calories,ทดสอบตัวเลขผิด,pytest_commit_category,not_a_number,4,10,2,,,\r\n'
    )
    created_item_id = None
    created_category_id = None
    try:
        resp = _csv_upload(client, csv_content, dry_run=False)
        assert resp.status_code == 200, resp.get_json()
        body = resp.get_json()
        assert body['dry_run'] is False
        assert body['created_count'] == 1
        assert body['error_count'] == 2

        results_by_row = {r['row']: r for r in body['results']}
        assert results_by_row[2]['status'] == 'created'
        created_item_id = results_by_row[2]['id']
        assert results_by_row[3]['status'] == 'error'
        assert 'name' in results_by_row[3]['error']
        assert results_by_row[4]['status'] == 'error'
        assert 'calories' in results_by_row[4]['error']

        with app.app_context():
            item = FoodItem.query.get(created_item_id)
            assert item is not None
            assert item.name == 'Pytest Commit Valid Item'
            created_category_id = item.category_id
    finally:
        with app.app_context():
            if created_item_id is not None:
                FoodItem.query.filter_by(id=created_item_id).delete()
            if created_category_id is not None:
                FoodCategory.query.filter_by(id=created_category_id).delete()
            db.session.commit()


# =========================
# UNDO EATEN (5-minute window)
# =========================

def _log_and_mark_eaten(client, auth):
    item = _first_food_item(client, auth)
    with freeze_meal_window('dinner'):
        resp = client.post('/meal-logs', json={'meal_type': 'dinner'}, headers=auth)
    assert resp.status_code in (200, 201), resp.get_json()
    log_id = resp.get_json()['id']
    resp = client.post(f'/meal-logs/{log_id}/items', json={'food_item_id': item['id'], 'quantity': 1}, headers=auth)
    assert resp.status_code == 201, resp.get_json()
    item_id = resp.get_json()['items'][0]['id']
    resp = client.patch(f'/meal-log-items/{item_id}/eaten', headers=auth)
    assert resp.status_code == 200, resp.get_json()
    return item_id


def test_undo_eaten_succeeds_within_5_minutes(client, test_user):
    auth = _login(client, test_user)
    item_id = _log_and_mark_eaten(client, auth)

    resp = client.patch(f'/api/meal-log-items/{item_id}/undo-eaten', headers=auth)
    assert resp.status_code == 200, resp.get_json()
    items_by_id = {i['id']: i for i in resp.get_json()['items']}
    assert items_by_id[item_id]['is_eaten'] is False


def test_undo_eaten_rejected_after_5_minutes(client, test_user):
    auth = _login(client, test_user)
    item_id = _log_and_mark_eaten(client, auth)

    # จำลอง "กดทานแล้วเมื่อ 10 นาทีก่อน" ตรงๆ ในฐานข้อมูล แทนการรอ 10 นาทีจริง
    with app.app_context():
        item = MealLogItem.query.get(item_id)
        item.eaten_at = get_thailand_time().replace(tzinfo=None) - timedelta(minutes=10)
        db.session.commit()

    resp = client.patch(f'/api/meal-log-items/{item_id}/undo-eaten', headers=auth)
    assert resp.status_code == 400
    assert resp.get_json()['code'] == 'EATEN_UNDO_EXPIRED'


def test_delete_meal_log_item_succeeds_within_5_minutes_of_eaten(client, test_user):
    auth = _login(client, test_user)
    item_id = _log_and_mark_eaten(client, auth)

    resp = client.delete(f'/meal-log-items/{item_id}', headers=auth)
    assert resp.status_code == 200, resp.get_json()
    assert all(i['id'] != item_id for i in resp.get_json()['items'])


def test_delete_meal_log_item_rejected_once_eaten_over_5_minutes(client, test_user):
    # ผู้ใช้รายงานจริง: ชีท "จัดการมื้อ" ยังโชว์ปุ่มลบให้กดได้ทั้งที่มื้อนั้น
    # ทานไปแล้วเกิน 5 นาที (undo-eaten ล็อกไปแล้วตอนนั้น) ไม่ตรงกับที่คาดไว้
    # ("ทานแล้ว+เกิน 5 นาที ต้องแก้ไม่ได้อีก รอมื้อถัดไป") จุดที่ต้องกันจริง
    # คือ backend endpoint นี้เอง (ฝั่ง UI ซ่อนปุ่มไปแล้ว แต่ต้องกันซ้ำกันเรียก
    # ตรงๆ ข้าม UI ไปด้วย เหมือน pattern allergen/calorie-cap block ก่อนหน้า)
    auth = _login(client, test_user)
    item_id = _log_and_mark_eaten(client, auth)

    with app.app_context():
        item = MealLogItem.query.get(item_id)
        item.eaten_at = get_thailand_time().replace(tzinfo=None) - timedelta(minutes=10)
        db.session.commit()

    resp = client.delete(f'/meal-log-items/{item_id}', headers=auth)
    assert resp.status_code == 400, resp.get_json()
    assert resp.get_json()['code'] == 'ITEM_EATEN_LOCKED'

    with app.app_context():
        assert MealLogItem.query.get(item_id) is not None, 'ต้องไม่ถูกลบ — บล็อกก่อนลบจริง'


def test_add_item_allowed_before_meal_seals(client, test_user):
    # เมนูแรกทานแล้วแต่ยังไม่เกิน 5 นาที (ยัง undo/แก้ไขได้อยู่) — มื้อยังไม่
    # "ปิดสนิท" ต้องเพิ่มเมนูใหม่เข้ามื้อเดิมได้ตามปกติ (กันเคส over-block)
    auth = _login(client, test_user)
    item_id = _log_and_mark_eaten(client, auth)
    with app.app_context():
        log_id = MealLogItem.query.get(item_id).meal_log_id

    item2 = _first_food_item(client, auth)
    resp = client.post(f'/meal-logs/{log_id}/items', json={'food_item_id': item2['id'], 'quantity': 1}, headers=auth)
    assert resp.status_code == 201, resp.get_json()


def test_add_item_rejected_once_meal_sealed_over_5_minutes(client, test_user):
    # ผู้ใช้รายงานจริง: มื้อที่ทานครบทุกเมนูแล้วเกิน 5 นาที (แก้ไข/ลบของเดิม
    # ไม่ได้อีกแล้ว) ยังเพิ่มเมนูใหม่เข้ามื้อเดิมได้อยู่ดี ทั้งที่ควรถือว่ามื้อ
    # นั้น "ปิดสนิท" แล้วเหมือนกับที่แก้ไขของเดิมไม่ได้ (บั๊กที่เจอจริง) —
    # ต้องบล็อกที่ backend endpoint นี้เอง (ฝั่ง UI เป็นแค่พรีวิว ไม่ใช่จุด
    # บังคับจริง เหมือน pattern allergen/calorie-cap/eaten-lock ก่อนหน้า)
    auth = _login(client, test_user)
    item_id = _log_and_mark_eaten(client, auth)
    with app.app_context():
        item = MealLogItem.query.get(item_id)
        log_id = item.meal_log_id
        item.eaten_at = get_thailand_time().replace(tzinfo=None) - timedelta(minutes=10)
        db.session.commit()

    item2 = _first_food_item(client, auth)
    resp = client.post(f'/meal-logs/{log_id}/items', json={'food_item_id': item2['id'], 'quantity': 1}, headers=auth)
    assert resp.status_code == 409, resp.get_json()
    assert resp.get_json()['code'] == 'MEAL_ALREADY_SEALED'


def test_meal_stays_sealed_even_if_a_newer_item_was_just_eaten(client, test_user):
    # ผู้ใช้รายงานจริง: เดิม _meal_is_sealed เช็คว่ามีเมนูไหนในมื้อยังไม่เกิน
    # 5 นาทีของ "ตัวมันเอง" บ้างไหม — ถ้ามีเมนูที่เพิ่งทานสดๆ ปนอยู่กับเมนูเก่า
    # ที่ทานไปแล้วเกิน 5 นาที มื้อจะถูกมองว่า "ยังไม่ปิด" อีกครั้ง เปิดช่องให้
    # เพิ่มเมนูใหม่ได้ไม่จำกัดตราบใดที่มีเมนูล่าสุดทานสดๆ อยู่เสมอ ต้องยึดเวลา
    # ทานแล้วครั้งแรกสุดของมื้อ ไม่ใช่ล่าสุด ถึงจะปิดถาวรจริงตามที่ควรเป็น
    auth = _login(client, test_user)
    item1_id = _log_and_mark_eaten(client, auth)
    item2 = _first_food_item(client, auth)
    with app.app_context():
        log_id = MealLogItem.query.get(item1_id).meal_log_id
        MealLogItem.query.get(item1_id).eaten_at = (
            get_thailand_time().replace(tzinfo=None) - timedelta(minutes=10)
        )
        # เมนูที่สอง "ทานสดๆ" เมื่อกี้ ปนอยู่ในมื้อเดียวกับเมนูแรกที่เกิน 5 นาที
        db.session.add(MealLogItem(
            meal_log_id=log_id, food_item_id=item2['id'], quantity=1.0,
            calories_actual=item2.get('calories') or 0, is_eaten=True,
            eaten_at=get_thailand_time().replace(tzinfo=None),
        ))
        db.session.commit()
        log = MealLog.query.get(log_id)
        assert _meal_is_sealed(log) is True, (
            'มื้อต้องปิดสนิทอยู่ ยึดเวลาทานแล้วครั้งแรกสุด ไม่ใช่ล่าสุดที่เพิ่งทานสดๆ'
        )

    item3 = _first_food_item(client, auth)
    resp = client.post(f'/meal-logs/{log_id}/items', json={'food_item_id': item3['id'], 'quantity': 1}, headers=auth)
    assert resp.status_code == 409, resp.get_json()
    assert resp.get_json()['code'] == 'MEAL_ALREADY_SEALED'


# =========================
# PDPA CONSENTS
# =========================

def test_consent_status_false_until_consenting_current_version(client, test_user):
    auth = _login(client, test_user)

    resp = client.get('/api/consents/status', headers=auth)
    assert resp.status_code == 200
    body = resp.get_json()
    assert body['consented'] is False
    current_version = body['current_version']

    resp = client.post('/api/consents', json={'consent_type': 'health_data_pdpa', 'policy_version': current_version}, headers=auth)
    assert resp.status_code == 201, resp.get_json()

    resp = client.get('/api/consents/status', headers=auth)
    assert resp.get_json()['consented'] is True


def test_consent_becomes_false_again_after_policy_version_bump(client, test_user):
    auth = _login(client, test_user)

    resp = client.get('/api/consents/status', headers=auth)
    current_version = resp.get_json()['current_version']
    resp = client.post('/api/consents', json={'consent_type': 'health_data_pdpa', 'policy_version': current_version}, headers=auth)
    assert resp.status_code == 201, resp.get_json()
    resp = client.get('/api/consents/status', headers=auth)
    assert resp.get_json()['consented'] is True

    # จำลอง policy bump เวอร์ชันใหม่ (แทนการแก้ CURRENT_PDPA_POLICY_VERSION
    # จริงซึ่งเป็นค่าคงที่ทั้งแอป) — ผู้ใช้ยินยอมเวอร์ชันเก่าไว้แล้วแต่ endpoint
    # ต้องเทียบกับ current_version เสมอ ไม่ใช่แค่ "เคยยินยอมไหม"
    with app.app_context():
        UserConsent.query.filter_by(user_id=test_user['user_id']).update({'policy_version': '0.1-old'})
        db.session.commit()

    resp = client.get('/api/consents/status', headers=auth)
    body = resp.get_json()
    assert body['consented'] is False, 'consented เวอร์ชันเก่าต้องไม่นับเป็นยินยอมเวอร์ชันปัจจุบัน'


# =========================
# CHANGE PASSWORD (auth ผ่าน token ต้องตรวจ username/email/old_password
# ให้ตรงกับบัญชีจริงเหมือน path ที่ไม่มี token — บั๊กที่เจอจริงคือ path ที่มี
# token ไม่เช็คอะไรพวกนี้เลย ปล่อยผ่านแม้กรอกอีเมล/ชื่อผู้ใช้ผิดบัญชี หรือไม่
# ส่ง old_password มาเลยก็ได้)
# =========================

CP_NEW_PASSWORD = 'NewPass1234!'


def test_change_password_rejects_mismatched_email_even_with_valid_token(client, test_user):
    auth = _login(client, test_user)
    resp = client.post('/change-password', json={
        'username': test_user['username'],
        'email': test_user['email'] + 'x',  # อีเมลผิดบัญชีนี้เล็กน้อย (typo)
        'old_password': PASSWORD,
        'new_password': CP_NEW_PASSWORD,
    }, headers=auth)
    assert resp.status_code == 401, resp.get_json()


def test_change_password_rejects_mismatched_username_even_with_valid_token(client, test_user):
    auth = _login(client, test_user)
    resp = client.post('/change-password', json={
        'username': test_user['username'] + 'x',
        'email': test_user['email'],
        'old_password': PASSWORD,
        'new_password': CP_NEW_PASSWORD,
    }, headers=auth)
    assert resp.status_code == 401, resp.get_json()


def test_change_password_rejects_missing_old_password_even_with_valid_token(client, test_user):
    auth = _login(client, test_user)
    resp = client.post('/change-password', json={
        'username': test_user['username'],
        'email': test_user['email'],
        'new_password': CP_NEW_PASSWORD,
    }, headers=auth)
    assert resp.status_code == 401, resp.get_json()


def test_change_password_succeeds_with_matching_identity_and_correct_old_password(client, test_user):
    auth = _login(client, test_user)
    resp = client.post('/change-password', json={
        'username': test_user['username'],
        'email': test_user['email'],
        'old_password': PASSWORD,
        'new_password': CP_NEW_PASSWORD,
    }, headers=auth)
    assert resp.status_code == 200, resp.get_json()

    # ต้อง login เข้าด้วยรหัสผ่านใหม่ได้จริง (ยืนยันว่าเปลี่ยนสำเร็จจริง ไม่ใช่
    # แค่ตอบ 200 หลอกๆ)
    resp = client.post('/login', json={'username': test_user['username'], 'password': CP_NEW_PASSWORD})
    assert resp.status_code == 200, resp.get_json()


# =========================
# ALLERGEN BLOCK ตอนบันทึกมื้ออาหาร (เดิม /meal-logs/<id>/items แค่แจ้งเตือน
# กลับไปเฉยๆ ยังบันทึกสำเร็จอยู่ดี — ผู้ใช้ขอให้บล็อกจริง ดู BUG-002 รอบหลัง)
# ใช้ FoodItem/Allergen ชั่วคราวที่สร้าง+ลบเองในเทสต์ ไม่พึ่งข้อมูล seed ที่
# อาจไม่มี allergen ผูกไว้เลย (allergens_reviewed=0 เป็น default)
# =========================

def test_meal_log_item_blocked_when_matches_user_allergy(client, test_user):
    auth = _login(client, test_user)

    with app.app_context():
        category = FoodCategory.query.filter_by(type='food').first()
        allergen = Allergen(name='ทดสอบแพ้_e2e')
        db.session.add(allergen)
        item = FoodItem(
            category_id=category.id, name='Test Allergen Food', name_th='เมนูทดสอบแพ้',
            calories=100, protein_g=5, carbs_g=10, fat_g=2, is_active=True,
        )
        db.session.add(item)
        db.session.flush()
        item.allergens.append(allergen)
        db.session.commit()
        item_id = item.id
        allergen_id = allergen.id

    try:
        resp = client.post(f'/user/{test_user["user_id"]}', json={'food_allergies': ['ทดสอบแพ้_e2e']}, headers=auth)
        assert resp.status_code == 200, resp.get_json()

        with freeze_meal_window('dinner'):
            resp = client.post('/meal-logs', json={'meal_type': 'dinner'}, headers=auth)
        assert resp.status_code in (200, 201), resp.get_json()
        log_id = resp.get_json()['id']

        resp = client.post(f'/meal-logs/{log_id}/items', json={'food_item_id': item_id, 'quantity': 1}, headers=auth)
        assert resp.status_code == 403, resp.get_json()
        assert resp.get_json().get('code') == 'ALLERGEN_BLOCKED'

        # ยืนยันว่าไม่มีแถวถูกสร้างขึ้นจริง (บล็อกก่อนบันทึก ไม่ใช่บันทึกแล้วค่อยเตือน)
        with app.app_context():
            assert MealLogItem.query.filter_by(meal_log_id=log_id, food_item_id=item_id).first() is None
    finally:
        with app.app_context():
            MealLogItem.query.filter_by(food_item_id=item_id).delete()
            db_item = FoodItem.query.get(item_id)
            if db_item:
                db.session.delete(db_item)
            db_allergen = Allergen.query.get(allergen_id)
            if db_allergen:
                db.session.delete(db_allergen)
            db.session.commit()


# เดิม disease-blocked category (blocked_category_reason — เบาหวานห้ามของหวาน
# ทั้งหมวด) เช็คแค่ตอน AI แนะนำเมนู (ai_recommend_menu) จุดเดียว ผู้ใช้เลือก
# เมนูของหวานเองผ่านหน้าบันทึกมื้อได้ปกติทั้งที่มีโรคประจำตัว (ผู้ใช้รายงานจริง)
def test_meal_log_item_blocked_when_category_restricted_by_disease(client, test_user):
    auth = _login(client, test_user)

    with app.app_context():
        category = FoodCategory.query.filter_by(type='dessert').first()
        item = FoodItem(
            category_id=category.id, name='Test Dessert', name_th='เมนูของหวานทดสอบ',
            calories=200, protein_g=2, carbs_g=40, fat_g=3, sugar_g=30, is_active=True,
        )
        db.session.add(item)
        db.session.commit()
        item_id = item.id

    try:
        resp = client.post(f'/user/{test_user["user_id"]}', json={'chronic_diseases': ['เบาหวาน']}, headers=auth)
        assert resp.status_code == 200, resp.get_json()

        with freeze_meal_window('dinner'):
            resp = client.post('/meal-logs', json={'meal_type': 'dinner'}, headers=auth)
        assert resp.status_code in (200, 201), resp.get_json()
        log_id = resp.get_json()['id']

        # หน้าบันทึกมื้อต้องเห็น flag เตือน/ปิดปุ่มเพิ่มด้วย (GET /api/food-items)
        resp = client.get('/api/food-items', headers=auth, query_string={'type': 'dessert'})
        items = {it['id']: it for it in resp.get_json()['items']}
        assert items[item_id]['allergy_warning'] is True
        assert items[item_id]['disease_warning_reason']

        resp = client.post(f'/meal-logs/{log_id}/items', json={'food_item_id': item_id, 'quantity': 1}, headers=auth)
        assert resp.status_code == 403, resp.get_json()
        assert resp.get_json().get('code') == 'ALLERGEN_BLOCKED'

        with app.app_context():
            assert MealLogItem.query.filter_by(meal_log_id=log_id, food_item_id=item_id).first() is None
    finally:
        with app.app_context():
            MealLogItem.query.filter_by(food_item_id=item_id).delete()
            db_item = FoodItem.query.get(item_id)
            if db_item:
                db.session.delete(db_item)
            db.session.commit()


# =========================
# PER-MEAL CALORIE CAP (แบ่งโควตาเท่ากัน 3 มื้อ) — เดิม cap นี้บล็อกการบันทึก
# จริง (409 MEAL_CALORIE_CAP_EXCEEDED) ผู้ใช้ขอให้เอาข้อจำกัดออก ให้บันทึก
# เกินโควตาได้เสมอ แล้วเอาไปนับสรุปตอนจบรอบเป้าหมายสุขภาพแทน (ดู
# meals_over_quota ใน api._finalize_expired_goal_cycle)
# =========================

def test_meal_log_item_allowed_when_exceeds_one_third_daily_goal(client, test_user):
    auth = _login(client, test_user)

    with app.app_context():
        u = User.query.get(test_user['user_id'])
        u.calories_goal = 900  # -> cap ต่อมื้อ (เดิม) = 300 kcal
        db.session.commit()
        category = FoodCategory.query.filter_by(type='food').first()
        item = FoodItem(
            category_id=category.id, name='Test Cap Food', name_th='เมนูทดสอบโควตามื้อ',
            calories=400, protein_g=0, carbs_g=100, fat_g=0, is_active=True,  # 100*4=400 kcal ต่อ 1 หน่วย
        )
        db.session.add(item)
        db.session.commit()
        item_id = item.id

    try:
        with freeze_meal_window('breakfast'):
            resp = client.post('/meal-logs', json={'meal_type': 'breakfast'}, headers=auth)
        assert resp.status_code in (200, 201), resp.get_json()
        log_id = resp.get_json()['id']

        # 400 kcal > cap (เดิม) 300 kcal ของมื้อนี้ — ต้องบันทึกผ่านได้ปกติแล้ว
        resp = client.post(f'/meal-logs/{log_id}/items', json={'food_item_id': item_id, 'quantity': 1}, headers=auth)
        assert resp.status_code == 201, resp.get_json()

        with app.app_context():
            assert MealLogItem.query.filter_by(meal_log_id=log_id, food_item_id=item_id).first() is not None
    finally:
        with app.app_context():
            MealLogItem.query.filter_by(food_item_id=item_id).delete()
            db_item = FoodItem.query.get(item_id)
            if db_item:
                db.session.delete(db_item)
            db.session.commit()


def test_meal_log_item_allowed_when_within_one_third_daily_goal(client, test_user):
    auth = _login(client, test_user)

    with app.app_context():
        u = User.query.get(test_user['user_id'])
        u.calories_goal = 900  # -> cap ต่อมื้อ = 300 kcal
        db.session.commit()
        category = FoodCategory.query.filter_by(type='food').first()
        item = FoodItem(
            category_id=category.id, name='Test Cap Food OK', name_th='เมนูทดสอบโควตามื้อ (พอดี)',
            calories=200, protein_g=0, carbs_g=50, fat_g=0, is_active=True,  # 50*4=200 kcal ต่อ 1 หน่วย < cap 300
        )
        db.session.add(item)
        db.session.commit()
        item_id = item.id

    try:
        with freeze_meal_window('breakfast'):
            resp = client.post('/meal-logs', json={'meal_type': 'breakfast'}, headers=auth)
        assert resp.status_code in (200, 201), resp.get_json()
        log_id = resp.get_json()['id']

        resp = client.post(f'/meal-logs/{log_id}/items', json={'food_item_id': item_id, 'quantity': 1}, headers=auth)
        assert resp.status_code == 201, resp.get_json()
    finally:
        with app.app_context():
            MealLogItem.query.filter_by(food_item_id=item_id).delete()
            db_item = FoodItem.query.get(item_id)
            if db_item:
                db.session.delete(db_item)
            db.session.commit()
