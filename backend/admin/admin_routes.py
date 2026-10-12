from flask import Blueprint, request, jsonify
import os
import csv
import io
from datetime import timedelta

from models import (
    db, Report, ReportMessage, User, ProfileAuditLog, Submission,
    FoodCategory, FoodType, FoodItem, ServingSize, Allergen, MealLog,
    MealLogItem, AdminActionLog, UserFavoriteFood, food_allergens,
    get_thailand_time,
)
from sqlalchemy import text, func
from sqlalchemy.orm import selectinload
from flask import session
from error_utils import error_response, ERROR_STATUS_DEFAULTS
from health_calc import calc_calories_from_macros

admin_bp = Blueprint('admin_bp', __name__)


def _check_admin_secret(req):
    # ห้ามมี default secret ฝังในซอร์สโค้ด — เดิม fallback เป็น '12345678zA*'
    # ถ้า deploy ไหนลืมตั้ง ADMIN_SECRET เอง ใครก็ได้ที่เห็นซอร์สโค้ดนี้ (เช่น
    # จาก repo ที่เปิด public) จะเข้าถึง endpoint แอดมินทั้งหมดได้ทันที รวม
    # endpoint ที่ทำลายข้อมูลได้ (บั๊กที่เจอจริง) ถ้าไม่ตั้งค่าไว้ การเช็คทาง
    # header/query จะไม่มีทาง match เลย เหลือแค่ session login จริงผ่าน
    # /admin/login (is_admin=True) เท่านั้นที่ใช้ได้
    admin_secret = os.environ.get('ADMIN_SECRET')
    # รับเฉพาะทาง header เท่านั้น — เดิมรับผ่าน query string (?admin_secret=)
    # ด้วย ซึ่งหลุดเข้า server access log/Referer header ได้ง่ายกว่า header เอง
    provided = req.headers.get('X-Admin-Secret')
    # 1) Accept explicit admin_secret (header only)
    try:
        if admin_secret and provided and provided == admin_secret:
            return True
    except Exception:
        pass

    # 2) Accept session-based admin login (if admin logged in via /admin/login)
    try:
        user_id = session.get('admin_user_id')
        if user_id:
            u = User.query.get(user_id)
            if u and getattr(u, 'is_admin', False):
                return True
    except Exception:
        pass

    return False


# Thai labels for ProfileAuditLog.field_name — keeps the raw column name in
# the DB/API stable while the admin UI shows a readable label.
_PROFILE_FIELD_LABELS_TH = {
    'name': 'ชื่อ',
    'surname': 'นามสกุล',
    'gender': 'เพศ',
    'date_of_birth': 'วันเกิด',
    'weight': 'น้ำหนัก',
    'height': 'ส่วนสูง',
    'activity_level': 'กิจกรรม',
    'chronic_diseases': 'โรคประจำตัว',
    'food_allergies': 'แพ้อาหาร',
}


@admin_bp.route('/profile-history', methods=['GET'])
def list_profile_history():
    """Read-only, admin-facing history feed. No PUT/DELETE exists for this
    data anywhere — admins can only ever view it here.

    Merges two append-only sources chronologically:
      - ProfileAuditLog: personal-info field edits (old -> new), logged by
        POST /user/<id> whenever a user changes their own profile.
      - Submission: menu suggestions the user submitted for review.

    Query params: user_id (optional), start_date/end_date (YYYY-MM-DD,
    optional, inclusive), page/per_page (default 1/50).
    """
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    user_id = request.args.get('user_id')
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    try:
        page = max(int(request.args.get('page', 1)), 1)
    except (ValueError, TypeError):
        page = 1
    try:
        per_page = min(max(int(request.args.get('per_page', 50)), 1), 200)
    except (ValueError, TypeError):
        per_page = 50

    def _date_bounds():
        from datetime import datetime as _dt, timedelta as _td
        start_dt = end_dt = None
        try:
            if start_date:
                start_dt = _dt.strptime(start_date, '%Y-%m-%d')
            if end_date:
                end_dt = _dt.strptime(end_date, '%Y-%m-%d') + _td(days=1)
        except Exception:
            pass
        return start_dt, end_dt

    start_dt, end_dt = _date_bounds()

    audit_q = ProfileAuditLog.query
    sub_q = Submission.query
    if user_id:
        try:
            uid = int(user_id)
            audit_q = audit_q.filter(ProfileAuditLog.user_id == uid)
            sub_q = sub_q.filter(Submission.user_id == uid)
        except (ValueError, TypeError):
            pass
    if start_dt is not None:
        audit_q = audit_q.filter(ProfileAuditLog.changed_at >= start_dt)
        sub_q = sub_q.filter(Submission.created_at >= start_dt)
    if end_dt is not None:
        audit_q = audit_q.filter(ProfileAuditLog.changed_at < end_dt)
        sub_q = sub_q.filter(Submission.created_at < end_dt)

    events = []
    for a in audit_q.order_by(ProfileAuditLog.changed_at.desc()).limit(1000).all():
        events.append({
            'type': 'profile_edit',
            'user_id': a.user_id,
            'username': a.user.username if a.user else None,
            'field': a.field_name,
            'field_label': _PROFILE_FIELD_LABELS_TH.get(a.field_name, a.field_name),
            'old_value': a.old_value,
            'new_value': a.new_value,
            'at': a.changed_at.isoformat() if a.changed_at else None,
        })
    for s in sub_q.order_by(Submission.created_at.desc()).limit(1000).all():
        events.append({
            'type': 'menu_submission',
            'user_id': s.user_id,
            'username': s.user.username if s.user else None,
            'name_th': s.name_th,
            'name_en': s.name_en,
            'item_type': s.item_type,
            'status': s.status,
            'at': s.created_at.isoformat() if s.created_at else None,
        })

    events.sort(key=lambda e: e['at'] or '', reverse=True)

    total = len(events)
    start_idx = (page - 1) * per_page
    page_events = events[start_idx:start_idx + per_page]

    return jsonify({
        'events': page_events,
        'page': page,
        'per_page': per_page,
        'total': total,
    })


@admin_bp.route('/dashboard-stats', methods=['GET'])
def dashboard_stats():
    """Real numbers for the admin dashboard — no mock data. All counts are
    computed on request; this app has no dashboard-stats cache table.
    """
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    from datetime import timedelta

    now = get_thailand_time()
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_ago = today_start - timedelta(days=6)  # 7 days inclusive of today

    total_members = User.query.filter_by(is_deleted=False).count()
    members_this_week = User.query.filter(
        User.is_deleted == False,
        User.created_at >= week_ago,
    ).count()

    total_menu_items = FoodItem.query.count()
    total_categories = FoodCategory.query.count()

    today_activity = Submission.query.filter(Submission.created_at >= today_start).count()
    yesterday_start = today_start - timedelta(days=1)
    yesterday_activity = Submission.query.filter(
        Submission.created_at >= yesterday_start,
        Submission.created_at < today_start,
    ).count()
    activity_delta_pct = None
    if yesterday_activity > 0:
        activity_delta_pct = round((today_activity - yesterday_activity) / yesterday_activity * 100)

    # Weekly usage trend — Submission count per day, oldest first
    weekly_trend = []
    for i in range(6, -1, -1):
        day_start = today_start - timedelta(days=i)
        day_end = day_start + timedelta(days=1)
        count = Submission.query.filter(
            Submission.created_at >= day_start,
            Submission.created_at < day_end,
        ).count()
        weekly_trend.append({'date': day_start.strftime('%Y-%m-%d'), 'count': count})

    # Category composition — how many food items exist per category.
    def _label(cat_name, cat_type):
        return f'{cat_name} ({cat_type})' if cat_type else cat_name

    category_rows = (
        db.session.query(FoodCategory.name, FoodCategory.type, func.count(FoodItem.id))
        .outerjoin(FoodItem, FoodItem.category_id == FoodCategory.id)
        .group_by(FoodCategory.id, FoodCategory.name, FoodCategory.type)
        .order_by(func.count(FoodItem.id).desc())
        .all()
    )
    category_breakdown = [{'name': _label(name, ctype), 'count': count} for name, ctype, count in category_rows]

    # Category popularity — how often each category was actually logged
    # (meal_log_items -> food_items -> food_categories), independent of
    # how many menu items exist in the catalog.
    popularity_rows = (
        db.session.query(FoodCategory.name, FoodCategory.type, func.count(MealLogItem.id))
        .join(FoodItem, FoodItem.category_id == FoodCategory.id)
        .join(MealLogItem, MealLogItem.food_item_id == FoodItem.id)
        .group_by(FoodCategory.id, FoodCategory.name, FoodCategory.type)
        .order_by(func.count(MealLogItem.id).desc())
        .limit(10)
        .all()
    )
    category_popularity = [{'name': _label(name, ctype), 'count': count} for name, ctype, count in popularity_rows]

    return jsonify({
        'total_members': total_members,
        'members_this_week': members_this_week,
        'total_menu_items': total_menu_items,
        'total_categories': total_categories,
        'today_activity': today_activity,
        'activity_delta_pct': activity_delta_pct,
        'weekly_trend': weekly_trend,
        'category_breakdown': category_breakdown,
        'category_popularity': category_popularity,
    })


