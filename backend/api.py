from flask import Flask, request, jsonify, send_file, Response, session, redirect, url_for, current_app
from sqlalchemy import func, create_engine, text, JSON as SA_JSON, inspect
from sqlalchemy.exc import IntegrityError, ProgrammingError
from sqlalchemy.orm import selectinload, joinedload
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import os
import io
import re
import csv
import csv_utils
import json
import logging
import secrets
from dotenv import load_dotenv
import hashlib
import hmac
import base64
import time
import random
import pathlib
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse, quote_plus
from health_calc import (
    calc_age, calc_bmi, bmi_status as calc_bmi_status, calc_tdee, calc_calories_goal,
    calc_calories_from_macros, disease_adjustment_factor, calc_calories_goal_custom,
    score_food_candidate, blocked_category_reason,
)
from recommendation_ai import trained_scores
from config import CURRENT_PDPA_POLICY_VERSION
from models import *
from error_utils import error_response, ERROR_STATUS_DEFAULTS

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
DB_PATH = os.path.join(BASE_DIR, 'nutrition_app.db')

AVATAR_UPLOAD_DIR = os.path.join(BASE_DIR, 'uploads', 'avatars')
ALLOWED_AVATAR_EXTENSIONS = {'png', 'jpg', 'jpeg', 'webp'}
MAX_AVATAR_BYTES = 5 * 1024 * 1024  # 5MB
MAX_AVATAR_DIMENSION_PX = 1024  # resize ลงถ้าใหญ่กว่านี้ กันไฟล์ normal ขนาดใหญ่

# .env มี SECRET_KEY/JWT_SECRET_KEY/MYSQL_* จริงอยู่แล้ว แต่ import load_dotenv
# เฉยๆ ไม่ทำให้มันถูกอ่านเข้า os.environ — ต้องเรียก load_dotenv() เองด้วย
# (ไม่งั้น os.environ.get('SECRET_KEY') จะได้ None เสมอ ทั้งที่ตั้งค่าไว้แล้ว)
load_dotenv(os.path.join(BASE_DIR, '.env'))

limiter = Limiter(get_remote_address, storage_uri='memory://')

CANONICAL_DISEASES = ['เบาหวาน', 'ความดันโลหิตสูง', 'โรคไต', 'โรคหัวใจ', 'ไขมันในเลือดสูง']
CANONICAL_ALLERGIES = ['กุ้ง', 'ปู', 'หอย', 'ปลา', 'ถั่วลิสง', 'ถั่วเหลือง', 'นม', 'ไข่', 'กลูเตน', 'งา']


def parse_date_of_birth(value):
    """Parse various date-of-birth representations into a date object."""
    import datetime as dt  # ใช้ตัวย่อเพื่อป้องกันการสับสนกับชื่อตัวแปรอื่น

    try:
        if value is None:
            return None

        # ถ้าเป็นวัตถุ datetime หรือ date อยู่แล้ว
        if isinstance(value, dt.datetime):
            return value.date()
        if isinstance(value, dt.date):
            return value

        if isinstance(value, str):
            s = value.strip()
            if not s:
                return None

            # 1. พยายามดึงแบบ ISO (YYYY-MM-DD)
            try:
                return dt.date.fromisoformat(s)
            except Exception:
                pass

            # 2. พยายามดึงแบบ Format ยอดฮิต
            for fmt in ('%Y-%m-%d', '%d/%m/%Y', '%d-%m-%Y'):
                try:
                    return dt.datetime.strptime(s, fmt).date()
                except Exception:
                    pass

            # 3. ถ้าเป็นตัวเลข Timestamp
            if s.isdigit():
                try:
                    return dt.date.fromtimestamp(int(s))
                except Exception:
                    pass

        # ถ้าเป็นตัวเลข int/float
        if isinstance(value, (int, float)):
            try:
                return dt.date.fromtimestamp(int(value))
            except Exception:
                return None

    except Exception as e:
        print(f"Error parsing DOB: {e}")
        return None

    return None


def _sanitize_string_list(items, max_len=100):
    """กรอง chronic_diseases/food_allergies ที่ผู้ใช้พิมพ์เอง (ช่อง "อื่นๆ")
    รับ list ได้เฉยๆ ไม่เช็คว่า item เป็น string ที่มีความยาวเหมาะสมมาก่อนหน้านี้
    เลยหลุดพวกค่าที่ไม่ใช่ string, ค่าว่าง, หรือข้อความยาวเกินไปเข้า DB ได้"""
    if not isinstance(items, list):
        return []
    seen = set()
    result = []
    for item in items:
        if not isinstance(item, str):
            continue
        s = item.strip()[:max_len]
        if not s or s in seen:
            continue
        seen.add(s)
        result.append(s)
    return result


def create_app():
    app = Flask(__name__)
    # Load SECRET_KEY from environment so token/OTP generation works.
    try:
        sk = os.environ.get('SECRET_KEY')
        if sk and sk.strip():
            app.config['SECRET_KEY'] = sk
        else:
            app.logger.warning('SECRET_KEY not set; some features (forgot-password) will fail')
    except Exception:
        pass
    # initialize limiter and other extensions later
    try:
        limiter.init_app(app)
    except Exception:
        pass
    # ======================
    # MySQL Configuration
    # ======================
    cfg_path = os.path.join(BASE_DIR, "mysql_config.json")

    mysql_user = os.environ.get("MYSQL_USER")
    mysql_pass = os.environ.get("MYSQL_PASS")
    mysql_host = os.environ.get("MYSQL_HOST", "127.0.0.1")
    mysql_port = os.environ.get("MYSQL_PORT", "3306")
    mysql_db = os.environ.get("MYSQL_DB")

    # Optional config file fallback
    if os.path.exists(cfg_path):
        try:
            with open(cfg_path, "r", encoding="utf-8") as f:
                cfg = json.load(f)

            mysql_user = cfg.get("user") or cfg.get("username") or mysql_user
            # Empty string is a valid password (e.g. XAMPP's default root user),
            # so check for presence of the key rather than truthiness.
            if "password" in cfg:
                mysql_pass = cfg.get("password")
            elif "pass" in cfg:
                mysql_pass = cfg.get("pass")
            mysql_host = cfg.get("host") or mysql_host
            mysql_port = str(cfg.get("port") or mysql_port)
            mysql_db = cfg.get("database") or cfg.get("db") or mysql_db

            app.logger.info("Loaded MySQL config from %s", cfg_path)

        except Exception as e:
            app.logger.warning("Failed to load mysql_config.json: %s", e)

    # ======================
    # Validate MySQL Config
    # ======================
    if not (mysql_user and mysql_pass is not None and mysql_db):
        raise RuntimeError(
            "MySQL configuration missing. "
            "Set MYSQL_USER, MYSQL_PASS, MYSQL_DB or provide mysql_config.json"
        )

    # ======================
    # Build MySQL URI
    # ======================
    mysql_pass_q = quote_plus(mysql_pass)

    mysql_uri = (
        f"mysql+pymysql://{mysql_user}:{mysql_pass_q}"
        f"@{mysql_host}:{mysql_port}/{mysql_db}?charset=utf8mb4"
    )

    # ======================
    # Test Database Connection
    # ======================
    try:
        test_engine = create_engine(mysql_uri, pool_pre_ping=True)
        with test_engine.connect():
            pass
        test_engine.dispose()

        app.config["SQLALCHEMY_DATABASE_URI"] = mysql_uri

    except Exception:
        app.logger.exception("MySQL connection failed. Aborting startup.")
        raise

    # ======================
    # SQLAlchemy Settings
    # ======================
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    # Echo SQL to stdout for debugging updates — เดิมเปิดไม่มีเงื่อนไขทุก
    # environment (ทั้งที่เซิร์ฟเวอร์นี้ internet-facing จริง) ทำให้ SQL +
    # bound parameter (รวม password_hash/reset_otp/token ที่ผ่านเป็น
    # parameter) หลุดเข้า stdout/log ทุก request (บั๊กที่เจอจริง) ผูกกับ
    # FLASK_ENV เหมือนจุดอื่นที่ตั้งใจแยก dev/prod ในไฟล์นี้
    app.config["SQLALCHEMY_ECHO"] = os.environ.get('FLASK_ENV') == 'development'
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
        "pool_pre_ping": True,
        "pool_recycle": 280
    }

    db.init_app(app)

    # ======================
    # CORS Configuration
    # ======================
    frontend_origins = [
        o.strip() for o in os.environ.get(
            "FRONTEND_ORIGIN", "http://localhost:5000,http://localhost:5173"
        ).split(",") if o.strip()
    ]

    CORS(
        app,
        resources={
            r"/*": {
                "origins": frontend_origins,
                "methods": ["GET", "POST", "PUT", "PATCH", "DELETE"],
                "allow_headers": ["Content-Type", "Authorization"],
            }
        },
        supports_credentials=True
    )

    return app


app = create_app()


# ครอบคลุม error ที่ "ไม่ได้ตั้งใจ return jsonify เอง" ทั้งหมด — 404 จาก
# get_or_404(), 429 จาก Flask-Limiter, 405 method ผิด, และ exception ที่หลุดมา
# ไม่ได้ catch เอง (กลายเป็น 500) ให้ยังคงได้ format {error,code,message} เดิม
# แทนหน้า HTML/text ธรรมดาของ Werkzeug — ทำงานร่วมกับ error_response() ที่ใช้
# ใน route ต่างๆ ตรงๆ ได้เลย เพราะ endpoint ที่ return error_response(...) เอง
# จะไม่ผ่าน error handler พวกนี้อยู่แล้ว (ไม่ได้ raise exception)
from werkzeug.exceptions import HTTPException


@app.errorhandler(HTTPException)
def handle_http_exception(e):
    message = e.description if isinstance(e.description, str) else str(e)
    if e.code == 429:
        message = 'ทำรายการถี่เกินไป กรุณาลองใหม่ภายหลัง'
    elif e.code == 404:
        message = 'ไม่พบข้อมูลที่ต้องการ'
    elif e.code == 405:
        message = 'ไม่รองรับ method นี้สำหรับ endpoint นี้'
    return error_response(message, e.code or 500, ERROR_STATUS_DEFAULTS.get(e.code, 'ERROR'))


@app.errorhandler(Exception)
def handle_uncaught_exception(e):
    app.logger.exception('unhandled exception')
    return error_response('เกิดข้อผิดพลาดที่เซิร์ฟเวอร์ กรุณาลองใหม่ภายหลัง', 500, 'SERVER_ERROR')


# Register admin blueprint if available so frontend can fetch admin reports
try:
    from admin.admin_routes import admin_bp
    app.register_blueprint(admin_bp, url_prefix='/admin')
except Exception:
    try:
        app.logger.debug('admin_bp not registered')
    except Exception:
        pass

@app.route('/')
def serve_frontend_index():
    frontend_dir = os.path.abspath(os.path.join(BASE_DIR, '..', 'frontend', 'web'))
    index_path = os.path.join(frontend_dir, 'index.html')
    if os.path.exists(index_path):
        return send_file(index_path, mimetype='text/html')
    return error_response('Nutritional Health API', 200)
@app.route('/favicon.ico')
def serve_favicon():
    frontend_dir = os.path.abspath(os.path.join(BASE_DIR, '..', 'frontend', 'web'))
    favicon_path = os.path.join(frontend_dir, 'favicon.ico')
    if os.path.exists(favicon_path):
        return send_file(favicon_path, mimetype='image/x-icon')
    return '', 204

@app.route('/assets/<path:filepath>')
def serve_assets(filepath):
    """Serve static assets from frontend/web/assets directory"""
    frontend_dir = os.path.abspath(os.path.join(BASE_DIR, '..', 'frontend', 'web'))
    assets_dir = os.path.abspath(os.path.join(frontend_dir, 'assets'))
    file_path = os.path.join(assets_dir, filepath)
    # Security check: prevent directory traversal
    if not os.path.abspath(file_path).startswith(assets_dir):
        return '', 404
    if os.path.exists(file_path) and os.path.isfile(file_path):
        return send_file(file_path)
    return '', 404

@app.route('/<filename>.js')
def serve_js_files(filename):
    """Serve JS files from frontend/web directory"""
    frontend_dir = os.path.abspath(os.path.join(BASE_DIR, '..', 'frontend', 'web'))
    file_path = os.path.join(frontend_dir, f'{filename}.js')
    if not os.path.abspath(file_path).startswith(os.path.abspath(frontend_dir)):
        return '', 404
    if os.path.exists(file_path):
        return send_file(file_path, mimetype='text/javascript')
    return '', 404

@app.route('/<filename>.html')
def serve_html_files(filename):
    """Serve static HTML files from frontend/web directory"""
    frontend_dir = os.path.abspath(os.path.join(BASE_DIR, '..', 'frontend', 'web'))
    file_path = os.path.join(frontend_dir, f'{filename}.html')
    # Security check: prevent directory traversal
    if not os.path.abspath(file_path).startswith(os.path.abspath(frontend_dir)):
        return '', 404
    if os.path.exists(file_path):
        return send_file(file_path, mimetype='text/html')
    return '', 404
def _best_match(term, candidates, cutoff=0.72):
    # Exact-match helper used by medical validation: return (match,1.0)
    if not term:
        return None, 0.0
    t = term.strip().lower()
    for c in (candidates or []):
        try:
            if (c or '').strip().lower() == t:
                return c, 1.0
        except Exception:
            continue
    return None, 0.0


def _is_none_token(s):
    """Return True if `s` represents an explicit none/empty token.

    This treats common tokens like 'no', 'none', 'n/a', '-', 'na', and
    empty/whitespace as indicating no-value. Note: the Thai literal
    'ไม่มี' is intentionally not included here so that an explicit user
    entry of 'ไม่มี' is preserved as a stored value.
    """
    if s is None:
        return True
    try:
        ss = str(s).strip().lower()
    except Exception:
        return False
    if ss == '':
        return True
    none_tokens = {'ไม่มีย', 'no', 'none', 'n/a', '-', 'na'}
    return ss in none_tokens


@app.route('/api/medical-lists', methods=['GET'])
def api_medical_lists():
    return jsonify({'diseases': CANONICAL_DISEASES, 'allergies': CANONICAL_ALLERGIES})
def _valid_food_category_type(category):
    """หมวดที่ pick/แนะนำเมนูได้ — 3 หมวด built-in เสมอ บวกหัวข้อที่แอดมินเพิ่ม
    เองผ่านหน้า "หมวดหมู่อาหาร" (เก็บใน FoodType) endpoint สุ่ม/แนะนำเมนูเลย
    ใช้กับหัวข้อใหม่ได้ทันที ไม่ต้องมาแก้โค้ดนี้ซ้ำทุกครั้งที่แอดมินเพิ่มหัวข้อ"""
    if category in ('food', 'drink', 'dessert'):
        return True
    return FoodType.query.filter_by(name=category).first() is not None


@app.route('/api/ai/random', methods=['POST'])
@limiter.limit("60 per minute")
def ai_random_menu():
    """Pick a random food_items row for the given category type."""
    data = request.get_json(silent=True) or {}
    category = (data.get('category') or '').strip().lower()
    if not _valid_food_category_type(category):
        return error_response('ไม่พบหมวดนี้', 400, 'VALIDATION_ERROR')

    candidates = (
        FoodItem.query.join(FoodCategory)
        .filter(FoodCategory.type == category, FoodItem.is_active == True)
        .limit(200).all()
    )
    if not candidates:
        return error_response('ไม่มีเมนูในหมวดนี้', 404, 'NOT_FOUND')
    item = random.choice(candidates)
    serving = ServingSize.query.filter_by(food_item_id=item.id, unit_name='medium').first() \
        or ServingSize.query.filter_by(food_item_id=item.id).first()

    return jsonify({
        'menu_name': item.name_th or item.name,
        'portion_size': (serving.unit_name_th or serving.unit_name) if serving else 'หน่วย',
        'calories': float(item.calories or 0) * (serving.calories_multiplier if serving else 1.0),
        'image_url': item.image_url or '',
    }), 200


@app.route('/api/ai/recommend', methods=['POST'])
@limiter.limit("60 per minute")
def ai_recommend_menu():
    """Rule-based nutrition recommender (see health_calc.score_food_candidate):
    ranks active food_items by closeness to the user's remaining daily calorie
    budget, nudged by health_goal/chronic_diseases, excludes known allergens."""
    user, err = _require_auth_user()
    if err:
        return err

    data = request.get_json(silent=True) or {}
    category = (data.get('category') or 'food').strip().lower()
    if not _valid_food_category_type(category):
        return error_response('ไม่พบหมวดนี้', 400, 'VALIDATION_ERROR')
    limit = min(max(int(data.get('limit') or 5), 1), 20)
    randomize = bool(data.get('randomize'))

    # วันที่จะคำนวณคำแนะนำให้ — ค่าเริ่มต้นคือวันนี้ แต่ให้ระบุ 'date' มาแทนได้
    # (ใช้คู่กับปฏิทินในกล่อง "AI แนะนำเมนู" ที่จำกัดช่วงตามรอบเป้าหมายสุขภาพ
    # อยู่แล้วฝั่งแอป — เดิม endpoint นี้ไม่รับ 'date' เลย ปฏิทินเลยกดยังไงก็ได้
    # ผลลัพธ์เดิม ผู้ใช้รายงานจริง)
    target_date = get_thailand_time().date()
    if data.get('date'):
        parsed_date = parse_date_of_birth(data.get('date'))
        if parsed_date is None:
            return error_response('รูปแบบวันที่ (date) ไม่ถูกต้อง', 400, 'VALIDATION_ERROR')
        if parsed_date > target_date:
            return error_response('ไม่สามารถดูคำแนะนำของวันในอนาคตได้', 400, 'VALIDATION_ERROR')
        target_date = parsed_date

    # โรคประจำตัวบางอย่างห้ามทั้งหมวด (เช่นเบาหวานกับของหวาน) ไม่ใช่แค่ลดคะแนน
    # ให้เมนูหวานน้อยสุดในหมวดยังโดนแนะนำอยู่ดี — เช็คก่อนคำนวณคะแนนเลย ไม่ต้อง
    # เสียเวลา query candidates ถ้าหมวดนี้ไม่ควรแนะนำอยู่แล้ว
    reason = blocked_category_reason(user.chronic_diseases, category)
    if reason:
        return jsonify({'blocked': True, 'reason': reason, 'target_calories': 0, 'recommendations': []}), 200

    _, eaten_on_date, _, _ = _day_meal_log_totals(user.id, target_date)
    remaining = max(float(user.calories_goal or 0) - eaten_on_date, 0)
    # ponytail: fixed remaining/3 (สมมติ 3 มื้อ/วัน) แทนจำนวนมื้อที่เหลือจริง
    # ของวันนี้ — เปลี่ยนเป็นหารด้วยมื้อที่ยังไม่ได้บันทึกจริงถ้าต้องแม่นกว่านี้
    target_calories = remaining / 3 if remaining > 0 else 500

    user_allergens = {str(a).strip().lower() for a in (user.food_allergies or [])}

    candidates = (
        FoodItem.query.join(FoodCategory)
        .filter(FoodCategory.type == category, FoodItem.is_active == True)
        .all()
    )
    eligible_candidates = []
    excluded_for_allergy = 0
    for item in candidates:
        item_allergens = {a.name.strip().lower() for a in item.allergens}
        if user_allergens & item_allergens:
            excluded_for_allergy += 1
            continue
        eligible_candidates.append(item)

    positive_food_ids = {
        food_id for (food_id,) in db.session.query(UserFavoriteFood.food_item_id)
        .filter(UserFavoriteFood.user_id == user.id)
        .all()
    }
    positive_food_ids.update(
        food_id for (food_id,) in db.session.query(MealLogItem.food_item_id)
        .join(MealLog, MealLog.id == MealLogItem.meal_log_id)
        .filter(MealLog.user_id == user.id, MealLogItem.is_eaten == True)
        .all()
    )
    negative_food_ids = {
        food_id for (food_id,) in db.session.query(MealLogItem.food_item_id)
        .join(MealLog, MealLog.id == MealLogItem.meal_log_id)
        .filter(MealLog.user_id == user.id, MealLogItem.is_eaten == False)
        .all()
    }
    learned_scores = trained_scores(
        eligible_candidates, positive_food_ids, negative_food_ids, target_calories
    )

    scored = []
    for item in eligible_candidates:
        s = score_food_candidate(
            {'calories': item.calories, 'protein_g': item.protein_g, 'fat_g': item.fat_g,
             'fiber_g': item.fiber_g, 'sugar_g': item.sugar_g},
            target_calories, user.health_goal, user.chronic_diseases,
        )
        if learned_scores is not None:
            s = round(s + learned_scores[item.id] * 100, 2)
        scored.append((s, item))

    if not scored:
        if candidates and excluded_for_allergy == len(candidates):
            return error_response('เมนูในหมวดนี้ทั้งหมดมีสารก่อภูมิแพ้ที่คุณแพ้ ลองหมวดอื่นดูนะ', 404, 'NOT_FOUND')
        return error_response('ไม่มีเมนูที่เหมาะกับโปรไฟล์นี้', 404, 'NOT_FOUND')

    scored.sort(key=lambda pair: pair[0], reverse=True)
    ranked_pool = scored[:max(min(len(scored), limit * 4), limit)]
    if randomize:
        random.shuffle(ranked_pool)
    results = []
    for s, item in ranked_pool[:limit]:
        serving = ServingSize.query.filter_by(food_item_id=item.id, unit_name='medium').first() \
            or ServingSize.query.filter_by(food_item_id=item.id).first()
        results.append({
            'food_item_id': item.id,
            'menu_name': item.name_th or item.name,
            'portion_size': (serving.unit_name_th or serving.unit_name) if serving else 'หน่วย',
            'calories': float(item.calories or 0) * (serving.calories_multiplier if serving else 1.0),
            'image_url': item.image_url or '',
            'score': s,
        })
    return jsonify({'target_calories': round(target_calories), 'recommendations': results}), 200


def _day_meal_log_totals(user_id, d):
    """(planned_calories, eaten_calories, eaten_macros, meal_types_logged) for one date.
    eaten_macros = {'protein': .., 'carbs': .., 'fat': ..} summed over is_eaten=1 items only."""
    logs = MealLog.query.filter_by(user_id=user_id, log_date=d).all()
    log_ids = [l.id for l in logs]
    planned = eaten = 0.0
    eaten_macros = {'protein': 0.0, 'carbs': 0.0, 'fat': 0.0}
    if log_ids:
        for it in MealLogItem.query.filter(MealLogItem.meal_log_id.in_(log_ids)).all():
            cal = float(it.calories_actual or 0)
            planned += cal
            if it.is_eaten:
                eaten += cal
                eaten_macros['protein'] += float(it.protein_actual or 0)
                eaten_macros['carbs'] += float(it.carbs_actual or 0)
                eaten_macros['fat'] += float(it.fat_actual or 0)
    return planned, eaten, eaten_macros, {l.meal_type for l in logs}


