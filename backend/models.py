from flask_sqlalchemy import SQLAlchemy
from datetime import datetime, timezone, timedelta
from sqlalchemy import UniqueConstraint

db = SQLAlchemy()

# Helper: return current Thailand time (UTC+7)
def get_thailand_time():
    BANGKOK = timezone(timedelta(hours=7))
    return datetime.now(BANGKOK)

# =========================
# USER MODEL
# =========================

class User(db.Model):
    __tablename__ = 'users'

    id = db.Column(db.Integer, primary_key=True)

    username = db.Column(db.String(80), unique=True, nullable=False, index=True)
    email = db.Column(db.String(120), nullable=True, index=True)
    password_hash = db.Column(db.String(255), nullable=False)

    name = db.Column(db.String(60), nullable=True)
    surname = db.Column(db.String(60), nullable=True)
    avatar_url = db.Column(db.String(512), nullable=True)

    gender = db.Column(db.String(10))
    date_of_birth = db.Column(db.Date, nullable=True)
    weight = db.Column(db.Float)
    height = db.Column(db.Float)
    activity_level = db.Column(db.String(100), nullable=True)

    # ENUM('ลดน้ำหนัก','รักษาน้ำหนัก','เพิ่มน้ำหนัก') — คำนวณ calories_goal ทุกครั้งที่เปลี่ยน
    health_goal = db.Column(db.String(20), nullable=True)
    calories_goal = db.Column(db.Integer, nullable=True)
    # เปลี่ยน health_goal ได้อีกครั้งเมื่อเวลาปัจจุบัน >= ค่านี้ — ตอนนี้คือ
    # 22:00 (เวลาที่มื้อเย็นปิดรับ ดู MEAL_TIME_WINDOWS) ของ "วันที่ 7" นับจาก
    # health_goal_started_at ไม่ใช่ +7*24 ชม.ตรงๆ จากตอนตั้งเป้าหมาย เพื่อให้
    # รอบจบพร้อมมื้อสุดท้ายของวันจริง ไม่ใช่จบกลางดึกหรือกลางมื้อ — null แปลว่า
    # ยังไม่เคยตั้งเป้าหมาย เปลี่ยนได้อิสระ
    health_goal_locked_until = db.Column(db.DateTime, nullable=True)
    # ตอนที่ตั้ง/เปลี่ยน health_goal ครั้งล่าสุด — ใช้เป็นจุดเริ่ม "วันที่ 1"
    # ของรอบ 7 วัน (ดู api._finalize_expired_goal_cycle) แยกจาก
    # health_goal_locked_until เพราะตอนนี้ locked_until ไม่ใช่ started_at+7วัน
    # ตรงๆ อีกต่อไป (ปัดไปที่ 22:00 ของวันที่ 7) คำนวณย้อนกลับจาก locked_until
    # เพียงอย่างเดียวไม่ได้แม่นยำแล้ว
    health_goal_started_at = db.Column(db.DateTime, nullable=True)
    # น้ำหนักเป้าหมาย/จำนวนวันที่กรอกในกล่อง "วางแผนพลังงาน" ตอนบันทึก
    # health_goal ล่าสุด — เดิมไม่เก็บเลย มีแต่ผลลัพธ์ (calories_goal) พอ
    # รีเฟรช/เปิดแอปใหม่ ช่องกรอกในกล่องวางแผนพลังงานเลยว่างเปล่า ทั้งที่
    # เพิ่งกรอก+คำนวณ+บันทึกไปแล้ว (ผู้ใช้รายงานจริง) เก็บไว้ให้ฝั่ง Flutter
    # โหลดกลับมาเติมในช่องเดิมได้
    health_goal_target_weight = db.Column(db.Float, nullable=True)
    health_goal_target_days = db.Column(db.Integer, nullable=True)

    # JSON array, เช่น ["ความดันโลหิตสูง"] / ["กุ้ง"]
    chronic_diseases = db.Column(db.JSON, nullable=True)
    food_allergies = db.Column(db.JSON, nullable=True)

    is_admin = db.Column(db.Boolean, default=False, nullable=False)
    created_at = db.Column(db.DateTime, default=get_thailand_time, index=True)

    password_token = db.Column(db.String(255), nullable=True)
    token_created_at = db.Column(db.DateTime, nullable=True)
    reset_token_hash = db.Column(db.String(255), nullable=True)
    reset_token_expires_at = db.Column(db.DateTime, nullable=True)
    reset_otp_hash = db.Column(db.String(255), nullable=True)
    reset_otp_expires_at = db.Column(db.DateTime, nullable=True)
    reset_otp_attempts = db.Column(db.Integer, default=0)

    is_deleted = db.Column(db.Boolean, default=False, nullable=False)
    delete_reason = db.Column(db.Text, nullable=True)
    deleted_at = db.Column(db.DateTime, nullable=True)

    # Backwards-compatible alias: some code refers to `reset_password_otp`.
    @property
    def reset_password_otp(self):
        return getattr(self, 'reset_otp_hash', None)

    @reset_password_otp.setter
    def reset_password_otp(self, value):
        self.reset_otp_hash = value

    meal_logs = db.relationship('MealLog', backref='user', cascade="all, delete-orphan")
    # foreign_keys ต้องระบุชัด — submissions มี FK ไปหา users 2 เส้นแล้ว
    # (user_id คนส่ง, reviewed_by แอดมินที่ตรวจ) ไม่งั้น SQLAlchemy งงว่า
    # relationship นี้ควร join ผ่านคอลัมน์ไหน
    submissions = db.relationship(
        'Submission', backref='user', cascade="all, delete-orphan",
        foreign_keys='Submission.user_id',
    )
    reports = db.relationship('Report', backref='user', cascade="all, delete-orphan")