# =========================
# New admin dashboard (redesign) — 5 endpoint แยกกัน ตัวเลขล้วนมาจาก
# meal_logs/meal_log_items/users/reports จริง ไม่ใช่ Submission (คนละความหมาย
# กับ /dashboard-stats เดิมด้านบนที่ยังคงไว้เผื่อหน้าอื่นใช้อยู่)
# =========================

@admin_bp.route('/dashboard/summary', methods=['GET'])
def admin_dashboard_summary():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)

    now = get_thailand_time()
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_ago = today_start - timedelta(days=6)

    total_members = User.query.filter_by(is_deleted=False).count()
    new_members_7d = User.query.filter(
        User.is_deleted == False,
        User.created_at >= week_ago,
    ).count()
    meals_logged_today = MealLog.query.filter(MealLog.log_date == now.date()).count()
    pending_tickets = Report.query.filter_by(status='pending').count()

    return jsonify({
        'total_members': total_members,
        'new_members_7d': new_members_7d,
        'meals_logged_today': meals_logged_today,
        'pending_tickets': pending_tickets,
    })


@admin_bp.route('/dashboard/meal-trend', methods=['GET'])
def admin_dashboard_meal_trend():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)

    today = get_thailand_time().date()
    raw_days = request.args.get('days', '30')
    if raw_days == 'all':
        # โหมด "ทั้งหมด" — ไม่ cap เลย เริ่มจากมื้ออาหารแรกสุดที่เคยบันทึกไว้จริง
        # (ไม่มี log เลยก็ start = today ไป loop รอบเดียวคืน trend ว่าง)
        earliest = db.session.query(func.min(MealLog.log_date)).scalar()
        start = earliest or today
        days = (today - start).days + 1
    else:
        try:
            # เดิม cap ไว้แค่ 90 วัน — หน้าแดชบอร์ดตอนนี้มีฟิลเตอร์วัน/เดือน/ปี
            # โหมด "ปี" ต้องดึงย้อนหลังได้เกิน 1 ไตรมาสถึงจะรวมเป็นแท่งรายเดือน/
            # รายปีได้จริง ขยับ cap เป็น 366 วัน (1 ปีเต็ม) พอสำหรับทั้ง 3 โหมด
            days = max(1, min(int(raw_days), 366))
        except (TypeError, ValueError):
            days = 30
        start = today - timedelta(days=days - 1)

    # eager-load items กัน N+1 ตอนเช็ค any(it.is_eaten ...) ต่อ log
    logs = (
        MealLog.query.options(selectinload(MealLog.items))
        .filter(MealLog.log_date >= start, MealLog.log_date <= today)
        .all()
    )
    by_day = {}
    for log in logs:
        d = log.log_date.isoformat()
        entry = by_day.setdefault(d, {'planned': 0, 'eaten': 0})
        entry['planned'] += 1
        if any(it.is_eaten for it in log.items):
            entry['eaten'] += 1

    trend = []
    for i in range(days):
        d = (start + timedelta(days=i)).isoformat()
        entry = by_day.get(d, {'planned': 0, 'eaten': 0})
        trend.append({'date': d, 'planned': entry['planned'], 'eaten': entry['eaten']})

    return jsonify({'trend': trend})


def _optional_days_arg():
    """?days=N ใช้ร่วมกันสำหรับฟิลเตอร์ วัน/เดือน/ปี ของกราฟที่นับ event จาก
    meal_logs — ไม่ส่งมาเลย (None) แปลว่าไม่กรอง (all-time เหมือนเดิม) ต่างจาก
    /dashboard/meal-trend ที่ days บังคับมีค่าเสมอ เพราะสองกราฟนี้ไม่มี default
    ช่วงเวลาที่ตายตัว"""
    raw = request.args.get('days')
    if not raw:
        return None
    try:
        return max(1, min(int(raw), 366))
    except (TypeError, ValueError):
        return None


@admin_bp.route('/dashboard/food-type-dist', methods=['GET'])
def admin_dashboard_food_type_dist():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)

    days = _optional_days_arg()

    q = (
        db.session.query(FoodCategory.type, func.count(MealLogItem.id))
        .join(FoodItem, FoodItem.category_id == FoodCategory.id)
        .join(MealLogItem, MealLogItem.food_item_id == FoodItem.id)
        .filter(MealLogItem.is_eaten == True)
    )
    if days is not None:
        # ฟิลเตอร์ "วัน/เดือน/ปี" ที่หน้าแดชบอร์ดขอ — นับเฉพาะเมนูที่ทานจริง
        # ในมื้อที่ log_date อยู่ในช่วง N วันย้อนหลังเท่านั้น (ใช้ตัวเลขเดียวกับ
        # /dashboard/meal-trend: 1/30/366 วัน สำหรับวัน/เดือน/ปี)
        start = get_thailand_time().date() - timedelta(days=days - 1)
        q = q.join(MealLog, MealLog.id == MealLogItem.meal_log_id).filter(MealLog.log_date >= start)
    rows = q.group_by(FoodCategory.type).all()
    distribution = [{'type': t, 'count': c} for t, c in rows]
    return jsonify({'distribution': distribution})


@admin_bp.route('/dashboard/top-foods', methods=['GET'])
def admin_dashboard_top_foods():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)

    try:
        limit = max(1, min(int(request.args.get('limit', 10)), 50))
    except (TypeError, ValueError):
        limit = 10
    days = _optional_days_arg()

    q = (
        db.session.query(FoodItem.id, FoodItem.name, FoodItem.name_th, func.count(MealLogItem.id))
        .join(MealLogItem, MealLogItem.food_item_id == FoodItem.id)
        .filter(MealLogItem.is_eaten == True)
    )
    if days is not None:
        start = get_thailand_time().date() - timedelta(days=days - 1)
        q = q.join(MealLog, MealLog.id == MealLogItem.meal_log_id).filter(MealLog.log_date >= start)
    rows = (
        q.group_by(FoodItem.id, FoodItem.name, FoodItem.name_th)
        .order_by(func.count(MealLogItem.id).desc())
        .limit(limit)
        .all()
    )
    top_foods = [{'id': i, 'name': (name_th or name), 'count': cnt} for i, name, name_th, cnt in rows]
    return jsonify({'top_foods': top_foods})


@admin_bp.route('/dashboard/goal-dist', methods=['GET'])
def admin_dashboard_goal_dist():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)

    rows = (
        db.session.query(User.health_goal, func.count(User.id))
        .filter(User.is_deleted == False)
        .group_by(User.health_goal)
        .all()
    )
    distribution = [{'health_goal': (g or 'ยังไม่ระบุ'), 'count': c} for g, c in rows]
    return jsonify({'distribution': distribution})


@admin_bp.route('/dashboard/gender-dist', methods=['GET'])
def admin_dashboard_gender_dist():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)

    rows = (
        db.session.query(User.gender, func.count(User.id))
        .filter(User.is_deleted == False)
        .group_by(User.gender)
        .all()
    )
    # ใช้เกณฑ์เดียวกับ health_calc.calc_tdee ที่ตรวจ 'หญิง'/'female'/'f'
    # เพื่อไม่ให้มีจุดเช็คเพศซ้ำกันคนละมาตรฐานในระบบ
    male = female = unspecified = 0
    for g, c in rows:
        gnorm = (g or '').strip().lower()
        if gnorm in ('ชาย', 'male', 'm'):
            male += c
        elif gnorm in ('หญิง', 'female', 'f'):
            female += c
        else:
            unspecified += c
    return jsonify({'male': male, 'female': female, 'unspecified': unspecified})