def _dashboard_summary_for_user(user):
    today = get_thailand_time().date()
    planned_today, eaten_today, eaten_macros_today, meal_types_today = _day_meal_log_totals(user.id, today)

    meals = [
        {'meal_type': mt, 'status': 'logged' if mt in meal_types_today else 'pending'}
        for mt in ('breakfast', 'lunch', 'dinner')
    ]

    last_7_days = []
    for offset in range(6, -1, -1):
        d = today - timedelta(days=offset)
        _, eaten_d, _, _ = _day_meal_log_totals(user.id, d)
        last_7_days.append({'date': d.isoformat(), 'eaten_calories': eaten_d})

    bmi_val = calc_bmi(user.weight, user.height)
    goal = float(user.calories_goal or 0)
    # over_limit ต้องมี goal ตั้งไว้จริงก่อน (>0) ไม่งั้น user ที่ยังไม่ตั้ง
    # เป้าหมายจะโดนตีว่า "เกิน" ทันทีตั้งแต่ยังไม่กินอะไรเลย (0 > 0 เป็น False
    # อยู่แล้วก็จริง แต่กันไว้ให้ชัดเจนเผื่อกรณี goal ติดลบผิดปกติ)
    over_limit = goal > 0 and eaten_today > goal
    dinner_logged = 'dinner' in meal_types_today
    return {
        'planned_calories': planned_today,
        'eaten_calories': eaten_today,
        # SUM(protein_actual/carbs_actual/fat_actual) เฉพาะ is_eaten=1 — ใช้ค่า
        # snapshot ที่บันทึกไว้ตอนเลือกเมนู ไม่ใช่คำนวณใหม่จาก food_items ตรงๆ
        # กันกรณีฐานข้อมูลเมนูเปลี่ยนย้อนหลัง (เหตุผลเดียวกับ calories_actual เดิม)
        'eaten_protein': eaten_macros_today['protein'],
        'eaten_carbs': eaten_macros_today['carbs'],
        'eaten_fat': eaten_macros_today['fat'],
        'calories_goal': goal,
        'over_limit': over_limit,
        # เย็นถูกบันทึกแล้ว (มี meal_log ของมื้อเย็นวันนี้) — ฝั่ง Flutter ใช้
        # ตัวนี้ตัดสินใจว่าจะโชว์การ์ดสรุปผลการกินท้ายวันหรือยัง รายละเอียด
        # การคำนวณ kcal เชิงลึกรอ prompt ถัดไปตามที่ผู้ใช้แจ้งไว้ — ตอนนี้ส่ง
        # แค่ตัวเลขที่มีอยู่แล้วพอ (eaten/planned/goal ด้านบน) ให้การ์ดสรุปใช้
        'dinner_logged': dinner_logged,
        'meals': meals,
        'weight_kg': float(user.weight or 0),
        # bmi_val เป็น None ได้ถ้า user ยังไม่กรอกน้ำหนัก/ส่วนสูง — ฝั่ง Flutter
        # cast เป็น non-nullable num ตรงๆ (`json['bmi'] as num`) จึง crash ถ้าส่ง
        # null ไป coerce เป็น 0 ให้เหมือน field ตัวเลขอื่นๆ ในนี้ (weight_kg/
        # calories_goal ก็ทำแบบเดียวกัน)
        'bmi': bmi_val or 0,
        'bmi_status': calc_bmi_status(bmi_val),
        'last_7_days': last_7_days,
    }


@app.route('/api/dashboard', methods=['GET'])
@app.route('/dashboard/summary', methods=['GET'])
def get_dashboard_summary():
    """สรุปแคลอรีวันนี้ (planned vs eaten จาก meal_logs), BMI สด, กราฟ 7 วันย้อนหลัง."""
    user, err = _require_auth_user()
    if err:
        return err

    # หน้าหลักคือหน้าแรกที่ผู้ใช้เห็นทุกครั้งที่เปิดแอป — ถ้ารอบ 7 วันเพิ่ง
    # หมดอายุ (22:00 ของวันที่ 7) ให้สรุปผลแล้วแจ้งทันทีที่นี่ ไม่ต้องรอให้
    # ผู้ใช้กดเข้าโปรไฟล์/ประวัติเอง
    _finalize_expired_goal_cycle(user)
    summary = _dashboard_summary_for_user(user)
    unacknowledged = HealthGoalCycle.query.filter_by(
        user_id=user.id,
        health_goal=user.health_goal,
        acknowledged_at=None,
    ).order_by(HealthGoalCycle.period_end.desc()).first()
    summary['goal_cycle_result'] = _serialize_goal_cycle(unacknowledged) if unacknowledged else None

    return jsonify(summary), 200


@app.route('/api/user/health-goal-cycles/<int:cycle_id>/ack', methods=['POST'])
@limiter.limit("60 per minute")
def acknowledge_health_goal_cycle(cycle_id):
    """ผู้ใช้ปิด dialog สรุปผล 7 วันไปแล้ว — เซ็ต acknowledged_at กัน
    goal_cycle_result โผล่ซ้ำทุกครั้งที่เปิดหน้าหลักอีก (ดู get_dashboard_summary)"""
    user, err = _require_auth_user()
    if err:
        return err
    cycle = HealthGoalCycle.query.filter_by(id=cycle_id, user_id=user.id).first()
    if cycle is None:
        return error_response('ไม่พบข้อมูลรอบเป้าหมายนี้', 404, 'NOT_FOUND')
    if cycle.acknowledged_at is None:
        cycle.acknowledged_at = get_thailand_time()
        db.session.commit()
    return jsonify({'status': 'ok'}), 200


@app.route('/api/dashboard/weekly-summary', methods=['GET'])
def dashboard_weekly_summary():
    """ภาพรวม 7 วันล่าสุดเป็นตัวเลขสรุป — on_target/over/under คำนวณเทียบ
    calories_goal ±10% ต่อวัน นับเฉพาะวันที่มีรายการ is_eaten=1 จริงอย่างน้อย
    1 รายการ (มี meal_log แต่ยังไม่กดทานแล้วสักอย่าง ไม่นับเป็นวันที่ "กิน")"""
    user, err = _require_auth_user()
    if err:
        return err

    today = get_thailand_time().date()
    since = today - timedelta(days=6)
    goal = float(user.calories_goal or 0)

    # ดึงทุกอย่างที่ต้องใช้ในคำสั่งเดียว (log_date + calories_actual + ชื่อ
    # หมวดหมู่ต่อรายการที่ทานแล้วจริงในสัปดาห์นี้) กัน N+1
    rows = (
        db.session.query(MealLog.log_date, MealLogItem.calories_actual, FoodCategory.name)
        .join(MealLogItem, MealLogItem.meal_log_id == MealLog.id)
        .join(FoodItem, FoodItem.id == MealLogItem.food_item_id)
        .join(FoodCategory, FoodCategory.id == FoodItem.category_id)
        .filter(
            MealLog.user_id == user.id,
            MealLog.log_date >= since,
            MealLog.log_date <= today,
            MealLogItem.is_eaten == True,
        )
        .all()
    )

    per_day_eaten = {}
    category_counts = {}
    for log_date, cal, category_name in rows:
        per_day_eaten[log_date] = per_day_eaten.get(log_date, 0.0) + float(cal or 0)
        category_counts[category_name] = category_counts.get(category_name, 0) + 1

    days_on_target = days_over_goal = days_under_goal = 0
    if goal > 0:
        lower, upper = goal * 0.9, goal * 1.1
        for eaten in per_day_eaten.values():
            if eaten > upper:
                days_over_goal += 1
            elif eaten < lower:
                days_under_goal += 1
            else:
                days_on_target += 1

    avg_eaten_calories = round(sum(per_day_eaten.values()) / len(per_day_eaten), 1) if per_day_eaten else 0

    # streak: จำนวนวันติดต่อกันนับจากวันนี้ย้อนหลังที่มีรายการทานแล้วจริง —
    # หยุดนับทันทีที่เจอวันว่าง (ไม่ต้องมองย้อนไปไกลกว่านั้น)
    streak_days_logged = 0
    for offset in range(0, 7):
        if (today - timedelta(days=offset)) in per_day_eaten:
            streak_days_logged += 1
        else:
            break

    most_frequent_category = max(category_counts, key=category_counts.get) if category_counts else None

    return jsonify({
        'days_on_target': days_on_target,
        'days_over_goal': days_over_goal,
        'days_under_goal': days_under_goal,
        'avg_eaten_calories': avg_eaten_calories,
        'streak_days_logged': streak_days_logged,
        'most_frequent_category': most_frequent_category,
    }), 200


@app.route("/api/food-categories")
def api_food_categories():
    type_filter = request.args.get("type")

    q = FoodCategory.query
    if type_filter:
        q = q.filter(FoodCategory.type == type_filter)

    return jsonify([
        {"id": c.id, "name": c.name, "type": c.type}
        for c in q.all()
    ])


@app.route("/api/food-types")
def api_food_types():
    """หัวข้อเมนูทั้งหมด (built-in food/drink/dessert + หัวข้อที่แอดมินเพิ่มเอง
    ในหน้า "หมวดหมู่อาหาร") ให้แอปมือถือดึงไปสร้างแท็บ/ตัวกรองแบบไดนามิก แทน
    hardcode 3 ค่าไว้ในแอป (ผู้ใช้รายงานจริง: เพิ่มหัวข้อใหม่ในแอดมินแล้ว แต่
    ฝั่งผู้ใช้ไม่เห็นเลย) ไม่ต้อง auth เหมือน /api/food-categories เพราะเป็น
    ชื่อหมวดหมู่ล้วนๆ ไม่ใช่ข้อมูลลับ — เผื่อ built-in ยังไม่เคย seed ไว้ใน
    FoodType (ดู admin_routes.py _ensure_builtin_food_types) จึงรวม 3 ค่า
    built-in เข้าไปเองเสมอถ้ายังไม่มีแถวจริงในตาราง"""
    rows = {t.name: t.sort_order for t in FoodType.query.all()}
    for i, name in enumerate(('food', 'drink', 'dessert')):
        rows.setdefault(name, i)
    ordered = sorted(rows.items(), key=lambda kv: (kv[1], kv[0]))
    return jsonify({'types': [{'name': name, 'sort_order': order} for name, order in ordered]})


def _matched_restricted_allergens(user, allergen_names):
    """จุดเดียวที่เทียบ allergen ของเมนูกับสิ่งที่ผู้ใช้ต้องเลี่ยง (food_allergies
    + chronic_diseases ผ่าน mechanism เดียวกับ allergen — ดู _serialize_food_item)
    — เดิมมี logic แบบนี้ก็อปซ้ำอยู่ 2 จุด (ที่นี่ + meal_log_items()) ทำให้
    ตอนแก้ chronic_diseases เข้าไปรอบก่อน อีกจุดหนึ่งหลุดไม่ได้แก้ตาม
    (บั๊กที่เจอจริง) รวมเป็นฟังก์ชันเดียวกันกันหลุดอีกในอนาคต"""
    if user is None:
        return []
    restricted = set()
    if user.food_allergies:
        restricted |= set(user.food_allergies) if isinstance(user.food_allergies, list) else set()
    if user.chronic_diseases:
        restricted |= set(user.chronic_diseases) if isinstance(user.chronic_diseases, list) else set()
    return [a for a in allergen_names if a in restricted]


def _serialize_food_item(item, user=None):
    # ใช้ relationship ที่ eager-load มาแล้วจาก query (ดู api_food_items) แทน
    # การยิง query แยกต่อเมนู — servings เดิมยิง SELECT ใหม่ทุกครั้งที่เรียก
    # ฟังก์ชันนี้ ทำให้ list 500 เมนูกลายเป็น ~500 query ซ้ำ (N+1)
    servings = item.serving_sizes
    allergen_names = [a.name for a in item.allergens]
    category_type = item.category.type if item.category else None

    matched_allergens = _matched_restricted_allergens(user, allergen_names)
    # เดิม blocked_category_reason (เบาหวาน -> ของหวาน) เช็คแค่ตอน AI แนะนำเมนู
    # (ai_recommend_menu) จุดเดียว — หน้าบันทึกมื้อที่ผู้ใช้เลือกเมนูเองไม่เคย
    # เรียกใช้เลย ของหวานเลยยังเลือกได้ปกติทั้งที่มีโรคประจำตัว (ผู้ใช้รายงาน
    # จริง) _serialize_food_item เป็นจุดเดียวที่ทุก endpoint ที่คืน FoodItem
    # เต็มรูปแบบใช้ร่วมกัน (list/detail/favorites/recent) เช็คที่นี่จุดเดียว
    # ครอบคลุมทุกที่ที่ผู้ใช้เห็นเมนูนี้
    disease_reason = blocked_category_reason(user.chronic_diseases, category_type) if user else None
    allergy_warning = bool(matched_allergens) or bool(disease_reason)

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
        'serving_sizes': [{
            'id': s.id,
            'unit_name': s.unit_name,
            'unit_name_th': s.unit_name_th,
            'calories_multiplier': s.calories_multiplier,
            'grams_approx': s.grams_approx,
        } for s in servings],
        'allergens': allergen_names,
        'allergy_warning': allergy_warning,
        'allergy_warning_allergens': matched_allergens,
        'disease_warning_reason': disease_reason,
        # 200 พร้อม flag เตือน ไม่ใช่ error — ผู้ใช้ยังดู/เลือกเมนูนี้ได้ปกติ
        # (เหมือน allergen — เตือนแทนที่จะซ่อน ให้ผู้ใช้ตัดสินใจเอง)
        'warning': ({
            'code': 'ALLERGEN_WARNING',
            'message': disease_reason or
                f"เมนูนี้มีส่วนผสมที่คุณควรระวัง (แพ้อาหาร/โรคประจำตัว): {', '.join(matched_allergens)}",
            'detail': {'allergens': matched_allergens},
        } if allergy_warning else None),
    }


@app.route('/api/food-items', methods=['GET'])
def api_food_items():
    """Consolidated menu listing — replaces the old per-table food/dessert/drink
    menu endpoints. ?type=food|drink|dessert, ?category_id=, ?search="""
    # eager-load category/serving_sizes/allergens ในคำสั่งเดียว กัน N+1 ตอน
    # _serialize_food_item เข้าถึง item.category / item.serving_sizes /
    # item.allergens ต่อเมนู (เดิมแต่ละแถวยิง query แยกกันหมด)
    q = (
        FoodItem.query.join(FoodCategory)
        .options(
            joinedload(FoodItem.category),
            selectinload(FoodItem.serving_sizes),
            selectinload(FoodItem.allergens),
        )
        .filter(FoodItem.is_active == True)
    )

    type_filter = request.args.get('type')
    if type_filter:
        q = q.filter(FoodCategory.type == type_filter)

    category_id = request.args.get('category_id', type=int)
    if category_id:
        q = q.filter(FoodItem.category_id == category_id)

    search = (request.args.get('search') or '').strip()
    if search:
        like = f'%{search}%'
        q = q.filter(db.or_(FoodItem.name.ilike(like), FoodItem.name_th.ilike(like)))

    user = get_current_user_from_jwt()
    items = q.limit(500).all()
    return jsonify({'items': [_serialize_food_item(i, user) for i in items]}), 200


@app.route('/api/food-items/<int:item_id>', methods=['GET'])
def api_food_item_detail(item_id):
    # เดิมไม่ eager-load เหมือน endpoint อื่นที่เรียก _serialize_food_item
    # (list/favorites/recent-items) ทำให้ .category/.serving_sizes/.allergens
    # ยิง query แยกกันทีละ relationship แทนที่จะเป็นคำสั่งเดียว (ไม่ใช่ N+1
    # เต็มรูปแบบเพราะเป็น N=1 request แต่ยังคงไม่จำเป็น — reuse helper เดียว
    # กับจุดอื่นให้ทุก endpoint ที่คืน FoodItem เต็มรูปแบบ eager-load เหมือนกัน)
    item = _eager_food_items_query().filter(FoodItem.id == item_id).first_or_404()
    user = get_current_user_from_jwt()
    return jsonify(_serialize_food_item(item, user)), 200


# =========================
# FAVORITES + RECENT ITEMS
# =========================

def _eager_food_items_query():
    """เหมือน query ใน api_food_items() เป๊ะ — eager-load category/
    serving_sizes/allergens ในคำสั่งเดียว กัน N+1 ใช้ร่วมกันทุกจุดที่ต้อง
    คืน FoodItem เต็มรูปแบบ (favorites, recent-items)"""
    return FoodItem.query.options(
        joinedload(FoodItem.category),
        selectinload(FoodItem.serving_sizes),
        selectinload(FoodItem.allergens),
    )


@app.route('/api/favorites', methods=['GET'])
def list_favorites():
    user, err = _require_auth_user()
    if err:
        return err

    favs = (
        db.session.query(UserFavoriteFood.food_item_id)
        .filter(UserFavoriteFood.user_id == user.id)
        .order_by(UserFavoriteFood.created_at.desc())
        .all()
    )
    fav_ids = [f[0] for f in favs]
    if not fav_ids:
        return jsonify({'items': []}), 200

    items_by_id = {i.id: i for i in _eager_food_items_query().filter(FoodItem.id.in_(fav_ids)).all()}
    ordered = [items_by_id[fid] for fid in fav_ids if fid in items_by_id]
    return jsonify({'items': [_serialize_food_item(i, user) for i in ordered]}), 200


@app.route('/api/favorites/<int:food_item_id>', methods=['POST'])
def add_favorite(food_item_id):
    user, err = _require_auth_user()
    if err:
        return err
    if not FoodItem.query.get(food_item_id):
        return error_response('ไม่พบเมนูที่เลือก', 404, 'NOT_FOUND')

    # idempotent — มีอยู่แล้วก็ถือว่าสำเร็จ ไม่ error (ปุ่มดาวกดซ้ำได้อย่างปลอดภัย)
    existing = UserFavoriteFood.query.filter_by(user_id=user.id, food_item_id=food_item_id).first()
    if not existing:
        db.session.add(UserFavoriteFood(user_id=user.id, food_item_id=food_item_id))
        db.session.commit()
    return jsonify({'status': 'ok', 'food_item_id': food_item_id, 'favorited': True}), 200


@app.route('/api/favorites/<int:food_item_id>', methods=['DELETE'])
def remove_favorite(food_item_id):
    user, err = _require_auth_user()
    if err:
        return err

    UserFavoriteFood.query.filter_by(user_id=user.id, food_item_id=food_item_id).delete()
    db.session.commit()
    return jsonify({'status': 'ok', 'food_item_id': food_item_id, 'favorited': False}), 200


@app.route('/api/meal-logs/recent-items', methods=['GET'])
def recent_meal_log_items():
    """เมนูล่าสุดที่เคยเลือก (ไม่ซ้ำ) เรียงจาก meal_log ที่สังกัดล่าสุดก่อน
    — ให้ผู้ใช้บันทึกซ้ำเมนูเดิมได้เร็วโดยไม่ต้องค้นหาใหม่"""
    user, err = _require_auth_user()
    if err:
        return err
    limit = request.args.get('limit', 5, type=int)
    if not limit or limit < 1:
        limit = 5

    # ดึงมาเผื่อเกินจำนวนที่ต้องการ (เมนูซ้ำกันหลายมื้อ) แล้ว dedupe ใน
    # Python — จำกัดจำนวนแถวตั้งต้นกันดึงประวัติทั้งหมดของ user ที่ใช้แอปมานาน
    rows = (
        db.session.query(MealLogItem.food_item_id)
        .join(MealLog, MealLogItem.meal_log_id == MealLog.id)
        .filter(MealLog.user_id == user.id)
        .order_by(MealLog.created_at.desc())
        .limit(200)
        .all()
    )
    recent_ids = []
    seen = set()
    for (food_item_id,) in rows:
        if food_item_id not in seen:
            seen.add(food_item_id)
            recent_ids.append(food_item_id)
        if len(recent_ids) >= limit:
            break

    if not recent_ids:
        return jsonify({'items': []}), 200

    items_by_id = {i.id: i for i in _eager_food_items_query().filter(FoodItem.id.in_(recent_ids)).all()}
    ordered = [items_by_id[fid] for fid in recent_ids if fid in items_by_id]
    return jsonify({'items': [_serialize_food_item(i, user) for i in ordered]}), 200


@app.route('/api/food-items/popular', methods=['GET'])
def popular_food_items():
    """เมนูยอดนิยม — นับจำนวนครั้งที่แต่ละเมนูถูกเพิ่มเข้า meal_log_items
    สะสมตลอดกาลจากผู้ใช้ทุกคนรวมกัน (ไม่ใช่แค่ user ปัจจุบันแบบ recent-items)
    ?type=food|drink|dessert กรองตามแท็บได้ ไม่ต้องล็อกอินก็ดูได้เหมือน
    /api/food-items ปกติ"""
    type_filter = request.args.get('type')
    limit = request.args.get('limit', 10, type=int)
    if not limit or limit < 1:
        limit = 10

    cnt = func.count(MealLogItem.id)
    q = (
        db.session.query(MealLogItem.food_item_id, cnt)
        .join(FoodItem, MealLogItem.food_item_id == FoodItem.id)
        .join(FoodCategory, FoodItem.category_id == FoodCategory.id)
        .filter(FoodItem.is_active == True)
    )
    if type_filter:
        q = q.filter(FoodCategory.type == type_filter)

    rows = (
        q.group_by(MealLogItem.food_item_id)
        .order_by(cnt.desc())
        .limit(limit)
        .all()
    )
    popular_ids = [r[0] for r in rows]
    if not popular_ids:
        return jsonify({'items': []}), 200

    user = get_current_user_from_jwt()
    items_by_id = {i.id: i for i in _eager_food_items_query().filter(FoodItem.id.in_(popular_ids)).all()}
    ordered = [items_by_id[fid] for fid in popular_ids if fid in items_by_id]
    return jsonify({'items': [_serialize_food_item(i, user) for i in ordered]}), 200