# =========================
# FOOD CATALOG
# =========================

class FoodCategory(db.Model):
    __tablename__ = 'food_categories'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    # 'food'/'drink'/'dessert' คือหัวข้อหลักที่ระบบอื่นผูก logic ไว้ (ป้องกันแก้/ลบ
    # ใน PROTECTED_TYPES ด้านล่าง) หัวข้อที่แอดมินเพิ่มเอง (เช่น "ผลไม้") จะมี
    # แถวคู่กันใน FoodType ด้วย เก็บ sort_order — หัวข้อ built-in ไม่มีแถวใน
    # FoodType เพราะลำดับตายตัวอยู่แล้ว (คงที่ในโค้ด ไม่ต้องเรียงเอง)
    type = db.Column(db.String(30), nullable=False, default='food')

    items = db.relationship('FoodItem', backref='category', lazy=True)


class FoodType(db.Model):
    """หัวข้อหลักที่แอดมินเพิ่มเอง นอกเหนือจาก food/drink/dessert (built-in ไม่มี
    แถวที่นี่) — เก็บแยกจาก FoodCategory.type (string) เพื่อให้มี sort_order ลาก
    เรียงลำดับได้ และสร้างหัวข้อว่างได้โดยยังไม่ต้องมีหมวดหมู่ย่อย"""
    __tablename__ = 'food_types'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(30), nullable=False, unique=True)
    sort_order = db.Column(db.Integer, nullable=False, default=0)


class FoodItem(db.Model):
    __tablename__ = 'food_items'

    id = db.Column(db.Integer, primary_key=True)
    category_id = db.Column(db.Integer, db.ForeignKey('food_categories.id'), nullable=False, index=True)
    name = db.Column(db.String(255), nullable=False)
    name_th = db.Column(db.String(255), nullable=True)

    calories = db.Column(db.Float, nullable=True)
    protein_g = db.Column(db.Float, nullable=True)
    carbs_g = db.Column(db.Float, nullable=True)
    fat_g = db.Column(db.Float, nullable=True)
    fiber_g = db.Column(db.Float, nullable=True)
    sugar_g = db.Column(db.Float, nullable=True)
    iron_mg = db.Column(db.Float, nullable=True)
    vitamin_c_mg = db.Column(db.Float, nullable=True)

    swap_food_id = db.Column(db.Integer, db.ForeignKey('food_items.id'), nullable=True, index=True)
    upgrade_tips = db.Column(db.Text, nullable=True)
    image_url = db.Column(db.String(512), nullable=True)
    is_active = db.Column(db.Boolean, default=True)
    # แยก "ยังไม่ได้ตรวจสารก่อภูมิแพ้" ออกจาก "ตรวจแล้วว่าไม่มีเลย" —
    # food_allergens ว่างเปล่าทั้งสองแบบนี้ความหมายต่างกัน (เพิ่มจากงานที่ 4
    # เพราะ CSV import ต้องตั้งค่า default ตอนสร้างเมนูใหม่)
    allergens_reviewed = db.Column(db.Boolean, nullable=False, default=False)

    swap_food = db.relationship('FoodItem', remote_side=[id], uselist=False)
    serving_sizes = db.relationship('ServingSize', backref='food_item', cascade="all, delete-orphan")
    allergens = db.relationship('Allergen', secondary='food_allergens', backref='food_items')