@admin_bp.route('/dashboard/allergen-stats', methods=['GET'])
def admin_dashboard_allergen_stats():
    """ความถี่สารก่อภูมิแพ้ทั้งหมดที่ผู้ใช้ระบุไว้ — food_allergies เป็น JSON
    array นับความถี่ต้องทำฝั่ง Python (ไม่ใช่ SQL GROUP BY ตรงๆ เพราะเป็น
    array ในคอลัมน์เดียว ไม่ใช่ 1 แถวต่อ 1 ค่า)"""
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)

    counts = {}
    for u in User.query.filter_by(is_deleted=False).all():
        allergies = u.food_allergies
        if isinstance(allergies, list):
            # set() กัน user ที่ food_allergies ตัวเองมีชื่อซ้ำ (data-entry
            # ผิดพลาดจุดอื่น) มานับเป็น 2 คน — นับ "กี่คนแพ้สิ่งนี้" ไม่ใช่
            # "มีชื่อนี้ปรากฏกี่ครั้งรวม" (เหมือน pattern ที่ _serialize_food_item
            # ใช้ set(user.food_allergies) ตรวจ allergy_warning อยู่แล้ว)
            for a in set(allergies):
                counts[a] = counts.get(a, 0) + 1

    distribution = sorted(
        ({'allergen': name, 'count': c} for name, c in counts.items()),
        key=lambda row: row['count'],
        reverse=True,
    )
    return jsonify({'distribution': distribution}), 200


@admin_bp.route('/dashboard/menu-completeness', methods=['GET'])
def admin_dashboard_menu_completeness():
    """เมนูที่ยังขาดข้อมูลสำคัญ — allergens_reviewed มาจากงานที่ 4 (CSV
    import) column เดียวกัน ไม่ ALTER ซ้ำ"""
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)

    items = FoodItem.query.options(selectinload(FoodItem.serving_sizes)).all()

    def _brief(item):
        return {'id': item.id, 'name': item.name_th or item.name}

    return jsonify({
        'missing_image': [_brief(i) for i in items if not i.image_url],
        'missing_serving_sizes': [_brief(i) for i in items if not i.serving_sizes],
        'not_yet_allergen_reviewed': [_brief(i) for i in items if not i.allergens_reviewed],
    }), 200


def _category_dict(c):
    return {
        'id': c.id,
        'type': c.type,
        'name': c.name,
        'menu_count': len(c.items or []),
    }


# 3 หัวข้อนี้ผูก logic ไว้นอกหน้า admin ด้วย (endpoint สุ่ม/แนะนำเมนูและแอป
# มือถือใน api.py hardcode รับแค่ 3 ค่านี้) ห้ามแก้ชื่อ/ลบผ่าน food-types
# endpoint ด้านล่าง กันข้อมูลเสียหายไปถึงฝั่งนั้น
PROTECTED_FOOD_TYPES = ('food', 'drink', 'dessert')


@admin_bp.route('/food-categories', methods=['POST'])
def create_food_category():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    data = request.get_json(silent=True) or {}
    cat_type = (data.get('type') or '').strip()
    name = (data.get('name') or '').strip()
    if not cat_type or not name:
        return error_response("type and name required", 400)
    # หมวดหมู่ย่อยสร้างได้เฉพาะใต้หัวข้อที่มีอยู่จริงแล้ว (built-in หรือหัวข้อที่
    # แอดมินสร้างผ่าน POST /admin/food-types มาก่อน) กันหมวดหมู่หลุดไปอยู่ใต้
    # หัวข้อพิมพ์ผิด/ไม่มีจริง
    if cat_type not in PROTECTED_FOOD_TYPES and not FoodType.query.filter_by(name=cat_type).first():
        return error_response('ไม่พบหัวข้อนี้ สร้างหัวข้อก่อนเพิ่มหมวดหมู่', 404)
    dup = FoodCategory.query.filter(
        FoodCategory.type == cat_type,
        func.lower(FoodCategory.name) == name.lower(),
    ).first()
    if dup:
        return error_response('มีหมวดหมู่นี้อยู่แล้วในประเภทนี้', 409)
    c = FoodCategory(type=cat_type, name=name)
    db.session.add(c)
    db.session.flush()
    _log_admin_action('create', 'food_category', c.id, detail=f'{cat_type}/{name}')
    db.session.commit()
    return jsonify(_category_dict(c)), 201


@admin_bp.route('/food-categories/<int:category_id>', methods=['PUT'])
def rename_food_category(category_id):
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    c = FoodCategory.query.get(category_id)
    if not c:
        return error_response('not_found', 404)
    data = request.get_json(silent=True) or {}
    name = (data.get('name') or '').strip()
    if not name:
        return error_response('name required', 400)
    dup = FoodCategory.query.filter(
        FoodCategory.type == c.type,
        FoodCategory.id != category_id,
        func.lower(FoodCategory.name) == name.lower(),
    ).first()
    if dup:
        return error_response('มีหมวดหมู่นี้อยู่แล้วในประเภทนี้', 409)
    c.name = name
    _log_admin_action('update', 'food_category', c.id, detail=f'renamed to {name}')
    db.session.commit()
    return jsonify(_category_dict(c))


@admin_bp.route('/food-categories/<int:category_id>', methods=['DELETE'])
def delete_food_category(category_id):
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    c = FoodCategory.query.get(category_id)
    if not c:
        return error_response('not_found', 404)
    item_count = FoodItem.query.filter_by(category_id=category_id).count()
    if item_count > 0:
        return error_response(f'ลบไม่ได้ เพราะยังมีเมนูผูกอยู่ {item_count} รายการ', 400)
    _log_admin_action('delete', 'food_category', category_id, detail=c.name)
    db.session.delete(c)
    db.session.commit()
    return jsonify({'status': 'deleted', 'id': category_id})


def _ensure_builtin_food_types():
    """food/drink/dessert ต้องมีแถวใน FoodType ด้วยเหมือนหัวข้อที่แอดมินเพิ่มเอง
    ไม่งั้นลาก reorder ปนกับหัวข้อ built-in ไม่ได้ (ไม่มีแถวให้ update sort_order)
    — เรียกทุกครั้งที่ list เผื่อ DB เก่ายังไม่มี insert ไว้ตอน seed แรก
    ป้องกัน (แก้ชื่อ/ลบ) ยังเช็คจาก PROTECTED_FOOD_TYPES แยกอยู่ดี ไม่เกี่ยวกับตรงนี้"""
    existing = {t.name for t in FoodType.query.filter(FoodType.name.in_(PROTECTED_FOOD_TYPES)).all()}
    missing = [n for n in PROTECTED_FOOD_TYPES if n not in existing]
    if not missing:
        return
    for i, name in enumerate(PROTECTED_FOOD_TYPES):
        if name in missing:
            db.session.add(FoodType(name=name, sort_order=i))
    db.session.commit()


# หัวข้อทุกหัวข้อ (ทั้ง built-in และที่แอดมินเพิ่มเอง) มีแถวใน FoodType เพื่อให้
# ลาก reorder ปนกันได้อย่างเดียว — ป้องกันแก้ชื่อ/ลบยังคงแยกเช็คจาก
# PROTECTED_FOOD_TYPES เหมือนเดิม (ตำแหน่งขยับได้ แต่ชื่อ/ลบไม่ได้)
@admin_bp.route('/food-types', methods=['GET'])
def list_food_types():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    _ensure_builtin_food_types()
    types = FoodType.query.order_by(FoodType.sort_order, FoodType.id).all()
    return jsonify({'types': [{'id': t.id, 'name': t.name, 'sort_order': t.sort_order} for t in types]})