def admin_required(f):
    from functools import wraps
    @wraps(f)
    def wrapper(*args, **kwargs):
        user_id = session.get('admin_user_id')
        if user_id:
            try:
                user = User.query.get(user_id)
            except Exception:
                user = None
            if user and getattr(user, 'is_admin', False):
                request.admin_user = user
                return f(*args, **kwargs)

        # รับเฉพาะทาง header เท่านั้น — เดิมรับผ่าน query string/JSON body/form
        # ด้วย ซึ่งหลุดเข้า server access log/Referer header ได้ง่ายกว่า header เอง
        provided = request.headers.get('X-Admin-Secret')

        # ห้ามมี default secret ฝังในซอร์สโค้ด — เดิม fallback เป็น '12345678zA*'
        # (บั๊กที่เจอจริง เหมือนกับ admin/admin_routes.py._check_admin_secret)
        admin_secret = os.environ.get('ADMIN_SECRET')
        if admin_secret and provided and provided == admin_secret:
            request.admin_user = None
            return f(*args, **kwargs)

        return error_response('forbidden', 403)
    return wrapper


@app.route('/admin/login', methods=['POST'])
@limiter.limit("10 per minute")
def admin_api_login():
    # Accept JSON or form-encoded
    data = request.get_json(silent=True) or request.form or {}
    username = (data.get('username') or '').strip()
    password = data.get('password') or ''

    if not username or not password:
        return error_response('username and password required', 400)
    user = User.query.filter(func.lower(User.username) == username.lower()).first()
    # Do not reveal which part failed
    if not user or not getattr(user, 'is_admin', False):
        return error_response('unauthorized', 401)
    if not check_password_hash(user.password_hash, password):
        return error_response('unauthorized', 401)
    # Login success: create session
    session.clear()
    session['admin_user_id'] = user.id
    session.permanent = True

    return jsonify({'id': user.id, 'username': user.username, 'is_admin': 1}), 200


@app.route('/admin/logout', methods=['POST'])
def admin_api_logout():
    session.clear()
    return jsonify({'status': 'ok'}), 200
def token_valid_for_user(user: User, token: str) -> bool:
    """Return True if token matches and is not expired.

    TTL days can be configured via env `TOKEN_TTL_DAYS` (default 30).
    """
    if not user or getattr(user, 'is_deleted', False) or not user.password_token or token != user.password_token:
        return False
    try:
        ttl_days = int(os.environ.get('TOKEN_TTL_DAYS', '30'))
    except Exception:
        ttl_days = 30
    if not user.token_created_at:
        return True
    try:
        age = get_thailand_time() - user.token_created_at
        return age <= timedelta(days=ttl_days)
    except Exception:
        return True

# NOTE: automatic SQLite->MySQL migration at startup was removed because it
# caused fragile reflection/serialization errors in some environments.
# Use the provided `migrate_with_config.py` script to preview and perform
# a safe migration when ready. If a local SQLite DB exists, log an advisory
# message instead of attempting an automatic migration here.
if 'mysql' in app.config.get('SQLALCHEMY_DATABASE_URI', ''):
    sqlite_path = pathlib.Path(DB_PATH)
    if sqlite_path.exists():
        app.logger.info(
            'Local SQLite DB found at %s. To migrate users to MySQL run: migrate_with_config.py --preview --migrate',
            DB_PATH,
        )

@app.route('/init-db', methods=['POST'])
def init_db():
    """
    Initialize database (EXTREMELY DANGEROUS).
    Only allowed in DEBUG mode + localhost + ADMIN_SECRET.
    """

    # ❌ ห้ามรันใน production เด็ดขาด
    if not app.debug:
        return error_response('forbidden', 403)
    admin_secret = os.environ.get("ADMIN_SECRET")
    provided = request.headers.get("X-Admin-Secret")

    # ต้องมี secret และต้องตรงกัน
    if not admin_secret or provided != admin_secret:
        return error_response('forbidden', 403)
    # อนุญาตเฉพาะเรียกจากเครื่อง server เท่านั้น
    if request.remote_addr not in ("127.0.0.1", "::1"):
        return error_response('local requests only', 403)
    try:
        db.drop_all()
        db.create_all()
        return jsonify({'status': 'ok', 'msg': 'db initialized'})
    except Exception:
        app.logger.exception("DB init failed")
        return error_response('database error', 500)
@app.route('/register', methods=['POST'], strict_slashes=False)
@limiter.limit("5 per minute")
def register():

    # -------------------------
    # Require JSON
    # -------------------------
    if not request.is_json:
        return error_response('JSON body required', 400)
    data = request.get_json(silent=True) or {}

    # register logic continues

    username = (data.get('username') or '').strip()
    password = data.get('password') or ''
    confirm = data.get('confirm_password')
    email = (data.get('email') or '').strip().lower()

    app.logger.info(
        'Register attempt: username=%s email=%s',
        username,
        email
    )

    # -------------------------
    # Block Guest registrations
    # -------------------------
    is_guest_flag = data.get('is_guest')
    if is_guest_flag is True:
        return error_response('guest cannot be registered', 400)
    uname = username.lower()
    mail = email.lower()
    if uname.startswith('guest_') or mail.startswith('guest+'):
        return error_response('guest cannot be registered', 400)
    # -------------------------
    # Validation
    # -------------------------
    if not username or not password:
        return error_response('username and password are required', 400)
    if confirm is not None and confirm != '' and password != confirm:
        return error_response('password and confirm_password do not match', 400)
    if not email:
        return error_response('email is required', 400)
    # -------------------------
    # Validate email format
    # -------------------------
    email_pattern = r'^[^@\s]+@[^@\s]+\.[^@\s]+$'
    if not re.match(email_pattern, email):
        return error_response('invalid email format', 400)
    # NOTE: Do not restrict TLDs here. Email must match DB exactly on lookup.

    if len(username) < 4:
        return error_response('username must be at least 4 characters long', 400)
    if len(password) < 8:
        return error_response('password must be at least 8 characters long', 400)
    # Password must be strong (uppercase, lowercase, number, special character)
    strong_pattern = r'(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[^A-Za-z0-9])'
    if not re.search(strong_pattern, password):
        return error_response('password must include uppercase, lowercase, number and special character', 400)

    # -------------------------
    # Check duplicates (case-insensitive)
    # -------------------------
    try:
        if User.query.filter(func.lower(User.username) == username.lower()).first():
            return error_response('username exists', 400)
        if User.query.filter(func.lower(User.email) == email.lower()).first():
            return error_response('email already in use', 400)
    except Exception:
        app.logger.exception('DB lookup failed during register')
        return error_response('database error', 500)
    # -------------------------
    # Create user
    # -------------------------
    try:
        pwd_hash = generate_password_hash(password)
        token = secrets.token_urlsafe(32)

        user = User(
            username=username,
            email=email,
            password_hash=pwd_hash,
            password_token=token,
            token_created_at=get_thailand_time()
        )

        db.session.add(user)
        db.session.commit()
        try:
            # Ensure session returns fresh data from DB and clear any cached state
            db.session.expire_all()
            db.session.refresh(user)
        except Exception:
            # Non-fatal: proceed even if refresh fails
            app.logger.debug('session refresh/expire_all failed during register for user %s', getattr(user, 'id', None))

    except Exception:
        db.session.rollback()
        app.logger.exception('DB commit failed during register')
        return error_response('database error', 500)
    # -------------------------
    # Response
    # -------------------------
    try:
        created_at = user.created_at.isoformat()
    except Exception:
        created_at = get_thailand_time().isoformat()

    return jsonify({
        'success': True,
        'id': user.id,
        'user_id': user.id,
        'username': user.username,
        'email': user.email,
        'authToken': token,
        'password_token': token,
        'created_at': created_at,
        'data': {
            'userid': user.id,
            'authToken': token
        }
    }), 201


@app.route('/login', methods=['POST'], strict_slashes=False)
@limiter.limit("5 per minute")
def login():
    time.sleep(0.6)  # 🔐 mitigate brute force timing

    # -------------------------
    # Get JSON safely
    # -------------------------
    if not request.is_json:
        return error_response('ต้องส่งข้อมูลเป็น JSON', 400, 'VALIDATION_ERROR')

    data = request.get_json(silent=True) or {}
    username_input = (data.get('username') or '').strip()
    password = data.get('password') or ''

    if not username_input or not password:
        return error_response('กรุณากรอกชื่อผู้ใช้และรหัสผ่าน', 400, 'VALIDATION_ERROR')


    # -------------------------
    # Lookup user (email or username)
    # -------------------------
    try:
        # If the input contains an @ assume an email and compare case-insensitively.
        # Otherwise compare username case-insensitively.
        if '@' in username_input:
            user = User.query.filter(func.lower(User.email) == username_input.lower()).first()
        else:
            user = User.query.filter(func.lower(User.username) == username_input.lower()).first()
    except Exception:
        app.logger.exception('DB lookup failed during login')
        return error_response('เกิดข้อผิดพลาดที่เซิร์ฟเวอร์ กรุณาลองใหม่ภายหลัง', 500, 'SERVER_ERROR')

    app.logger.info('Login attempt: input=%s found=%s', username_input, 'yes' if user else 'no')

    # If user not found -> authentication error (don't leak which)
    if not user:
        app.logger.info('Login failed: user not found input=%s', username_input)
        return error_response('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง', 401, 'UNAUTHORIZED')

    # Note: do not immediately reject deleted users here. We want the client
    # to be required to provide the correct password first. Record the deleted
    # flag for logging/diagnostics and continue to password verification.
    if getattr(user, 'is_deleted', False):
        reason_tmp = getattr(user, 'delete_reason', None) or 'ไม่มีเหตุผล'
        app.logger.info('Login attempt for deleted user_id=%s reason=%s — will verify password before responding', user.id, reason_tmp)

    # -------------------------
    # Check permanent password (using werkzeug check_password_hash)
    # -------------------------
    if not user.password_hash:
        app.logger.info('Login failed: missing password hash for user_id=%s', user.id)
        return error_response('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง', 401, 'UNAUTHORIZED')

    # Extra defensive guard: if the stored "password_hash" accidentally contains
    # a plaintext password (migration bug or manual DB edit), never accept a
    # direct equality — require proper hashed check only.
    try:
        if isinstance(user.password_hash, str) and password == user.password_hash:
            app.logger.warning('Login failed: password equals stored hash (possible plaintext) for user_id=%s', user.id)
            return error_response('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง', 401, 'UNAUTHORIZED')
    except Exception:
        pass

    perm_ok = False
    try:
        perm_ok = check_password_hash(user.password_hash, password)
    except Exception:
        perm_ok = False

    app.logger.info('Login password check: user_id=%s perm_ok=%s hash_len=%s', user.id, perm_ok, len(user.password_hash or ''))

    # -------------------------
    # Success case (ตรวจสอบเฉพาะรหัสผ่านหลัก)
    # -------------------------
    if perm_ok:
        # Defensive: if the user was marked deleted concurrently, do not allow login.
        if getattr(user, 'is_deleted', False):
            reason = getattr(user, 'delete_reason', None) or 'ไม่มีเหตุผล'
            app.logger.info('Login blocked after password verified: deleted user_id=%s reason=%s', user.id, reason)
            msg = f'บัญชีถูกลบโดยผู้ดูแล: {reason}'
            return jsonify({
                'is_error': True,
                'error': msg,
                'code': 'FORBIDDEN',
                'message': msg,
                'delete_reason': reason,
                'is_deleted': True
            }), 403
        # generate a server-side token (keeps compatibility with other endpoints)
        new_token = secrets.token_urlsafe(32)
        user.password_token = new_token
        user.token_created_at = get_thailand_time()

        # ล้างค่าระบบ OTP เก่าออกทันทีเพื่อความปลอดภัยสูงสุดหลังเปลี่ยนรหัสและเข้าสู่ระบบสำเร็จ
        user.reset_token_hash = None
        user.reset_token_expires_at = None
        user.reset_password_otp = None
        user.reset_otp_attempts = 0

        try:
            db.session.commit()
        except Exception:
            db.session.rollback()
            return error_response('database error', 500)
        app.logger.info('Login success: user_id=%s', user.id)

        return jsonify({
            'message': 'Login successful',
            'id': user.id,
            'user_id': user.id,
            'username': user.username,
            'email': user.email,
            'authToken': new_token,
            'password_token': new_token,
            'is_deleted': bool(getattr(user, 'is_deleted', False)),
            'delete_reason': getattr(user, 'delete_reason', None),
            'data': {
                'userid': user.id,
                'authToken': new_token
            }
        }), 200

    # -------------------------
    # Failure: wrong password
    # -------------------------
    app.logger.info('Login failed: invalid credentials user_id=%s', user.id if user else 'unknown')
    return error_response('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง', 401, 'UNAUTHORIZED')

def _serialize_user_profile(user):
    age = calc_age(user.date_of_birth)
    bmi_val = calc_bmi(user.weight, user.height)
    return {
        'id': user.id,
        'username': user.username,
        'email': user.email,
        'name': user.name,
        'surname': user.surname,
        'avatar_url': user.avatar_url,
        'gender': user.gender,
        'date_of_birth': user.date_of_birth.isoformat() if user.date_of_birth else None,
        'age': age,
        'weight': user.weight,
        'height': user.height,
        'activity_level': user.activity_level,
        # bmi_val เป็น None ได้ถ้ายังไม่กรอกน้ำหนัก/ส่วนสูง — coerce เป็น 0
        # กัน client ที่ cast แบบ non-nullable พังแบบเดียวกับที่เจอใน
        # /api/dashboard มาก่อน (ดูคอมเมนต์ที่ _dashboard_summary_for_user)
        'bmi': bmi_val or 0,
        'bmi_status': calc_bmi_status(bmi_val),
        'health_goal': user.health_goal,
        'calories_goal': user.calories_goal,
        'health_goal_start_weight': user.health_goal_start_weight,
        'health_goal_locked_until': user.health_goal_locked_until.isoformat() if user.health_goal_locked_until else None,
        # ให้ฝั่ง Flutter คำนวณ "วันที่ N" ของรอบเป้าหมาย (ดูปุ่ม "บันทึก
        # ย้อนหลัง" ในหน้าหลัก/ประวัติ) — เดิมไม่เคยส่งฟิลด์นี้ออกมาเลย
        'health_goal_started_at': user.health_goal_started_at.isoformat() if user.health_goal_started_at else None,
        'health_goal_target_weight': user.health_goal_target_weight,
        'health_goal_target_days': user.health_goal_target_days,
        'health_goal_calorie_adjustment': user.health_goal_calorie_adjustment,
        'chronic_diseases': user.chronic_diseases or [],
        'food_allergies': user.food_allergies or [],
        'is_admin': bool(user.is_admin),
        'is_deleted': bool(user.is_deleted),
        'delete_reason': user.delete_reason,
        'deleted_at': user.deleted_at.isoformat() if user.deleted_at else None,
        'created_at': user.created_at.isoformat() if user.created_at else None,
    }


@app.route('/user/<int:user_id>', methods=['GET', 'POST'])
@limiter.limit("30 per minute")
def user_info(user_id):
    # Ensure any cached ORM state is expired so we load fresh values from DB
    try:
        db.session.expire_all()
    except Exception:
        pass
    user = User.query.get_or_404(user_id)
    # Require Authorization for both GET and POST — ต้องเป็น token ของ user
    # คนนี้เองเท่านั้น (ไม่ใช่แค่ token ที่ valid ของ user คนไหนก็ได้)
    requester, err = _require_auth_user()
    if err:
        return err
    if requester.id != user.id:
        return error_response('ไม่มีสิทธิ์เข้าถึงข้อมูลผู้ใช้นี้', 403, 'FORBIDDEN')

    if request.method == 'GET':
        _finalize_expired_goal_cycle(user)
        return jsonify(_serialize_user_profile(user)), 200

    # POST -> update personal info. age/bmi are never accepted from the
    # client — they're always computed live from date_of_birth/weight/height.
    data = request.json or {}

    _audit_orig = {
        'name': user.name,
        'surname': user.surname,
        'gender': user.gender,
        'date_of_birth': user.date_of_birth.isoformat() if user.date_of_birth else None,
        'weight': user.weight,
        'height': user.height,
        'activity_level': user.activity_level,
        'chronic_diseases': user.chronic_diseases,
        'food_allergies': user.food_allergies,
    }

    if 'name' in data:
        user.name = (data.get('name') or '').strip() or None
    if 'surname' in data:
        user.surname = (data.get('surname') or '').strip() or None
    if 'gender' in data:
        user.gender = data.get('gender') or None
    if 'date_of_birth' in data:
        dob_parsed = parse_date_of_birth(data.get('date_of_birth'))
        if dob_parsed is not None:
            # ต้องอายุ 13 ปีขึ้นไปถึงจะกรอกข้อมูลโปรไฟล์ได้ (ตรวจจากวันเกิดจริง
            # ไม่ใช่ตัวเลขอายุที่ client ส่งมาตรงๆ กัน bypass)
            entered_age = calc_age(dob_parsed)
            if entered_age is not None and entered_age < 13:
                return error_response(
                    'ต้องมีอายุ 13 ปีขึ้นไปจึงจะกรอกข้อมูลโปรไฟล์ได้', 400, 'VALIDATION_ERROR'
                )
            user.date_of_birth = dob_parsed
    if 'weight' in data:
        try:
            new_weight = float(data['weight']) if data['weight'] not in (None, '') else None
        except (TypeError, ValueError):
            new_weight = user.weight
        if new_weight is not None and not (0 < new_weight <= 1000):
            return error_response('น้ำหนักต้องอยู่ระหว่าง 1 ถึง 1000 กก.', 400, 'VALIDATION_ERROR')
        user.weight = new_weight
    if 'height' in data:
        try:
            new_height = float(data['height']) if data['height'] not in (None, '') else None
        except (TypeError, ValueError):
            new_height = user.height
        if new_height is not None and not (0 < new_height <= 300):
            return error_response('ส่วนสูงต้องอยู่ระหว่าง 1 ถึง 300 ซม.', 400, 'VALIDATION_ERROR')
        user.height = new_height
    if 'activity_level' in data:
        user.activity_level = (data.get('activity_level') or '').strip() or None

    if 'chronic_diseases' in data:
        user.chronic_diseases = _sanitize_string_list(data.get('chronic_diseases'))
    if 'food_allergies' in data:
        user.food_allergies = _sanitize_string_list(data.get('food_allergies'))

    _audit_new = {
        'name': user.name,
        'surname': user.surname,
        'gender': user.gender,
        'date_of_birth': user.date_of_birth.isoformat() if user.date_of_birth else None,
        'weight': user.weight,
        'height': user.height,
        'activity_level': user.activity_level,
        'chronic_diseases': user.chronic_diseases,
        'food_allergies': user.food_allergies,
    }
    for _field, _old in _audit_orig.items():
        _new = _audit_new[_field]
        if _old != _new:
            db.session.add(ProfileAuditLog(
                user_id=user.id,
                field_name=_field,
                old_value=None if _old is None else str(_old),
                new_value=None if _new is None else str(_new),
            ))

    # calories_goal เดิมคำนวณแค่ครั้งเดียวตอน save_health_goal() แล้วค้างค่าไว้
    # จนครบรอบล็อก (ตามจำนวนวันที่ผู้ใช้ตั้งไว้ — ดู custom_days ใน
    # save_health_goal()) แม้ผู้ใช้จะมาเปลี่ยนน้ำหนัก/ส่วนสูง/กิจกรรมที่นี่ก็ตาม
    # (บั๊กที่เจอจริง — หน้าพรีวิว BMI โชว์เลขใหม่ แต่เป้าหมายจริงไม่ขยับ) จึง
    # คำนวณ TDEE ใหม่สดๆ ทุกครั้งที่ค่าที่มีผลต่อ TDEE เปลี่ยน โดยไม่แตะ
    # weight_goal/health_goal_locked_until (ยังล็อกทิศทางเป้าหมายไว้ตามรอบเดิมเหมือนเดิม)
    # เดิมเช็คแค่ weight/height/activity_level — gender กับ date_of_birth (อายุ)
    # ก็เข้าสูตร calc_tdee() ด้วยเหมือนกัน (gender ยังกำหนด floor 1200/1500 อีก)
    # แก้แค่ 2 ช่องนี้แล้ว calories_goal เดิมจะไม่ขยับตามเลย (ผู้ใช้รายงานจริง)
    _tdee_inputs_changed = any(
        _audit_orig[f] != _audit_new[f]
        for f in ('weight', 'height', 'activity_level', 'gender', 'date_of_birth')
    )
    if user.health_goal and _tdee_inputs_changed:
        _tdee = calc_tdee(user.weight, user.height, calc_age(user.date_of_birth), user.gender, user.activity_level)
        if _tdee is not None:
            # เป้าหมายที่ตั้งจากกล่อง "วางแผนพลังงาน" (มี target_weight/days)
            # ต้องคำนวณด้วยสูตรเดียวกับตอนบันทึกครั้งแรกใน save_health_goal()
            # (calc_calories_goal_custom ปรับตาม TDEE ที่ disease-adjusted แล้ว)
            # ไม่ใช่สูตร ±500 เดิม — เดิมโค้ดนี้ใช้ calc_calories_goal() เสมอไม่ว่า
            # เป้าหมายจะมี target_weight ผูกอยู่หรือไม่ ทำให้ calories_goal ที่
            # persist จริงหลังแก้น้ำหนัก/ส่วนสูง/กิจกรรม ไม่ตรงกับแผนที่ตั้งไว้
            # เลย (ผู้ใช้รายงานจริง)
            _adjusted_tdee = _tdee * (1.0 + disease_adjustment_factor(user.chronic_diseases))
            _custom_calories = (
                calc_calories_goal_custom(
                    _adjusted_tdee, user.weight, user.health_goal_target_weight,
                    user.health_goal_target_days, user.gender,
                )
                if user.health_goal_target_weight is not None else None
            )
            if _custom_calories is not None:
                _daily_adjustment = (
                    (user.health_goal_target_weight - user.weight) * 7700
                    / user.health_goal_target_days
                )
                _calorie_floor = 1200 if user.gender == 'หญิง' else 1500
                if abs(_daily_adjustment) > 1000 or _custom_calories <= 0 or (
                    user.health_goal == 'ลดน้ำหนัก' and _custom_calories < _calorie_floor
                ):
                    db.session.rollback()
                    return error_response(
                        'แผนเป้าหมายทำให้พลังงานต่อวันต่ำหรือปรับมากกว่าขอบเขตที่ปลอดภัย '
                        'กรุณาเพิ่มจำนวนวันหรือปรับน้ำหนักเป้าหมาย',
                        400,
                        'UNSAFE_HEALTH_GOAL',
                    )
            user.calories_goal = (
                _custom_calories if _custom_calories is not None
                else calc_calories_goal(_adjusted_tdee, user.health_goal, user.gender)
            )

    try:
        db.session.add(user)
        db.session.commit()
    except Exception:
        app.logger.exception('user_info commit failed for user_id=%s', user_id)
        db.session.rollback()
        return error_response('เกิดข้อผิดพลาดที่เซิร์ฟเวอร์ กรุณาลองใหม่ภายหลัง', 500, 'SERVER_ERROR')

    return jsonify(_serialize_user_profile(user)), 200