class ServingSize(db.Model):
    __tablename__ = 'serving_sizes'

    id = db.Column(db.Integer, primary_key=True)
    food_item_id = db.Column(db.Integer, db.ForeignKey('food_items.id', ondelete='CASCADE'), nullable=False, index=True)
    unit_name = db.Column(db.String(50), nullable=False)
    unit_name_th = db.Column(db.String(50), nullable=True)
    calories_multiplier = db.Column(db.Float, nullable=False, default=1.0)
    grams_approx = db.Column(db.Float, nullable=True)


class Allergen(db.Model):
    __tablename__ = 'allergens'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), unique=True, nullable=False)


food_allergens = db.Table(
    'food_allergens',
    db.Column('food_item_id', db.Integer, db.ForeignKey('food_items.id', ondelete='CASCADE'), primary_key=True),
    db.Column('allergen_id', db.Integer, db.ForeignKey('allergens.id', ondelete='CASCADE'), primary_key=True),
)


class UserFavoriteFood(db.Model):
    __tablename__ = 'user_favorite_foods'

    user_id = db.Column(db.Integer, db.ForeignKey('users.id', ondelete='CASCADE'), primary_key=True)
    food_item_id = db.Column(db.Integer, db.ForeignKey('food_items.id', ondelete='CASCADE'), primary_key=True)
    created_at = db.Column(db.DateTime, default=get_thailand_time)


# =========================
# MEAL LOGGING
# =========================

class MealLog(db.Model):
    __tablename__ = 'meal_logs'

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True)
    log_date = db.Column(db.Date, nullable=False)
    # ENUM('breakfast','lunch','dinner')
    meal_type = db.Column(db.String(20), nullable=False)
    # snapshot ของ users.calories_goal ณ วันที่บันทึก
    calories_goal = db.Column(db.Integer, nullable=True)
    created_at = db.Column(db.DateTime, default=get_thailand_time)

    items = db.relationship('MealLogItem', backref='meal_log', cascade="all, delete-orphan")

    __table_args__ = (
        UniqueConstraint('user_id', 'log_date', 'meal_type', name='uq_one_meal_per_day'),
    )


class MealLogItem(db.Model):
    __tablename__ = 'meal_log_items'

    id = db.Column(db.Integer, primary_key=True)
    meal_log_id = db.Column(db.Integer, db.ForeignKey('meal_logs.id', ondelete='CASCADE'), nullable=False, index=True)
    food_item_id = db.Column(db.Integer, db.ForeignKey('food_items.id'), nullable=False, index=True)
    serving_size_id = db.Column(db.Integer, db.ForeignKey('serving_sizes.id', ondelete='SET NULL'), nullable=True)
    quantity = db.Column(db.Float, nullable=False, default=1.0)
    # snapshot คำนวณตอนบันทึก กันค่าฐานเปลี่ยนย้อนหลัง — ทั้ง 4 ค่านี้มาจาก
    # multiplier × quantity เดียวกันเสมอ (ดู health_calc.calc_calories_from_macros)
    calories_actual = db.Column(db.Float, nullable=True)
    protein_actual = db.Column(db.Float, nullable=True)
    carbs_actual = db.Column(db.Float, nullable=True)
    fat_actual = db.Column(db.Float, nullable=True)

    is_eaten = db.Column(db.Boolean, default=False)
    eaten_at = db.Column(db.DateTime, nullable=True)

    food_item = db.relationship('FoodItem')
    serving_size = db.relationship('ServingSize')


# =========================
# HEALTH GOAL CYCLES (สรุปผลรอบเป้าหมายสุขภาพ 7 วันที่จบแล้ว)
# =========================