@admin_bp.route('/food-types', methods=['POST'])
def create_food_type():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    data = request.get_json(silent=True) or {}
    name = (data.get('name') or '').strip()
    if not name or len(name) > 30:
        return error_response('ชื่อหัวข้อห้ามว่างและยาวไม่เกิน 30 ตัวอักษร', 400)
    if name in PROTECTED_FOOD_TYPES or FoodType.query.filter(func.lower(FoodType.name) == name.lower()).first():
        return error_response('มีหัวข้อนี้อยู่แล้ว', 409)
    next_order = (db.session.query(func.max(FoodType.sort_order)).scalar() or 0) + 1
    t = FoodType(name=name, sort_order=next_order)
    db.session.add(t)
    db.session.flush()
    _log_admin_action('create', 'food_type', t.id, detail=name)
    db.session.commit()
    return jsonify({'id': t.id, 'name': t.name, 'sort_order': t.sort_order}), 201


@admin_bp.route('/food-types/reorder', methods=['PUT'])
def reorder_food_types():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    data = request.get_json(silent=True) or {}
    order = data.get('order')
    if not isinstance(order, list):
        return error_response('order must be a list of type names', 400)
    for i, name in enumerate(order):
        FoodType.query.filter_by(name=name).update({'sort_order': i})
    db.session.commit()
    return jsonify({'status': 'reordered'})


@admin_bp.route('/food-types/<old_type>', methods=['PUT'])
def rename_food_type(old_type):
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    if old_type in PROTECTED_FOOD_TYPES:
        return error_response('แก้ไขหัวข้อหลักของระบบไม่ได้', 400)
    t = FoodType.query.filter_by(name=old_type).first()
    if not t:
        return error_response('not_found', 404)
    data = request.get_json(silent=True) or {}
    new_type = (data.get('name') or '').strip()
    if not new_type or len(new_type) > 30:
        return error_response('ชื่อหัวข้อห้ามว่างและยาวไม่เกิน 30 ตัวอักษร', 400)
    if new_type != old_type and (
        new_type in PROTECTED_FOOD_TYPES
        or FoodType.query.filter(func.lower(FoodType.name) == new_type.lower()).first()
    ):
        return error_response('มีหัวข้อนี้อยู่แล้ว', 409)
    t.name = new_type
    FoodCategory.query.filter_by(type=old_type).update({'type': new_type})
    _log_admin_action('update', 'food_type', t.id, detail=f'{old_type} -> {new_type}')
    db.session.commit()
    return jsonify({'type': new_type})


@admin_bp.route('/food-types/<type_name>', methods=['DELETE'])
def delete_food_type(type_name):
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    if type_name in PROTECTED_FOOD_TYPES:
        return error_response('ลบหัวข้อหลักของระบบไม่ได้', 400)
    t = FoodType.query.filter_by(name=type_name).first()
    if not t:
        return error_response('not_found', 404)
    cats = FoodCategory.query.filter_by(type=type_name).all()
    item_count = FoodItem.query.filter(FoodItem.category_id.in_([c.id for c in cats])).count() if cats else 0
    if item_count > 0:
        return error_response(f'ลบไม่ได้ เพราะยังมีเมนูผูกอยู่ {item_count} รายการ', 400)
    for c in cats:
        db.session.delete(c)
    db.session.delete(t)
    _log_admin_action('delete', 'food_type', t.id, detail=type_name)
    db.session.commit()
    return jsonify({'status': 'deleted', 'type': type_name})


def _validate_nutrition_numbers(data, fields):
    for f in fields:
        if f in data and data.get(f) is not None and data.get(f) != '':
            try:
                if float(data.get(f)) < 0:
                    return f'{f} ต้องไม่ติดลบ'
            except (TypeError, ValueError):
                return f'{f} ต้องเป็นตัวเลข'
    return None


_FOOD_ITEM_NUMERIC_FIELDS = ('calories', 'protein_g', 'carbs_g', 'fat_g', 'fiber_g', 'sugar_g', 'iron_mg', 'vitamin_c_mg')


def _food_item_dict(item):
    return {
        'id': item.id,
        'category_id': item.category_id,
        'category_type': item.category.type if item.category else None,
        'name': item.name,
        'name_th': item.name_th,
        'calories': item.calories,
        'protein_g': item.protein_g,
        'carbs_g': item.carbs_g,
        'fat_g': item.fat_g,
        'fiber_g': item.fiber_g,
        'sugar_g': item.sugar_g,
        'iron_mg': item.iron_mg,
        'vitamin_c_mg': item.vitamin_c_mg,
        'image_url': item.image_url,
        'swap_food_id': item.swap_food_id,
        'upgrade_tips': item.upgrade_tips,
        'is_active': bool(item.is_active),
        'allergens_reviewed': bool(item.allergens_reviewed),
        'serving_sizes': [{
            'id': s.id, 'unit_name': s.unit_name, 'unit_name_th': s.unit_name_th,
            'calories_multiplier': s.calories_multiplier, 'grams_approx': s.grams_approx,
        } for s in item.serving_sizes],
        'allergen_ids': [a.id for a in item.allergens],
    }


@admin_bp.route('/food-items', methods=['GET'])
def admin_list_food_items():
    """Consolidated admin catalog — replaces the old separate food/dessert/drink
    menu CRUD (one table, filter by category type instead)."""
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    q = FoodItem.query.join(FoodCategory)
    cat_type = request.args.get('type')
    if cat_type:
        q = q.filter(FoodCategory.type == cat_type)
    items = q.order_by(FoodItem.id.desc()).limit(1000).all()
    return jsonify({'items': [_food_item_dict(i) for i in items]})


@admin_bp.route('/food-items', methods=['POST'])
def admin_create_food_item():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    data = request.get_json(silent=True) or {}
    name = (data.get('name') or '').strip()
    raw_category_id = data.get('category_id')
    if not name or not raw_category_id:
        return error_response('name and category_id required', 400)
    # รับได้ทั้ง int และ string ตัวเลข เหมือน admin_update_food_item ด้านล่าง
    try:
        category_id = int(raw_category_id)
    except (TypeError, ValueError):
        return error_response('category_id ต้องเป็นตัวเลข', 400, 'VALIDATION_ERROR')
    if not FoodCategory.query.get(category_id):
        return error_response('category_id not found', 404)
    raw_swap_id = data.get('swap_food_id')
    swap_food_id = None
    if raw_swap_id not in (None, ''):
        try:
            swap_food_id = int(raw_swap_id)
        except (TypeError, ValueError):
            return error_response('swap_food_id ต้องเป็นตัวเลข', 400, 'VALIDATION_ERROR')
    err = _validate_nutrition_numbers(data, _FOOD_ITEM_NUMERIC_FIELDS)
    if err:
        return error_response(err, 400)
    item = FoodItem(
        category_id=category_id,
        name=name,
        name_th=(data.get('name_th') or '').strip() or None,
        image_url=(data.get('image_url') or '').strip() or None,
        upgrade_tips=(data.get('upgrade_tips') or '').strip() or None,
        swap_food_id=swap_food_id,
        is_active=bool(data.get('is_active', True)),
    )
    for f in _FOOD_ITEM_NUMERIC_FIELDS:
        if f in data and data.get(f) not in (None, ''):
            setattr(item, f, float(data[f]))
    db.session.add(item)
    db.session.flush()
    _log_admin_action('create', 'food_item', item.id, detail=name)
    db.session.commit()
    return jsonify(_food_item_dict(item)), 201