@app.route('/user/<int:user_id>/avatar', methods=['POST'])
@limiter.limit("10 per minute")
def upload_user_avatar(user_id):
    user = User.query.get_or_404(user_id)
    requester, err = _require_auth_user()
    if err:
        return err
    if requester.id != user.id:
        return error_response('ไม่มีสิทธิ์เข้าถึงข้อมูลผู้ใช้นี้', 403, 'FORBIDDEN')

    file = request.files.get('avatar')
    if not file or not file.filename:
        return error_response('กรุณาแนบไฟล์รูปภาพ (avatar)', 400, 'VALIDATION_ERROR')

    ext = file.filename.rsplit('.', 1)[-1].lower() if '.' in file.filename else ''
    if ext not in ALLOWED_AVATAR_EXTENSIONS:
        return error_response('รองรับเฉพาะไฟล์ JPG, PNG หรือ WEBP เท่านั้น', 400, 'VALIDATION_ERROR')

    file.seek(0, os.SEEK_END)
    size = file.tell()
    file.seek(0)
    if size <= 0:
        return error_response('ไฟล์รูปว่างเปล่า', 400, 'VALIDATION_ERROR')
    if size > MAX_AVATAR_BYTES:
        return error_response('ไฟล์รูปใหญ่เกินไป (จำกัด 5MB)', 400, 'VALIDATION_ERROR')

    try:
        from PIL import Image
        img = Image.open(file.stream)
        img.verify()  # ยืนยันว่าเป็นไฟล์รูปจริง ไม่ใช่แค่ตั้งชื่อ .jpg หลอก
        file.stream.seek(0)
        img = Image.open(file.stream)
        img.load()
        if img.mode != 'RGB':
            img = img.convert('RGB')
        img.thumbnail((MAX_AVATAR_DIMENSION_PX, MAX_AVATAR_DIMENSION_PX))
    except Exception:
        return error_response('ไฟล์ที่แนบไม่ใช่รูปภาพที่ถูกต้อง', 400, 'VALIDATION_ERROR')

    os.makedirs(AVATAR_UPLOAD_DIR, exist_ok=True)
    filename = secure_filename(f'user_{user.id}_{secrets.token_hex(8)}.jpg')
    filepath = os.path.join(AVATAR_UPLOAD_DIR, filename)

    # ลบรูปเก่าของ user คนนี้ทิ้ง กันไฟล์ขยะสะสมไม่มีวันหมดทุกครั้งที่เปลี่ยนรูป
    try:
        if user.avatar_url:
            old_filename = secure_filename(user.avatar_url.rsplit('/', 1)[-1])
            old_path = os.path.join(AVATAR_UPLOAD_DIR, old_filename)
            if os.path.exists(old_path):
                os.remove(old_path)
    except Exception:
        pass

    try:
        img.save(filepath, 'JPEG', quality=85)
    except Exception:
        app.logger.exception('avatar save failed for user_id=%s', user_id)
        return error_response('บันทึกรูปไม่สำเร็จ กรุณาลองใหม่ภายหลัง', 500, 'SERVER_ERROR')

    user.avatar_url = f'/uploads/avatars/{filename}'
    db.session.add(user)
    db.session.commit()

    return jsonify(_serialize_user_profile(user)), 200


@app.route('/uploads/avatars/<path:filename>')
def serve_avatar(filename):
    safe_name = secure_filename(filename)
    filepath = os.path.join(AVATAR_UPLOAD_DIR, safe_name)
    if not os.path.exists(filepath) or not os.path.isfile(filepath):
        return error_response('ไม่พบรูปภาพ', 404, 'NOT_FOUND')
    return send_file(filepath)


@app.route('/user/<int:user_id>/mark-saved', methods=['POST'])
@limiter.limit("10 per minute")
def user_mark_saved(user_id):
    """Lightweight endpoint the frontend calls to confirm a profile save;
    just validates the token — nothing else to record since History was
    removed (meal-eaten events now live in meal_log_items)."""
    user = User.query.get_or_404(user_id)
    requester, err = _require_auth_user()
    if err:
        return err
    if requester.id != user.id:
        return error_response('ไม่มีสิทธิ์เข้าถึงข้อมูลผู้ใช้นี้', 403, 'FORBIDDEN')
    return jsonify({'status': 'ok'}), 200


@app.route('/admin/set-password', methods=['POST'])
@limiter.limit("5 per minute")
def admin_set_password():
    """
    Admin helper to set a user's permanent password.
    Protected by ADMIN_SECRET (header only).
    Disabled automatically outside development unless explicitly allowed.
    """

    # =========================
    # 🔒 Environment restriction
    # =========================
    if os.environ.get("FLASK_ENV") != "development":
        return error_response('forbidden', 403)
    # =========================
    # 🔒 Header secret check
    # =========================
    admin_secret = os.environ.get('ADMIN_SECRET')
    provided = request.headers.get('X-Admin-Secret')

    if not admin_secret or not provided or not secrets.compare_digest(provided, admin_secret):
        return error_response('forbidden', 403)
    # =========================
    # 📥 Input
    # =========================
    data = request.json or {}
    username = (data.get('username') or '').strip()
    password = (data.get('password') or '').strip()

    if not username or not password:
        return error_response('username and password required', 400)
    # =========================
    # 🔒 Password policy
    # =========================
    if len(password) < 8 \
       or not re.search(r'[A-Z]', password) \
       or not re.search(r'[a-z]', password) \
       or not re.search(r'\d', password) \
       or not re.search(r'[!@#$%&*()]', password):
        return error_response('password must include upper, lower, digit, special and be 8+ chars', 400)

    user = User.query.filter(func.lower(User.username) == username.lower()).first()

    # 🔐 ไม่เปิดเผยว่ามี user หรือไม่
    if not user:
        return jsonify({'status': 'ok'}), 200

    try:
        # =========================
        # 🔄 Set new permanent password
        # =========================
        user.password_hash = generate_password_hash(password)

        # No temporary-password fields remain in the model; nothing to clear

        # 🔄 Rotate login token immediately
        user.password_token = secrets.token_urlsafe(32)
        user.token_created_at = get_thailand_time()

        # Mark password change time
        user.password_changed_at = get_thailand_time()

        db.session.commit()

    except Exception:
        db.session.rollback()
        app.logger.exception('Failed to set admin password')
        return error_response('database error', 500)
    return jsonify({'status': 'ok'}), 200


# -----------------------------
# Health Goal Endpoints
# -----------------------------
HEALTH_GOALS = ('ลดน้ำหนัก', 'รักษาน้ำหนัก', 'เพิ่มน้ำหนัก')


@app.route('/api/user/health-goal', methods=['POST'])
@limiter.limit("20 per minute")
def save_health_goal():
    """Set health_goal (one of HEALTH_GOALS) and compute+persist calories_goal
    from the user's current TDEE (weight/height/age/gender/activity_level)."""
    data = request.get_json(silent=True) or {}

    user, err = _require_auth_user()
    if err:
        return err

    goal = (data.get('health_goal') or '').strip()
    if goal not in HEALTH_GOALS:
        return error_response(
            f"health_goal ต้องเป็นหนึ่งใน {', '.join(HEALTH_GOALS)} เท่านั้น", 400, 'INVALID_HEALTH_GOAL'
        )

    calorie_adjustment = data.get('calorie_adjustment')
    if calorie_adjustment is not None:
        try:
            parsed_adjustment = float(calorie_adjustment)
        except (TypeError, ValueError):
            return error_response('อัตราแคลอรีไม่ถูกต้อง', 400, 'VALIDATION_ERROR')
        if (
            goal == 'รักษาน้ำหนัก'
            or not parsed_adjustment.is_integer()
            or int(parsed_adjustment) not in (500, 1000)
        ):
            return error_response(
                'อัตราแคลอรีต้องเป็น 500 หรือ 1000 kcal/วัน สำหรับเป้าหมายลด/เพิ่มน้ำหนัก',
                400,
                'VALIDATION_ERROR',
            )
        calorie_adjustment = int(parsed_adjustment)

    # ก่อนจะให้ตั้งเป้าหมายใหม่ (ซึ่งจะเขียนทับ health_goal_locked_until เดิม)
    # ต้องสรุปผลรอบก่อนหน้าที่หมดอายุแล้วก่อน ไม่งั้นคำนวณ period_start ของ
    # รอบเก่าย้อนหลังไม่ได้อีกเลย (ดู _finalize_expired_goal_cycle)
    _finalize_expired_goal_cycle(user)

    now_thailand = get_thailand_time()
    tdee = calc_tdee(user.weight, user.height, calc_age(user.date_of_birth), user.gender, user.activity_level)
    if tdee is None:
        return error_response(
            'ต้องกรอกน้ำหนัก ส่วนสูง วันเกิด เพศ และกิจกรรม ก่อนตั้งเป้าหมาย', 400, 'PROFILE_INCOMPLETE'
        )
    # ปรับ TDEE ตามโรคประจำตัวก่อนคิด calories_goal — เดิมพรีวิวหน้าโปรไฟล์
    # ปรับตามโรคแล้ว (ดู bmi_calculator.dart) แต่ตัวเลขที่บันทึกจริงตรงนี้
    # ไม่เคยปรับตาม ทำให้พรีวิว/ค่าจริงไม่ตรงกัน
    adjusted_tdee = tdee * (1.0 + disease_adjustment_factor(user.chronic_diseases))

    # จำนวนวันที่ล็อกเป้าหมายไว้ มาจากแผนพลังงานที่ผู้ใช้กรอกจริง (ฝั่ง Flutter
    # ส่ง "days" มาจากช่อง "จำนวนวัน" ในกล่องวางแผนพลังงาน) — เดิมล็อกตายตัว
    # 7 วันเสมอไม่ว่าจะวางแผนกี่วันก็ตาม (ผู้ใช้รายงานจริง: อยากให้ระยะเวลา
    # ล็อกตรงกับแผนจริง เช่น วางแผน 30 วัน ก็ควรล็อก 30 วัน) กันค่าประหลาด
    # (0/ลบ/พิมพ์ผิดเป็นตัวเลขมหาศาล) ด้วยการ clamp ไว้ 1-3650 วัน (10 ปี)
    # ไม่มี/parse ไม่ได้ fallback กลับไปที่ 7 วันเดิมเพื่อความเข้ากันได้ย้อนหลัง
    target_weight_provided = data.get('target_weight') is not None
    try:
        custom_days = int(data.get('days'))
        if target_weight_provided and not 1 <= custom_days <= 3650:
            return error_response('จำนวนวันต้องอยู่ระหว่าง 1 ถึง 3650 วัน', 400, 'VALIDATION_ERROR')
        if not target_weight_provided:
            custom_days = min(max(custom_days, 1), 3650)
    except (TypeError, ValueError):
        if target_weight_provided:
            return error_response('กรุณาระบุจำนวนวันให้ถูกต้อง', 400, 'VALIDATION_ERROR')
        custom_days = 7

    # น้ำหนักเป้าหมาย (ฝั่ง Flutter ส่ง "target_weight" มาจากกล่องวางแผน
    # พลังงานเดียวกัน) — ถ้ามีให้คำนวณ calories_goal แบบเจาะจงตามแผนจริง
    # (สูตรเดียวกับพรีวิวหน้าโปรไฟล์ _dietRecommendedFor() เป๊ะ) ไม่มี/parse
    # ไม่ได้ก็ fallback ไปสูตร ±500 คงที่เดิม (ผู้ใช้รายงานจริง: บันทึกเป้าหมาย
    # จากกล่องวางแผนพลังงานที่กรอกน้ำหนักเป้าหมาย+จำนวนวันไว้แล้ว แต่ตัวเลขที่
    # แดชบอร์ดโชว์จริงไม่ตรงกับที่พรีวิวไว้ในหน้าโปรไฟล์เลย เพราะ endpoint นี้
    # ไม่เคยรับ/ใช้น้ำหนักเป้าหมายมาคิดเลย มีแต่สูตร TDEE±500 ตายตัว)
    target_weight = None
    try:
        tw = data.get('target_weight')
        if tw is not None:
            target_weight = float(tw)
    except (TypeError, ValueError):
        if target_weight_provided:
            return error_response('น้ำหนักเป้าหมายไม่ถูกต้อง', 400, 'VALIDATION_ERROR')

    if target_weight_provided and (
        target_weight is None or target_weight <= 0 or target_weight > 1000
    ):
        return error_response('น้ำหนักเป้าหมายต้องอยู่ระหว่าง 1 ถึง 1000 กก.', 400, 'VALIDATION_ERROR')

    if target_weight_provided:
        if goal == 'ลดน้ำหนัก' and target_weight >= user.weight:
            return error_response('เป้าหมายลดน้ำหนักต้องต่ำกว่าน้ำหนักปัจจุบัน', 400, 'VALIDATION_ERROR')
        if goal == 'เพิ่มน้ำหนัก' and target_weight <= user.weight:
            return error_response('เป้าหมายเพิ่มน้ำหนักต้องสูงกว่าน้ำหนักปัจจุบัน', 400, 'VALIDATION_ERROR')
        if goal == 'รักษาน้ำหนัก' and abs(target_weight - user.weight) > 0.5:
            return error_response('เป้าหมายรักษาน้ำหนักต้องใกล้เคียงน้ำหนักปัจจุบันไม่เกิน 0.5 กก.', 400, 'VALIDATION_ERROR')

        daily_adjustment = ((target_weight - user.weight) * 7700) / custom_days
        if abs(daily_adjustment) > 1000:
            return error_response(
                'แผนเป้าหมายต้องปรับพลังงานไม่เกิน 1000 kcal/วัน '
                'กรุณาเพิ่มจำนวนวันหรือปรับน้ำหนักเป้าหมาย',
                400,
                'UNSAFE_HEALTH_GOAL',
            )

    custom_calories = (
        calc_calories_goal_custom(adjusted_tdee, user.weight, target_weight, custom_days, user.gender)
        if target_weight_provided else None
    )

    calorie_floor = 1200 if user.gender == 'หญิง' else 1500
    if target_weight_provided and (
        custom_calories is None or custom_calories <= 0 or (
            goal == 'ลดน้ำหนัก' and custom_calories < calorie_floor
        )
    ):
        return error_response(
            'พลังงานที่แนะนำต่ำกว่าขั้นต่ำที่ปลอดภัย '
            'กรุณาเพิ่มจำนวนวันหรือปรับน้ำหนักเป้าหมาย',
            400,
            'UNSAFE_HEALTH_GOAL',
        )

    user.health_goal = goal
    user.calories_goal = (
        custom_calories if custom_calories is not None
        else calc_calories_goal(adjusted_tdee, goal, user.gender)
    )
    user.health_goal_start_weight = user.weight
    # เก็บอินพุตที่ใช้คำนวณไว้ด้วย (ไม่ใช่แค่ผลลัพธ์) ให้ฝั่ง Flutter โหลด
    # กลับมาเติมช่อง "เป้าหมายน้ำหนักที่ต้องการ"/"จำนวนวัน" ได้หลังรีเฟรช —
    # ไม่มี target_weight รอบนี้ (fallback ไปสูตร ±500) ก็เคลียร์ทิ้งไปด้วย
    # กันโชว์ค่าเก่าจากเป้าหมายก่อนหน้าที่ไม่เกี่ยวกันแล้ว
    user.health_goal_target_weight = target_weight
    user.health_goal_target_days = custom_days if target_weight is not None else None
    user.health_goal_calorie_adjustment = calorie_adjustment
    user.health_goal_started_at = now_thailand.replace(tzinfo=None)
    # เปลี่ยนเป้าหมายได้อีกครั้งพอถึง 22:00 (มื้อเย็นปิดรับ ดู
    # MEAL_TIME_WINDOWS['dinner']) ของ "วันที่ N" นับจากวันนี้เป็นวันที่ 1 —
    # ไม่ใช่ now+N*24 ชม.ตรงๆ เพราะงั้นรอบจะจบกลางดึก/กลางมื้อแทนที่จะจบพร้อม
    # มื้อสุดท้ายของวันจริงตามที่ผู้ใช้ต้องการ
    day_n = now_thailand.date() + timedelta(days=custom_days - 1)
    dinner_end_hour = MEAL_TIME_WINDOWS['dinner'][1]
    user.health_goal_locked_until = datetime(
        day_n.year, day_n.month, day_n.day, dinner_end_hour, 0,
        tzinfo=timezone(timedelta(hours=7)),
    )
    db.session.add(user)
    db.session.commit()

    return jsonify({
        'status': 'ok',
        'health_goal': user.health_goal,
        'calories_goal': user.calories_goal,
        'health_goal_start_weight': user.health_goal_start_weight,
        'health_goal_locked_until': user.health_goal_locked_until.isoformat(),
        'health_goal_target_weight': user.health_goal_target_weight,
        'health_goal_target_days': user.health_goal_target_days,
        'health_goal_calorie_adjustment': user.health_goal_calorie_adjustment,
    }), 200


@app.route('/api/user/health-goal/<int:user_id>', methods=['GET'])
@limiter.limit("60 per minute")
def get_user_health_goal(user_id):
    user = User.query.get_or_404(user_id)
    locked_until = user.health_goal_locked_until
    return jsonify({
        'health_goal': user.health_goal,
        'calories_goal': user.calories_goal,
        'health_goal_start_weight': user.health_goal_start_weight,
        'health_goal_locked_until': locked_until.isoformat() if locked_until else None,
        'health_goal_target_weight': user.health_goal_target_weight,
        'health_goal_target_days': user.health_goal_target_days,
        'health_goal_calorie_adjustment': user.health_goal_calorie_adjustment,
    }), 200


def _serialize_goal_cycle(cycle):
    logs = MealLog.query.options(selectinload(MealLog.items)).filter(
        MealLog.user_id == cycle.user_id,
        MealLog.log_date >= cycle.period_start.date(),
        MealLog.log_date <= cycle.period_end.date(),
    ).all()
    eaten_calories_by_day = {}
    for log in logs:
        eaten_calories_by_day[log.log_date] = eaten_calories_by_day.get(log.log_date, 0.0) + sum(
            float(item.calories_actual or 0)
            for item in log.items
            if item.is_eaten
        )
    calories_goal = float(cycle.calories_goal or 0)
    daily_quota_excess_percent = max(
        (
            ((calories - calories_goal) / calories_goal) * 100
            for calories in eaten_calories_by_day.values()
            if calories_goal > 0 and calories > calories_goal
        ),
        default=0.0,
    )
    return {
        'id': cycle.id,
        'health_goal': cycle.health_goal,
        'calories_goal': cycle.calories_goal,
        'period_start': cycle.period_start.isoformat(),
        'period_end': cycle.period_end.isoformat(),
        'meals_logged': cycle.meals_logged,
        'meals_available': cycle.meals_available,
        'meals_over_quota': cycle.meals_over_quota,
        'daily_quota_excess_percent': daily_quota_excess_percent,
        'success_ratio': cycle.success_ratio,
        'is_success': bool(cycle.is_success),
        'weight_start': cycle.weight_start,
        'weight_end': cycle.weight_end,
        'weight_delta': cycle.weight_delta,
    }


@app.route('/api/user/health-goal-cycles', methods=['GET'])
@limiter.limit("60 per minute")
def health_goal_cycles():
    """ประวัติผลรอบเป้าหมายสุขภาพ 7 วันที่จบไปแล้วทั้งหมดของผู้ใช้คนนี้ —
    ให้หน้า "ประวัติ" ฝั่ง Flutter ดึงมาโชว์สะสมทีละรอบ (ดู
    _finalize_expired_goal_cycle สำหรับตรรกะคำนวณ)"""
    user, err = _require_auth_user()
    if err:
        return err
    _finalize_expired_goal_cycle(user)
    cycles = HealthGoalCycle.query.filter_by(user_id=user.id).order_by(
        HealthGoalCycle.period_end.desc()
    ).all()
    return jsonify({'cycles': [_serialize_goal_cycle(c) for c in cycles]}), 200


@app.route('/menu-info', methods=['POST'])
@limiter.limit("30 per minute")
def menu_info():
    """Batch lookup for menu names -> calories + รายละเอียดสารอาหาร (food_items).

    Request JSON: { "names": ["Name1", "Name2"] }
    Response JSON: { "items": [{"name": "Name1", "kcal": 123, "protein": ..,
        "carbs": .., "fat": .., "sugar": .., "fiber": ..}, ...] }
    """
    try:
        if not request.is_json:
            return error_response('JSON body required', 400)
        data = request.get_json(silent=True) or {}
        names = data.get('names') or []
        if not isinstance(names, list):
            return error_response('names must be list', 400)
        out = []
        for n in names:
            if not n or not isinstance(n, str):
                out.append({'name': n, 'kcal': None})
                continue
            name = n.strip()
            item = FoodItem.query.filter(
                db.or_(FoodItem.name == name, FoodItem.name_th == name)
            ).first()
            if item is None:
                out.append({'name': name, 'kcal': 0, 'group': 'unknown', 'image_url': ''})
                continue
            out.append({
                'name': name,
                'kcal': int(item.calories or 0),
                'group': item.category.type if item.category else None,
                'image_url': item.image_url or '',
                'protein': item.protein_g,
                'carbs': item.carbs_g,
                'fat': item.fat_g,
                'sugar': item.sugar_g,
                'fiber': item.fiber_g,
            })

        return jsonify({'items': out})
    except Exception:
        app.logger.exception('menu-info failed')
        return jsonify({'items': []}), 500
def get_current_user_from_jwt():
    auth = request.headers.get('Authorization') or ''
    if not auth.startswith('Bearer '):
        return None

    token = auth.split(' ', 1)[1].strip()
    user = User.query.filter_by(password_token=token).first()
    if not user or not token_valid_for_user(user, token):
        return None
    return user