class HealthGoalCycle(db.Model):
    """1 แถวต่อ 1 รอบ health_goal 7 วันที่หมดอายุแล้ว (users.health_goal_locked_until
    ผ่านไปแล้ว) — คำนวณครั้งเดียวตอนรอบหมดอายุแล้วเก็บถาวรไว้ (ดู
    api._finalize_expired_goal_cycle) ไม่คำนวณซ้ำทุกครั้งที่เปิดหน้า เพื่อให้
    ผลลัพธ์ของรอบเก่าไม่เปลี่ยนแม้ผู้ใช้จะตั้งเป้าหมายใหม่ทับไปแล้ว
    (users.health_goal_locked_until ขยับไปเป็นของรอบใหม่ทันที)
    """
    __tablename__ = 'health_goal_cycles'

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True)
    # snapshot ของ users.health_goal/calories_goal ตอนรอบนี้จบ — เปลี่ยนระหว่าง
    # ทางไม่ได้อยู่แล้ว (ล็อกไว้ตลอด 7 วัน) จึงเป็นค่าเดียวกับตอนเริ่มรอบเสมอ
    health_goal = db.Column(db.String(20), nullable=False)
    calories_goal = db.Column(db.Integer, nullable=True)
    period_start = db.Column(db.DateTime, nullable=False)
    period_end = db.Column(db.DateTime, nullable=False)
    meals_logged = db.Column(db.Integer, nullable=False)
    meals_available = db.Column(db.Integer, nullable=False)
    # จำนวนมื้อในรอบนี้ที่กินเกินโควตาต่อมื้อ (calories_goal/3) — เดิม cap
    # นี้บล็อกการบันทึกจริง (409) ผู้ใช้ขอให้เอาออกแล้วเก็บไว้สรุปตอนจบรอบ
    # แทน (ดู api._finalize_expired_goal_cycle)
    meals_over_quota = db.Column(db.Integer, nullable=False, default=0)
    success_ratio = db.Column(db.Float, nullable=False)
    is_success = db.Column(db.Boolean, nullable=False)
    created_at = db.Column(db.DateTime, default=get_thailand_time)
    # ผู้ใช้เห็น dialog สรุปผลนี้แล้วหรือยัง (ดู api.get_dashboard_summary) —
    # null = ยังไม่เคยเห็น, dashboard จะโชว์ dialog ครั้งเดียวแล้วเซ็ตค่านี้
    # ผ่าน POST /api/user/health-goal-cycles/<id>/ack กันโผล่ซ้ำทุกครั้งที่
    # เปิดหน้าหลัก
    acknowledged_at = db.Column(db.DateTime, nullable=True)

    __table_args__ = (
        # กัน finalize ซ้ำสองแถวสำหรับรอบเดียวกัน (idempotent — เรียกจากหลาย
        # endpoint ได้โดยไม่ต้องเช็ค race condition เอง)
        UniqueConstraint('user_id', 'period_end', name='uq_goal_cycle_user_period'),
    )


# =========================
# WEIGHT TRACKING
# =========================

class WeightLog(db.Model):
    __tablename__ = 'weight_logs'

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True)
    weight = db.Column(db.Float, nullable=False)
    logged_at = db.Column(db.Date, nullable=False)
    created_at = db.Column(db.DateTime, default=get_thailand_time)

    __table_args__ = (
        UniqueConstraint('user_id', 'logged_at', name='uq_weight_user_date'),
    )


# =========================
# REPORTS (ticket system)
# =========================

class Report(db.Model):
    __tablename__ = 'reports'

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True)

    title = db.Column(db.String(255), nullable=False)
    # ข้อความแรกตอนสร้าง ticket — ยังเก็บไว้เพื่อ backward-compat (ของเดิม
    # อ่านฟิลด์นี้ตรงๆ) แต่บทสนทนาจริงทั้งหมดอยู่ใน ReportMessage แล้ว
    message = db.Column(db.Text, nullable=False)
    # ENUM('pending','replied','closed') — pending=รอแอดมินตอบ,
    # replied=แอดมินตอบแล้วรอผู้ใช้/ปิดเรื่อง, closed=จบเรื่องแล้ว (chat
    # กลายเป็น read-only ทั้งสองฝั่ง)
    status = db.Column(db.String(20), nullable=False, default='pending')
    admin_reply = db.Column(db.Text, nullable=True)
    replied_at = db.Column(db.DateTime, nullable=True)
    # id ของ ReportMessage (sender_type='admin') ล่าสุดที่ผู้ใช้อ่านแล้ว —
    # NULL แปลว่ายังไม่เคยอ่านข้อความจากแอดมินเลยสักข้อความ
    user_last_read_message_id = db.Column(db.Integer, nullable=True)

    created_at = db.Column(db.DateTime, default=get_thailand_time, index=True)

    messages = db.relationship(
        'ReportMessage', backref='report', cascade="all, delete-orphan",
        order_by='ReportMessage.created_at',
    )