@admin_bp.route('/food-items/<int:item_id>', methods=['PUT'])
def admin_update_food_item(item_id):
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    item = FoodItem.query.get(item_id)
    if not item:
        return error_response('not_found', 404)
    data = request.get_json(silent=True) or {}
    err = _validate_nutrition_numbers(data, _FOOD_ITEM_NUMERIC_FIELDS)
    if err:
        return error_response(err, 400)
    if 'name' in data and (data.get('name') or '').strip():
        item.name = data['name'].strip()
    if 'name_th' in data:
        item.name_th = (data.get('name_th') or '').strip() or None
    if 'category_id' in data and data.get('category_id'):
        # รับได้ทั้ง int และ string ตัวเลข (Mantine Select ส่ง value เป็น
        # string เสมอ) — เดิมไม่มี validate/coerce เลย อาศัย MySQL implicit
        # cast ให้เฉยๆ (บั๊กที่เจอจริง ดู MenuFoodModal.jsx)
        try:
            category_id = int(data['category_id'])
        except (TypeError, ValueError):
            return error_response('category_id ต้องเป็นตัวเลข', 400, 'VALIDATION_ERROR')
        if not FoodCategory.query.get(category_id):
            return error_response('category_id not found', 404)
        item.category_id = category_id
    if 'image_url' in data:
        item.image_url = (data.get('image_url') or '').strip() or None
    if 'upgrade_tips' in data:
        item.upgrade_tips = (data.get('upgrade_tips') or '').strip() or None
    if 'swap_food_id' in data:
        raw_swap_id = data.get('swap_food_id')
        if raw_swap_id in (None, ''):
            item.swap_food_id = None
        else:
            try:
                item.swap_food_id = int(raw_swap_id)
            except (TypeError, ValueError):
                return error_response('swap_food_id ต้องเป็นตัวเลข', 400, 'VALIDATION_ERROR')
    if 'is_active' in data:
        item.is_active = bool(data.get('is_active'))
    for f in _FOOD_ITEM_NUMERIC_FIELDS:
        if f in data and data.get(f) not in (None, ''):
            setattr(item, f, float(data[f]))

    _log_admin_action('update', 'food_item', item.id, detail=item.name)
    db.session.commit()
    return jsonify(_food_item_dict(item))


@admin_bp.route('/food-items/<int:item_id>', methods=['DELETE'])
def admin_delete_food_item(item_id):
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)

    item = FoodItem.query.get(item_id)
    if not item:
        return error_response('not_found', 404)

    # Remove dependent rows before deleting the food item so MySQL foreign-key
    # constraints are satisfied. This is intentionally scoped to the food-item
    # delete flow and does not modify unrelated admin logic.
    MealLogItem.query.filter_by(food_item_id=item_id).delete(synchronize_session=False)
    UserFavoriteFood.query.filter_by(food_item_id=item_id).delete(synchronize_session=False)
    ServingSize.query.filter_by(food_item_id=item_id).delete(synchronize_session=False)
    db.session.execute(
        food_allergens.delete().where(food_allergens.c.food_item_id == item_id)
    )
    FoodItem.query.filter_by(swap_food_id=item_id).update({FoodItem.swap_food_id: None})

    _log_admin_action('delete', 'food_item', item_id, detail=item.name)
    db.session.delete(item)
    db.session.commit()
    return jsonify({'status': 'deleted', 'id': item_id})


_CSV_IMPORT_NUMERIC_FIELDS = ('calories', 'protein_g', 'carbs_g', 'fat_g', 'fiber_g', 'sugar_g')


def _parse_import_row(row):
    """ตรวจ+เตรียมข้อมูล 1 แถวจาก CSV ล้วนๆ ไม่แตะ DB เลย — ให้ dry_run กับ
    การเขียนจริงใช้ตรรกะตรวจสอบเดียวกันเป๊ะ พรีวิวจึงไม่มีทางไม่ตรงกับผลจริง
    คืน (parsed_dict หรือ None, error_message หรือ None, warning_message หรือ None)"""
    name = (row.get('name') or '').strip()
    if not name:
        return None, 'ไม่มีชื่อเมนู (name)', None

    category_name = (row.get('category_name') or '').strip()
    if not category_name:
        return None, 'ไม่มีชื่อหมวดหมู่ (category_name)', None

    parsed = {
        'name': name,
        'name_th': (row.get('name_th') or '').strip() or None,
        'category_name': category_name,
        'image_url': (row.get('image_url') or '').strip() or None,
    }

    for f in _CSV_IMPORT_NUMERIC_FIELDS:
        raw = (row.get(f) or '').strip()
        if raw == '':
            parsed[f] = None
            continue
        try:
            val = float(raw)
        except ValueError:
            return None, f'{f} ต้องเป็นตัวเลข (ได้ค่า {raw!r})', None
        if val < 0:
            return None, f'{f} ต้องไม่ติดลบ', None
        parsed[f] = val

    warning = None
    cal, p, c, fa = parsed['calories'], parsed['protein_g'], parsed['carbs_g'], parsed['fat_g']
    if cal is not None and cal > 0 and None not in (p, c, fa):
        expected = calc_calories_from_macros(c, p, fa)
        pct = abs(expected - cal) / cal * 100
        if pct > 10:
            warning = f'calories ({cal}) ต่างจากที่คำนวณจากสูตร 4/4/9 ({expected:.1f}) เกิน 10% ({pct:.1f}%)'

    return parsed, None, warning


@admin_bp.route('/food-items/import', methods=['POST'])
def admin_import_food_items():
    """นำเข้าเมนูจาก CSV — คอลัมน์: name, name_th, category_name, calories,
    protein_g, carbs_g, fat_g, fiber_g, sugar_g, image_url โดย category_name
    ต้องตรงกับหมวดหมู่ย่อยที่มีอยู่ในหัวข้อที่ส่งมากับ request
    """
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)

    category_type = (request.args.get('type') or '').strip()
    if not category_type:
        return error_response('ต้องระบุประเภทหัวข้อเมนู (type)', 400)
    if (
        category_type not in PROTECTED_FOOD_TYPES
        and not FoodType.query.filter_by(name=category_type).first()
    ):
        return error_response('ไม่พบหัวข้อเมนูที่ระบุ', 400)

    file = request.files.get('file') or request.files.get('csv')
    if not file:
        return error_response('ต้องแนบไฟล์ CSV (multipart field name: file)', 400)

    # dry_run เป็นค่า default (ปลอดภัยไว้ก่อน) — ต้องส่ง ?dry_run=false ชัดเจน
    # ถึงจะเขียนจริง กันแอดมินเผลอกดครั้งแรกแล้วข้อมูลเข้า DB ทันทีโดยไม่ได้ดู
    # ผล preview ก่อน
    dry_run = request.args.get('dry_run', 'true').strip().lower() != 'false'

    try:
        text_data = file.read().decode('utf-8-sig')
    except UnicodeDecodeError:
        return error_response('ไฟล์ CSV ต้องเป็น UTF-8', 400)
    reader = csv.DictReader(io.StringIO(text_data))
    if reader.fieldnames is None:
        return error_response('ไฟล์ CSV ว่างเปล่าหรืออ่านหัวตารางไม่ได้', 400)

    existing_categories = {
        c.name: c for c in FoodCategory.query.filter_by(type=category_type).all()
    }

    results = []
    to_create = []  # (row_result, parsed) — เฉพาะแถวที่ผ่าน validation แล้ว

    for i, row in enumerate(reader, start=2):  # แถว 1 คือ header
        parsed, error, warning = _parse_import_row(row)
        if not error and parsed['category_name'] not in existing_categories:
            error = (
                f'ไม่พบหมวดหมู่ "{parsed["category_name"]}" '
                f'ในหัวข้อ "{category_type}"'
            )
        if error:
            results.append({
                'row': i,
                'name': (row.get('name') or '').strip() or None,
                'category_name': (row.get('category_name') or '').strip() or None,
                'status': 'error',
                'error': error,
            })
            continue
        row_result = {
            'row': i,
            'name': parsed['name'],
            'category_name': parsed['category_name'],
            'status': 'would_create' if dry_run else 'pending',
        }
        if warning:
            row_result['warning'] = warning
        results.append(row_result)
        to_create.append((row_result, parsed))

    if dry_run:
        return jsonify({
            'dry_run': True,
            'total_rows': len(results),
            'would_create_count': len(to_create),
            'error_count': sum(1 for r in results if r['status'] == 'error'),
            'new_categories': [],
            'results': results,
        }), 200

    created_count = 0
    for row_result, parsed in to_create:
        cat_name = parsed['category_name']
        cat = existing_categories[cat_name]
        try:
            with db.session.begin_nested():
                item = FoodItem(
                    category_id=cat.id,
                    name=parsed['name'],
                    name_th=parsed['name_th'],
                    image_url=parsed['image_url'],
                    calories=parsed['calories'],
                    protein_g=parsed['protein_g'],
                    carbs_g=parsed['carbs_g'],
                    fat_g=parsed['fat_g'],
                    fiber_g=parsed['fiber_g'],
                    sugar_g=parsed['sugar_g'],
                    allergens_reviewed=False,
                    is_active=True,
                )
                db.session.add(item)
                db.session.flush()
            row_result['status'] = 'created'
            row_result['id'] = item.id
            created_count += 1
        except Exception as exc:
            row_result['status'] = 'error'
            row_result['error'] = f'สร้างเมนูไม่สำเร็จ: {exc}'

    db.session.commit()

    return jsonify({
        'dry_run': False,
        'total_rows': len(results),
        'created_count': created_count,
        'error_count': sum(1 for r in results if r['status'] == 'error'),
        'new_categories': [],
        'results': results,
    }), 200