@app.route('/api/report_problem', methods=['POST'])
@limiter.limit("10 per minute")
def report_problem():
    # เดิมลองอ่านจาก get_jwt_identity() ก่อน (flask_jwt_extended) แต่ไม่มี
    # route ไหนใน app นี้ตั้ง JWT context จริงเลย (auth จริงทั้งหมดใช้ token
    # สุ่มผ่าน get_current_user_from_jwt()/_require_auth_user() — ชื่อฟังก์ชัน
    # ชวนสับสนแต่ไม่ใช่ JWT จริง) ผลคือ get_jwt_identity() คืน None เสมอ
    # ตัดโค้ดที่ตายแล้วทิ้ง เรียก get_current_user_from_jwt() ตรงๆ
    user = get_current_user_from_jwt()
    if not user:
        return error_response("ไม่พบข้อมูลผู้ใช้", 404)
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        data = request.form.to_dict() or {}

    title = (data.get('title') or data.get('subject') or '').strip()
    message = (data.get('message') or data.get('detail') or '').strip()
    if not title or not message:
        return error_response('กรุณากรอกหัวข้อและรายละเอียดปัญหา', 400, 'VALIDATION_ERROR')

    try:
        new_report = Report(user_id=user.id, title=title, message=message, status='pending')
        db.session.add(new_report)
        db.session.flush()  # ให้ new_report.id พร้อมใช้ก่อน commit
        db.session.add(ReportMessage(report_id=new_report.id, sender_type='user', message=message))
        db.session.commit()
        return jsonify({
            "status": "success",
            "message": "ส่งรายงานปัญหาแล้ว",
            "report": {
                "id": new_report.id,
                "title": new_report.title,
                "message": new_report.message,
                "status": new_report.status,
                "admin_reply": new_report.admin_reply,
                "created_at": new_report.created_at.isoformat() if new_report.created_at else None,
            }
        }), 201
    except Exception:
        db.session.rollback()
        app.logger.exception('report_problem failed')
        return error_response("เกิดข้อผิดพลาดในระบบฐานข้อมูล", 500)
@app.route('/api/my_reports', methods=['GET'])
@limiter.limit("30 per minute")
def my_reports():
    # เดิมลองอ่านจาก get_jwt_identity() ก่อน (flask_jwt_extended) แต่ไม่มี
    # route ไหนใน app นี้ตั้ง JWT context จริงเลย (auth จริงทั้งหมดใช้ token
    # สุ่มผ่าน get_current_user_from_jwt()/_require_auth_user() — ชื่อฟังก์ชัน
    # ชวนสับสนแต่ไม่ใช่ JWT จริง) ผลคือ get_jwt_identity() คืน None เสมอ
    # ตัดโค้ดที่ตายแล้วทิ้ง เรียก get_current_user_from_jwt() ตรงๆ
    user = get_current_user_from_jwt()
    if not user:
        return error_response("ไม่พบข้อมูลผู้ใช้", 404)

    q = Report.query.filter_by(user_id=user.id)
    # scope=open (default) -> เฉพาะ ticket ที่ยังดำเนินการอยู่ (โปรไฟล์ใช้ตัวนี้
    # กันไม่ให้รายการยาวสะสม), scope=closed -> เฉพาะที่ปิดแล้ว (หน้าประวัติ)
    scope = (request.args.get('scope') or 'open').strip().lower()
    if scope == 'open':
        q = q.filter(Report.status != 'closed')
    elif scope == 'closed':
        q = q.filter(Report.status == 'closed')
    # scope=all -> ไม่กรอง

    reps = q.order_by(Report.created_at.desc(), Report.id.desc()).limit(200).all()

    reports = [{
        "id": r.id,
        "title": r.title,
        "message": r.message,
        "status": r.status,
        "admin_reply": r.admin_reply,
        "replied_at": r.replied_at.isoformat() if r.replied_at else None,
        "created_at": r.created_at.isoformat() if r.created_at else None,
    } for r in reps]

    return jsonify({"status": "success", "reports": reports}), 200


def _serialize_report_message(m):
    return {
        'id': m.id,
        'report_id': m.report_id,
        'sender_type': m.sender_type,
        'message': m.message,
        'created_at': m.created_at.isoformat() if m.created_at else None,
    }


@app.route('/api/reports/<int:report_id>/messages', methods=['GET', 'POST'])
@limiter.limit("60 per minute")
def report_messages(report_id):
    user, err = _require_auth_user()
    if err:
        return err

    report = Report.query.get_or_404(report_id)
    if report.user_id != user.id:
        return error_response('ไม่มีสิทธิ์เข้าถึง ticket นี้', 403, 'FORBIDDEN')

    if request.method == 'GET':
        msgs = ReportMessage.query.filter_by(report_id=report.id).order_by(ReportMessage.created_at).all()
        return jsonify({
            'messages': [_serialize_report_message(m) for m in msgs],
            'status': report.status,
            'can_reply': report.status != 'closed',
        }), 200

    # POST — ส่งข้อความใหม่ (เฉพาะตอน ticket ยังไม่ปิด) — 409 ไม่ใช่ 403 ด้วย
    # เหตุผลเดียวกับ HEALTH_GOAL_LOCKED ด้านบน (กัน Flutter แม็พเป็น AuthError)
    if report.status == 'closed':
        return error_response('เรื่องนี้ปิดแล้ว ไม่สามารถส่งข้อความเพิ่มได้', 409, 'TICKET_CLOSED')

    data = request.get_json(silent=True) or {}
    message = (data.get('message') or '').strip()
    if not message:
        return error_response('กรุณากรอกข้อความ', 400, 'VALIDATION_ERROR')

    msg = ReportMessage(report_id=report.id, sender_type='user', message=message)
    db.session.add(msg)
    # ผู้ใช้ทักกลับมา -> กลับไปสถานะรอแอดมินตอบเสมอ (เผื่อแอดมินตอบไปแล้วแต่
    # ผู้ใช้มีคำถามต่อ)
    report.status = 'pending'
    db.session.commit()

    return jsonify(_serialize_report_message(msg)), 201


@app.route('/api/reports/unread-count', methods=['GET'])
def reports_unread_count():
    """ticket ที่ยังไม่ปิด และมีข้อความจากแอดมิน (id ใหม่กว่า
    user_last_read_message_id หรือยังไม่เคยอ่านเลย) — นับจำนวน ticket ไม่ใช่
    จำนวนข้อความ (badge ตัวเลขบนหน้าแอปคือ "กี่เรื่อง" ไม่ใช่ "กี่ข้อความ")"""
    user, err = _require_auth_user()
    if err:
        return err

    max_admin_msg = (
        db.session.query(
            ReportMessage.report_id.label('report_id'),
            func.max(ReportMessage.id).label('max_admin_id'),
        )
        .filter(ReportMessage.sender_type == 'admin')
        .group_by(ReportMessage.report_id)
        .subquery()
    )

    rows = (
        db.session.query(Report.id)
        .join(max_admin_msg, max_admin_msg.c.report_id == Report.id)
        .filter(Report.user_id == user.id, Report.status != 'closed')
        .filter(
            db.or_(
                Report.user_last_read_message_id.is_(None),
                max_admin_msg.c.max_admin_id > Report.user_last_read_message_id,
            )
        )
        .all()
    )
    unread_ids = [r[0] for r in rows]
    return jsonify({'unread_count': len(unread_ids), 'unread_report_ids': unread_ids}), 200


@app.route('/api/reports/<int:report_id>/mark-read', methods=['PATCH'])
def mark_report_read(report_id):
    user, err = _require_auth_user()
    if err:
        return err

    report = Report.query.get_or_404(report_id)
    if report.user_id != user.id:
        return error_response('ไม่มีสิทธิ์เข้าถึง ticket นี้', 403, 'FORBIDDEN')

    latest_admin_msg = (
        ReportMessage.query.filter_by(report_id=report.id, sender_type='admin')
        .order_by(ReportMessage.id.desc())
        .first()
    )
    if latest_admin_msg:
        report.user_last_read_message_id = latest_admin_msg.id
        db.session.commit()

    return jsonify({
        'status': 'ok',
        'report_id': report.id,
        'user_last_read_message_id': report.user_last_read_message_id,
    }), 200


@app.route('/api/request_unban', methods=['POST'])
def request_unban():
    """Filed as a regular ticket (title="คำขอปลดแบน") — the new reports
    schema has no separate ticket-type column."""
    # เดิมลองอ่านจาก get_jwt_identity() ก่อน (flask_jwt_extended) แต่ไม่มี
    # route ไหนใน app นี้ตั้ง JWT context จริงเลย (auth จริงทั้งหมดใช้ token
    # สุ่มผ่าน get_current_user_from_jwt()/_require_auth_user() — ชื่อฟังก์ชัน
    # ชวนสับสนแต่ไม่ใช่ JWT จริง) ผลคือ get_jwt_identity() คืน None เสมอ
    # ตัดโค้ดที่ตายแล้วทิ้ง เรียก get_current_user_from_jwt() ตรงๆ
    user = get_current_user_from_jwt()

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        data = request.form.to_dict() or {}

    detail = (data.get('detail') or data.get('message') or '').strip()
    username = (data.get('username') or '').strip()
    email = (data.get('email') or '').strip().lower()

    if not user and not username and not email:
        return error_response("กรุณาระบุชื่อผู้ใช้หรืออีเมลเพื่อยืนยันบัญชี", 400)
    if not detail:
        return error_response("กรุณาระบุเหตุผลในการขอปลดแบน", 400)
    try:
        if not user:
            if username and email:
                user = User.query.filter(
                    func.lower(User.username) == username.lower(),
                    func.lower(User.email) == email.lower()
                ).first()
            elif username:
                user = User.query.filter(func.lower(User.username) == username.lower()).first()
            elif email:
                user = User.query.filter(func.lower(User.email) == email.lower()).first()

        if user and current_user_id and (username or email):
            if username and user.username and user.username.lower() != username.lower():
                return error_response("ชื่อผู้ใช้ไม่ตรงกับข้อมูลที่เข้าสู่ระบบ", 400)
            if email and user.email and user.email.lower() != email.lower():
                return error_response("อีเมลไม่ตรงกับข้อมูลที่เข้าสู่ระบบ", 400)
        if not user:
            return error_response("ไม่พบบัญชีผู้ใช้ที่ตรงกัน", 404)
        if not getattr(user, 'is_deleted', False):
            return error_response("บัญชีนี้ยังไม่ถูกระงับ", 400)
        if not current_user_id:
            supplied_pw = (data.get('password') or '').strip()
            if not supplied_pw:
                return error_response("กรุณาระบุรหัสผ่านเพื่อยืนยันตัวตน", 400)
            if not user.password_hash or not check_password_hash(user.password_hash, supplied_pw):
                app.logger.info('Unban request rejected: invalid password for user_id=%s', user.id)
                return error_response('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง', 401, 'UNAUTHORIZED')

        unban_report = Report(user_id=user.id, title='คำขอปลดแบน', message=detail, status='pending')
        db.session.add(unban_report)
        db.session.commit()

        return jsonify({
            "status": "success",
            "message": "คำขอปลดแบนของคุณถูกส่งไปยังผู้ดูแลระบบแล้ว"
        }), 201
    except Exception:
        db.session.rollback()
        app.logger.exception('request_unban failed')
        return error_response('เกิดข้อผิดพลาดในระบบฐานข้อมูล', 500, 'SERVER_ERROR')




@app.route('/submit', methods=['POST'])
@limiter.limit("20 per minute")
def submit():
    """Submit a new-menu suggestion for admin review.

    JSON accepted:
      - Registered user: { "user_id": <int>, "name_th": "...", "name_en": "...",
        "item_type": "food|drink|dessert", "detail": "..." }
        Requires: Authorization: Bearer <token>
      - Anonymous: same fields plus "anon_id" instead of "user_id".
        Server enforces one submission per anon_id.
    """
    if not request.is_json:
        return error_response('JSON body required', 400)
    data = request.get_json(silent=True) or {}
    user_id = data.get('user_id')
    anon_id = data.get('anon_id')
    name_th = (data.get('name_th') or '').strip()
    name_en = (data.get('name_en') or '').strip()
    item_type = (data.get('item_type') or 'food').strip().lower()
    detail = (data.get('detail') or '').strip()

    if item_type not in ('food', 'drink', 'dessert'):
        return error_response('item_type must be food, drink or dessert', 400)
    if not name_th and not name_en:
        return error_response('name_th or name_en required', 400)
    if user_id is not None:
        try:
            user_id = int(user_id)
        except (TypeError, ValueError):
            return error_response('user_id must be integer', 400)
        auth = request.headers.get('Authorization') or ''
        if not auth.startswith('Bearer '):
            return error_response('authorization required', 401)
        token = auth.split(' ', 1)[1].strip()

        user = User.query.get(user_id)
        if not user:
            return error_response('user not found', 404)
        if not token_valid_for_user(user, token):
            return error_response('invalid or expired token', 401)
        s = Submission(user_id=user.id, anon_id=None, name_th=name_th or None,
                        name_en=name_en or None, item_type=item_type, detail=detail or None)
        db.session.add(s)
        try:
            db.session.commit()
        except Exception:
            db.session.rollback()
            return error_response('database error', 500)
        return jsonify({'status': 'ok', 'id': s.id}), 201

    # Anonymous flow
    if not anon_id or not isinstance(anon_id, str):
        return error_response('anon_id required for anonymous submission', 400)
    if len(anon_id) > 100:
        return error_response('anon_id too long', 400)
    if Submission.query.filter_by(anon_id=anon_id).first():
        return error_response('anonymous submission already used', 403)
    s = Submission(user_id=None, anon_id=anon_id, name_th=name_th or None,
                    name_en=name_en or None, item_type=item_type, detail=detail or None)
    db.session.add(s)
    try:
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        return error_response('anonymous submission already used', 403)
    except Exception:
        db.session.rollback()
        return error_response('database error', 500)
    return jsonify({'status': 'ok', 'id': s.id}), 201


@app.route('/api/my_submissions', methods=['GET'])
@limiter.limit("30 per minute")
def my_submissions():
    user = get_current_user_from_jwt()
    if not user:
        return error_response("ไม่พบข้อมูลผู้ใช้", 404)

    subs = (Submission.query.filter_by(user_id=user.id)
            .order_by(Submission.created_at.desc(), Submission.id.desc()).limit(200).all())

    submissions = [{
        "id": s.id,
        "name_th": s.name_th,
        "name_en": s.name_en,
        "item_type": s.item_type,
        "detail": s.detail,
        "status": s.status,
        "review_note": s.review_note,
        "reviewed_at": s.reviewed_at.isoformat() if s.reviewed_at else None,
        "created_at": s.created_at.isoformat() if s.created_at else None,
    } for s in subs]

    return jsonify({"status": "success", "submissions": submissions}), 200


@app.route('/anon-status/<string:anon_id>', methods=['GET'])
@limiter.limit("30 per minute")
def anon_status(anon_id):
    """Return whether an anonymous id may still submit (true/false).

    Frontend can call this to show immediate feedback before attempting a POST.
    """
    
    existing = Submission.query.filter_by(anon_id=anon_id).first()
    return jsonify({'can_submit': existing is None})

def _user_meal_logs_as_dicts(user):
    logs = MealLog.query.filter_by(user_id=user.id).order_by(MealLog.log_date.desc()).all()
    out = []
    for l in logs:
        items = [{
            'food_item': (it.food_item.name_th or it.food_item.name) if it.food_item else None,
            'quantity': it.quantity,
            'calories_actual': it.calories_actual,
            'is_eaten': bool(it.is_eaten),
            'eaten_at': it.eaten_at.isoformat() if it.eaten_at else None,
        } for it in l.items]
        out.append({
            'id': l.id,
            'user_id': l.user_id,
            'created_at': l.created_at.isoformat() if l.created_at else None,
            'data': json.dumps({'log_date': l.log_date.isoformat(), 'meal_type': l.meal_type, 'items': items}, ensure_ascii=False),
        })
    return out


@app.route('/export/history/<int:user_id>', methods=['GET'])
@limiter.limit("5 per minute")
def export_history_csv(user_id):
    auth = request.headers.get('Authorization') or ''
    if not auth.startswith('Bearer '):
        return error_response('authorization required', 401)
    token = auth.split(' ', 1)[1].strip()
    user = User.query.get_or_404(user_id)
    if not token_valid_for_user(user, token):
        return error_response('invalid or expired token', 401)
    csv_bytes = csv_utils.histories_to_csv_bytes(_user_meal_logs_as_dicts(user))
    return Response(
        csv_bytes,
        mimetype='text/csv; charset=utf-8',
        headers={'Content-Disposition': f'attachment; filename=history_user_{user_id}.csv'}
    )


@app.route('/history/<int:user_id>', methods=['GET'])
@limiter.limit("20 per minute")
def get_history(user_id):
    auth = request.headers.get('Authorization') or ''
    if not auth.startswith('Bearer '):
        return error_response('authorization required', 401)
    token = auth.split(' ', 1)[1].strip()
    user = User.query.get_or_404(user_id)
    if not token_valid_for_user(user, token):
        return error_response('invalid or expired token', 401)
    logs = MealLog.query.filter_by(user_id=user.id).order_by(MealLog.log_date.desc()).all()
    history = [{
        'id': l.id,
        'user_id': l.user_id,
        'log_date': l.log_date.isoformat(),
        'meal_type': l.meal_type,
        'created_at': l.created_at.isoformat() if l.created_at else None,
        'items': [{
            'id': it.id,
            'food_item_id': it.food_item_id,
            'food_item_name': (it.food_item.name_th or it.food_item.name) if it.food_item else None,
            'quantity': it.quantity,
            'calories_actual': it.calories_actual,
            'is_eaten': bool(it.is_eaten),
            'eaten_at': it.eaten_at.isoformat() if it.eaten_at else None,
        } for it in l.items],
    } for l in logs]

    return jsonify({'history': history}), 200


@app.route('/export/history/<int:user_id>/excel', methods=['GET'])
def export_history_excel(user_id):
    auth = request.headers.get('Authorization') or ''
    if not auth.startswith('Bearer '):
        return error_response('authorization required', 401)
    token = auth.split(' ', 1)[1].strip()
    user = User.query.get_or_404(user_id)
    if not token_valid_for_user(user, token):
        return error_response('invalid or expired token', 401)
    try:
        excel_bytes = csv_utils.histories_to_excel_bytes(_user_meal_logs_as_dicts(user))
    except RuntimeError:
        return error_response('pandas required for excel export', 400)
    return Response(
        excel_bytes,
        mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        headers={'Content-Disposition': f'attachment; filename=history_user_{user_id}.xlsx'}
    )


@app.route('/import/users', methods=['POST'])
@limiter.limit("5 per minute")
def import_users():
    """
    Admin only.
    Expect multipart/form-data with file field 'file' (CSV)
    CSV headers: username,email,password (password optional)
    """

    # =========================
    # 🔐 1. Require Admin Token
    # =========================
    auth = request.headers.get('Authorization') or ''
    if not auth.startswith('Bearer '):
        return error_response('authorization required', 401)
    token = auth.split(' ', 1)[1].strip()
    admin_user = User.query.filter_by(password_token=token).first()

    if not admin_user or not admin_user.is_admin or not token_valid_for_user(admin_user, token):
        return error_response('admin only', 403)
    # =========================
    # 📁 2. Validate File
    # =========================
    file = request.files.get('file')
    if not file:
        return error_response('file required', 400)
    if not file.filename.lower().endswith('.csv'):
        return error_response('only csv allowed', 400)
    try:
        data = file.read()
        users = csv_utils.csv_bytes_to_users_list(data)
    except Exception:
        app.logger.exception("Invalid CSV during import_users")
        return error_response('invalid csv', 400)
    created = []
    skipped = []

    # =========================
    # 👤 3. Process Users
    # =========================
    for u in users:
        username = (u.get('username') or '').strip()
        email = (u.get('email') or '').strip()

        if not username:
            skipped.append({'reason': 'missing username'})
            continue

        if User.query.filter(func.lower(User.username) == username.lower()).first():
            skipped.append({'username': username, 'reason': 'already exists'})
            continue

        pwd = u.get('password')

        # 🔐 Validate or generate password
        if pwd:
            if len(pwd) < 8:
                skipped.append({'username': username, 'reason': 'weak password'})
                continue

            if not re.search(r'(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[^A-Za-z0-9])', pwd):
                skipped.append({'username': username, 'reason': 'weak password'})
                continue
        else:
            pwd = secrets.token_urlsafe(12)

        try:
            token = secrets.token_urlsafe(32)

            user = User(
                username=username,
                email=email,
                password_hash=generate_password_hash(pwd),
                password_token=token,
                token_created_at=get_thailand_time()
            )

            db.session.add(user)
            db.session.commit()   # ✅ commit ทีละ user

            created.append({
                'id': user.id,
                'username': user.username
            })

        except Exception:
            app.logger.exception("DB error during user import")
            db.session.rollback()
            skipped.append({'username': username, 'reason': 'db error'})

    return jsonify({
        'created': created,
        'created_count': len(created),
        'skipped': skipped,
        'skipped_count': len(skipped)
    })

def _otp_request_rate_limit_key():
    """จำกัดตาม email ที่ขอ OTP จริง (ไม่ใช่ IP) กัน attacker สลับ IP ยิงอีเมล
    เดิมซ้ำๆ ได้ — ถ้า parse email ไม่ได้ fallback เป็น IP กันเคส body พัง"""
    try:
        data = request.get_json(silent=True) or {}
        email = (data.get('email') or '').strip().lower()
        return email or get_remote_address()
    except Exception:
        return get_remote_address()