class ReportMessage(db.Model):
    """ข้อความ 1 รายการใน thread แชทของ ticket — แทนที่รูปแบบเดิมที่มีแค่
    message (จากผู้ใช้) + admin_reply (จากแอดมิน) อย่างละ 1 ข้อความ ให้เป็น
    บทสนทนาไปมาได้หลายรอบจนกว่าแอดมินจะปิดเรื่อง"""
    __tablename__ = 'report_messages'

    id = db.Column(db.Integer, primary_key=True)
    report_id = db.Column(db.Integer, db.ForeignKey('reports.id', ondelete='CASCADE'), nullable=False, index=True)
    # ENUM('user','admin')
    sender_type = db.Column(db.String(10), nullable=False)
    message = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime, default=get_thailand_time, index=True)


# =========================
# SUBMISSIONS
# =========================

class Submission(db.Model):
    __tablename__ = 'submissions'

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=True, index=True)
    anon_id = db.Column(db.String(128), unique=True, nullable=True)

    name_th = db.Column(db.String(255), nullable=True)
    name_en = db.Column(db.String(255), nullable=True)
    # ENUM('food','drink','dessert')
    item_type = db.Column(db.String(10), default='food')
    detail = db.Column(db.Text, nullable=True)
    # ENUM('pending','approved','rejected')
    status = db.Column(db.String(20), default='pending')

    # ใครตรวจ/เมื่อไหร่/เหตุผล (เฉพาะ reject ต้องมี review_note — approve
    # ไม่บังคับ) reviewed_by เป็น NULL ได้ถ้าแอดมิน auth ผ่าน shared secret
    # ล้วนๆ ไม่ได้ login แบบผูกกับ user คนไหนเจาะจง
    reviewed_by = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=True)
    review_note = db.Column(db.Text, nullable=True)
    reviewed_at = db.Column(db.DateTime, nullable=True)

    created_at = db.Column(db.DateTime, default=get_thailand_time, index=True)


# =========================
# PROFILE AUDIT LOG (read-only history for admin)
# =========================

class ProfileAuditLog(db.Model):
    """One row per changed personal-info field, written whenever a user
    edits their own profile via POST /user/<id>. Admin-facing history is
    read-only and derived entirely from this table.
    """
    __tablename__ = 'profile_audit_log'

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False, index=True)
    field_name = db.Column(db.String(50), nullable=False)
    old_value = db.Column(db.Text, nullable=True)
    new_value = db.Column(db.Text, nullable=True)
    changed_at = db.Column(db.DateTime, default=get_thailand_time, index=True)

    user = db.relationship('User')


# =========================
# PDPA CONSENT
# =========================

class UserConsent(db.Model):
    """1 แถวต่อ 1 ครั้งที่ผู้ใช้กดยินยอม — append-only (ไม่ update ทับของเดิม)
    เพราะต้องเป็นหลักฐานย้อนหลังได้ว่ายินยอมเวอร์ชันไหนตอนไหนจริง ไม่ใช่แค่
    เก็บสถานะล่าสุด"""
    __tablename__ = 'user_consents'

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True)
    consent_type = db.Column(db.String(50), nullable=False, default='health_data_pdpa')
    policy_version = db.Column(db.String(20), nullable=False)
    consented_at = db.Column(db.DateTime, default=get_thailand_time)


# =========================
# ADMIN ACTION LOG
# =========================

class AdminActionLog(db.Model):
    """1 แถวต่อ 1 ครั้งที่แอดมินแก้ข้อมูลสำคัญสำเร็จ — ความรับผิดชอบเมื่อมี
    หลายแอดมิน (ใครแก้อะไรเมื่อไหร่) เขียนเฉพาะ action ที่เปลี่ยนข้อมูลจริง
    ไม่ hook endpoint ที่แค่อ่านอย่างเดียว"""
    __tablename__ = 'admin_action_log'

    id = db.Column(db.Integer, primary_key=True)
    admin_user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    action = db.Column(db.String(50), nullable=False)
    entity_type = db.Column(db.String(50), nullable=False)
    entity_id = db.Column(db.Integer, nullable=True)
    detail = db.Column(db.Text, nullable=True)
    created_at = db.Column(db.DateTime, default=get_thailand_time)

    admin_user = db.relationship('User', foreign_keys=[admin_user_id])


if __name__ == "__main__":
    print("models.py loaded successfully")