@admin_bp.route('/food-items/<int:item_id>/serving-sizes', methods=['POST'])
def admin_add_serving_size(item_id):
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    item = FoodItem.query.get(item_id)
    if not item:
        return error_response('not_found', 404)
    data = request.get_json(silent=True) or {}
    unit_name = (data.get('unit_name') or '').strip()
    if not unit_name:
        return error_response('unit_name required', 400)
    # เดิมไม่มี validate ก่อน float() เลย (ต่างจาก endpoint เมนูอาหารข้างเคียง
    # ที่ใช้ _validate_nutrition_numbers) ค่าที่ไม่ใช่ตัวเลขจะโยน ValueError
    # ดิบ กลายเป็น 500 generic error แทน 400 ที่บอกสาเหตุชัดเจน
    err = _validate_nutrition_numbers(data, ('calories_multiplier', 'grams_approx'))
    if err:
        return error_response(err, 400, 'VALIDATION_ERROR')
    s = ServingSize(
        food_item_id=item.id,
        unit_name=unit_name,
        unit_name_th=(data.get('unit_name_th') or '').strip() or None,
        calories_multiplier=float(data.get('calories_multiplier', 1.0) or 1.0),
        grams_approx=float(data['grams_approx']) if data.get('grams_approx') not in (None, '') else None,
    )
    db.session.add(s)
    db.session.commit()
    return jsonify({'id': s.id, 'unit_name': s.unit_name, 'unit_name_th': s.unit_name_th,
                     'calories_multiplier': s.calories_multiplier, 'grams_approx': s.grams_approx}), 201


@admin_bp.route('/allergens', methods=['GET'])
def admin_list_allergens():
    """Master list for the allergen checkbox picker — narrow addition, the
    existing POST /food-items/<id>/allergens needs ids the admin UI had no
    way to discover otherwise."""
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    rows = Allergen.query.order_by(Allergen.name.asc()).all()
    return jsonify({'allergens': [{'id': a.id, 'name': a.name} for a in rows]})


@admin_bp.route('/allergens', methods=['POST'])
def admin_create_allergen():
    """Body: { "name": "..." } — เพิ่มสารก่อภูมิแพ้ใหม่เข้า master list ตอนที่
    checkbox ที่มีอยู่ไม่ครอบคลุมเมนูบางอัน (ผู้ใช้รายงานจริง) เทียบชื่อแบบไม่
    สนตัวพิมพ์ใหญ่/เล็กก่อนสร้าง กัน 'กะทิ'/'กะทิ ' สร้างซ้ำเป็นคนละแถว."""
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    data = request.get_json(silent=True) or {}
    name = (data.get('name') or '').strip()
    if not name:
        return error_response('name required', 400, 'VALIDATION_ERROR')
    existing = Allergen.query.filter(db.func.lower(Allergen.name) == name.lower()).first()
    if existing:
        return jsonify({'id': existing.id, 'name': existing.name}), 200
    a = Allergen(name=name)
    db.session.add(a)
    db.session.commit()
    return jsonify({'id': a.id, 'name': a.name}), 201


@admin_bp.route('/allergens/<int:allergen_id>', methods=['PUT'])
def admin_update_allergen(allergen_id):
    """Body: { "name": "..." } — เปลี่ยนชื่อสารก่อภูมิแพ้ใน master list (ใช้
    ร่วมกันทุกเมนู ไม่ใช่แค่เมนูที่กำลังแก้อยู่)."""
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    a = Allergen.query.get(allergen_id)
    if not a:
        return error_response('not_found', 404)
    data = request.get_json(silent=True) or {}
    name = (data.get('name') or '').strip()
    if not name:
        return error_response('name required', 400, 'VALIDATION_ERROR')
    dup = Allergen.query.filter(
        db.func.lower(Allergen.name) == name.lower(), Allergen.id != allergen_id
    ).first()
    if dup:
        return error_response('มีสารก่อภูมิแพ้ชื่อนี้อยู่แล้ว', 400, 'VALIDATION_ERROR')
    a.name = name
    db.session.commit()
    return jsonify({'id': a.id, 'name': a.name})


@admin_bp.route('/allergens/<int:allergen_id>', methods=['DELETE'])
def admin_delete_allergen(allergen_id):
    """ลบสารก่อภูมิแพ้ออกจาก master list ทั้งระบบ — food_allergens ผูก
    ondelete='CASCADE' ไว้แล้ว (ดู models.py) เมนูที่เคยติ๊กตัวนี้ไว้จะหลุด
    ออกจากลิสต์ของเมนูนั้นไปด้วยอัตโนมัติ ไม่ต้อง loop ลบเองที่นี่."""
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    a = Allergen.query.get(allergen_id)
    if not a:
        return error_response('not_found', 404)
    db.session.delete(a)
    db.session.commit()
    return jsonify({'status': 'deleted', 'id': allergen_id})


@admin_bp.route('/food-items/<int:item_id>/serving-sizes/<int:serving_id>', methods=['PUT'])
def admin_update_serving_size(item_id, serving_id):
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    s = ServingSize.query.filter_by(id=serving_id, food_item_id=item_id).first()
    if not s:
        return error_response('not_found', 404)
    data = request.get_json(silent=True) or {}
    # เดิมไม่มี validate ก่อน float() เลย (ต่างจาก endpoint เมนูอาหารข้างเคียง
    # ที่ใช้ _validate_nutrition_numbers) ค่าที่ไม่ใช่ตัวเลขจะโยน ValueError
    # ดิบ กลายเป็น 500 generic error แทน 400 ที่บอกสาเหตุชัดเจน
    err = _validate_nutrition_numbers(data, ('calories_multiplier', 'grams_approx'))
    if err:
        return error_response(err, 400, 'VALIDATION_ERROR')
    if 'unit_name' in data and (data.get('unit_name') or '').strip():
        s.unit_name = data['unit_name'].strip()
    if 'unit_name_th' in data:
        s.unit_name_th = (data.get('unit_name_th') or '').strip() or None
    if 'calories_multiplier' in data and data.get('calories_multiplier') not in (None, ''):
        s.calories_multiplier = float(data['calories_multiplier'])
    if 'grams_approx' in data:
        s.grams_approx = float(data['grams_approx']) if data.get('grams_approx') not in (None, '') else None
    db.session.commit()
    return jsonify({'id': s.id, 'unit_name': s.unit_name, 'unit_name_th': s.unit_name_th,
                     'calories_multiplier': s.calories_multiplier, 'grams_approx': s.grams_approx})


@admin_bp.route('/food-items/<int:item_id>/serving-sizes/<int:serving_id>', methods=['DELETE'])
def admin_delete_serving_size(item_id, serving_id):
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    s = ServingSize.query.filter_by(id=serving_id, food_item_id=item_id).first()
    if not s:
        return error_response('not_found', 404)
    db.session.delete(s)
    db.session.commit()
    return jsonify({'status': 'deleted', 'id': serving_id})


@admin_bp.route('/food-items/<int:item_id>/allergens', methods=['POST'])
def admin_set_food_item_allergens(item_id):
    """Body: { "allergen_ids": [1,2,3] } — replaces the full allergen set for this item."""
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    item = FoodItem.query.get(item_id)
    if not item:
        return error_response('not_found', 404)
    data = request.get_json(silent=True) or {}
    allergen_ids = data.get('allergen_ids')
    if not isinstance(allergen_ids, list):
        return error_response('allergen_ids must be a list', 400)
    item.allergens = Allergen.query.filter(Allergen.id.in_(allergen_ids)).all()
    item.allergens_reviewed = True
    db.session.commit()
    return jsonify({'id': item.id, 'allergens': [a.name for a in item.allergens]})