@app.route('/forgot-password', methods=['POST'])
@limiter.limit("3 per 15 minutes", key_func=_otp_request_rate_limit_key)
def forgot_password():
    time.sleep(0.8)

    if not request.is_json:
        return error_response('Invalid JSON format. Please provide a valid JSON object.', 400)
    data = request.get_json(silent=True) or {}

    username = (data.get('username') or '').strip()
    email = (data.get('email') or '').strip()

    if not username or not email:
        return error_response('Both username and email must be provided.', 400)
    # Exact match on email (case-insensitive)
    user = User.query.filter(
        func.lower(User.username) == username.lower(),
        func.lower(User.email) == email.lower()
    ).first()

    if not user:
        return error_response('ไม่พบชื่อผู้ใช้', 404)
    try:
        # Generate a raw reset token and a 6-digit OTP. Store only hashes.
        reset_token = secrets.token_urlsafe(32)
        otp = f"{secrets.randbelow(10**6):06d}"
        app.logger.info("GENERATING RESET TOKEN+OTP for user id=%s", user.id)

        # Use HMAC-SHA256 with server secret to hash token and otp
        secret = current_app.config.get('SECRET_KEY', '')
        if not secret:
            app.logger.error('SECRET_KEY not set; cannot generate reset hashes')
            return error_response('server configuration error', 500)
        token_hmac = hmac.new(secret.encode('utf-8'), reset_token.encode('utf-8'), hashlib.sha256).hexdigest()
        otp_hmac = hmac.new(secret.encode('utf-8'), otp.encode('utf-8'), hashlib.sha256).hexdigest()

        # Persist hashes and expiries (token + OTP TTL: 5 minutes from now)
        user.reset_token_hash = token_hmac
        user.reset_token_expires_at = get_thailand_time() + timedelta(minutes=5)
        user.reset_password_otp = otp_hmac
        user.reset_otp_expires_at = get_thailand_time() + timedelta(minutes=5)
        user.reset_otp_attempts = 0

        db.session.commit()

        # Double-check persistence
        persisted = User.query.get(user.id)
        if not persisted or not persisted.reset_token_hash or not persisted.reset_password_otp:
            app.logger.error('Failed to persist reset_token_hash/reset_password_otp for user id=%s', user.id)
            return error_response('Failed to generate reset credentials', 500)
        app.logger.info('Reset token+otp stored for user id=%s expires=%s/%s', user.id, persisted.reset_token_expires_at, persisted.reset_otp_expires_at)

    except Exception as e:
        db.session.rollback()
        app.logger.exception("Error saving reset token for user id=%s: %s", user.id if user else None, e)
        return error_response('Failed to generate reset token, please try again later.', 500)
    # เดิมผูก "ส่ง token กลับใน response ไหม" ไว้กับ app.debug ตัวเดียวกับที่
    # คุม Werkzeug debugger — พอแก้ BUG-009 (ตัวก่อนหน้า) ให้ app.debug ปิดโดย
    # default เพื่อความปลอดภัย (ถูกต้องแล้วสำหรับ debugger) ผลข้างเคียงคือ
    # /forgot-password หยุดส่ง token/OTP กลับไปด้วย ทั้งที่โปรเจกต์นี้ไม่มี
    # ระบบส่งอีเมลจริงเลย (grep แล้วไม่พบ smtp/mail library ใดๆ) กลายเป็นว่า
    # ผู้ใช้ไม่มีทางได้ token มาเลย (บั๊กที่เจอจริง — "ไม่พบข้อมูลโทเค่น")
    # แยกเป็น flag ของตัวเองต่างหาก ไม่ผูกกับ debugger อีก default เปิดไว้
    # (ต่างจาก FLASK_ENV ที่ default ปิด) เพราะนี่คือช่องทางส่ง token เดียวที่
    # มีจริงในระบบนี้ ไม่ใช่แค่ dev convenience
    return_reset_token = os.environ.get('RETURN_RESET_TOKEN_IN_RESPONSE', 'true').strip().lower() != 'false'
    if not reset_token:
        app.logger.error('Generated reset_token is empty for user id=%s', user.id)
        return error_response('Failed to generate reset token', 500)
    if return_reset_token:
        app.logger.info('Returning reset_token and otp in response for user id=%s', user.id)
        return jsonify({
            'status': 'ok',
            'username': user.username,
            'email': user.email,
            'reset_token': reset_token,
            'otp': otp
        }), 200
    else:
        # ตั้ง RETURN_RESET_TOKEN_IN_RESPONSE=false เอง ถ้าต่อระบบส่งอีเมลจริง
        # แล้วในอนาคต — ตอนนั้นค่อยส่ง token ผ่านอีเมลแทนตรงนี้
        app.logger.info('Reset credentials generated for user id=%s (not returned in response)', user.id)
        return jsonify({'status': 'ok'}), 200

def _clear_reset_fields(user):
    """ล้าง reset_token_hash/reset_token_expires_at/reset_otp_hash/
    reset_otp_expires_at/reset_otp_attempts ทิ้งทันที — ใช้ตอนหมดอายุ (เดิม
    ปล่อยค้างจน request ขอ OTP ใหม่รอบถัดไปมาเขียนทับ ผู้ใช้รายงานจริงว่า
    ค้างอยู่ใน DB) เหมือนที่ path "กรอกผิดครบ 5 ครั้ง" ทำอยู่แล้ว"""
    user.reset_token_hash = None
    user.reset_token_expires_at = None
    user.reset_password_otp = None
    user.reset_otp_expires_at = None
    user.reset_otp_attempts = 0
    db.session.commit()


def _verify_reset_token_and_otp(reset_token, otp, username='', email=''):
    """ตรวจ reset_token + OTP ให้ตรงกับ user ที่ขอไว้จริง (hash เทียบแบบ
    constant-time, เช็ค expiry ของทั้ง token และ OTP, นับ/ล้าง
    reset_otp_attempts) ใช้ร่วมกันทั้ง /verify-reset-otp (เช็คอย่างเดียว
    ไม่เปลี่ยนรหัสผ่าน) และ /reset-password (เช็คแล้วเปลี่ยนรหัสผ่านต่อเลย)
    — แยกออกมาเป็นจุดเดียวกันลอจิกความปลอดภัยนี้เพี้ยนไปคนละทางระหว่าง 2
    endpoint คืน (user, None) ถ้าผ่าน หรือ (None, error_response(...)) ถ้าไม่ผ่าน
    ผู้เรียกต้อง db.session.commit() เองหลังเรียกถ้าต้องการให้ reset_otp_attempts
    ที่รีเซ็ตเป็น 0 ตอนถูกต้องถูกบันทึกจริง (ฝั่ง fail มี commit ในนี้ให้แล้ว)"""
    if not reset_token:
        return None, error_response('reset_token required', 400)
    if len(reset_token) < 16:
        return None, error_response('invalid token', 400)
    if not otp:
        return None, error_response('otp required', 400)

    secret = current_app.config.get('SECRET_KEY', '')
    if not secret:
        app.logger.error('SECRET_KEY not set; cannot verify reset token')
        return None, error_response('server configuration error', 500)
    hashed_token = hmac.new(secret.encode('utf-8'), reset_token.encode('utf-8'), hashlib.sha256).hexdigest()

    # Ensure token hash maps to a single user (sanity check)
    try:
        dup_count = db.session.query(User).filter_by(reset_token_hash=hashed_token).count()
    except Exception:
        app.logger.exception('DB error during token duplicate check')
        return None, error_response('database error', 500)
    if dup_count == 0:
        return None, error_response('โทเคนไม่ถูกต้อง', 400)
    if dup_count > 1:
        app.logger.error('reset_token hash duplicated in DB (count=%s)', dup_count)
        return None, error_response('โทเคนไม่ถูกต้อง', 400)
    # Look up the user by reset_token hash and lock the row to prevent reuse
    try:
        user = db.session.query(User).filter_by(reset_token_hash=hashed_token).with_for_update().first()
    except Exception:
        app.logger.exception('DB error during token lookup')
        return None, error_response('database error', 500)
    if not user:
        return None, error_response('โทเคนไม่ถูกต้อง', 400)
    # Read current Thailand time once and perform fail-fast expiry checks
    try:
        now_thailand = get_thailand_time()
    except Exception:
        # Fallback: construct Thailand tz-aware now
        now_thailand = datetime.now(timezone(timedelta(hours=7)))

    # Token expiry must exist and be interpreted as Thailand time if naive
    expires = user.reset_token_expires_at
    if not expires:
        _clear_reset_fields(user)
        return None, error_response('ลิงก์รีเซ็ตรหัสผ่านนี้หมดอายุแล้ว กรุณาทำรายการใหม่', 400)
    try:
        if expires.tzinfo is None:
            expires = expires.replace(tzinfo=timezone(timedelta(hours=7)))
    except Exception:
        pass
    if now_thailand > expires:
        _clear_reset_fields(user)
        return None, error_response('ลิงก์รีเซ็ตรหัสผ่านนี้หมดอายุแล้ว กรุณาทำรายการใหม่', 400)
    # OTP expiry must exist and be interpreted as Thailand time if naive
    otp_expires = user.reset_otp_expires_at
    if not otp_expires:
        _clear_reset_fields(user)
        return None, error_response('รหัส OTP หมดอายุแล้ว กรุณาขอรหัส OTP ใหม่', 400)
    try:
        if otp_expires.tzinfo is None:
            otp_expires = otp_expires.replace(tzinfo=timezone(timedelta(hours=7)))
    except Exception:
        pass
    if now_thailand > otp_expires:
        _clear_reset_fields(user)
        return None, error_response('รหัส OTP หมดอายุแล้ว กรุณาขอรหัส OTP ใหม่', 400)
    # Additional strict check: ensure the stored token hash exactly matches (constant-time)
    try:
        if not hmac.compare_digest((user.reset_token_hash or ''), hashed_token):
            return None, error_response('โทเคนไม่ถูกต้อง', 400)
    except Exception:
        return None, error_response('โทเคนไม่ถูกต้อง', 400)
    # Check OTP attempts
    try:
        attempts = int(user.reset_otp_attempts or 0)
    except Exception:
        attempts = 0
    if attempts >= 5:
        # Exceeded attempts -> clear token and otp
        _clear_reset_fields(user)
        return None, error_response('กรอกรหัสผิดเกิน 5 ครั้ง กรุณาขอรหัส OTP ใหม่', 400)
    # Verify OTP hash (constant-time)
    otp_hmac_candidate = hmac.new(secret.encode('utf-8'), otp.encode('utf-8'), hashlib.sha256).hexdigest()
    otp_ok = False
    try:
        if user.reset_password_otp and hmac.compare_digest(user.reset_password_otp, otp_hmac_candidate):
            otp_ok = True
    except Exception:
        otp_ok = False

    # (OTP expiry was checked earlier as a fail-fast)
    if not otp_ok:
        # increment attempts
        try:
            user.reset_otp_attempts = (int(user.reset_otp_attempts or 0) + 1)
            db.session.commit()
        except Exception:
            db.session.rollback()

        # If attempts reached limit, clear creds and return a specific message
        try:
            if int(user.reset_otp_attempts or 0) >= 5:
                _clear_reset_fields(user)
                return None, error_response('กรอกรหัสผิดเกิน 5 ครั้ง กรุณาขอรหัส OTP ใหม่', 400)
        except Exception:
            db.session.rollback()

        return None, error_response('invalid otp', 400)
    # OTP correct: reset attempts counter (ผู้เรียกต้อง commit เองถ้าจะให้ค่านี้ติด)
    try:
        user.reset_otp_attempts = 0
    except Exception:
        pass

    # Verify provided username/email match the account the token belongs to
    if username and username.lower() != (user.username or '').lower():
        return None, error_response('โทเคนนี้ไม่ตรงกับบัญชีที่ทำการขอรีเซ็ตรหัสผ่าน', 400)
    if email and email.lower() != (user.email or '').lower():
        return None, error_response('โทเคนนี้ไม่ตรงกับบัญชีที่ทำการขอรีเซ็ตรหัสผ่าน', 400)
    return user, None


@app.route('/verify-reset-otp', methods=['POST'])
@limiter.limit("10 per minute")
def verify_reset_otp():
    """เช็คว่า OTP ที่กรอกตรงกับที่ backend สร้างไว้จริงไหม โดย "ไม่" เปลี่ยน
    รหัสผ่าน — ใช้ที่หน้า step 2 ของ ForgotPasswordPage (ปุ่ม "ยืนยัน OTP")
    เดิมหน้านั้นเช็คแค่ "กรอกครบ 6 หลักไหม" ไม่ได้เช็คกับค่าจริงเลย ทำให้กรอก
    เลขอะไรก็ผ่านไป step 3 ได้ (ผู้ใช้รายงานจริง) แชร์ลอจิกตรวจเดียวกับ
    /reset-password ผ่าน _verify_reset_token_and_otp กันพังคนละแบบ"""
    import time
    time.sleep(0.5)  # Mitigate timing attacks — เหมือน /reset-password

    if not request.is_json:
        return error_response('JSON body required', 400)
    data = request.json or {}
    reset_token = (data.get('reset_token') or '').strip()
    otp = (data.get('otp') or '').strip()
    username = (data.get('username') or '').strip()
    email = (data.get('email') or '').strip()

    user, err = _verify_reset_token_and_otp(reset_token, otp, username, email)
    if err:
        return err
    db.session.commit()
    return jsonify({'status': 'ok'}), 200


@app.route('/reset-password', methods=['POST'])
@limiter.limit("5 per minute")
def reset_password():
    import time
    time.sleep(0.5)  # Mitigate timing attacks

    if not request.is_json:
        return error_response('JSON body required', 400)
    data = request.json or {}
    reset_token = (data.get('reset_token') or '').strip()
    new_password = data.get('new_password') or ''

    # Accept username and email in the request for additional verification,
    # but do NOT use them to identify the user when updating the DB.
    username = (data.get('username') or '').strip()
    email = (data.get('email') or '').strip()

    # Reject other disallowed fields that should never be provided here
    forbidden_keys = {'user_id', 'password_token', 'auth_token', 'token'}
    present_forbidden = forbidden_keys.intersection(set(k.lower() for k in data.keys()))
    if present_forbidden:
        app.logger.warning('reset-password called with forbidden keys: %s', present_forbidden)
        return error_response('invalid request fields', 400)
    # Reject Authorization header for this endpoint (token must be in body)
    # NOTE: Allowing frontend to call this endpoint even if an Authorization
    # header is present; the reset token should be provided in the JSON body.
    # The previous implementation returned 400 here which prevented the
    # backend from incrementing `reset_otp_attempts` when the frontend sent
    # an Authorization header during the forgot-password flow. Commenting
    # out the check so OTP validation logic can run regardless of headers.
    # if request.headers.get('Authorization'):
    #     app.logger.warning('reset-password called with Authorization header')
    #     return error_response('authorization not allowed for this endpoint', 400)
    # Enforce required fields: reset_token and new_password
    if not reset_token:
        return error_response('reset_token required', 400)
    if not new_password:
        return error_response('new_password required', 400)
    # Password length and strength validation
    if len(new_password) < 8:
        return error_response('password must be at least 8 characters long', 400)
    if not re.search(r'(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[^A-Za-z0-9])', new_password):
        return error_response('password must include uppercase, lowercase, number, and special character', 400)

    otp = (data.get('otp') or '').strip()
    user, err = _verify_reset_token_and_otp(reset_token, otp, username, email)
    if err:
        return err
    # **Check if the new password is the same as the current password**
    if check_password_hash(user.password_hash, new_password):
        return error_response('new password cannot be the same as the current password', 400)
    try:
        # Set the new password after hashing it
        user.password_hash = generate_password_hash(new_password)

        # Clear the reset token and its expiration time, and OTP fields
        user.reset_token_hash = None
        user.reset_token_expires_at = None
        user.reset_password_otp = None
        user.reset_otp_expires_at = None
        user.reset_otp_attempts = 0

        # Rotate the login token for security
        user.password_token = secrets.token_urlsafe(32)
        user.token_created_at = get_thailand_time()

        db.session.commit()

        # Log success
        current_app.logger.info(f"Password for user {user.username} reset successfully.")

    except Exception as e:
        db.session.rollback()
        current_app.logger.exception(f"Error resetting password for user {user.username}: {e}")
        return error_response('database error', 500)
    return jsonify({'status': 'password reset successful'}), 200


@app.route('/reset-token-info', methods=['POST'])
@limiter.limit("10 per minute")
def reset_token_info():
    """Given a reset_token (plain from email), return the username and a masked
    email for the account that the token grants access to.

    This endpoint proves possession of the token and is intended for the
    frontend reset page to confirm which account the token belongs to.
    """

    if not request.is_json:
        return error_response('JSON body required', 400)
    data = request.get_json(silent=True) or {}
    reset_token = (data.get('reset_token') or '').strip()

    if not reset_token or len(reset_token) < 16:
        return error_response('โทเคนไม่ถูกต้อง', 400)
    # Do not accept Authorization header for this flow
    if request.headers.get('Authorization'):
        return error_response('authorization not allowed', 400)
    secret = current_app.config.get('SECRET_KEY', '')
    if not secret:
        app.logger.error('SECRET_KEY not set; cannot verify reset token')
        return error_response('server configuration error', 500)
    hashed_token = hmac.new(secret.encode('utf-8'), reset_token.encode('utf-8'), hashlib.sha256).hexdigest()

    try:
        user = db.session.query(User).filter_by(reset_token_hash=hashed_token).first()
    except Exception:
        app.logger.exception('DB error during reset-token-info lookup')
        return error_response('database error', 500)
    if not user:
        return error_response('โทเคนไม่ถูกต้อง', 400)
    # ตรวจสอบเวลาหมดอายุของโทเคน
    expires = user.reset_token_expires_at
    if not expires:
        return error_response('ลิงก์รีเซ็ตรหัสผ่านนี้หมดอายุแล้ว', 400)
    try:
        if expires.tzinfo is None:
            expires = expires.replace(tzinfo=timezone.utc)
    except Exception:
        pass

    # 🔥 ตรรกะตรวจสอบเวลาปัจจุบัน: ถ้าเวลาปัจจุบันเกินเวลาหมดอายุในฐานข้อมูล ให้บล็อกทันที
    if get_thailand_time() > expires:
        return error_response('ลิงก์รีเซ็ตรหัสผ่านนี้หมดอายุแล้ว กรุณาทำรายการใหม่', 400)
    # ตรวจสอบเพิ่มเติมในกรณีที่ผูกกับระบบ OTP เพื่อความปลอดภัยสองชั้น
    otp_expires = user.reset_otp_expires_at
    if otp_expires:
        try:
            if otp_expires.tzinfo is None:
                otp_expires = otp_expires.replace(tzinfo=timezone.utc)
        except Exception:
            pass
        if get_thailand_time() > otp_expires:
            return error_response('รหัส OTP หมดอายุแล้ว กรุณาทำรายการใหม่', 400)
    # ทำการ Masking เซนเซอร์อีเมล (เช่น m***r@gmail.com) ป้องกันการส่องดูข้อมูลส่วนบุคคล
    masked_email = "******"
    if user.email and '@' in user.email:
        try:
            parts = user.email.split('@')
            name_part, domain_part = parts[0], parts[1]
            if len(name_part) <= 2:
                masked_email = name_part[0] + "*@" + domain_part
            else:
                masked_email = name_part[0] + "***" + name_part[-1] + "@" + domain_part
        except Exception:
            pass

    return jsonify({
        'status': 'success',
        'username': user.username,
        'email': masked_email
    }), 200
@app.route('/change-password', methods=['POST'])
@limiter.limit("5 per minute")
def change_password():
    # Change-password: support two modes
    # 1) Authenticated: Authorization: Bearer <password_token> (existing flow)
    # 2) Unauthenticated: provide username/email + old_password in JSON
    auth_header = request.headers.get('Authorization') or ''

    # Require JSON body
    if not request.is_json:
        return error_response('JSON body required', 400)
    data = request.get_json() or {}

    user = None
    token = None
    # Attempt authenticated flow first if Authorization header provided
    if auth_header.startswith('Bearer '):
        token = auth_header.split(' ', 1)[1].strip()
        if token:
            try:
                user = User.query.filter_by(password_token=token).first()
            except Exception:
                app.logger.exception('DB error during password_token lookup')
                return error_response('database error', 500)
            if not user or not token_valid_for_user(user, token):
                # Invalid token supplied — do not fail immediately; allow fallback
                # to username/email + old_password flow if present in the request.
                app.logger.info('Invalid or expired Authorization token provided; falling back to credential verification')
                user = None
                token = None

    # If no Authorization or token flow didn't resolve a user, try username/email + old_password
    if not user:
        username = (data.get('username') or '').strip()
        email = (data.get('email') or '').strip()
        old_password = data.get('old_password') or ''

        if not old_password or (not username and not email):
            return error_response('authorization required or provide username/email+old_password', 401)
        # If both username and email are provided, require they match the
        # same user record (AND) to avoid leaking or matching across accounts.
        try:
            if username and email:
                user = User.query.filter(
                    func.lower(User.username) == username.lower(),
                    func.lower(User.email) == email.lower()
                ).first()
            else:
                # Fallbacks: if single identifier provided, allow email-or-username lookup
                if '@' in (username or ''):
                    q = func.lower(User.email) == username.lower()
                    user = User.query.filter(q).first()
                elif email:
                    user = User.query.filter(func.lower(User.email) == email.lower()).first()
                else:
                    user = User.query.filter(func.lower(User.username) == username.lower()).first()
        except Exception:
            app.logger.exception('DB lookup failed during unauthenticated change-password')
            return error_response('database error', 500)
        if not user:
            return error_response('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง', 401)
    else:
        # ผ่าน token แล้ว (session ยัง valid อยู่) แต่ฝั่ง client (มือถือ) ยัง
        # ส่ง username/email มาด้วยเสมอเป็นการยืนยันตัวตนซ้ำก่อนทำ action
        # อ่อนไหวแบบนี้ — เดิม path นี้ไม่เช็คเลยว่าค่าที่ส่งมาตรงกับบัญชีของ
        # token จริงไหม ทำให้กรอกอีเมล/ชื่อผู้ใช้ผิดบัญชีก็ยังผ่านได้ (บั๊กที่
        # เจอจริง) ต้องเช็คให้ตรงเหมือน path ที่ไม่มี token ทุกประการ
        username = (data.get('username') or '').strip()
        email = (data.get('email') or '').strip()
        if username and username.lower() != (user.username or '').lower():
            return error_response('ชื่อผู้ใช้ไม่ตรงกับบัญชีนี้', 401)
        if email and email.lower() != (user.email or '').lower():
            return error_response('อีเมลไม่ตรงกับบัญชีนี้', 401)

    # ตรวจรหัสผ่านเดิมเสมอ ไม่ว่า user จะมาจาก token หรือ username/email —
    # เดิม path ที่ auth ผ่าน token ข้ามการตรวจ old_password ไปเลย (แก้รหัส
    # ผ่านได้โดยไม่ต้องรู้รหัสเดิมจริง แค่มี session ค้างอยู่ก็พอ) รวมจุด
    # ตรวจเป็นที่เดียวให้ทุก path ต้องผ่านเงื่อนไขเดียวกันเป๊ะ
    old_password = data.get('old_password') or ''
    if not old_password or not check_password_hash(user.password_hash, old_password):
        return error_response('invalid current password', 401)
    # By here we have a valid `user` object (either via token or username+old_password)
    new_password = data.get('new_password') or ''

    if not new_password:
        return error_response('new_password required', 400)
    # Password policy
    if len(new_password) < 8:
        return error_response('password must be at least 8 characters long', 400)
    if not re.search(r'(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[^A-Za-z0-9])', new_password):
        return error_response('password must include uppercase, lowercase, number, and special character', 400)
    # Ensure new password is not the same as current
    try:
        if check_password_hash(user.password_hash, new_password):
            return error_response('new password cannot be the same as the current password', 400)
    except Exception:
        pass

    try:
        user.password_hash = generate_password_hash(new_password)

        # Clear any reset token/expiry
        user.reset_token_hash = None
        user.reset_token_expires_at = None

        # Rotate login token (invalidate other sessions)
        user.password_token = secrets.token_urlsafe(32)
        user.token_created_at = get_thailand_time()

        db.session.commit()
        current_app.logger.info('Password changed for user id=%s (auth header present=%s)', user.id, bool(token))
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception('Error changing password for user id=%s: %s', getattr(user, 'id', None), e)
        return error_response('database error', 500)
    return error_response('เปลี่ยนรหัสผ่านสำเร็จ', 200)
