"""End-to-end flow test: register -> login -> profile -> health-goal ->
food-items -> allergy warning -> log a meal -> duplicate rejected -> mark
eaten -> dashboard summary -> change weight -> BMI updates live.

Runs against the real dev DB (Flask's in-process test_client, no mocks) —
not a transaction-rollback sandbox, because this codebase has no test-DB /
Alembic setup to hook a rollback into. Instead every value this test writes
belongs to one disposable user created via /register and deleted in the
fixture teardown (same pattern used for all the live-curl testing earlier
in this project). Every expected number is derived by calling health_calc
directly, not hardcoded, so it stays correct if the seed data changes.
"""
import os
import sys
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from health_calc import calc_age, calc_bmi, bmi_status, calc_tdee, calc_calories_goal, calc_calories_from_macros

# client/test_user fixtures now live in conftest.py (shared with the newer
# test_new_features.py) — PASSWORD stays here since test bodies reference it.
from conftest import PASSWORD, freeze_meal_window


def test_full_e2e_flow(client, test_user):
    user_id = test_user['user_id']

    # 2. POST /login -> token
    resp = client.post('/login', json={'username': test_user['username'], 'password': PASSWORD})
    assert resp.status_code == 200, resp.get_json()
    token = resp.get_json()['authToken']
    auth = {'Authorization': f'Bearer {token}'}

    # 3. PUT /profile (จริงคือ POST /user/<id>) -> กรอก gender/dob/weight/height/activity
    resp = client.post(f'/user/{user_id}', json={
        'gender': 'ชาย', 'date_of_birth': '1996-01-01',
        'weight': 65, 'height': 170, 'activity_level': 'ไม่ออกกำลัง',
    }, headers=auth)
    assert resp.status_code == 200, resp.get_json()

    # 4. GET /profile -> age/bmi/bmi_status ตรงกับคำนวณมือ (health_calc ตรงๆ,
    # อ้างอิงวิธีคิดเดียวกับ WORKED_EXAMPLE.md)
    resp = client.get(f'/user/{user_id}', headers=auth)
    assert resp.status_code == 200
    profile = resp.get_json()
    expected_age = calc_age(date(1996, 1, 1))
    expected_bmi = calc_bmi(65, 170)
    assert profile['age'] == expected_age
    assert profile['bmi'] == expected_bmi
    assert profile['bmi_status'] == bmi_status(expected_bmi)

    # 5. PUT /profile/health-goal (จริงคือ POST /api/user/health-goal) -> calories_goal
    resp = client.post('/api/user/health-goal', json={'health_goal': 'รักษาน้ำหนัก'}, headers=auth)
    assert resp.status_code == 200, resp.get_json()
    expected_tdee = calc_tdee(65, 170, expected_age, 'ชาย', 'ไม่ออกกำลัง')
    expected_calories_goal = calc_calories_goal(expected_tdee, 'รักษาน้ำหนัก')
    assert resp.get_json()['calories_goal'] == expected_calories_goal

    # 6. GET /api/food-items -> ไม่มี field ที่ไม่ควรเป็น null
    resp = client.get('/api/food-items', headers=auth)
    assert resp.status_code == 200
    items = resp.get_json()['items']
    assert len(items) > 0, 'food_items table is empty — cannot exercise the rest of the flow'
    for it in items:
        for field in ('calories', 'protein_g', 'carbs_g', 'fat_g'):
            assert it[field] is not None, f"food_item id={it['id']} has null {field}"

    # 7. ตั้ง food_allergies=["กุ้ง"] -> allergy_warning=true เฉพาะเมนูที่มีกุ้งจริง
    resp = client.post(f'/user/{user_id}', json={'food_allergies': ['กุ้ง']}, headers=auth)
    assert resp.status_code == 200, resp.get_json()
    resp = client.get('/api/food-items', headers=auth)
    items = resp.get_json()['items']
    for it in items:
        should_warn = 'กุ้ง' in it['allergens']
        assert it['allergy_warning'] == should_warn, (
            f"food_item id={it['id']} allergens={it['allergens']} "
            f"expected allergy_warning={should_warn}, got {it['allergy_warning']}"
        )

    # 8. POST /meal-logs + .../items -> บันทึกมื้อเช้า
    with freeze_meal_window('breakfast'):
        resp = client.post('/meal-logs', json={'meal_type': 'breakfast'}, headers=auth)
    assert resp.status_code in (200, 201), resp.get_json()
    log_id = resp.get_json()['id']

    # เดิมใช้ items[0] ตรงๆ — แต่ step 7 เพิ่งตั้ง food_allergies=["กุ้ง"]
    # ไปแล้ว ถ้า items[0] ดันมีกุ้งพอดีจะโดนบล็อก 403 แทนที่จะสำเร็จ (ตอนนี้
    # /meal-logs/<id>/items บล็อกจริงไม่ใช่แค่เตือน ดู BUG-002 ตอนหลัง) จุด
    # ทดสอบตรงนี้ตั้งใจเช็ค "เพิ่มเมนูสำเร็จ + macro ตรง" ไม่ใช่เช็คการบล็อก
    # (มีเทสต์แยกต่างหากสำหรับกรณีนั้นแล้ว) เลือกเมนูที่ไม่ติด allergy_warning
    # แทนเพื่อไม่ให้ผลลัพธ์ขึ้นกับข้อมูล allergen สุ่มใน DB
    chosen = next((it for it in items if not it['allergy_warning']), None)
    assert chosen is not None, 'ทุกเมนูตรงกับ "กุ้ง" หมด — หา non-allergenic item ทดสอบไม่ได้'
    resp = client.post(f'/meal-logs/{log_id}/items', json={'food_item_id': chosen['id'], 'quantity': 1}, headers=auth)
    assert resp.status_code == 201, resp.get_json()
    logged_item = resp.get_json()['items'][0]
    item_id = logged_item['id']

    expected_item_calories = calc_calories_from_macros(chosen['carbs_g'], chosen['protein_g'], chosen['fat_g'])
    assert logged_item['calories_actual'] == expected_item_calories
    assert logged_item['protein_actual'] == chosen['protein_g']
    assert logged_item['carbs_actual'] == chosen['carbs_g']
    assert logged_item['fat_actual'] == chosen['fat_g']

    # 9. บันทึกมื้อเช้าซ้ำ -> ต้องได้ 409
    with freeze_meal_window('breakfast'):
        resp = client.post('/meal-logs', json={'meal_type': 'breakfast'}, headers=auth)
    assert resp.status_code == 409, resp.get_json()
    assert resp.get_json().get('code') == 'MEAL_ALREADY_LOGGED'

    # 10. PATCH .../eaten -> is_eaten=1
    resp = client.patch(f'/meal-log-items/{item_id}/eaten', headers=auth)
    assert resp.status_code == 200, resp.get_json()
    updated_items = {i['id']: i for i in resp.get_json()['items']}
    assert updated_items[item_id]['is_eaten'] is True

    # 11. GET /dashboard/summary -> eaten_calories ตรงกับที่บันทึกจริง (คำนวณมือเทียบ)
    resp = client.get('/api/dashboard', headers=auth)
    assert resp.status_code == 200
    dash = resp.get_json()
    assert dash['eaten_calories'] == expected_item_calories
    assert dash['eaten_protein'] == chosen['protein_g']
    assert dash['eaten_carbs'] == chosen['carbs_g']
    assert dash['eaten_fat'] == chosen['fat_g']

    # 12. เปลี่ยน weight -> GET /profile อีกครั้ง -> BMI เปลี่ยนทันที ไม่ค้างค่าเดิม
    resp = client.post(f'/user/{user_id}', json={'weight': 80}, headers=auth)
    assert resp.status_code == 200, resp.get_json()
    resp = client.get(f'/user/{user_id}', headers=auth)
    new_bmi = resp.get_json()['bmi']
    expected_new_bmi = calc_bmi(80, 170)
    assert new_bmi == expected_new_bmi
    assert new_bmi != expected_bmi, 'BMI ค้างค่าเดิมหลังเปลี่ยนน้ำหนัก — cache/stale-read บั๊ก'