@admin_bp.route('/reports', methods=['GET'])
def list_reports():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    query = Report.query
    status = request.args.get('status')
    if status == 'open':
        query = query.filter(Report.status != 'closed')
    elif status and status != 'all':
        query = query.filter_by(status=status)

    user_id = request.args.get('user_id')
    if user_id:
        try:
            query = query.filter_by(user_id=int(user_id))
        except Exception:
            pass

    reps = query.order_by(Report.created_at.desc(), Report.id.desc()).limit(500).all()

    user_ids = {r.user_id for r in reps}
    usernames = {}
    if user_ids:
        for u in User.query.filter(User.id.in_(user_ids)).all():
            usernames[u.id] = u.username

    out = []
    for r in reps:
        out.append({
            'id': r.id,
            'user_id': r.user_id,
            'username': usernames.get(r.user_id),
            'title': r.title,
            'message': r.message,
            'status': r.status,
            'admin_reply': r.admin_reply,
            'replied_at': r.replied_at.isoformat() if r.replied_at else None,
            'created_at': r.created_at.isoformat() if r.created_at else None
        })

    return jsonify({'reports': out})


@admin_bp.route('/users', methods=['GET'])
def list_all_users():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)

    search = (request.args.get('search') or '').strip()
    health_goal = (request.args.get('health_goal') or '').strip()
    gender = (request.args.get('gender') or '').strip()
    allergy = (request.args.get('allergy') or '').strip()
    sort = (request.args.get('sort') or 'username').strip()

    try:
        q = User.query
        # ทุกตัวกรองต่อกันด้วย .filter() ตามลำดับ = AND เสมอ (ไม่ใช่ OR) —
        # ค้นหาด้วยชื่อบางส่วน + กรอง health_goal พร้อมกันจะได้แค่แถวที่ตรง
        # ทั้งสองเงื่อนไข
        if search:
            like = f'%{search}%'
            q = q.filter(db.or_(
                User.username.ilike(like),
                User.email.ilike(like),
                User.name.ilike(like),
                User.surname.ilike(like),
            ))
        if health_goal:
            q = q.filter(User.health_goal == health_goal)
        if gender:
            q = q.filter(User.gender == gender)

        sort_columns = {'created_at': User.created_at, 'username': User.username}
        order_col = sort_columns.get(sort, User.username)
        rows = q.order_by(order_col.asc()).all()

        # allergy กรองฝั่ง Python — food_allergies เป็น JSON array ในคอลัมน์
        # เดียว ใช้ list membership ตรงไปตรงมา แทนพึ่งฟังก์ชัน JSON เฉพาะของ
        # MariaDB ที่เปราะบางต่างเวอร์ชัน (ผู้ใช้ในระบบนี้มีจำนวนจำกัด กรอง
        # ใน Python ที่นี่ไม่ใช่คอขวด)
        if allergy:
            rows = [u for u in rows if isinstance(u.food_allergies, list) and allergy in u.food_allergies]
    except Exception:
        return jsonify({'users': []})

    out = []
    for u in rows:
        out.append({
            'id': u.id,
            'username': u.username or f'user_{u.id}',
            'email': u.email,
            'gender': u.gender,
            'health_goal': u.health_goal,
            'food_allergies': u.food_allergies or [],
            'created_at': u.created_at.isoformat() if u.created_at else None,
            'is_admin': bool(getattr(u, 'is_admin', False)),
        })

    return jsonify({'users': out})


@admin_bp.route('/user/action', methods=['POST'])
def user_action():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    data = request.get_json(silent=True) or {}
    user_id = data.get('user_id')
    action = (data.get('action') or '').strip().lower()

    if not user_id or action not in ('approve', 'delete', 'make_admin'):
        return error_response('user_id and valid action required', 400)
    try:
        u = User.query.get(int(user_id))
    except Exception:
        u = None

    if not u:
        return error_response('user_not_found', 404)
    if action == 'delete' and getattr(u, 'is_admin', False):
        return error_response('cannot_delete_admin', 400)
    try:
        if action == 'approve':
            return jsonify({'status': 'approved', 'user_id': u.id}), 200

        if action == 'make_admin':
            # หน้า "ตรวจสอบข้อมูลสมาชิก" ใช้ปุ่มนี้ตั้งผู้ใช้ที่ต้องการเป็น
            # แอดมิน — ตั้งซ้ำกับคนที่เป็นแอดมินอยู่แล้วก็แค่ no-op ไม่ error
            u.is_admin = True
            db.session.add(u)
            _log_admin_action('promote_admin', 'user', u.id, detail=u.username)
            db.session.commit()
            return jsonify({'status': 'promoted', 'user_id': u.id}), 200

        # action == 'delete' — meal_logs/submissions/reports all CASCADE via
        # FK ON DELETE CASCADE, so no manual dependent-row cleanup needed.
        db.session.execute(text('DELETE FROM users WHERE id = :id'), {'id': int(user_id)})
        db.session.commit()
        return jsonify({'status': 'deleted', 'user_id': int(user_id)}), 200
    except Exception as exc:
        try:
            db.session.rollback()
        except Exception:
            pass
        return error_response('เกิดข้อผิดพลาดที่ฐานข้อมูล', 500, 'SERVER_ERROR', detail={'details': str(exc)})
def _serialize_report_message(m):
    return {
        'id': m.id,
        'report_id': m.report_id,
        'sender_type': m.sender_type,
        'message': m.message,
        'created_at': m.created_at.isoformat() if m.created_at else None,
    }


@admin_bp.route('/reports/<int:report_id>/messages', methods=['GET'])
def admin_report_messages(report_id):
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    r = Report.query.get(report_id)
    if not r:
        return error_response('not_found', 404)
    msgs = ReportMessage.query.filter_by(report_id=r.id).order_by(ReportMessage.created_at).all()
    return jsonify({
        'messages': [_serialize_report_message(m) for m in msgs],
        'status': r.status,
        'can_reply': r.status != 'closed',
    }), 200


@admin_bp.route('/reply', methods=['POST'])
def admin_reply():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    data = request.get_json(silent=True) or {}
    report_id = data.get('report_id')
    message = (data.get('message') or '').strip()

    if not report_id or not message:
        return error_response('report_id and message required', 400)
    try:
        r = Report.query.get(int(report_id))
        if not r:
            return error_response('not_found', 404)
        if r.status == 'closed':
            return error_response('เรื่องนี้ปิดแล้ว ไม่สามารถตอบเพิ่มได้', 409, 'TICKET_CLOSED')
        r.admin_reply = message
        r.status = 'replied'
        r.replied_at = get_thailand_time()
        db.session.add(ReportMessage(report_id=r.id, sender_type='admin', message=message))
        _log_admin_action('reply', 'report', r.id)
        db.session.commit()
        return jsonify({'status': 'ok', 'id': r.id, 'ticket_status': r.status}), 200
    except Exception as exc:
        try:
            db.session.rollback()
        except Exception:
            pass
        return error_response('เกิดข้อผิดพลาดที่ฐานข้อมูล', 500, 'SERVER_ERROR', detail={'details': str(exc)})
@admin_bp.route('/close_report', methods=['POST'])
def admin_close_report():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    data = request.get_json(silent=True) or {}
    report_id = data.get('report_id')
    if not report_id:
        return error_response('report_id required', 400)
    try:
        r = Report.query.get(int(report_id))
        if not r:
            return error_response('not_found', 404)
        r.status = 'closed'
        _log_admin_action('close', 'report', r.id)
        db.session.commit()
        return jsonify({'status': 'ok', 'id': r.id, 'ticket_status': r.status}), 200
    except Exception as exc:
        try:
            db.session.rollback()
        except Exception:
            pass
        return error_response('เกิดข้อผิดพลาดที่ฐานข้อมูล', 500, 'SERVER_ERROR', detail={'details': str(exc)})