@app.route('/db-info', methods=['GET'])
def db_info():
    # 🔒 อนุญาตเฉพาะตอน debug mode เท่านั้น
    if not app.debug:
        return error_response('forbidden', 403)
    try:
        uri = app.config.get('SQLALCHEMY_DATABASE_URI', '')
        masked = uri

        try:
            if '//' in uri and ':' in uri.split('//', 1)[1]:
                parts = uri.split('//', 1)
                creds_host = parts[1]
                if '@' in creds_host:
                    cred, rest = creds_host.split('@', 1)
                    if ':' in cred:
                        user, _ = cred.split(':', 1)
                        masked = parts[0] + '//' + f"{user}:***@" + rest
        except Exception:
            masked = '<secure masking failed>'

    except Exception:
        masked = '<unknown>'

    info = {
        'db_uri': masked,
        'using_mysql': ('mysql' in app.config.get('SQLALCHEMY_DATABASE_URI', ''))
    }

    try:
        cnt = User.query.count()
        sample = [u.username for u in User.query.limit(5).all()]
        info.update({
            'users_count': cnt,
            'users_sample': sample
        })
    except Exception as e:
        info.update({
            'users_count': None,
            'users_sample': [],
            'error': str(e)
        })

    return jsonify(info)

@app.teardown_appcontext
def shutdown_session(exception=None):
    db.session.remove()


# -----------------------------
# Meal logging (replaces the old `histories` blob)
# -----------------------------
MEAL_TYPES = ('breakfast', 'lunch', 'dinner')

# ต้องตรงกับ kMealTimeWindows ใน frontend/mobile/lib/models/meal_log.dart เป๊ะ
# (comment ที่นั่นอ้างว่า backend ล็อกด้วยเหมือนกัน แต่ก่อนหน้านี้ยังไม่มีจริง
# — เช็คแค่ฝั่ง UI ทำให้ยิง POST /meal-logs ตรงๆ ข้ามเวลาที่ล็อกได้)
MEAL_TIME_WINDOWS = {'breakfast': (5, 10), 'lunch': (10, 15), 'dinner': (15, 22)}

# สัดส่วนมื้อที่บันทึก+กินจริง ÷ มื้อที่มีให้เลือกได้จริงตลอดรอบ (ตามจำนวนวัน
# ที่ผู้ใช้ตั้งไว้ ไม่ใช่ 7 วันตายตัว) เก็บไว้แสดงผลสรุปของรอบ
# (health goal ที่เลือกไว้ตอนต้นรอบ)
GOAL_SUCCESS_THRESHOLD = 0.6


def _finalize_expired_goal_cycle(user):
    """ถ้ารอบ health_goal ก่อนหน้าหมดอายุแล้ว (health_goal_locked_until ผ่าน
    มาแล้ว) และยังไม่เคยสรุปผลไว้ ให้คำนวณแล้วบันทึกเป็น HealthGoalCycle 1
    แถวถาวร (idempotent ผ่าน UniqueConstraint user_id+period_end — เรียกซ้ำ
    กี่ครั้งก็ได้ไม่สร้างซ้ำ) เรียกจากทุก endpoint ที่อ่าน/แก้ health_goal
    เพื่อให้ผลของรอบเก่าถูกบันทึกไว้ก่อนที่ users.health_goal_locked_until
    จะขยับไปเป็นของรอบใหม่ (ไม่งั้นจะคำนวณ period_start ของรอบเก่าย้อนกลับ
    ไม่ได้อีกเลย)

    มื้อ "มีให้เลือกได้จริง" (meals_available) นับเฉพาะช่วงเวลาของมื้อ (ดู
    MEAL_TIME_WINDOWS) ที่เริ่มตั้งแต่ตอนที่ผู้ใช้ตั้งเป้าหมายนี้เป็นต้นไป —
    ถ้าตั้งเป้าหมายตอนบ่าย มื้อเช้า/กลางวันของวันนั้นที่ผ่านไปแล้วก่อนตั้ง
    เป้าหมายจะไม่ถูกนับเป็น "พลาด" (ผู้ใช้ไม่มีทางเลือกได้ทันอยู่แล้ว)
    """
    locked_until = user.health_goal_locked_until
    if locked_until is None or not user.health_goal:
        return
    if locked_until.tzinfo is None:
        locked_until = locked_until.replace(tzinfo=timezone(timedelta(hours=7)))
    if get_thailand_time() < locked_until:
        return

    period_end_naive = locked_until.replace(tzinfo=None)
    already = HealthGoalCycle.query.filter_by(user_id=user.id, period_end=period_end_naive).first()
    if already is not None and already.acknowledged_at is not None:
        return

    # health_goal_started_at คือจุดเริ่มจริง — locked_until ไม่ใช่ started_at+7
    # วันตรงๆ อีกต่อไป (ปัดไปที่ 22:00 ของวันที่ 7 แล้ว) ย้อนคำนวณจาก
    # locked_until เพียงอย่างเดียวไม่แม่นยำ ต้องใช้ค่าที่บันทึกไว้จริง — เผื่อ
    # แถวเก่าก่อนมีคอลัมน์นี้ (started_at เป็น None) ค่อย fallback ไปแบบเดิม
    started_at = user.health_goal_started_at
    if started_at is not None:
        period_start = started_at.replace(tzinfo=timezone(timedelta(hours=7)))
    else:
        period_start = locked_until - timedelta(days=7)
    logs = MealLog.query.options(selectinload(MealLog.items)).filter(
        MealLog.user_id == user.id,
        MealLog.log_date >= period_start.date(),
        MealLog.log_date <= locked_until.date(),
    ).all()

    # เดิม cap ต่อมื้อ (calories_goal/3) บล็อกการบันทึกจริงตอนกด "ยืนยัน" —
    # เอาข้อจำกัดนั้นออกแล้ว (ดู meal_log_items()) แต่ยังอยากรู้ว่ารอบนี้กินเกิน
    # โควตาไปกี่มื้อ เอามานับสรุปตอนจบรอบแทน (ผู้ใช้ขอ) ใช้สูตร cap เดียวกับ
    # ตอนเขียนเดิมทุกประการ (calories_actual รวมของมื้อ เทียบ calories_goal/3)
    logged_slots = set()
    meals_over_quota = 0
    eaten_calories_by_day = {}
    for log in logs:
        eaten_items = [it for it in log.items if it.is_eaten]
        if not eaten_items:
            continue
        logged_slots.add((log.log_date, log.meal_type))
        eaten_calories_by_day[log.log_date] = eaten_calories_by_day.get(log.log_date, 0.0) + sum(
            float(it.calories_actual or 0) for it in eaten_items
        )
        if log.calories_goal and log.calories_goal > 0:
            meal_total = sum(float(it.calories_actual or 0) for it in eaten_items)
            if meal_total > log.calories_goal / 3:
                meals_over_quota += 1

    # เป้าหมายสำเร็จหรือไม่ให้นับตามวันที่ของแผนเท่านั้น ไม่ตัดมื้อจากเวลา
    # ที่เริ่มตั้งเป้าหมายหรือช่วงเวลาอาหาร ผู้ใช้กรอกวันไหน/มื้อไหนภายในรอบ
    # ก็ได้ และแต่ละวันมี 3 มื้อที่นับได้เสมอ
    meals_available = ((locked_until.date() - period_start.date()).days + 1) * len(MEAL_TYPES)

    meals_logged = len(logged_slots)
    ratio = (meals_logged / meals_available) if meals_available else 0.0
    weight_logs = WeightLog.query.filter(
        WeightLog.user_id == user.id,
        WeightLog.logged_at >= period_start.date(),
        WeightLog.logged_at <= locked_until.date(),
    ).order_by(WeightLog.logged_at.asc(), WeightLog.id.asc()).all()
    # เก็บน้ำหนักโปรไฟล์ ณ ตอนเริ่มรอบแยกจากน้ำหนักเป้าหมาย
    # และใช้ข้อมูลน้ำหนักย้อนหลังล่าสุดเป็นค่าน้ำหนักปัจจุบันของรอบ
    target_weight = float(user.health_goal_target_weight) if user.health_goal_target_weight is not None else None
    if user.health_goal_start_weight is not None:
        weight_start = float(user.health_goal_start_weight)
    elif weight_logs:
        weight_start = float(weight_logs[0].weight)
    else:
        weight_start = float(user.weight) if user.weight is not None else None
    weight_end = float(weight_logs[-1].weight) if weight_logs else None
    weight_delta = (weight_end - weight_start) if weight_start is not None and weight_end is not None else None
    daily_quota_excess_percent = max(
        (
            ((calories - float(user.calories_goal)) / float(user.calories_goal)) * 100
            for calories in eaten_calories_by_day.values()
            if user.calories_goal and calories > float(user.calories_goal)
        ),
        default=0.0,
    )
    cycle = already or HealthGoalCycle(
        user_id=user.id,
        period_end=period_end_naive,
    )
    cycle.health_goal = user.health_goal
    cycle.calories_goal = user.calories_goal
    cycle.period_start = period_start.replace(tzinfo=None)
    cycle.meals_logged = meals_logged
    cycle.meals_available = meals_available
    cycle.meals_over_quota = meals_over_quota
    cycle.daily_quota_excess_percent = daily_quota_excess_percent
    cycle.success_ratio = ratio
    cycle.weight_start = weight_start
    cycle.weight_end = weight_end
    # เป้าหมายสำเร็จต้องผ่านเกณฑ์ 60% และไม่ให้มีมื้อใดเกินโควตา
    # เป้าหมายลด/เพิ่มต้องถึงน้ำหนักปลายทาง; เป้าหมายรักษาต้องอยู่ใกล้
    # น้ำหนักเริ่มต้นไม่เกิน 0.1 กก. หากยังไม่มีค่าเป้าหมาย (รอบเก่า) ให้
    # ใช้ทิศทางการเปลี่ยนแปลงจากน้ำหนักเริ่มต้นแทน
    goal_matches_weight = False
    if weight_start is not None and weight_end is not None:
        if user.health_goal == 'ลดน้ำหนัก':
            goal_matches_weight = (
                weight_end <= target_weight
                if target_weight is not None
                else weight_end < weight_start
            )
        elif user.health_goal == 'เพิ่มน้ำหนัก':
            goal_matches_weight = (
                weight_end >= target_weight
                if target_weight is not None
                else weight_end > weight_start
            )
        elif user.health_goal == 'รักษาน้ำหนัก':
            goal_matches_weight = round(abs(weight_end - weight_start), 1) <= 0.1
    # ต้องบันทึกมื้อถึง 60% และน้ำหนักต้องสอดคล้องกับเป้าหมายเสมอ ส่วนกรณี
    # กินเกิน kcal แต่ทำให้น้ำหนักไปถูกทิศทางยังถือว่าสำเร็จได้ หากมื้อถึงเกณฑ์
    cycle.is_success = ratio >= GOAL_SUCCESS_THRESHOLD and goal_matches_weight
    db.session.add(cycle)
    try:
        db.session.commit()
    except IntegrityError:
        # race: อีก request คำนวณรอบเดียวกันเสร็จไปก่อนแล้ว (UNIQUE user_id+
        # period_end กันซ้ำที่ระดับ DB) — ไม่ใช่ error จริง แค่ทิ้งของเราไป
        db.session.rollback()


def _require_auth_user():
    """Return (user, None) or (None, (json_response, status)) on failure."""
    auth = request.headers.get('Authorization') or ''
    if not auth.startswith('Bearer '):
        return None, error_response('กรุณาเข้าสู่ระบบ', 401, 'UNAUTHORIZED')
    token = auth.split(' ', 1)[1].strip()
    user = User.query.filter_by(password_token=token).first()
    if not user or getattr(user, 'is_deleted', False) or not user.password_token or token != user.password_token:
        return None, error_response('เซสชันไม่ถูกต้อง กรุณาเข้าสู่ระบบใหม่', 401, 'UNAUTHORIZED')
    # ตรงนี้ token match กับ user แล้วแน่ๆ (เช็คด้านบน) — ถ้า token_valid_for_user
    # ยังคืน False แปลว่าสาเหตุเดียวที่เหลือคือหมดอายุ (TTL) เท่านั้น จึงแยก code
    # TOKEN_EXPIRED ออกจาก UNAUTHORIZED ทั่วไปได้โดยไม่ต้องเขียนตรรกะ TTL ซ้ำ
    if not token_valid_for_user(user, token):
        return None, error_response('เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่', 401, 'TOKEN_EXPIRED')
    return user, None


def _serialize_meal_log(log):
    return {
        'id': log.id,
        'user_id': log.user_id,
        'log_date': log.log_date.isoformat(),
        'meal_type': log.meal_type,
        'calories_goal': log.calories_goal,
        'created_at': log.created_at.isoformat() if log.created_at else None,
        'items': [{
            'id': it.id,
            'food_item_id': it.food_item_id,
            'food_item_name': (it.food_item.name_th or it.food_item.name) if it.food_item else None,
            'serving_size_id': it.serving_size_id,
            'quantity': it.quantity,
            'calories_actual': it.calories_actual,
            'protein_actual': it.protein_actual,
            'carbs_actual': it.carbs_actual,
            'fat_actual': it.fat_actual,
            'is_eaten': bool(it.is_eaten),
            'eaten_at': it.eaten_at.isoformat() if it.eaten_at else None,
        } for it in log.items],
    }


def _meal_already_logged_response(existing):
    msg = 'มื้อนี้บันทึกไปแล้วสำหรับวันนี้'
    return jsonify({
        'is_error': True,
        'error': msg,
        'code': 'MEAL_ALREADY_LOGGED',
        'message': msg,
        'meal_log': _serialize_meal_log(existing),
    }), 409


@app.route('/meal-logs', methods=['POST', 'GET'])
def meal_logs():
    user, err = _require_auth_user()
    if err:
        return err

    if request.method == 'GET':
        # eager-load items + food_item ในคำสั่งเดียว กัน N+1 (เดิม access
        # log.items / it.food_item ผ่าน lazy relationship ทีละแถวตอน serialize)
        q = MealLog.query.options(
            selectinload(MealLog.items).selectinload(MealLogItem.food_item)
        ).filter_by(user_id=user.id)
        date_param = request.args.get('date')
        from_param = request.args.get('from')
        to_param = request.args.get('to')
        if date_param:
            d = parse_date_of_birth(date_param)
            if d is None:
                return error_response('รูปแบบวันที่ไม่ถูกต้อง', 400, 'VALIDATION_ERROR')
            q = q.filter(MealLog.log_date == d)
        else:
            if from_param:
                d = parse_date_of_birth(from_param)
                if d is None:
                    return error_response('รูปแบบวันที่เริ่มต้น (from) ไม่ถูกต้อง', 400, 'VALIDATION_ERROR')
                q = q.filter(MealLog.log_date >= d)
            if to_param:
                d = parse_date_of_birth(to_param)
                if d is None:
                    return error_response('รูปแบบวันที่สิ้นสุด (to) ไม่ถูกต้อง', 400, 'VALIDATION_ERROR')
                q = q.filter(MealLog.log_date <= d)
        logs = q.order_by(MealLog.log_date.desc()).all()
        return jsonify({'meal_logs': [_serialize_meal_log(l) for l in logs]}), 200

    # POST — create today's (or given date's) log for one meal_type.
    data = request.get_json(silent=True) or {}
    meal_type = (data.get('meal_type') or '').strip().lower()
    if meal_type not in MEAL_TYPES:
        return error_response(
            f"meal_type ต้องเป็นหนึ่งใน {', '.join(MEAL_TYPES)} เท่านั้น", 400, 'VALIDATION_ERROR'
        )

    log_date = parse_date_of_birth(data.get('log_date')) if data.get('log_date') else get_thailand_time().date()
    if log_date is None:
        return error_response('รูปแบบวันที่ (log_date) ไม่ถูกต้อง', 400, 'VALIDATION_ERROR')
    if log_date > get_thailand_time().date():
        return error_response('ไม่สามารถบันทึกล่วงหน้า', 400, 'VALIDATION_ERROR')

    # เดิมล็อกมื้อของวันนี้ตามช่วงเวลา (MEAL_TIME_WINDOWS) ห้ามบันทึกมื้อเช้า
    # ตอนบ่าย/มื้อเย็นตอนเที่ยง ฯลฯ — ผู้ใช้ยืนยันชัดเจน: อนุญาตให้กรอกมื้อไหน
    # เวลาไหนก็ได้เต็มที่ ไม่ต้องกรอกตามช่วงเวลาอีกต่อไป (MEAL_TIME_WINDOWS ยัง
    # ใช้อยู่ที่อื่น เช่น _finalize_expired_goal_cycle คิด meals_available ของ
    # รอบเป้าหมาย ไม่ได้ลบทิ้งทั้งหมด แค่เอาการล็อกจุดนี้ออก)

    existing = MealLog.query.filter_by(user_id=user.id, log_date=log_date, meal_type=meal_type).first()
    if existing:
        return _meal_already_logged_response(existing)

    log = MealLog(user_id=user.id, log_date=log_date, meal_type=meal_type, calories_goal=user.calories_goal)
    db.session.add(log)
    try:
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        existing = MealLog.query.filter_by(user_id=user.id, log_date=log_date, meal_type=meal_type).first()
        return _meal_already_logged_response(existing)

    return jsonify(_serialize_meal_log(log)), 201


def _meal_is_sealed(log):
    """มื้อ 'ปิดสนิท' แล้วหรือยัง — อิงเวลาที่เมนู "แรก" ของมื้อนี้ถูกกดทานแล้ว
    ไม่ใช่เมนูล่าสุด — เดิมเช็คว่ามีเมนูไหนในมื้อยังไม่เกิน 5 นาทีของ "ตัวมันเอง"
    บ้างไหม (ต้องทานครบทุกเมนูด้วย) ทำให้เพิ่มเมนูใหม่เข้ามื้อที่ทานไปแล้วนาน
    กว่า 5 นาที แล้วกดทานแล้วให้เมนูใหม่นี้ ได้นาฬิกาใหม่ทุกครั้ง เลื่อนวันที่
    มื้อจะปิดออกไปเรื่อยๆ ไม่มีที่สิ้นสุด (ผู้ใช้รายงานจริง) เปลี่ยนมายึดเวลา
    "ทานแล้วครั้งแรกสุด" ของมื้อนี้แทน ครบ 5 นาทีจากจุดนั้นคือปิดถาวร ไม่ว่าจะ
    เพิ่ม/มาร์กเมนูใหม่เข้ามาอีกกี่ตัวก็ตาม — คุมแค่ "เพิ่มเมนูใหม่ได้ไหม"
    เท่านั้น ไม่กระทบสิทธิ์แก้ไข/ลบ/ยกเลิกทานแล้วของแต่ละเมนูที่ยังคง
    อิงเวลาของตัวเองตามเดิม (ดู delete_meal_log_item/undo_meal_log_item_eaten)"""
    eaten_ats = [it.eaten_at for it in log.items if it.is_eaten and it.eaten_at is not None]
    if not eaten_ats:
        return False
    earliest = min(eaten_ats)
    if earliest.tzinfo is None:
        earliest = earliest.replace(tzinfo=timezone(timedelta(hours=7)))
    return get_thailand_time() - earliest > timedelta(minutes=5)


@app.route('/meal-logs/<int:log_id>/items', methods=['POST'])
def meal_log_items(log_id):
    user, err = _require_auth_user()
    if err:
        return err

    log = MealLog.query.get_or_404(log_id)
    if log.user_id != user.id:
        return error_response('ไม่มีสิทธิ์เข้าถึงมื้อนี้', 403, 'FORBIDDEN')

    # ผู้ใช้รายงานจริง — เดิมต่อให้ทุกเมนูของมื้อนี้ "ทานแล้ว" และเกิน 5 นาที
    # ไปแล้ว (แก้ไข/ลบของเดิมไม่ได้แล้ว) ก็ยังเพิ่มเมนูใหม่เข้ามื้อเดียวกันได้
    # อยู่ดี ทั้งที่ประวัติการกินของมื้อนี้ควรถือว่า "ปิดสนิท" แล้วเหมือนกัน —
    # บล็อกตรงนี้ให้สอดคล้องกับกฎ 5 นาทีเดียวกับ undo-eaten/delete
    if _meal_is_sealed(log):
        return error_response(
            'มื้อนี้ทานครบและเกิน 5 นาทีแล้ว ไม่สามารถเพิ่มเมนูใหม่ได้อีก', 409, 'MEAL_ALREADY_SEALED',
        )

    # หลายเมนูต่อมื้อได้แล้ว (FoodBrowserPage เลือกหลายอย่างแล้วค่อยกดยืนยัน
    # รวดเดียว) — เดิมล็อกไว้ที่รายการแรกเสมอ ตอนนี้ยกเลิกแล้ว ตาราง
    # meal_log_items ไม่มี constraint ใดๆ ที่ผูกกับจำนวนรายการต่อมื้ออยู่แล้ว
    data = request.get_json(silent=True) or {}
    food_item = FoodItem.query.get(data.get('food_item_id'))
    if not food_item:
        return error_response('ไม่พบเมนูที่เลือก', 404, 'NOT_FOUND')

    # เดิมแค่แจ้งเตือนกลับไป (200/201 ปกติ) ไม่บล็อกจริง — ผู้ใช้ขอให้ห้าม
    # บันทึกเมนูที่ตรงกับสิ่งที่แพ้/โรคประจำตัวไปเลย ไม่ใช่แค่เตือน (เปลี่ยน
    # จาก advisory เป็น hard block จริง) เช็คก่อนสร้างแถวเลย ไม่ใช่หลังบันทึก
    # แล้วค่อยแจ้ง — กันกรณี client ถูกดัดแปลงข้ามการเช็คฝั่ง UI ไปเลย (จุด
    # บล็อกฝั่ง UI คือ ServingPickerSheet ปิดปุ่ม "เพิ่มลงมื้อ" — จุดนี้คือ
    # เช็คซ้ำฝั่ง server กันหลุดจริง)
    allergen_names = [a.name for a in food_item.allergens]
    matched = _matched_restricted_allergens(user, allergen_names)
    if matched:
        return error_response(
            f"ไม่สามารถบันทึกเมนูนี้ได้ — มีส่วนผสมที่คุณควรระวัง: {', '.join(matched)}",
            403, 'ALLERGEN_BLOCKED', detail={'allergens': matched},
        )

    # เช็คเดียวกับด้านบนแต่สำหรับหมวดที่ห้ามทั้งหมวด (เช่นเบาหวานกับของหวาน —
    # blocked_category_reason) เดิมเช็คแค่ตอน AI แนะนำเมนู (ai_recommend_menu)
    # จุดเดียว ผู้ใช้เลือกเมนูของหวานเองผ่านหน้าบันทึกมื้อได้ปกติทั้งที่มีโรค
    # ประจำตัว (ผู้ใช้รายงานจริง) — บล็อกฝั่ง server ที่นี่เหมือน allergen กัน
    # client ที่ถูกดัดแปลงข้ามการเช็คฝั่ง UI (ServingPickerSheet ปิดปุ่มไว้แล้ว
    # จาก item.allergyWarning ที่รวม disease_warning_reason เข้าไปแล้ว)
    category_type = food_item.category.type if food_item.category else None
    disease_reason = blocked_category_reason(user.chronic_diseases, category_type)
    if disease_reason:
        return error_response(disease_reason, 403, 'ALLERGEN_BLOCKED', detail={'allergens': []})

    quantity = data.get('quantity', 1.0)
    try:
        quantity = float(quantity)
    except (TypeError, ValueError):
        return error_response('quantity ต้องเป็นตัวเลข', 400, 'VALIDATION_ERROR')
    if quantity < 0.5 or quantity > 10:
        return error_response('quantity ต้องอยู่ระหว่าง 0.5 ถึง 10', 400, 'VALIDATION_ERROR')

    serving = None
    if data.get('serving_size_id'):
        serving = ServingSize.query.filter_by(id=data['serving_size_id'], food_item_id=food_item.id).first()
        if not serving:
            return error_response('ไม่พบขนาดหน่วยบริโภคนี้สำหรับเมนูที่เลือก', 404, 'NOT_FOUND')

    multiplier = serving.calories_multiplier if serving else 1.0
    protein_actual = float(food_item.protein_g or 0) * multiplier * quantity
    carbs_actual = float(food_item.carbs_g or 0) * multiplier * quantity
    fat_actual = float(food_item.fat_g or 0) * multiplier * quantity
    calories_actual = calc_calories_from_macros(carbs_actual, protein_actual, fat_actual)

    # เดิม cap ต่อมื้อ (calories_goal/3, แบ่งเท่ากัน 3 มื้อ) บล็อกการบันทึกจริง
    # (409 MEAL_CALORIE_CAP_EXCEEDED) เกินแล้วเพิ่มเมนูต่อไม่ได้เลย — ผู้ใช้
    # ขอให้เอาข้อจำกัดนี้ออก ให้เกินโควตาได้ตามใจ (ฝั่ง UI ก็แค่เตือนไว้ ไม่
    # เคยบล็อกอยู่แล้ว ดู food_browser_page.dart._buildMealCapPreview) แล้ว
    # เอาไปนับสรุปตอนจบรอบเป้าหมายสุขภาพแทน (ดู meals_over_quota ใน
    # _finalize_expired_goal_cycle) ไม่ต้องเช็ค/บล็อกตรงนี้อีกต่อไป
    item = MealLogItem(
        meal_log_id=log.id,
        food_item_id=food_item.id,
        serving_size_id=serving.id if serving else None,
        quantity=quantity,
        calories_actual=calories_actual,
        protein_actual=protein_actual,
        carbs_actual=carbs_actual,
        fat_actual=fat_actual,
    )
    db.session.add(item)
    db.session.commit()

    return jsonify(_serialize_meal_log(log)), 201


@app.route('/meal-log-items/<int:item_id>/eaten', methods=['PATCH'])
def mark_meal_log_item_eaten(item_id):
    user, err = _require_auth_user()
    if err:
        return err

    item = MealLogItem.query.get_or_404(item_id)
    if item.meal_log.user_id != user.id:
        return error_response('ไม่มีสิทธิ์เข้าถึงรายการนี้', 403, 'FORBIDDEN')

    item.is_eaten = True
    item.eaten_at = get_thailand_time()
    db.session.commit()

    return jsonify(_serialize_meal_log(item.meal_log)), 200


@app.route('/api/meal-log-items/<int:item_id>/undo-eaten', methods=['PATCH'])
def undo_meal_log_item_eaten(item_id):
    """ยกเลิก 'ทานแล้ว' ได้ภายใน 5 นาทีหลังกด — กันกดพลาด หลังจากนั้นถือเป็น
    ค่าถาวร แก้ย้อนหลังไม่ได้ (ตัดสินใจแบบเดียวกับที่ meal_logs ห้ามแก้เมนู
    ย้อนหลังหลังเลือกไปแล้ว — ข้อมูลประวัติการกินต้องเชื่อถือได้)

    เดิมเช็คแค่เวลาของ item ตัวเองเทียบ 5 นาที — ถ้าเมนูนี้เพิ่งถูกเพิ่ม/มาร์ก
    ทานแล้วสดๆ (ยังไม่เกิน 5 นาทีของตัวเอง) จะยังยกเลิกได้ ทั้งที่มื้อนี้ปิด
    สนิทไปแล้วจากเมนูอื่นที่ทานก่อนหน้าเกิน 5 นาที (ผู้ใช้รายงานจริง — ไม่ตรง
    กับปุ่ม "+ เลือกเมนูเพิ่ม" ที่ล็อกทั้งมื้อไปแล้วตาม _meal_is_sealed) เปลี่ยน
    มาเช็คที่ระดับมื้อแทน ให้สอดคล้องกันทั้งแอป"""
    user, err = _require_auth_user()
    if err:
        return err

    item = MealLogItem.query.get_or_404(item_id)
    if item.meal_log.user_id != user.id:
        return error_response('ไม่มีสิทธิ์เข้าถึงรายการนี้', 403, 'FORBIDDEN')

    if not item.is_eaten or item.eaten_at is None:
        return error_response('รายการนี้ยังไม่ได้กดทานแล้ว', 400, 'VALIDATION_ERROR')

    if _meal_is_sealed(item.meal_log):
        return error_response('เกินเวลาที่จะยกเลิกได้แล้ว (5 นาที)', 400, 'EATEN_UNDO_EXPIRED')

    item.is_eaten = False
    item.eaten_at = None
    db.session.commit()

    return jsonify(_serialize_meal_log(item.meal_log)), 200


@app.route('/meal-log-items/<int:item_id>', methods=['DELETE'])
def delete_meal_log_item(item_id):
    """ลบเมนูที่เลือกผิด/อยากเปลี่ยนออกจากมื้อที่บันทึกไว้แล้ว — เดิมไม่มี
    endpoint นี้เลย ทำให้มื้อที่มีเมนูอย่างน้อย 1 รายการแล้วแก้ไขไม่ได้อีก
    ต้องรอวันถัดไปเท่านั้น (บั๊กที่ผู้ใช้รายงานจริง) รายการที่ยังไม่ทาน (หรือ
    ทานแล้วแต่ยังไม่เกิน 5 นาที) ลบได้ไม่จำกัดเวลาเหมือนเดิม แต่รายการที่
    ทานแล้ว+เกิน 5 นาทีไปแล้วต้องล็อกเหมือน undo-eaten (ข้อมูลประวัติการกิน
    ต้องเชื่อถือได้หลังผ่านช่วงแก้ไขพลาดไปแล้ว) — ผู้ใช้รายงานจริงว่า UI เดิม
    (ก่อนหน้านี้) ยังโชว์ปุ่มลบให้กดได้ทั้งที่เลย 5 นาทีไปแล้ว ไม่ตรงกับ
    undo-eaten ที่ล็อกจริง จึงย้ายมาเช็คตรงนี้ด้วยให้สอดคล้องกัน

    เดิมเช็คแค่เวลาของ item ตัวเองเทียบ 5 นาที — เมนูที่เพิ่งทานสดๆ (ยังไม่
    เกิน 5 นาทีของตัวเอง) จะยังลบได้ ทั้งที่มื้อนี้ปิดสนิทไปแล้วจากเมนูอื่นที่
    ทานก่อนหน้าเกิน 5 นาที (ผู้ใช้รายงานจริง) เปลี่ยนมาเช็คที่ระดับมื้อแทน"""
    user, err = _require_auth_user()
    if err:
        return err

    item = MealLogItem.query.get_or_404(item_id)
    log = item.meal_log
    if log.user_id != user.id:
        return error_response('ไม่มีสิทธิ์เข้าถึงรายการนี้', 403, 'FORBIDDEN')

    if item.is_eaten and _meal_is_sealed(log):
        return error_response(
            'รายการนี้ทานไปแล้วเกิน 5 นาที แก้ไขไม่ได้อีก', 400, 'ITEM_EATEN_LOCKED',
        )

    db.session.delete(item)
    db.session.commit()

    return jsonify(_serialize_meal_log(log)), 200


# =========================
# WEIGHT TRACKING
# =========================

def _serialize_weight_log(w):
    return {
        'id': w.id,
        'weight': w.weight,
        'logged_at': w.logged_at.isoformat(),
        'created_at': w.created_at.isoformat() if w.created_at else None,
    }


def _sync_user_weight_to_latest_log(user):
    """users.weight ต้องตรงกับค่าน้ำหนักของ logged_at ล่าสุดเสมอ (ไม่ใช่แค่
    ค่าที่เพิ่ง POST เข้ามาล่าสุด) กัน backfill วันที่ย้อนหลังทำให้ users.weight
    เพี้ยนไปจากค่าจริงของ "วันนี้" ที่เคยบันทึกไว้แล้ว"""
    latest = WeightLog.query.filter_by(user_id=user.id).order_by(WeightLog.logged_at.desc()).first()
    if latest is not None:
        user.weight = latest.weight


@app.route('/api/weight-logs', methods=['POST', 'GET'])
def weight_logs():
    user, err = _require_auth_user()
    if err:
        return err

    if request.method == 'GET':
        days = request.args.get('days', 30, type=int)
        if days is None or days < 1:
            days = 30
        since = get_thailand_time().date() - timedelta(days=days - 1)
        rows = (
            WeightLog.query.filter_by(user_id=user.id)
            .filter(WeightLog.logged_at >= since)
            .order_by(WeightLog.logged_at.asc())
            .all()
        )
        return jsonify({'weight_logs': [_serialize_weight_log(w) for w in rows]}), 200

    # POST — upsert ตามวันที่ (default วันนี้ตามเวลาไทย) ต่างจาก meal_logs
    # ตรงที่ "บันทึกซ้ำวันเดียวกัน" ไม่ error 409 แต่อัปเดตค่าเดิมแทน เพราะ
    # น้ำหนักแก้ค่าของวันเดียวกันซ้ำได้สมเหตุสมผลกว่ามื้ออาหาร
    data = request.get_json(silent=True) or {}
    weight = data.get('weight')
    try:
        weight = float(weight)
    except (TypeError, ValueError):
        return error_response('weight ต้องเป็นตัวเลข', 400, 'VALIDATION_ERROR')
    if weight <= 0 or weight > 500:
        return error_response('weight ต้องอยู่ระหว่าง 0 ถึง 500 กก.', 400, 'VALIDATION_ERROR')

    if data.get('logged_at'):
        logged_at = parse_date_of_birth(data.get('logged_at'))
        if logged_at is None:
            return error_response('รูปแบบวันที่ (logged_at) ไม่ถูกต้อง', 400, 'VALIDATION_ERROR')
    else:
        logged_at = get_thailand_time().date()
    if logged_at > get_thailand_time().date():
        return error_response('ไม่สามารถบันทึกล่วงหน้าได้', 400, 'VALIDATION_ERROR')

    existing = WeightLog.query.filter_by(user_id=user.id, logged_at=logged_at).first()
    if existing:
        existing.weight = weight
        log = existing
    else:
        log = WeightLog(user_id=user.id, weight=weight, logged_at=logged_at)
        db.session.add(log)

    try:
        db.session.commit()
    except IntegrityError:
        # race condition: สองคำขอพร้อมกันวันเดียวกัน คนแรกชนะสร้างแถวใหม่
        # ไปแล้ว ผู้แพ้ (ตรงนี้) เจอ UNIQUE(user_id, logged_at) ชน — เดิมปล่อย
        # เป็น raw exception (500 ผ่าน global handler แทนที่จะเป็น 200 ปกติ)
        # แก้โดย rollback แล้ว UPDATE แถวที่ชนะไปแล้วแทน ให้ผลลัพธ์เหมือน
        # upsert ที่ตั้งใจไว้จริงๆ (ผู้ใช้ไม่ควรเห็น error จากการกดซ้ำ/สองอุปกรณ์)
        db.session.rollback()
        log = WeightLog.query.filter_by(user_id=user.id, logged_at=logged_at).first()
        log.weight = weight
        db.session.commit()
    return jsonify(_serialize_weight_log(log)), 200


# =========================
# PDPA CONSENT
# =========================

@app.route('/api/consents/status', methods=['GET'])
def consent_status():
    user, err = _require_auth_user()
    if err:
        return err
    consent_type = (request.args.get('type') or 'health_data_pdpa').strip()

    # เทียบกับ "เวอร์ชันล่าสุดที่เคยยินยอม" เท่านั้น — ถ้าเคยยินยอมเวอร์ชันเก่า
    # ไว้แล้วแต่ CURRENT_PDPA_POLICY_VERSION ถูก bump ทีหลัง consented ต้องเป็น
    # false ใหม่ทันที (ต้องยินยอมนโยบายที่เปลี่ยนไปอีกครั้ง)
    latest = (
        UserConsent.query.filter_by(user_id=user.id, consent_type=consent_type)
        .order_by(UserConsent.consented_at.desc())
        .first()
    )
    consented_version = latest.policy_version if latest else None
    return jsonify({
        'consented': consented_version == CURRENT_PDPA_POLICY_VERSION,
        'current_version': CURRENT_PDPA_POLICY_VERSION,
        'consented_version': consented_version,
    }), 200


@app.route('/api/consents', methods=['POST'])
def create_consent():
    user, err = _require_auth_user()
    if err:
        return err
    data = request.get_json(silent=True) or {}
    consent_type = (data.get('consent_type') or 'health_data_pdpa').strip()
    policy_version = (data.get('policy_version') or '').strip()
    if not policy_version:
        return error_response('ต้องระบุ policy_version', 400, 'VALIDATION_ERROR')

    # append-only เสมอ — ไม่ upsert ทับของเดิม เพราะต้องเป็นหลักฐานย้อนหลัง
    # ได้ว่ายินยอมเวอร์ชันไหนตอนไหนบ้าง ไม่ใช่แค่สถานะล่าสุด
    consent = UserConsent(user_id=user.id, consent_type=consent_type, policy_version=policy_version)
    db.session.add(consent)
    db.session.commit()
    return jsonify({
        'status': 'ok',
        'consent_type': consent_type,
        'policy_version': policy_version,
        'consented_at': consent.consented_at.isoformat() if consent.consented_at else None,
    }), 201


# =========================
# EXPORT HISTORY (PDF/CSV)
# =========================

MEAL_TYPE_LABEL_TH = {'breakfast': 'เช้า', 'lunch': 'กลางวัน', 'dinner': 'เย็น'}
EXPORT_HISTORY_HEADERS_TH = [
    'วันที่', 'มื้อ', 'ชื่อเมนู', 'ขนาดที่เลือก', 'จำนวน',
    'แคลอรี', 'โปรตีน', 'คาร์บ', 'ไขมัน', 'สถานะ',
]

# ponytail: fpdf2's core fonts (Helvetica ฯลฯ) render ภาษาไทยไม่ได้เลย ต้อง
# embed font ที่มี glyph ไทยจริง — เครื่องนี้ (Windows) มี Tahoma ติดมาด้วย
# จึงใช้ได้ทันทีสำหรับ dev/demo แต่ path นี้เป็น Windows-only ถ้า deploy จริง
# บน Linux ต้องเปลี่ยนไปชี้ font ที่ bundle มากับโปรเจกต์เอง (เช่น Noto Sans
# Thai / Sarabun วางไว้ที่ backend/assets/fonts/) แล้วอัปเดต path ด้านล่างนี้
_THAI_FONT_CANDIDATES = [
    r'C:\Windows\Fonts\tahoma.ttf',
    r'C:\Windows\Fonts\leelawad.ttf',
    '/usr/share/fonts/truetype/thai/Waree.ttf',
]


def _resolve_thai_font_path():
    for path in _THAI_FONT_CANDIDATES:
        if os.path.exists(path):
            return path
    return None


def _export_history_rows(user, from_date, to_date):
    q = (
        MealLog.query.options(
            selectinload(MealLog.items).selectinload(MealLogItem.food_item),
            selectinload(MealLog.items).selectinload(MealLogItem.serving_size),
        )
        .filter(MealLog.user_id == user.id)
    )
    if from_date:
        q = q.filter(MealLog.log_date >= from_date)
    if to_date:
        q = q.filter(MealLog.log_date <= to_date)
    logs = q.order_by(MealLog.log_date.asc(), MealLog.meal_type.asc()).all()

    rows = []
    for log in logs:
        for it in log.items:
            rows.append([
                log.log_date.isoformat(),
                MEAL_TYPE_LABEL_TH.get(log.meal_type, log.meal_type),
                (it.food_item.name_th or it.food_item.name) if it.food_item else '',
                (it.serving_size.unit_name_th or it.serving_size.unit_name) if it.serving_size else '-',
                it.quantity,
                it.calories_actual or 0,
                it.protein_actual or 0,
                it.carbs_actual or 0,
                it.fat_actual or 0,
                'ทานแล้ว' if it.is_eaten else 'วางแผน',
            ])
    return rows


@app.route('/api/export/history', methods=['GET'])
def export_history_pdf_csv():
    user, err = _require_auth_user()
    if err:
        return err

    fmt = (request.args.get('format') or 'csv').strip().lower()
    if fmt not in ('csv', 'pdf'):
        return error_response('format ต้องเป็น csv หรือ pdf เท่านั้น', 400, 'VALIDATION_ERROR')

    from_date = to_date = None
    if request.args.get('from'):
        from_date = parse_date_of_birth(request.args.get('from'))
        if from_date is None:
            return error_response('รูปแบบวันที่เริ่มต้น (from) ไม่ถูกต้อง', 400, 'VALIDATION_ERROR')
    if request.args.get('to'):
        to_date = parse_date_of_birth(request.args.get('to'))
        if to_date is None:
            return error_response('รูปแบบวันที่สิ้นสุด (to) ไม่ถูกต้อง', 400, 'VALIDATION_ERROR')

    rows = _export_history_rows(user, from_date, to_date)

    if fmt == 'csv':
        output = io.StringIO()
        writer = csv.writer(output)
        writer.writerow(EXPORT_HISTORY_HEADERS_TH)
        writer.writerows(rows)
        # BOM (utf-8-sig) กัน Excel เปิดภาษาไทยเพี้ยนเป็น mojibake
        csv_bytes = output.getvalue().encode('utf-8-sig')
        return Response(
            csv_bytes,
            mimetype='text/csv',
            headers={'Content-Disposition': 'attachment; filename=history.csv'},
        )

    # format == 'pdf'
    font_path = _resolve_thai_font_path()
    if font_path is None:
        return error_response(
            'เซิร์ฟเวอร์นี้ยังไม่มีฟอนต์ภาษาไทยสำหรับสร้าง PDF กรุณาใช้ format=csv แทน',
            500, 'SERVER_ERROR',
        )

    from fpdf import FPDF
    pdf = FPDF(orientation='L')  # แนวนอน กัน 10 คอลัมน์ล้นหน้า
    pdf.add_page()
    pdf.add_font('Thai', '', font_path)
    pdf.set_font('Thai', '', 10)

    col_widths = [22, 16, 45, 28, 16, 20, 20, 20, 20, 22]
    for header, w in zip(EXPORT_HISTORY_HEADERS_TH, col_widths):
        pdf.cell(w, 8, header, border=1)
    pdf.ln()
    for row in rows:
        for value, w in zip(row, col_widths):
            pdf.cell(w, 8, str(value), border=1)
        pdf.ln()

    pdf_bytes = bytes(pdf.output())
    return Response(
        pdf_bytes,
        mimetype='application/pdf',
        headers={'Content-Disposition': 'attachment; filename=history.pdf'},
    )


if __name__ == '__main__':
    # เดิมไฟล์นี้ไม่มี entrypoint เลย — รัน `py api.py`/`python api.py` ตรงๆ
    # จะจบทันทีแบบไม่มี output ใดๆ (แค่ import/define ทุกอย่างแล้วจบสคริปต์
    # เฉยๆ) ต้องใช้ `flask run` เท่านั้นถึงจะเห็นเซิร์ฟเวอร์รันจริง จุดนี้เพิ่ม
    # ให้ `py api.py` ใช้งานได้ตรงไปตรงมาเหมือนที่คาดหวัง
    #
    # debug=True เดิม hardcode ไว้ไม่มีเงื่อนไข — เซิร์ฟเวอร์นี้เปิดสู่
    # อินเทอร์เน็ตจริง (ยืนยันแล้ว) ถ้า debug mode เปิดอยู่ Werkzeug interactive
    # debugger จะเปิดให้รันโค้ดผ่าน endpoint ที่ error ได้ (บั๊กที่เจอจริง —
    # BUG-009) แก้ให้ผูกกับ FLASK_ENV เหมือน endpoint อันตรายอื่นๆ ในไฟล์นี้
    # (ดู /admin/set-password, /init-db) ปิดโดย default ต้องตั้ง
    # FLASK_ENV=development เองถึงจะเปิด debug mode
    debug_mode = os.environ.get('FLASK_ENV') == 'development'
    app.run(host='127.0.0.1', port=5000, debug=debug_mode)