@admin_bp.route('/user/<int:user_id>/delete', methods=['POST'])
def delete_user(user_id):
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    user = User.query.get(user_id)
    if not user:
        return error_response('not_found', 404)
    if getattr(user, 'is_admin', False):
        return error_response('cannot_delete_admin', 400)
    data = request.get_json(silent=True) or {}
    reason = (data.get('reason') or '').strip()
    if not reason:
        return error_response('reason_required', 400)
    try:
        # Keep the user's history and submissions intact so the admin can
        # still review and potentially restore the user later.
        # Also invalidate any existing login token immediately.
        user.is_deleted = True
        user.delete_reason = reason
        user.deleted_at = get_thailand_time()
        user.password_token = None
        user.token_created_at = None
        db.session.add(user)
        _log_admin_action('delete', 'user', user.id, detail=reason)
        db.session.commit()
        return jsonify({'status': 'deleted', 'user_id': user.id}), 200
    except Exception as exc:
        try:
            db.session.rollback()
        except Exception:
            pass
        return error_response('เกิดข้อผิดพลาดที่ฐานข้อมูล', 500, 'SERVER_ERROR', detail={'details': str(exc)})
@admin_bp.route('/user/<int:user_id>/restore', methods=['POST'])
def restore_user(user_id):
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    user = User.query.get(user_id)
    if not user:
        return error_response('not_found', 404)
    if getattr(user, 'is_admin', False):
        return error_response('cannot_restore_admin', 400)
    try:
        user.is_deleted = False
        user.delete_reason = None
        user.deleted_at = None
        db.session.add(user)
        _log_admin_action('restore', 'user', user.id)
        db.session.commit()
        return jsonify({'status': 'restored', 'user_id': user.id}), 200
    except Exception as exc:
        try:
            db.session.rollback()
        except Exception:
            pass
        return error_response('เกิดข้อผิดพลาดที่ฐานข้อมูล', 500, 'SERVER_ERROR', detail={'details': str(exc)})


# =========================
# SUBMISSIONS REVIEW
# =========================

def _current_admin_user():
    """คืน User object ของแอดมินที่ login ผ่าน session จริง — คืน None ถ้า
    auth ผ่าน X-Admin-Secret ล้วนๆ ที่ไม่ได้ผูกกับ user คนไหนเจาะจง ใช้บันทึก
    ว่า "ใครทำ" ในจุดที่ต้องมีความรับผิดชอบ (reviewed_by, admin_action_log)"""
    user_id = session.get('admin_user_id')
    if not user_id:
        return None
    return User.query.get(user_id)


def _log_admin_action(action, entity_type, entity_id=None, detail=None):
    """บันทึก 1 แถวใน admin_action_log — ข้ามเงียบๆ ถ้าไม่รู้ว่าเป็นแอดมิน
    คนไหน (auth ผ่าน X-Admin-Secret ล้วนๆ ไม่ผูก session) เพราะ
    admin_user_id เป็น NOT NULL ตาม schema ที่กำหนด ไม่มี "ใคร" จริงจะ log
    ไม่ได้อยู่แล้ว — เรียกหลังจาก action สำเร็จเท่านั้น (commit ไปแล้ว หรือ
    กำลังจะ commit พร้อมกันในธุรกรรมเดียวกัน)"""
    admin = _current_admin_user()
    if admin is None:
        return
    db.session.add(AdminActionLog(
        admin_user_id=admin.id, action=action, entity_type=entity_type,
        entity_id=entity_id, detail=detail,
    ))


def _submission_dict(s):
    return {
        'id': s.id,
        'user_id': s.user_id,
        'anon_id': s.anon_id,
        'name_th': s.name_th,
        'name_en': s.name_en,
        'item_type': s.item_type,
        'detail': s.detail,
        'status': s.status,
        'reviewed_by': s.reviewed_by,
        'review_note': s.review_note,
        'reviewed_at': s.reviewed_at.isoformat() if s.reviewed_at else None,
        'created_at': s.created_at.isoformat() if s.created_at else None,
    }


@admin_bp.route('/submissions', methods=['GET'])
def admin_list_submissions():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    status = (request.args.get('status') or 'pending').strip().lower()
    q = Submission.query
    if status != 'all':
        if status not in ('pending', 'approved', 'rejected'):
            return error_response(
                'status ต้องเป็นหนึ่งใน pending, approved, rejected, all', 400, 'VALIDATION_ERROR'
            )
        q = q.filter(Submission.status == status)
    subs = q.order_by(Submission.created_at.desc()).limit(200).all()
    return jsonify({'submissions': [_submission_dict(s) for s in subs]}), 200


@admin_bp.route('/submissions/<int:submission_id>/approve', methods=['PATCH'])
def admin_approve_submission(submission_id):
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    sub = Submission.query.get(submission_id)
    if not sub:
        return error_response('not_found', 404)

    data = request.get_json(silent=True) or {}
    create_food_item = bool(data.get('create_food_item'))

    new_item_id = None
    if create_food_item:
        # หมวดหมู่ตัวแรกที่ type ตรงกับ submission — เมนูร่างนี้ is_active=0
        # อยู่แล้ว แอดมินยังปรับหมวดหมู่ให้ถูกต้องทีหลังผ่าน PUT food-items ได้
        # ถ้า type นั้นไม่เคยมีหมวดหมู่เลยจริงๆ (ไม่ควรเกิดกับ seed data
        # ปัจจุบัน) ค่อยสร้างหมวดหมู่ชั่วคราวให้
        cat = FoodCategory.query.filter_by(type=sub.item_type).first()
        if cat is None:
            cat = FoodCategory(name='รอตรวจสอบ', type=sub.item_type)
            db.session.add(cat)
            db.session.flush()
        item = FoodItem(
            category_id=cat.id,
            name=sub.name_en or sub.name_th,
            name_th=sub.name_th,
            upgrade_tips=sub.detail,
            allergens_reviewed=False,
            # ร่างจากข้อเสนอผู้ใช้ ยังไม่มีข้อมูลโภชนาการ — แอดมินต้องมาเติมให้
            # ครบก่อนเปิดให้ผู้ใช้เห็นจริง
            is_active=False,
        )
        db.session.add(item)
        db.session.flush()
        new_item_id = item.id

    admin = _current_admin_user()
    sub.status = 'approved'
    sub.reviewed_by = admin.id if admin else None
    sub.reviewed_at = get_thailand_time()
    _log_admin_action('approve', 'submission', sub.id, detail=f'created_food_item_id={new_item_id}')
    db.session.commit()

    body = _submission_dict(sub)
    body['created_food_item_id'] = new_item_id
    return jsonify(body), 200


@admin_bp.route('/submissions/<int:submission_id>/reject', methods=['PATCH'])
def admin_reject_submission(submission_id):
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    sub = Submission.query.get(submission_id)
    if not sub:
        return error_response('not_found', 404)

    data = request.get_json(silent=True) or {}
    reason = (data.get('reason') or '').strip()
    if not reason:
        return error_response('ต้องระบุเหตุผล (reason)', 400, 'VALIDATION_ERROR')

    admin = _current_admin_user()
    sub.status = 'rejected'
    sub.review_note = reason
    sub.reviewed_by = admin.id if admin else None
    sub.reviewed_at = get_thailand_time()
    _log_admin_action('reject', 'submission', sub.id, detail=reason)
    db.session.commit()
    return jsonify(_submission_dict(sub)), 200


@admin_bp.route('/action-log', methods=['GET'])
def admin_list_action_log():
    if not _check_admin_secret(request):
        return error_response('forbidden', 403)
    entity_type = (request.args.get('entity_type') or '').strip()
    limit = request.args.get('limit', 50, type=int)
    if not limit or limit < 1:
        limit = 50

    q = AdminActionLog.query.options(selectinload(AdminActionLog.admin_user))
    if entity_type:
        q = q.filter(AdminActionLog.entity_type == entity_type)
    rows = q.order_by(AdminActionLog.created_at.desc()).limit(limit).all()

    return jsonify({'action_log': [{
        'id': r.id,
        'admin_user_id': r.admin_user_id,
        'admin_username': r.admin_user.username if r.admin_user else None,
        'action': r.action,
        'entity_type': r.entity_type,
        'entity_id': r.entity_id,
        'detail': r.detail,
        'created_at': r.created_at.isoformat() if r.created_at else None,
    } for r in rows]}), 200