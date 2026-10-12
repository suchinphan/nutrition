import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/widgets.dart';
import '../models/report.dart';
import '../models/weight_log.dart';
import '../services/app_config.dart';
import '../services/auth_service.dart';
import '../services/export_service.dart';
import '../services/report_service.dart';
import '../services/weight_log_service.dart';
import '../utils/bmi_calculator.dart' as bmi_calc;
import 'avatar_crop_page.dart';
import 'change_password_page.dart';
import 'login_page.dart';
import 'meal_log_flow.dart';
import 'ticket_chat_page.dart';
import 'ticket_history_page.dart';

const _activityOptions = [
  'ไม่ออกกำลังกายหรือออกกำลังกายน้อยมาก',
  'ออกกำลังกาย/เล่นกีฬา 1-3 วัน/สัปดาห์',
  'ออกกำลังกายปานกลาง/เล่นกีฬา 3-5 วัน/สัปดาห์',
  'ออกกำลังกายหนัก/เล่นกีฬา 6-7 วัน/สัปดาห์',
  'ออกกำลังกายหนักมากเป็นนักกีฬา',
];
const _genderOptions = ['ชาย', 'หญิง'];
const _goalOptions = ['ลดน้ำหนัก', 'รักษาน้ำหนัก', 'เพิ่มน้ำหนัก'];

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

int? _ageFromDob(DateTime? dob) {
  if (dob == null) return null;
  final now = DateTime.now();
  var age = now.year - dob.year;
  if (now.month < dob.month || (now.month == dob.month && now.day < dob.day))
    age -= 1;
  return age < 0 ? 0 : age;
}

Color _bmiColor(double? bmi) {
  if (bmi == null) return AppColors.gray400;
  if (bmi < 18.5) return AppColors.blue600;
  if (bmi < 25) return AppColors.teal500;
  if (bmi < 30) return AppColors.amber500;
  return AppColors.coral600;
}

/// สีของตัวเลข delta น้ำหนัก — ความหมาย "ดี/ไม่ดี" กลับทิศกันได้ตาม
/// health_goal ของ user เอง (ลดน้ำหนักสำเร็จ = เขียว, แต่ถ้าเป้าหมายคือ
/// เพิ่มน้ำหนัก น้ำหนักขึ้นต่างหากที่ควรเป็นเขียว) — ไม่ใช่ "ลดเสมอ=เขียว"
/// ตายตัวแบบไม่สนบริบท
Color _weightDeltaColor(double delta, String? healthGoal) {
  const epsilon = 0.3; // kg — เปลี่ยนน้อยกว่านี้ถือว่าคงที่ ไม่ตัดสินทิศทาง
  if (delta.abs() < epsilon) return AppColors.gray600;
  final isLoss = delta < 0;
  final isGain = delta > 0;
  switch (healthGoal) {
    case 'ลดน้ำหนัก':
      return isLoss ? AppColors.teal700 : AppColors.coral600;
    case 'เพิ่มน้ำหนัก':
      return isGain ? AppColors.teal700 : AppColors.coral600;
    default:
      // รักษาน้ำหนัก (หรือยังไม่ตั้งเป้าหมาย) — ยิ่งใกล้ 0 ยิ่งดี ไม่ใช่ยิ่ง
      // เพิ่ม/ลดยิ่งดี
      return delta.abs() < 1.0 ? AppColors.teal700 : AppColors.amber500;
  }
}

class ProfilePage extends StatefulWidget {
  // ตอนมาจาก dialog "ข้อมูลยังไม่ครบ" (ดู meal_log_flow.dart) ผู้ใช้กด
  // "ไปกรอกข้อมูล" แล้วเจอแค่หน้าโปรไฟล์เฉยๆ ต้องกด "แก้ไข" เองอีกที (บั๊กที่
  // ผู้ใช้รายงานจริง) — เปิดฟอร์มแก้ไข + เลื่อนไปให้เห็นเลยตั้งแต่หน้าเปิดมา
  final bool startInEditMode;

  const ProfilePage({super.key, this.startInEditMode = false});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ReportService _reportService = createReportService();
  final WeightLogService _weightLogService = createWeightLogService();
  final ExportService _exportService = createExportService();
  final _editFormKey = GlobalKey();
  // ตัวจับเวลาเดียวใช้ร่วมกันทุกปุ่ม spin (น้ำหนัก/ส่วนสูง) — เก็บเป็น field
  // ของ State แทนตัวแปร local ในโคลสเจอร์ เพราะทุกครั้งที่ bump() ยิง
  // setState() หน้าทั้งฟอร์มจะ rebuild ใหม่ ถ้า timer เป็นตัวแปร local
  // ในฟังก์ชันที่ถูกสร้างใหม่ทุก build ปุ่มปล่อยนิ้ว (stop) จะไปอ้างตัวแปร
  // timer ตัวใหม่ที่ยังไม่ถูกสั่ง ปล่อยตัวเก่าที่ยังรันค้างอยู่ไม่มีวันหยุด
  // (ค่าจะเพิ่ม/ลดไม่หยุดแม้ปล่อยนิ้วแล้ว)
  Timer? _spinnerTimer;

  bool _loading = true;
  late bool _editing = widget.startInEditMode;
  bool _savingProfile = false;
  bool _savingGoal = false;
  bool _uploadingAvatar = false;

  final _nameCtrl = TextEditingController();
  final _surnameCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  String? _gender;
  DateTime? _dob;
  String? _activity;
  List<String> _diseases = [];
  List<String> _allergies = [];
  List<String> _canonicalDiseases = [];
  List<String> _canonicalAllergies = [];

  String? _pendingGoal;
  // ไม่โชว์ BMR/TDEE ทันทีที่กรอกข้อมูลส่วนตัวครบ (อ้างอิงตามเครื่องคำนวณ
  // BMR ของ hpc5.go.th ที่ต้องกด "คำนวณ" เอง) ต้องกด "คำนวณ" ในกล่อง BMR
  // ก่อนถึงจะเห็นตัวเลข — คำนวณสดจากค่าที่พิมพ์อยู่ในฟอร์มตอนนั้นเลย (ไม่รอ
  // "บันทึก" อีกต่อไป — ผู้ใช้รายงานจริง: ต้องกด 2 ขั้นตอนกว่าจะเห็นตัวเลข
  // ทั้งที่กดคำนวณแล้ว) ปลอดภัยเพราะเลขที่โชว์คำนวณจาก _weightCtrl/_heightCtrl/
  // _gender/_dob/_activity ปัจจุบันตรงๆ ไม่ใช่ข้อมูลเก่าที่เคยบันทึกไว้
  // — รีเซ็ตกลับทุกครั้งที่ค่าที่ใช้คำนวณเปลี่ยนเพราะตัวเลขเก่าไม่ตรงกับที่พิมพ์แล้ว
  bool _bmrCalculated = false;

  // กล่องคำนวณ BMI (อ้างอิง hpc5.go.th/diet/?module=bmi) แยกกล่อง+ปุ่ม
  // คำนวณเป็นของตัวเอง แต่ใช้ _weightCtrl/_heightCtrl ตัวเดียวกับกล่อง BMR
  // (ข้อมูลเดียวกันจริง ไม่ให้มีน้ำหนัก/ส่วนสูง 2 ชุดที่อาจไม่ตรงกัน)
  bool _bmiCalculated = false;

  // กล่องวางแผนพลังงานใต้การ์ดเป้าหมาย (อ้างอิง Diet Planning step ของ
  // lovefitt) — กรอกน้ำหนักเป้าหมาย+จำนวนวัน กดคำนวณถึงเห็นผล เหมือน
  // BMR/TDEE ด้านบนที่ต้องกดคำนวณก่อนเช่นกัน แยก controller/สถานะคำนวณ
  // เป็นชุดต่อเป้าหมาย (ลด/รักษา/เพิ่มน้ำหนัก) ไม่ใช้ตัวแปรร่วมตัวเดียว —
  // ผู้ใช้รายงานจริง: สลับดูเป้าหมายอื่นแล้วเลขที่กรอก/ผลคำนวณของอันเดิมหาย/
  // ถูกทับ ทั้งที่ควรเป็นคนละชุดข้อมูลแยกกัน
  final _targetWeightCtrls = {
    for (final g in _goalOptions) g: TextEditingController(),
  };
  final _dietDaysCtrls = {
    for (final g in _goalOptions) g: TextEditingController(),
  };
  final _dietCalculated = {for (final g in _goalOptions) g: false};
  final Map<String, int?> _dietCalorieAdjustments = {
    'ลดน้ำหนัก': null,
    'เพิ่มน้ำหนัก': null,
  };
  // การ์ดเป้าหมาย (ลด/รักษา/เพิ่มน้ำหนัก) ไม่โชว์ kcal ทันทีที่กดคำนวณ
  // BMR/TDEE อีกต่อไป — ต้องกรอกเป้าหมายน้ำหนัก+จำนวนวันแล้วกด "คำนวณ" ใน
  // กล่องวางแผนพลังงานของการ์ดนั้นก่อนถึงจะเห็นตัวเลข (ผู้ใช้ยืนยันชัดเจน:
  // แค่กด "คำนวณ" ก็โชว์บนการ์ดได้เลย ไม่ต้องรอกด "บันทึกเป้าหมาย" ด้วย —
  // เพราะ "บันทึกเป้าหมาย" ล็อกได้แค่ 1 เป้าหมายที่ใช้งานจริงในแต่ละครั้ง
  // ทำให้ 3 การ์ดโชว์พร้อมกันไม่ได้เลยถ้าบังคับต้องบันทึกก่อน)

  bool _loadingReports = true;
  List<Report> _reports = [];
  String? _reportsError;

  bool _loadingWeightLogs = true;
  List<WeightLogEntry> _weightLogs = [];
  String? _weightLogsError;

  late AuthService _auth;
  // null = ยังไม่มี user ที่โหลดฟอร์มแล้ว (logged out/guest) — เทียบด้วย user
  // id จริงแทนการจำแค่ "เคยเห็นเป็น logged-out" (ดู _onAuthChanged) เพราะ
  // เดิมสลับ user คนละคนในเซสชันเดียว (logout แล้ว login คนอื่นต่อ โดยไม่
  // ผ่านสถานะ logged-out ที่หน้านี้ทัน) จะไม่ trigger การโหลดฟอร์มใหม่เลย —
  // สถิติด้านบน (_buildStatsRow) อ่านจาก auth.user สดทุกครั้งจึงเปลี่ยนตาม
  // user ใหม่ถูกต้อง แต่ฟอร์มแก้ไข (_nameCtrl/_weightCtrl/_dob/_diseases/...)
  // เป็น state ที่ตั้งครั้งเดียวผ่าน _loadFormFromUser() เลยค้างเป็นของ user
  // เก่า ทำให้เห็นข้อมูลสองชุดปนกันในหน้าเดียว (บั๊กที่ผู้ใช้รายงานจริง)
  String? _lastAuthUserId;
  // _init() เรียกซ้อนกันได้จริง — notifyListeners() ของ AuthService ยิงถี่
  // ตอนกด "บันทึก" หลายกล่องติดกัน (BMI/BMR/เป้าหมาย) โดยเฉพาะรอบแรกสุดหลัง
  // สมัครบัญชีใหม่ ที่ initState()'s Future.microtask(_init) ยังไม่ทันเซ็ต
  // _lastAuthUserId (ยังเป็น null) แล้วผู้ใช้กดบันทึกไปก่อน — _onAuthChanged
  // เห็น uid ไม่ตรงกับ _lastAuthUserId (ที่ยังเป็น null) เลยยิง _init() ซ้อน
  // เข้ามาอีกรอบ กลายเป็น _init() 2 ชุดวิ่งพร้อมกัน แต่ละชุดเรียก
  // auth.refreshProfile() (GET /user/<id>) เอง — ผู้ใช้รายงานจริง: ผ่าน
  // Flask dev server (single-threaded, ดูคอมเมนต์ที่ MealLogEvents batching)
  // คำขอที่ยิงก่อนตอบกลับช้ากว่าคำขอที่ยิงทีหลังได้ ถ้าปล่อยให้ผลลัพธ์ที่
  // "ตอบกลับมาถึงทีหลัง" ชนะเสมอ คำขอเก่าที่ยิงตั้งแต่ก่อนผู้ใช้กรอก/บันทึก
  // อะไรเลย (เห็นแค่โปรไฟล์ว่างๆ) จะมาเขียนทับฟอร์มที่เพิ่งโหลดข้อมูลถูกต้อง
  // ไปแล้วด้วยค่าว่าง/null ทั้งหมด (ผู้ใช้รายงานจริง: กรอกครบ+บันทึกทุกอย่าง
  // แล้ว สลับไปหน้าหลักแล้วกลับมา ข้อมูลส่วนตัว/BMI/BMR/TDEE/เป้าหมายหายเป็น
  // null หมด) — ใช้ generation counter แบบเดียวกับ _loadGeneration ใน
  // food_browser_page.dart กัน _init() รอบเก่าที่ตอบกลับมาทีหลังเขียนทับ
  // ผลของรอบล่าสุดที่ถูกต้องกว่า
  int _initGeneration = 0;
  // reentrancy guard — ดูคอมเมนต์เต็มที่ _onAuthChanged: saveUser() ยิง
  // notifyListeners() เสมอไม่ว่า syncToServer จะเป็นเท็จหรือไม่ และ _init()
  // เองก็เรียก auth.refreshProfile() ซึ่งเรียก saveUser() ข้างในอีกที ทำให้
  // เกิด feedback loop ที่ _onAuthChanged() เรียก _init() ใหม่ซ้อนเข้ามาได้
  // เรื่อยๆ ก่อน _lastAuthUserId จะทันถูกเซ็ต (ผู้ใช้รายงานจริง: เห็น
  // GET /user/<id> ยิงรัวๆ นับสิบครั้งใน log จนชน rate limit 429) —
  // _initGeneration ด้านบนกันแค่ "ผลลัพธ์เก่าเขียนทับผลลัพธ์ใหม่" แต่ไม่ได้
  // กัน "ยิง request ซ้อนกันโดยไม่จำเป็น" ต้องมีตัวนี้แยกกันคนละหน้าที่
  bool _initInFlight = false;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthService>();
    // Profile เป็นแท็บใน IndexedStack เหมือน HistoryPage เลย ไม่เคยได้
    // initState ใหม่ตอนสลับ user (logout แล้ว login คนอื่นต่อในเซสชันเดียว)
    // ถ้าไม่ฟัง auth เปลี่ยน _reports/_weightLogs ของคนเก่าจะค้างอยู่จนกว่า
    // จะ pull-to-refresh เอง (บั๊กเดียวกับที่ history_page.dart แก้ไปแล้ว)
    _auth.addListener(_onAuthChanged);
    Future.microtask(_init);
  }

  @override
  void dispose() {
    _spinnerTimer?.cancel();
    _auth.removeListener(_onAuthChanged);
    _nameCtrl.dispose();
    _surnameCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    for (final c in _targetWeightCtrls.values) {
      c.dispose();
    }
    for (final c in _dietDaysCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final loggedIn = _auth.isLoggedIn && !_auth.isGuest;
    String? uid;
    if (loggedIn) uid = _auth.user?['id']?.toString();
    if (uid == _lastAuthUserId) return;
    if (loggedIn) {
      // _init() ตัวหนึ่งกำลังวิ่งอยู่แล้ว — ห้ามซ้อนตัวใหม่เข้ามาอีก (ดู
      // คอมเมนต์เต็มที่ _initInFlight) ตัวที่วิ่งอยู่จะอ่าน auth.user สดๆ
      // ตอนจบเองอยู่แล้ว ไม่มีทางพลาดข้อมูลล่าสุดไป
      if (_initInFlight) return;
      setState(() => _loading = true);
      _init();
    } else {
      _lastAuthUserId = null;
      setState(() {});
    }
  }

  Future<void> _init() async {
    if (_initInFlight) return;
    _initInFlight = true;
    try {
      // ต้องจับ generation ตั้งแต่ต้นฟังก์ชัน (ก่อน await ตัวแรก) — ดูคอมเมนต์
      // เต็มที่ _initGeneration ด้านบน: กัน _init() รอบเก่าที่
      // auth.refreshProfile() ตอบกลับมาช้ากว่ารอบใหม่ (Flask dev server
      // single-threaded) เขียนทับฟอร์มด้วยข้อมูลเก่า/ว่างเปล่า
      final myGeneration = ++_initGeneration;
      final auth = context.read<AuthService>();
      await auth.loadToken();
      if (!auth.isLoggedIn || auth.isGuest) {
        if (!mounted || myGeneration != _initGeneration) return;
        _lastAuthUserId = null;
        setState(() => _loading = false);
        return;
      }
      try {
        await auth.refreshProfile();
      } catch (_) {}
      if (!mounted || myGeneration != _initGeneration) return;
      _lastAuthUserId = auth.user?['id']?.toString();
      _loadFormFromUser();
      setState(() => _loading = false);
      if (widget.startInEditMode) {
        // ต้องรอเฟรมที่วาดฟอร์มแก้ไขจริงๆ ก่อน (setState ด้านบนเพิ่งสั่ง
        // rebuild) ไม่งั้น _editFormKey.currentContext ยังเป็น null อยู่
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _editFormKey.currentContext;
          if (ctx != null)
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 300),
            );
        });
      }
      // เดิมยิง 3 คำขอพร้อมกันตอนเปิดหน้า (medical-lists/reports/weight-logs)
      // — โปรเจกต์นี้เคยเจอปัญหาจริงมาแล้วว่า Flask dev server (single-
      // threaded) รับคำขอพร้อมกันหลายตัวไม่ไหว ทำให้บาง request ค้าง/หลุด
      // connection (ดู MealLogEvents batching ที่แก้ปัญหาเดียวกันมาก่อน) —
      // ผู้ใช้รายงานว่า "น้ำหนักย้อนหลัง" กับ "รายงานปัญหา" (2 ใน 3 คำขอนี้)
      // โหลดไม่ขึ้นเป็นบางครั้ง เรียงให้ทำทีละอย่างแทนลดโอกาสชนกัน
      await _fetchMedicalLists();
      if (!mounted || myGeneration != _initGeneration) return;
      await _loadReports();
      if (!mounted || myGeneration != _initGeneration) return;
      await _loadWeightLogs();
    } finally {
      _initInFlight = false;
    }
  }

  void _loadFormFromUser() {
    final u = context.read<AuthService>().user ?? {};
    _nameCtrl.text = u['name']?.toString() ?? '';
    _surnameCtrl.text = u['surname']?.toString() ?? '';
    _gender = _genderOptions.contains(u['gender']?.toString())
        ? u['gender'].toString()
        : null;
    final dobStr = u['date_of_birth']?.toString();
    _dob = (dobStr != null && dobStr.isNotEmpty)
        ? DateTime.tryParse(dobStr)
        : null;
    _weightCtrl.text = u['weight']?.toString() ?? '';
    _heightCtrl.text = u['height']?.toString() ?? '';
    _activity = _activityOptions.contains(u['activity_level']?.toString())
        ? u['activity_level'].toString()
        : null;
    _diseases = _asStringList(u['chronic_diseases']);
    _allergies = _asStringList(u['food_allergies']);
    _pendingGoal = _goalOptions.contains(u['health_goal']?.toString())
        ? u['health_goal'].toString()
        : null;
    // ผู้ใช้รายงานจริง: กรอกเป้าหมายน้ำหนัก+จำนวนวัน กดคำนวณ+บันทึกเป้าหมาย
    // ไปแล้ว แต่รีเฟรช/เปิดแอปใหม่ ช่องในกล่อง "วางแผนพลังงาน" กลับว่างเปล่า
    // เพราะ _targetWeightCtrls/_dietDaysCtrls เป็นแค่ text field ในหน่วยความจำ
    // ไม่เคยถูกบันทึกไว้ที่ไหนเลย — ตอนนี้ backend เก็บ
    // health_goal_target_weight/_target_days คู่กับ calories_goal แล้ว โหลด
    // กลับมาเติมช่องของเป้าหมายที่บันทึกไว้ล่าสุดให้ (เป้าหมายอื่นที่ไม่ได้
    // บันทึกไว้ยังว่างเหมือนเดิม เพราะไม่มีข้อมูลให้เติม)
    //
    // ต้องล้างค่าเดิมของทั้ง 3 เป้าหมายก่อนเสมอ — ProfilePage เป็นแท็บใน
    // IndexedStack ไม่เคยถูก dispose ตอนสลับบัญชี (logout แล้ว login คนใหม่
    // ต่อในเซสชันเดียว) เดิมโค้ดนี้เติมค่าแบบมีเงื่อนไข (แค่ตอนบัญชีใหม่มี
    // ข้อมูลบันทึกไว้) แต่ไม่เคยล้างของเก่าออกก่อนเลย ทำให้เป้าหมายน้ำหนัก/
    // จำนวนวัน/สถานะคำนวณที่ค้างจากบัญชีก่อนหน้ายังโผล่ในฟอร์มของบัญชีใหม่
    // (ผู้ใช้รายงานจริง: "เป้าหมายสุขภาพมันแชร์ร่วมกับบัญชีผู้ใช้อื่น")
    for (final g in _goalOptions) {
      _targetWeightCtrls[g]!.clear();
      _dietDaysCtrls[g]!.clear();
      _dietCalculated[g] = false;
    }
    _dietCalorieAdjustments.updateAll((_, __) => null);
    if (_pendingGoal != null) {
      final savedAdjustment = int.tryParse(
        u['health_goal_calorie_adjustment']?.toString() ?? '',
      );
      if ((_pendingGoal == 'ลดน้ำหนัก' || _pendingGoal == 'เพิ่มน้ำหนัก') &&
          (savedAdjustment == 500 || savedAdjustment == 1000)) {
        _dietCalorieAdjustments[_pendingGoal!] = savedAdjustment;
      }
      final savedTargetWeight = u['health_goal_target_weight'];
      final savedTargetDays = u['health_goal_target_days'];
      if (savedTargetWeight != null && savedTargetDays != null) {
        _targetWeightCtrls[_pendingGoal]!.text = savedTargetWeight.toString();
        _dietDaysCtrls[_pendingGoal]!.text = savedTargetDays.toString();
        _dietCalculated[_pendingGoal!] = true;
      }
    }
    if (_pendingGoal == 'รักษาน้ำหนัก') {
      final targetCtrl = _targetWeightCtrls[_pendingGoal]!;
      final daysCtrl = _dietDaysCtrls[_pendingGoal]!;
      final currentWeight = double.tryParse(_weightCtrl.text.trim());
      if (targetCtrl.text.trim().isEmpty && currentWeight != null) {
        targetCtrl.text = currentWeight.toStringAsFixed(1);
      }
      if (daysCtrl.text.trim().isEmpty) {
        daysCtrl.text = '30';
      }
    }
    // ผู้ใช้รายงานจริง: ปิดแอปแล้วเปิดใหม่ผลลัพธ์หายไป เพราะ _bmrCalculated
    // เป็นแค่ state ชั่วคราวในหน่วยความจำ ไม่เคยคงอยู่ข้ามเซสชัน — ข้อมูลที่ใช้
    // คำนวณ (เพศ/วันเกิด/น้ำหนัก/ส่วนสูง/กิจกรรม) ถ้าครบทุกช่องก็คำนวณโชว์ได้
    // เลยไม่ต้องกดซ้ำทุกครั้งที่เปิดแอป
    final hasFullBmrData =
        _gender != null &&
        _dob != null &&
        _weightCtrl.text.isNotEmpty &&
        _heightCtrl.text.isNotEmpty &&
        _activity != null;
    _bmrCalculated = hasFullBmrData;
    final hasBmiData =
        _weightCtrl.text.isNotEmpty && _heightCtrl.text.isNotEmpty;
    _bmiCalculated = hasBmiData;
  }

  List<String> _asStringList(dynamic v) {
    if (v is List)
      return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    if (v is String && v.trim().isNotEmpty && v.trim() != 'ไม่มี') {
      return v
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  }

  Future<void> _fetchMedicalLists() async {
    try {
      final resp = await http
          .get(Uri.parse('${getApiBase()}/api/medical-lists'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200 && mounted) {
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _canonicalDiseases = ((j['diseases'] as List?) ?? [])
              .map((e) => e.toString())
              .toList();
          _canonicalAllergies = ((j['allergies'] as List?) ?? [])
              .map((e) => e.toString())
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadReports() async {
    setState(() {
      _loadingReports = true;
      _reportsError = null;
    });
    // scope: open — หน้าโปรไฟล์โชว์แค่ ticket ที่กำลังดำเนินการ ที่ปิดแล้วให้
    // ไปดูที่หน้าประวัติแยกต่างหาก (ดู TicketHistoryPage) กันรายการสะสมยาว
    final result = await _reportService.fetchMyReports(scope: 'open');
    if (!mounted) return;
    result.when(
      ok: (reports) => setState(() {
        _reports = reports;
        _loadingReports = false;
      }),
      err: (error) => setState(() {
        _loadingReports = false;
        _reportsError = error.toUserMessage();
      }),
    );
  }

  Future<void> _loadWeightLogs() async {
    setState(() {
      _loadingWeightLogs = true;
      _weightLogsError = null;
    });
    final result = await _weightLogService.fetchWeightLogs(days: 30);
    if (!mounted) return;
    result.when(
      ok: (logs) => setState(() {
        // เรียงตามวันที่ให้ชัวร์ (backend ก็เรียงมาให้แล้ว แต่กันไว้เผื่อ)
        logs.sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
        _weightLogs = logs;
        _loadingWeightLogs = false;
      }),
      err: (error) => setState(() {
        _loadingWeightLogs = false;
        _weightLogsError = error.toUserMessage();
      }),
    );
  }

  Future<void> _openLogWeightSheet() async {
    // ผู้ใช้รายงานจริง: บันทึกน้ำหนักที่ไม่เกี่ยวข้องกับเป้าหมายที่ตั้งไว้เลยได้
    // (เช่นเป้าหมายลดน้ำหนัก 55->52 แต่กรอก 65 ก็ผ่าน) ต้องกรอกโปรไฟล์+เลือก
    // เป้าหมายสุขภาพ+วางแผนพลังงานให้ครบก่อนถึงจะรู้ได้ว่าน้ำหนักที่กรอกควรอยู่
    // ช่วงไหน — ใช้ guard เดียวกับตอนบันทึกมื้ออาหาร (hasCompleteProfileAndGoal)
    if (!hasCompleteProfileAndGoal()) {
      await showIncompleteProfileDialog(context);
      return;
    }

    final user = AuthService().user;
    final currentWeight = double.tryParse(user?['weight']?.toString() ?? '');
    final targetWeight = double.tryParse(
      user?['health_goal_target_weight']?.toString() ?? '',
    );
    // ช่วงน้ำหนักที่ "ใกล้เคียง" เป้าหมาย — ครอบทั้งน้ำหนักปัจจุบันกับน้ำหนัก
    // เป้าหมาย บวกเผื่อความผันผวนรายวันปกติ ±5 กก. ไม่ใช้เกณฑ์ต่างกันตาม
    // ประเภทเป้าหมาย (ลด/รักษา/เพิ่ม) เพราะ min/max ของ 2 ค่านี้ครอบคลุมทั้ง
    // 3 แบบอยู่แล้วในสูตรเดียว (ผู้ใช้รายงานจริง)
    const tolerance = 5.0;
    final lowerBound = (currentWeight != null && targetWeight != null)
        ? (currentWeight < targetWeight ? currentWeight : targetWeight) -
              tolerance
        : null;
    final upperBound = (currentWeight != null && targetWeight != null)
        ? (currentWeight > targetWeight ? currentWeight : targetWeight) +
              tolerance
        : null;

    final ctrl = TextEditingController(
      text: _weightLogs.isEmpty
          ? ''
          : _weightLogs.last.weight.toStringAsFixed(1),
    );
    bool submitting = false;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'บันทึกน้ำหนักวันนี้',
                style: AppTextStyles.headingMedium.copyWith(
                  color: AppColors.gray900,
                ),
              ),
              const SizedBox(height: 16),
              if (error != null) ...[
                Text(
                  error!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.coral600,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _decoration('น้ำหนัก', suffixText: 'กก.'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final weight = double.tryParse(ctrl.text.trim());
                          if (weight == null || weight <= 0 || weight > 1000) {
                            setSheetState(
                              () => error =
                                  'กรุณากรอกน้ำหนักให้ถูกต้อง (0-1000 กก.)',
                            );
                            return;
                          }
                          if (lowerBound != null &&
                              upperBound != null &&
                              (weight < lowerBound || weight > upperBound)) {
                            setSheetState(
                              () => error =
                                  'น้ำหนักที่กรอกไม่ใกล้เคียงกับเป้าหมายที่ตั้งไว้ '
                                  '(ควรอยู่ระหว่าง ${lowerBound.toStringAsFixed(1)}-${upperBound.toStringAsFixed(1)} กก.)',
                            );
                            return;
                          }
                          setSheetState(() {
                            submitting = true;
                            error = null;
                          });
                          final result = await _weightLogService.logWeight(
                            weight: weight,
                          );
                          result.when(
                            ok: (_) {
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            },
                            err: (e) => setSheetState(() {
                              submitting = false;
                              error = e.toUserMessage();
                            }),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teal500,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'บันทึก',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    // รีเฟรชกราฟทันที + sync users.weight/BMI ที่ header/stats row (backend
    // อัปเดต users.weight ให้เองอยู่แล้วตอน POST สำเร็จ แค่ต้องดึงโปรไฟล์ใหม่
    // มาโชว์ฝั่งแอป) — เรียก AuthService() ตรงๆ (singleton) แทน context.read
    // กัน lint use_build_context_synchronously หลัง await
    await _loadWeightLogs();
    await AuthService().refreshProfile();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    // ต้องอายุ 13 ปีขึ้นไปถึงจะกรอกข้อมูลได้ — จำกัดที่ตัว date picker ตรงๆ
    // (lastDate) ให้เลือกวันเกิดที่ทำให้อายุ <13 ไม่ได้ตั้งแต่แรกเลย ไม่ต้อง
    // เขียน validation dialog แยกซ้ำ ฝั่ง backend ก็เช็คซ้ำอีกชั้นกันเลี่ยงผ่าน
    // API ตรงๆ (ดู POST /user/<id> ใน api.py)
    final maxDob = DateTime(now.year - 13, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: maxDob,
      helpText: 'วันเกิด (ต้องมีอายุ 13 ปีขึ้นไป)',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_uploadingAvatar) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null || !mounted) return;
    final originalBytes = await picked.readAsBytes();
    if (!mounted) return;
    final cropped = await Navigator.of(context, rootNavigator: true)
        .push<Uint8List>(
          MaterialPageRoute(
            builder: (_) => AvatarCropPage(imageBytes: originalBytes),
          ),
        );
    if (cropped == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    final error = await context.read<AuthService>().uploadAvatar(cropped);
    if (!mounted) return;
    setState(() => _uploadingAvatar = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('อัปเดตรูปโปรไฟล์แล้ว')));
    }
  }

  // คืน true เมื่อบันทึกจริงสำเร็จ — กล่อง BMR ใช้ค่านี้ตัดสินว่าจะเปิดเผย
  // ตัวเลข (ต้องกด "คำนวณ" + บันทึกสำเร็จ) โดยไม่ต้องมี logic ซ้ำซ้อนสองที่
  Future<bool> _saveProfile() async {
    // มนุษย์จริงไม่มีน้ำหนัก/ส่วนสูงเกินช่วงนี้ — เดิมไม่เช็คเลยกรอก 500 กก./
    // 18000 ซม. ผ่านได้ (บั๊กที่ผู้ใช้รายงานจริง ทำ BMI พัง) เช็คฝั่ง client
    // ก่อนส่งให้เห็น error ทันที ฝั่ง backend ก็เช็คซ้ำใน POST /user/<id>
    final weightVal = double.tryParse(_weightCtrl.text.trim());
    if (weightVal != null && (weightVal <= 0 || weightVal > 1000)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('น้ำหนักต้องอยู่ระหว่าง 1 ถึง 1000 กก.')),
      );
      return false;
    }
    final heightVal = double.tryParse(_heightCtrl.text.trim());
    if (heightVal != null && (heightVal <= 0 || heightVal > 300)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่วนสูงต้องอยู่ระหว่าง 1 ถึง 300 ซม.')),
      );
      return false;
    }
    setState(() => _savingProfile = true);
    final auth = context.read<AuthService>();
    final synced = await auth.saveUser({
      'name': _nameCtrl.text.trim(),
      'surname': _surnameCtrl.text.trim(),
      'gender': _gender,
      'date_of_birth': _dob == null
          ? null
          : '${_dob!.year.toString().padLeft(4, '0')}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
      'weight': _weightCtrl.text.trim(),
      'height': _heightCtrl.text.trim(),
      'activity_level': _activity,
      'chronic_diseases': _diseases,
      'food_allergies': _allergies,
    });
    if (!mounted) return false;
    setState(() => _savingProfile = false);
    // synced == false: server ไม่รับข้อมูล (timeout/error) — ห้ามบอกว่า
    // "บันทึกแล้ว" เพราะรีเฟรชครั้งต่อไปจะดึงค่าเก่าจาก server มาทับของที่
    // เพิ่งกรอก (ผู้ใช้รายงานจริง: โรคประจำตัว/แพ้อาหารหายหลังกลับมาหน้าเดิม)
    // — คงฟอร์มแก้ไขไว้ให้กดบันทึกซ้ำได้ทันที ไม่ใช่ปิดฟอร์มทิ้งข้อมูล
    if (!synced) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'บันทึกไม่สำเร็จ เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ กรุณาลองใหม่',
          ),
        ),
      );
      return false;
    }
    // เดิมล้าง _bmrCalculated/_bmrSaved/_bmiCalculated/_bmiSaved/_dietCalculated/
    // _goalSaved ทิ้งหมดทุกครั้งที่บันทึกสำเร็จ ไม่ว่าจะบันทึกจากกล่องไหนก็ตาม
    // — ผู้ใช้รายงานจริง: กด "บันทึก" ของกล่อง BMI แล้วผลของกล่อง BMR/TDEE
    // (ที่คำนวณ+บันทึกไปแล้วก่อนหน้า ไม่ได้แก้อะไรเลย) หายไปด้วย ต้องมานั่ง
    // กดคำนวณ+บันทึกซ้ำทั้งที่ไม่จำเป็น — ตอนนี้แต่ละช่องมี hook ล้างค่าเฉพาะ
    // จุดที่ข้อมูลจริงๆ เปลี่ยน (ดู _invalidateWeightHeight และ invalidate()
    // ในกล่อง BMR) แล้ว ไม่ต้องกวาดล้างรวมตรงนี้อีก
    setState(() {
      _editing = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('บันทึกข้อมูลแล้ว')));
    return true;
  }

  Future<void> _saveGoal(double? tdee) async {
    final goal = _pendingGoal;
    if (goal == null || tdee == null) return;
    // ต้องกด "คำนวณ" ในกล่องวางแผนพลังงานของเป้าหมายนี้ก่อนเสมอ ถึงจะบันทึก
    // ได้ (ปุ่ม "บันทึกเป้าหมาย" เองก็ถูก disable ไว้แล้วตามเงื่อนไขนี้ เช็ค
    // ซ้ำตรงนี้กันเรียกฟังก์ชันตรงๆ ผ่านทางอื่นข้ามเงื่อนไขไป) — เดิมเช็คแค่
    // _dietCalculated[goal] เฉยๆ ไม่เช็คว่าค่าที่กรอกจริงถูกต้องหรือไม่ (ปุ่ม
    // "คำนวณ" เดิมก็ตั้ง true ได้ทันทีไม่ว่าจะกรอกอะไรมา) เลยส่ง
    // days/target_weight ว่างๆ ไป backend ได้ ซึ่ง fallback เป็นล็อก 7 วัน
    // ตายตัว+สูตร TDEE±500 เดิมเงียบๆ (ผู้ใช้รายงานจริง) เช็คความถูกต้องซ้ำ
    // ด้วย _dietPlanValidationError() ตรงนี้ไปด้วยเลย
    final weightVal = double.tryParse(_weightCtrl.text.trim());
    final validationError = _dietCalculated[goal] == true && weightVal != null
        ? (_dietPlanValidationError(goal, weightVal) ??
              _dietSafetyError(goal, weightVal, tdee))
        : 'กรุณากรอกเป้าหมายน้ำหนัก/จำนวนวัน แล้วกด "คำนวณ" ก่อนบันทึกเป้าหมาย';
    if (validationError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }
    // จำนวนวันที่กรอกในกล่องวางแผนพลังงาน กำหนดว่าจะล็อกเป้าหมายนี้ไว้กี่วัน
    // (เดิม backend ล็อกตายตัว 7 วันเสมอ — ผู้ใช้รายงานจริง: อยากให้ระยะเวลา
    // ล็อกตรงกับแผนที่วางไว้จริง เช่น 30 วัน ก็ล็อก 30 วัน ไม่ใช่ 7 วันคงที่)
    // ส่ง target_weight ไปด้วย เพื่อให้ backend คำนวณ calories_goal ที่บันทึก
    // จริงด้วยสูตรเดียวกับพรีวิว _dietRecommendedFor() แทนสูตร TDEE±500 เดิม
    // (ผู้ใช้รายงานจริง: ตัวเลขที่พรีวิวไว้ในหน้าโปรไฟล์ไม่ตรงกับที่แดชบอร์ด
    // โชว์จริงเลย เพราะ backend ไม่เคยรู้จักน้ำหนักเป้าหมาย/จำนวนวันมาก่อน)
    final days = int.tryParse(_dietDaysCtrls[goal]?.text.trim() ?? '');
    final targetWeight = double.tryParse(
      _targetWeightCtrls[goal]?.text.trim() ?? '',
    );
    final auth = context.read<AuthService>();
    final token = auth.token;
    if (token == null) return;
    setState(() => _savingGoal = true);
    try {
      final resp = await http.post(
        Uri.parse('${getApiBase()}/api/user/health-goal'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'health_goal': goal,
          'days': days,
          'target_weight': targetWeight,
          'calorie_adjustment': _dietCalorieAdjustments[goal],
        }),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        // syncToServer: false — [j] คือผลลัพธ์ที่ /api/user/health-goal เพิ่ง
        // บันทึกไว้จริงแล้ว (ตอบกลับมาให้ตรงๆ) ไม่ต้อง POST ไปที่ /user/<id>
        // ซ้ำอีกรอบ (endpoint คนละตัวกัน ไม่ได้ใช้ sync เดียวกันด้วยซ้ำ) —
        // เหตุผลเดียวกับที่แก้ handleAuthSuccess()/refreshProfile() ใน
        // auth_service.dart: saveUser() ยิง notifyListeners() เสมอไม่ว่า
        // syncToServer จะเป็นเท็จหรือไม่ ยิ่งลด POST ที่ไม่จำเป็นได้ยิ่งลด
        // โอกาสชน rate limit ของ /user/<id> จากคำขออื่นที่ตามมา
        await auth.saveUser({
          'health_goal': j['health_goal'],
          'calories_goal': j['calories_goal'],
          'health_goal_start_weight': j['health_goal_start_weight'],
          'health_goal_locked_until': j['health_goal_locked_until'],
          'health_goal_target_weight': j['health_goal_target_weight'],
          'health_goal_target_days': j['health_goal_target_days'],
          'health_goal_calorie_adjustment':
              j['health_goal_calorie_adjustment'],
        }, syncToServer: false);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('บันทึกเป้าหมายสำเร็จ')));
      } else {
        String msg = 'บันทึกเป้าหมายไม่สำเร็จ';
        try {
          final j = jsonDecode(resp.body);
          if (j is Map && j['error'] != null) msg = j['error'].toString();
        } catch (_) {}
        if (!msg.contains('เปลี่ยนเป้าหมายได้อีกครั้งในวันที่')) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถติดต่อเซิร์ฟเวอร์ได้')),
      );
    } finally {
      if (mounted) setState(() => _savingGoal = false);
    }
  }

  Future<void> _openNewReportSheet() async {
    final titleCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    bool submitting = false;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'รายงานปัญหาใหม่',
                style: AppTextStyles.headingMedium.copyWith(
                  color: AppColors.gray900,
                ),
              ),
              const SizedBox(height: 16),
              if (error != null) ...[
                Text(
                  error!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.coral600,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'หัวข้อ'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageCtrl,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'รายละเอียด'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final title = titleCtrl.text.trim();
                          final message = messageCtrl.text.trim();
                          if (title.isEmpty || message.isEmpty) {
                            setSheetState(
                              () => error = 'กรุณากรอกหัวข้อและรายละเอียด',
                            );
                            return;
                          }
                          setSheetState(() {
                            submitting = true;
                            error = null;
                          });
                          final result = await _reportService
                              .submitReportProblem(
                                title: title,
                                message: message,
                              );
                          result.when(
                            ok: (_) {
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            },
                            err: (e) => setSheetState(() {
                              submitting = false;
                              error = e.toUserMessage();
                            }),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teal500,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'ส่งเรื่อง',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) _loadReports();
  }

  Future<void> _openTicketChat(Report report) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            TicketChatPage(report: report, reportService: _reportService),
      ),
    );
    if (mounted) _loadReports();
  }

  void _openTicketHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TicketHistoryPage(reportService: _reportService),
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยัน'),
        content: const Text('คุณต้องการออกจากระบบหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ไม่'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ใช่'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await context.read<AuthService>().clearToken();
    if (mounted) setState(() {});
  }

  void _openChangePassword(Map<String, dynamic> u) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => ChangePasswordPage(
          initialUsername: u['username']?.toString(),
          initialEmail: u['email']?.toString(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('โปรไฟล์')),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: AppSkeletonLoader(variant: AppSkeletonVariant.profileHeader),
        ),
      );
    }

    if (!auth.isLoggedIn || auth.isGuest) {
      return Scaffold(
        appBar: AppBar(title: const Text('โปรไฟล์')),
        body: AppEmptyState(
          icon: Icons.person_outline,
          title: 'เข้าสู่ระบบเพื่อดูโปรไฟล์ของคุณ',
          ctaLabel: 'เข้าสู่ระบบ',
          onCta: () => Navigator.of(
            context,
            rootNavigator: true,
          ).push(MaterialPageRoute(builder: (_) => const LoginPage())),
        ),
      );
    }

    final u = auth.user ?? {};
    final fullName = [
      u['name']?.toString() ?? '',
      u['surname']?.toString() ?? '',
    ].where((s) => s.trim().isNotEmpty).join(' ');
    final displayName = fullName.isEmpty
        ? (u['username']?.toString() ?? '-')
        : fullName;
    final email = u['email']?.toString() ?? '-';

    final weight = double.tryParse(u['weight']?.toString() ?? '');
    final height = double.tryParse(u['height']?.toString() ?? '');
    final dobStr = u['date_of_birth']?.toString();
    final dob = (dobStr != null && dobStr.isNotEmpty)
        ? DateTime.tryParse(dobStr)
        : null;
    final age = _ageFromDob(dob);
    final bmi = bmi_calc.calcBmi(weight, height);
    final bmiLabel = bmi_calc.bmiStatus(bmi);

    final gender = u['gender']?.toString();
    final bmr = bmi_calc.calcBmr(
      weight: weight,
      height: height,
      age: age,
      gender: gender,
    );
    final tdee = bmi_calc.calcTdee(
      weight: weight,
      height: height,
      age: age,
      gender: gender,
      activity: u['activity_level']?.toString(),
    );

    final lockedUntilStr = u['health_goal_locked_until']?.toString();
    final lockedUntilRaw = (lockedUntilStr != null && lockedUntilStr.isNotEmpty)
        ? DateTime.tryParse(lockedUntilStr)
        : null;
    final goalLockedUntil =
        (lockedUntilRaw != null && DateTime.now().isBefore(lockedUntilRaw))
        ? lockedUntilRaw
        : null;

    // ปรับ TDEE ตามโรคประจำตัวก่อนเอาไปคิดเป้าหมายสุขภาพ (การ์ดลด/รักษา/
    // เพิ่มน้ำหนัก + กล่องวางแผนพลังงาน) — ใช้เฉพาะตรงนี้ ไม่กระทบกล่อง BMR/
    // TDEE ด้านบนที่ต้องโชว์ค่าดิบให้ตรงกับ hpc5.go.th เป๊ะ (ผู้ใช้ขอให้ดึง
    // โรคประจำตัวมาคิดกับเป้าหมายสุขภาพด้วย — สูตร %ต่อโรคนี้มีอยู่แล้วใน
    // choose_a_health_goal.dart/show_bmi_and_suggested_calories.dart แค่ไม่
    // เคยเอามาใช้ตรงนี้) แพ้อาหารไม่มีสูตรปรับแคลอรี่ที่มีหลักฐานรองรับ (ทั้ง
    // 2 ไฟล์ที่มีอยู่ก็ไม่ได้เอาแพ้อาหารไปคิดตัวเลข แค่โชว์ไว้เฉยๆ) เลยไม่ใส่
    final diseaseAdjustment = bmi_calc.diseaseAdjustmentFactor(_diseases);
    final adjustedTdeeForGoals = tdee != null
        ? tdee * (1.0 + diseaseAdjustment)
        : null;
    final effectiveTdeeForGoals = adjustedTdeeForGoals ?? tdee;
    // ผู้ใช้รายงานจริง: ตัวเลข kcal ที่การ์ดเป้าหมาย/กล่องวางแผนพลังงานโชว์
    // ไม่ตรงกับที่แดชบอร์ดโชว์เลย ทั้งที่เป็นเป้าหมายเดียวกันที่ล็อกไว้อยู่
    // — เพราะสองจุดนี้ (goalCard/_buildDietPlanBox) คำนวณสดจาก tdee/weight
    // *ปัจจุบัน* ทุกครั้งที่ build ในขณะที่ user.calories_goal ที่แดชบอร์ดใช้
    // เป็นค่าที่คำนวณ+persist ไว้ ณ ตอนกด "บันทึกเป้าหมาย" ครั้งล่าสุด ถ้า
    // ผู้ใช้แก้น้ำหนัก/กิจกรรม/โรคประจำตัวในหน้าโปรไฟล์หลังล็อกเป้าหมายไปแล้ว
    // (แก้ได้ตลอด ไม่ผูกกับ isLocked) ตัวเลขสองจุดนี้จะเริ่มเพี้ยนจากที่บันทึก
    // จริงทันที — เป้าหมายที่ล็อกอยู่ต้องโชว์ค่าที่บันทึกจริง (u['calories_goal'])
    // ไม่ใช่คำนวณสดซ้ำ ถึงจะตรงกับแดชบอร์ดเสมอ
    final savedCaloriesGoal = double.tryParse(
      u['calories_goal']?.toString() ?? '',
    );

    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(title: const Text('โปรไฟล์')),
      body: RefreshIndicator(
        onRefresh: () async {
          await auth.refreshProfile();
          _loadFormFromUser();
          await _loadReports();
          await _loadWeightLogs();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeaderCard(displayName, email, u['avatar_url']?.toString()),
            const SizedBox(height: 12),
            _buildStatsRow(age, bmi, bmiLabel, weight, height),
            const SizedBox(height: 16),
            if (_editing) ...[
              KeyedSubtree(key: _editFormKey, child: _buildEditForm()),
              const SizedBox(height: 16),
            ],
            _buildBmiCalculatorBox(),
            _buildBmrCalculatorBox(),
            _buildGoalSection(
              bmr,
              effectiveTdeeForGoals,
              tdee,
              weight,
              goalLockedUntil,
              savedCaloriesGoal,
            ),
            const SizedBox(height: 16),
            _buildWeightHistorySection(u['health_goal']?.toString()),
            const SizedBox(height: 16),
            _buildReportsSection(),
            const SizedBox(height: 16),
            _buildExportSection(),
            const SizedBox(height: 24),
            Center(
              child: TextButton(
                onPressed: () => _openChangePassword(u),
                child: Text(
                  'เปลี่ยนรหัสผ่าน',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.gray600,
                  ),
                ),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: _logout,
                child: Text(
                  'ออกจากระบบ',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.coral600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    String displayName,
    String email,
    String? avatarPath,
  ) {
    final avatarUrl = (avatarPath != null && avatarPath.isNotEmpty)
        ? '${getApiBase()}$avatarPath'
        : null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _pickAndUploadAvatar,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: _uploadingAvatar ? 0.5 : 1.0,
                  child: AppAvatarInitials(
                    name: displayName,
                    size: 56,
                    imageUrl: avatarUrl,
                  ),
                ),
                if (_uploadingAvatar)
                  const Positioned.fill(
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.teal500,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: AppColors.teal500,
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(
                        BorderSide(color: Colors.white, width: 2),
                      ),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: AppTextStyles.headingMedium.copyWith(
                    color: AppColors.gray900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.gray600,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () {
              if (!_editing) _loadFormFromUser();
              setState(() => _editing = !_editing);
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.teal500),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              _editing ? 'ยกเลิก' : 'แก้ไข',
              style: const TextStyle(color: AppColors.teal500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(
    int? age,
    double? bmi,
    String? bmiLabel,
    double? weight,
    double? height,
  ) {
    Widget stat(String label, String value, {Color? valueColor}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: AppTextStyles.headingSmall.copyWith(
                color: valueColor ?? AppColors.gray900,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: AppTextStyles.caption),
          ],
        ),
      ),
    );

    // ช่อง BMI แยกออกมาต่างหาก — สถานะ (เช่น "ท้วม/น้ำหนักเกิน") ยาวกว่า
    // ตัวเลข/หน่วยของอีก 3 ช่องมาก เดิมต่อ '\n' รวมเป็น Text เดียวกับตัวเลข
    // ทำให้เรนเดอร์ที่ font size เดียวกับตัวเลขแล้วล้นจนขึ้นบรรทัดที่ 3 แบบ
    // ตัดคำเถื่อน (บั๊กที่ผู้ใช้รายงานจริง) — แยกเป็นบรรทัดของตัวเองด้วยฟอนต์
    // เล็กกว่า + ห่อ FittedBox ให้ย่อขนาดพอดีบรรทัดเดียวเสมอไม่ว่าข้อความจะยาว
    // แค่ไหน ส่วน IntrinsicHeight/stretch ด้านล่างทำให้ทั้ง 4 ช่องสูงเท่ากัน
    // ขอบล่างตรงกันแม้ช่อง BMI จะมีบรรทัดสถานะเพิ่มมา
    Widget bmiStat() => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              bmi == null ? '-' : bmi.toStringAsFixed(1),
              style: AppTextStyles.headingSmall.copyWith(color: _bmiColor(bmi)),
            ),
            if (bmiLabel != null) ...[
              const SizedBox(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    bmiLabel,
                    maxLines: 1,
                    style: AppTextStyles.caption.copyWith(
                      color: _bmiColor(bmi),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text('BMI', style: AppTextStyles.caption),
          ],
        ),
      ),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          stat('อายุ', age == null ? '-' : '$age ปี'),
          const SizedBox(width: 8),
          bmiStat(),
          const SizedBox(width: 8),
          stat(
            'น้ำหนัก',
            weight == null ? '-' : '${weight.toStringAsFixed(0)} กก.',
          ),
          const SizedBox(width: 8),
          stat(
            'ส่วนสูง',
            height == null ? '-' : '${height.toStringAsFixed(0)} ซม.',
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label, {String? suffixText}) =>
      InputDecoration(
        labelText: label,
        suffixText: suffixText,
        filled: true,
        fillColor: AppColors.gray50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gray100),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gray100),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.teal500, width: 2),
        ),
      );

  // ปุ่ม spin ขึ้น/ลง ข้างช่องน้ำหนัก/ส่วนสูง — เพิ่ม/ลดค่าใน controller ตรงๆ
  // ทีละ [step] แทนต้องพิมพ์เอง (ผู้ใช้รายงานจริง: อยากได้ปุ่มแบบ input
  // type=number ของเว็บที่มีลูกศรขึ้นลง) ใช้แพทเทิร์นเดียวกับที่มีอยู่แล้วใน
  // personal_information_page.dart (หน้ากรอกข้อมูลครั้งแรก) ให้สองหน้าดู
  // เหมือนกัน
  Widget _numberSpinner(
    TextEditingController ctrl, {
    required double step,
    required double min,
    required double max,
    required int decimals,
  }) {
    void bump(double delta) {
      final current = double.tryParse(ctrl.text.trim()) ?? min;
      final next = (current + delta).clamp(min, max);
      setState(() => ctrl.text = next.toStringAsFixed(decimals));
    }

    // กดค้าง = เพิ่ม/ลดรัวๆ: กดปุ๊บขยับทันที 1 ครั้ง แล้วรอสักครู่ก่อนเริ่ม
    // รัวถี่ๆ (กันกดสั้นๆ ครั้งเดียวโดนนับเป็นรัวเกินตั้งใจ) ปล่อยนิ้ว/ลาก
    // นิ้วออกนอกปุ่มค่อยหยุด
    void startHold(double delta) {
      _spinnerTimer?.cancel();
      bump(delta);
      _spinnerTimer = Timer(const Duration(milliseconds: 400), () {
        _spinnerTimer = Timer.periodic(
          const Duration(milliseconds: 80),
          (_) => bump(delta),
        );
      });
    }

    void stopHold() => _spinnerTimer?.cancel();

    Widget arrow(IconData icon, double delta) => SizedBox(
      width: 28,
      height: 20,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => startHold(delta),
        onTapUp: (_) => stopHold(),
        onTapCancel: stopHold,
        child: Icon(icon, size: 14, color: AppColors.gray600),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          arrow(Icons.keyboard_arrow_up, step),
          arrow(Icons.keyboard_arrow_down, -step),
        ],
      ),
    );
  }

  Widget _buildEditForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'แก้ไขข้อมูลส่วนตัว',
            style: AppTextStyles.headingSmall.copyWith(
              color: AppColors.gray900,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  decoration: _decoration('ชื่อ'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _surnameCtrl,
                  decoration: _decoration('นามสกุล'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppMultiSelectChip(
            label: 'โรคประจำตัว',
            options: _canonicalDiseases,
            selected: _diseases,
            onChanged: (v) => setState(() => _diseases = v),
          ),
          const SizedBox(height: 16),
          AppMultiSelectChip(
            label: 'แพ้อาหาร',
            options: _canonicalAllergies,
            selected: _allergies,
            onChanged: (v) => setState(() => _allergies = v),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _savingProfile ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal500,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _savingProfile
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'บันทึกข้อมูล',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // น้ำหนัก/ส่วนสูง เป็นข้อมูลร่วมของทั้งกล่อง BMI, กล่อง BMR/TDEE, และการ์ด
  // เป้าหมาย (พรีวิว kcal ใช้ทั้ง tdee กับ weight) แก้ค่าจากกล่องไหนก็ต้อง
  // ล้างผลเก่าของทุกจุดที่พึ่งพาค่านี้ ไม่งั้นจะยังโชว์ตัวเลขที่คำนวณจาก
  // น้ำหนัก/ส่วนสูงเก่าอยู่ — แต่ล้างเฉพาะจุดที่ข้อมูลจริงเปลี่ยนเท่านั้น (ไม่ใช่
  // กวาดล้างทุกครั้งที่กด "บันทึก" แบบเดิม ซึ่งไปล้างกล่องที่ไม่เกี่ยวด้วย)
  // เป้าหมายที่ถูกล็อกอยู่ (isLocked) แก้ไข/กดคำนวณใหม่ไม่ได้แล้ว (ดู
  // _buildDietPlanBox ที่ disable ช่องกรอก+ปุ่ม "คำนวณ" ตอนล็อก) ถ้าเผลอเคลียร์
  // _dietCalculated ของเป้าหมายนี้ไปด้วย ผู้ใช้จะไม่มีทางกดคำนวณคืนได้อีกเลย
  // จนกว่าจะครบกำหนดล็อก (ผู้ใช้รายงานจริง: แก้ น้ำหนัก/ส่วนสูง/อายุ แล้ว
  // ตัวเลขเป้าหมายสุขภาพที่บันทึกไว้หายไปเลย แทนที่จะอัปเดตตามข้อมูลใหม่) —
  // ข้ามเป้าหมายที่ล็อกอยู่ไว้ ไม่ต้องเคลียร์ (พรีวิว kcal ของมันคำนวณสดจาก
  // weight/tdee ปัจจุบันอยู่แล้วใน _dietRecommendedFor เลยอัปเดตเองโดยไม่ต้อง
  // รีเซ็ต flag นี้) ใช้ร่วมกันทั้งจากกล่อง BMI/ช่องน้ำหนัก-ส่วนสูง
  // (_invalidateWeightHeight) และกล่อง BMR/TDEE ตอนแก้เพศ/วันเกิด/กิจกรรม
  // (invalidate() ในตัว build ของกล่องนั้น) ไม่งั้นแก้แค่จุดเดียวจุดที่สองยัง
  // มีบั๊กเดิมอยู่
  void _invalidateDietCalculated() {
    final lockedUntilStr = context
        .read<AuthService>()
        .user?['health_goal_locked_until']
        ?.toString();
    final lockedUntil = (lockedUntilStr != null && lockedUntilStr.isNotEmpty)
        ? DateTime.tryParse(lockedUntilStr)
        : null;
    final isLocked =
        lockedUntil != null && DateTime.now().isBefore(lockedUntil);
    for (final g in _goalOptions) {
      if (isLocked && g == _pendingGoal) continue;
      _dietCalculated[g] = false;
    }
  }

  void _invalidateWeightHeight() => setState(() {
    _bmrCalculated = false;
    _bmiCalculated = false;
    _invalidateDietCalculated();
  });

  // กล่องคำนวณ BMI (อ้างอิงเครื่องคำนวณของ hpc5.go.th/diet/?module=bmi) — กด
  // "คำนวณ" โชว์ผลทันที (คำนวณสดจาก _weightCtrl/_heightCtrl ปัจจุบัน) "บันทึก"
  // แยกหน้าที่กันชัดเจน แค่บันทึกโปรไฟล์ ไม่ได้คุมว่าจะเห็นผลพรีวิวหรือไม่
  Widget _buildBmiCalculatorBox() {
    final weight = double.tryParse(_weightCtrl.text.trim());
    final height = double.tryParse(_heightCtrl.text.trim());
    final revealed = _bmiCalculated;
    // ใช้ค่า BMI ดิบตัดเศษ (ไม่ปัด) ตรงนี้แทน bmi_calc.calcBmi() ตัวกลาง
    // (ที่ปัดเศษ 2 ตำแหน่ง ใช้ทั่วแอปตรงกับ backend ที่โชว์แค่ 1 ตำแหน่งอยู่
    // แล้ว) เพราะ hpc5 โชว์ BMI 2 ตำแหน่งแบบตัดเศษทิ้ง (68/170cm ได้ 23.52
    // ไม่ใช่ 23.53 ที่ปัดเศษจะได้) จุดอื่นในแอปยังคงพฤติกรรมเดิมไม่กระทบ
    final rawBmi = (weight != null && height != null && height > 0)
        ? weight / ((height / 100) * (height / 100))
        : null;
    final bmi = revealed && rawBmi != null
        ? (rawBmi * 100).floorToDouble() / 100
        : null;
    final status = bmi_calc.bmiStatus(bmi);

    String? advisory;
    switch (status) {
      case 'ผอม':
        advisory = 'ควรเพิ่มน้ำหนักให้อยู่ในเกณฑ์ปกติ เพื่อสุขภาพที่ดี';
      case 'ปกติ':
        advisory = 'น้ำหนักอยู่ในเกณฑ์ปกติ ควรรักษาระดับนี้ไว้';
      case 'ท้วม/น้ำหนักเกิน':
        advisory =
            'หากคุณมีกรรมพันธุ์เป็นโรคเบาหวานหรือไขมันในเลือดสูง ควรพยายามลดน้ำหนักให้ดัชนีมวลกายต่ำกว่า 23';
      case 'อ้วน':
        advisory = 'ควรลดน้ำหนักและปรึกษาแพทย์เพื่อดูแลสุขภาพอย่างเหมาะสม';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'คำนวณดัชนีมวลกาย (BMI)',
            style: AppTextStyles.headingSmall.copyWith(
              color: AppColors.gray900,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _decoration('น้ำหนัก', suffixText: 'กก.'),
                  onChanged: (_) => _invalidateWeightHeight(),
                ),
              ),
              _numberSpinner(
                _weightCtrl,
                step: 0.1,
                min: 1,
                max: 1000,
                decimals: 1,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _heightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _decoration('ส่วนสูง', suffixText: 'ซม.'),
                  onChanged: (_) => _invalidateWeightHeight(),
                ),
              ),
              _numberSpinner(
                _heightCtrl,
                step: 0.1,
                min: 1,
                max: 300,
                decimals: 1,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    // ต้องกรอกน้ำหนัก+ส่วนสูงให้ครบ (เป็นตัวเลขจริง มากกว่า 0)
                    // ก่อนถึงจะกดคำนวณได้ — ผู้ใช้รายงานจริง: ช่องว่างอยู่แต่
                    // ปุ่มกดได้ ทั้งที่ยังไม่มีอะไรให้คำนวณเลย
                    onPressed:
                        (weight != null &&
                            weight > 0 &&
                            height != null &&
                            height > 0)
                        ? () => setState(() => _bmiCalculated = true)
                        : null,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.teal500),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'คำนวณ BMI',
                      style: TextStyle(
                        color: AppColors.teal700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed:
                        (_savingProfile ||
                            weight == null ||
                            weight <= 0 ||
                            height == null ||
                            height <= 0)
                        ? null
                        : () => _saveProfile(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.teal500,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _savingProfile
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'บันทึก',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
          if (revealed && bmi != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.gray50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'ค่า BMI = ',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.gray900,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _bmiColor(bmi),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          bmi.toStringAsFixed(2),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        status ?? '',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.gray900,
                        ),
                      ),
                    ],
                  ),
                  if (advisory != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      advisory,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.gray600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // กล่องคำนวณ BMR/TDEE (อ้างอิงเครื่องคำนวณของ hpc5.go.th/diet/?module=bmr)
  // — ย้ายเพศ/วันเกิด/น้ำหนัก/ส่วนสูง/ระดับกิจกรรมมาจากฟอร์ม "แก้ไขข้อมูล
  // ส่วนตัว" มาไว้ที่นี่แทน เพราะเป็นข้อมูลที่ใช้คำนวณ BMR/TDEE โดยตรง
  // กด "คำนวณ" โชว์ผลทันที "บันทึก" แยกหน้าที่กันชัดเจน แค่บันทึกโปรไฟล์
  // (เรียก _saveProfile() ตัวเดียวกับฟอร์มข้อมูลส่วนตัว) ไม่ได้คุมว่าจะเห็น
  // ผลพรีวิวหรือไม่
  Widget _buildBmrCalculatorBox() {
    // คำนวณสดจากค่าที่พิมพ์อยู่ในฟอร์มตอนนี้เลย (ตัวเดียวกับที่ใช้ตอนกด
    // "บันทึก") ไม่ใช้ bmr/tdee ที่คำนวณจากข้อมูลที่บันทึกไว้แล้วในโปรไฟล์
    // (ตัวแปรนอกฟังก์ชันนี้ที่ _buildGoalSection ใช้ต่อ) เพราะถ้าผู้ใช้เพิ่ง
    // แก้น้ำหนัก/วันเกิด/กิจกรรมแต่ยังไม่กด "บันทึก" ค่าที่บันทึกไว้จะเก่ากว่า
    // ที่พิมพ์อยู่ — โชว์ค่าเก่าจะ "เพี้ยน" ไม่ตรงกับที่เพิ่งกรอก
    final weight = double.tryParse(_weightCtrl.text.trim());
    final height = double.tryParse(_heightCtrl.text.trim());
    final age = _ageFromDob(_dob);
    final bmr = bmi_calc.calcBmr(
      weight: weight,
      height: height,
      age: age,
      gender: _gender,
    );
    final tdee = bmi_calc.calcTdee(
      weight: weight,
      height: height,
      age: age,
      gender: _gender,
      activity: _activity,
    );
    // กล่องสีๆ ล้อ "ผลการคำนวน" ของ hpc5.go.th (ผู้ใช้ขอให้ตัวเลขมีกล่องสี
    // เหมือนเว็บ แทนตัวหนังสือธรรมดา) — โทนสีใช้จากชุดสีที่มีอยู่แล้วในระบบ
    // (AppColors) ไม่ผสมสีใหม่ขึ้นมาเอง
    Widget pill(String text, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );

    Widget tile(String label, double? value, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.gray50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            value == null
                ? const Text('-')
                : pill('${value.round()} kcal', color),
            const SizedBox(height: 4),
            Text(label, style: AppTextStyles.caption),
          ],
        ),
      ),
    );

    Widget weeklyRow(String label, double value, Color color) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'คุณต้องบริโภค ',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
          ),
          pill('${value.round()}', color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'แคลอรี่/วัน เพื่อ$label',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
            ),
          ),
        ],
      ),
    );

    // เพศ/วันเกิด/ระดับกิจกรรม กระทบ tdee ด้วย (ไม่ใช่แค่ BMR) ต้องล้างพรีวิว
    // ของการ์ดเป้าหมายที่พึ่ง tdee ไปด้วย ไม่ใช่แค่ตัวเลขในกล่องนี้เอง
    void invalidate() => setState(() {
      _bmrCalculated = false;
      _invalidateDietCalculated();
    });

    final revealed = _bmrCalculated && bmr != null && tdee != null;
    // ต้องกรอกครบทุกช่อง (เพศ/วันเกิด/น้ำหนัก/ส่วนสูง/ระดับกิจกรรม) ก่อนถึงจะ
    // กดคำนวณได้ — ผู้ใช้รายงานจริง: ช่องว่างอยู่แต่ปุ่มกดได้
    final hasAllFields =
        _gender != null &&
        _dob != null &&
        weight != null &&
        weight > 0 &&
        height != null &&
        height > 0 &&
        _activity != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'คำนวณ BMR / TDEE',
            style: AppTextStyles.headingSmall.copyWith(
              color: AppColors.gray900,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _gender,
            isExpanded: true,
            decoration: _decoration('เพศ'),
            items: _genderOptions
                .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                .toList(),
            onChanged: (v) {
              setState(() => _gender = v);
              invalidate();
            },
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final before = _dob;
              await _pickDob();
              if (_dob != before) invalidate();
            },
            child: InputDecorator(
              decoration: _decoration('วันเกิด'),
              child: Text(
                _dob == null
                    ? '-'
                    : '${_dob!.day.toString().padLeft(2, '0')}/${_dob!.month.toString().padLeft(2, '0')}/${_dob!.year}'
                          ' (อายุ ${_ageFromDob(_dob) ?? '-'} ปี)',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _decoration('น้ำหนัก', suffixText: 'กก.'),
                  onChanged: (_) => _invalidateWeightHeight(),
                ),
              ),
              _numberSpinner(
                _weightCtrl,
                step: 0.1,
                min: 1,
                max: 1000,
                decimals: 1,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _heightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _decoration('ส่วนสูง', suffixText: 'ซม.'),
                  onChanged: (_) => _invalidateWeightHeight(),
                ),
              ),
              _numberSpinner(
                _heightCtrl,
                step: 0.1,
                min: 1,
                max: 300,
                decimals: 1,
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _activity,
            isExpanded: true,
            decoration: _decoration('ระดับกิจกรรม'),
            items: _activityOptions
                .map(
                  (a) => DropdownMenuItem(
                    value: a,
                    child: Text(a, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (v) {
              setState(() => _activity = v);
              invalidate();
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: hasAllFields
                        ? () => setState(() => _bmrCalculated = true)
                        : null,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.teal500),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'คำนวณ BMR',
                      style: TextStyle(
                        color: AppColors.teal700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: (_savingProfile || !hasAllFields)
                        ? null
                        : () => _saveProfile(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.teal500,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _savingProfile
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'บันทึก',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
          if (revealed) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                tile('BMR', bmr, AppColors.blue400),
                const SizedBox(width: 8),
                tile('TDEE', tdee, AppColors.blue600),
              ],
            ),
            const SizedBox(height: 10),
            weeklyRow(
              'ลด 0.5 กิโลกรัม/สัปดาห์',
              tdee - 500,
              AppColors.amber500,
            ),
            weeklyRow('ลด 1 กิโลกรัม/สัปดาห์', tdee - 1000, AppColors.coral400),
            weeklyRow(
              'เพิ่ม 0.5 กิโลกรัม/สัปดาห์',
              tdee + 500,
              AppColors.teal500,
            ),
            weeklyRow(
              'เพิ่ม 1 กิโลกรัม/สัปดาห์',
              tdee + 1000,
              AppColors.blue400,
            ),
          ],
        ],
      ),
    );
  }

  // สูตรเดียวกับที่ใช้ในกล่อง "วางแผนพลังงาน" (ดู _buildDietPlanBox) — ดึงมา
  // ใช้ซ้ำสำหรับพรีวิว kcal บนการ์ดเป้าหมายด้วย ไม่คัดลอกสูตรซ้ำสองที่
  double? _dietRecommendedFor(String goal, double? tdee, double? weight) {
    if (tdee == null || weight == null) return null;
    final targetWeight = double.tryParse(_targetWeightCtrls[goal]!.text.trim());
    final days = int.tryParse(_dietDaysCtrls[goal]!.text.trim());
    if (targetWeight == null || targetWeight <= 0 || days == null || days <= 0)
      return null;
    final perDay = ((targetWeight - weight) * 7700) / days;
    final raw = tdee + perDay;
    return raw;
  }

  double _dietAdjustmentFor(String goal, double? tdee, {int? requested}) {
    final adjustment = (requested ?? _dietCalorieAdjustments[goal] ?? 500)
        .toDouble();
    if (goal != 'ลดน้ำหนัก' || tdee == null) return adjustment;
    final floor = _gender == 'หญิง' ? 1200.0 : 1500.0;
    return (tdee - floor).clamp(0, adjustment).toDouble();
  }

  double? _goalCaloriesForRate(String goal, double? rawTdee, int rate) {
    if (rawTdee == null) return null;
    return goal == 'ลดน้ำหนัก' ? rawTdee - rate : rawTdee + rate;
  }

  String? _goalRateSafetyError(
    String goal,
    int rate,
    double? tdee,
    double? rawTdee,
  ) {
    final calories = _goalCaloriesForRate(goal, rawTdee, rate);
    if (calories == null || tdee == null) {
      return 'กรุณากรอกข้อมูลให้ครบก่อนเลือกอัตราแคลอรี';
    }
    if (goal == 'ลดน้ำหนัก') {
      final floor = _gender == 'หญิง' ? 1200 : 1500;
      if (calories < floor) {
        return 'ตัวเลือกนี้ให้พลังงาน ${calories.round()} kcal/วัน ต่ำกว่าขั้นต่ำที่ปลอดภัย ($floor kcal/วัน)';
      }
      final adjustment = tdee - calories;
      if (adjustment <= 0) {
        return 'ค่าแคลอรีนี้ไม่ต่ำกว่า TDEE ที่ใช้กับเป้าหมายสุขภาพ';
      }
      if (adjustment > 1000) {
        return 'ตัวเลือกนี้ปรับพลังงานเกิน 1000 kcal/วัน จึงไม่ปลอดภัย';
      }
    } else {
      final adjustment = calories - tdee;
      if (adjustment <= 0) {
        return 'ค่าแคลอรีนี้ไม่สูงกว่า TDEE ที่ใช้กับเป้าหมายสุขภาพ';
      }
      if (adjustment > 1000) {
        return 'ตัวเลือกนี้ปรับพลังงานเกิน 1000 kcal/วัน จึงไม่ปลอดภัย';
      }
    }
    return null;
  }

  void _selectDietCalorieAdjustment(
    String goal,
    int adjustment,
    double? tdee,
    double? rawTdee,
  ) {
    final safetyError = _goalRateSafetyError(goal, adjustment, tdee, rawTdee);
    if (safetyError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(safetyError)));
      return;
    }

    final weight = double.tryParse(_weightCtrl.text.trim());
    final targetWeight = double.tryParse(_targetWeightCtrls[goal]!.text.trim());
    setState(() {
      _dietCalorieAdjustments[goal] = adjustment;
      _dietCalculated[goal] = false;
      if (weight != null && targetWeight != null) {
        final days = _recommendedDietDays(
          goal,
          weight,
          targetWeight,
          tdee,
          rawTdee,
        );
        if (days == null) {
          _dietDaysCtrls[goal]!.clear();
        } else {
          _dietDaysCtrls[goal]!.text = days.toString();
        }
      }
    });
  }

  int? _recommendedDietDays(
    String goal,
    double weight,
    double? targetWeight,
    double? tdee,
    double? rawTdee,
  ) {
    if (goal == 'รักษาน้ำหนัก') {
      return 30;
    }
    if (targetWeight == null || targetWeight <= 0) {
      return null;
    }
    if (goal == 'ลดน้ำหนัก' && targetWeight >= weight) {
      return null;
    }
    if (goal == 'เพิ่มน้ำหนัก' && targetWeight <= weight) {
      return null;
    }
    final selectedRate = _dietCalorieAdjustments[goal];
    if (selectedRate != null) {
      if (_goalRateSafetyError(goal, selectedRate, tdee, rawTdee) != null) {
        return null;
      }
      final selectedCalories = _goalCaloriesForRate(
        goal,
        rawTdee,
        selectedRate,
      )!;
      final dailyAdjustment = goal == 'ลดน้ำหนัก'
          ? tdee! - selectedCalories
          : selectedCalories - tdee!;
      final days = (((targetWeight - weight).abs() * 7700) / dailyAdjustment)
          .ceil();
      return days > 3650 ? null : days.clamp(1, 3650).toInt();
    }
    final dailyAdjustment = _dietAdjustmentFor(goal, tdee);
    if (dailyAdjustment <= 0) return null;
    final days = (((targetWeight - weight).abs() * 7700) / dailyAdjustment)
        .ceil();
    return days > 3650 ? null : days.clamp(1, 3650).toInt();
  }

  String? _dietDaysRecommendationText(
    String goal,
    double weight,
    double? targetWeight,
    double? tdee,
    double? rawTdee,
  ) {
    if (goal == 'รักษาน้ำหนัก') {
      return tdee == null
          ? 'แนะนำ 30 วันสำหรับติดตามการรักษาน้ำหนัก'
          : 'แนะนำ 30 วันสำหรับติดตามการรักษาน้ำหนัก โดยใช้ประมาณ ${tdee.round()} kcal/วัน';
    }
    if (targetWeight == null || targetWeight <= 0 || tdee == null) {
      return null;
    }
    if ((goal == 'ลดน้ำหนัก' && targetWeight >= weight) ||
        (goal == 'เพิ่มน้ำหนัก' && targetWeight <= weight)) {
      return null;
    }
    final difference = (targetWeight - weight).abs();
    final selectedRate = _dietCalorieAdjustments[goal];
    if (selectedRate != null) {
      final safetyError = _goalRateSafetyError(
        goal,
        selectedRate,
        tdee,
        rawTdee,
      );
      if (safetyError != null) return safetyError;
      final selectedCalories = _goalCaloriesForRate(
        goal,
        rawTdee,
        selectedRate,
      )!.round();
      final selectedDays = _recommendedDietDays(
        goal,
        weight,
        targetWeight,
        tdee,
        rawTdee,
      );
      if (selectedDays == null) {
        return 'เป้าหมายนี้ต้องใช้เวลามากกว่า 3650 วัน กรุณาปรับน้ำหนักเป้าหมาย';
      }
      return 'เลือก $selectedCalories kcal/วัน (~${selectedRate == 500 ? '0.5' : '1'} กก./สัปดาห์); แนะนำ $selectedDays วัน';
    }
    final defaultRate = _dietCalorieAdjustments[goal] ?? 500;
    final selectedAdjustment = _dietAdjustmentFor(goal, tdee);
    if (selectedAdjustment <= 0) {
      return 'TDEE ต่ำกว่าขั้นต่ำที่ปลอดภัย จึงยังแนะนำแผนลดน้ำหนักไม่ได้';
    }
    final selectedDays = (difference * 7700 / selectedAdjustment).ceil();
    if (selectedDays > 3650) {
      return 'เป้าหมายนี้ต้องใช้เวลามากกว่า 3650 วัน กรุณาปรับน้ำหนักเป้าหมาย';
    }
    final direction = goal == 'ลดน้ำหนัก' ? -1 : 1;
    final selectedDailyAdjustment = difference * 7700 / selectedDays;
    final selectedCalories = (tdee + direction * selectedDailyAdjustment)
        .round();
    final selectedWeeklyRate = difference * 7 / selectedDays;
    final selectedLabel =
        '~${selectedWeeklyRate.toStringAsFixed(2)} กก./สัปดาห์';
    final alternateRate = defaultRate == 500 ? 1000 : 500;
    final alternateAdjustment = _dietAdjustmentFor(
      goal,
      tdee,
      requested: alternateRate,
    );
    final String alternateLabel;
    if (alternateAdjustment <= 0) {
      alternateLabel =
          'ทางเลือก ${alternateRate == 500 ? '0.5' : '1'} กก./สัปดาห์ '
          'ต่ำกว่าขั้นต่ำที่ปลอดภัย';
    } else {
      final alternateDays = (difference * 7700 / alternateAdjustment).ceil();
      if (alternateDays > 3650) {
        alternateLabel =
            'ทางเลือก ${alternateRate == 500 ? '0.5' : '1'} กก./สัปดาห์เกินระยะเวลาสูงสุด 3650 วัน';
      } else {
        final alternateDailyAdjustment = difference * 7700 / alternateDays;
        final alternateCalories = (tdee + direction * alternateDailyAdjustment)
            .round();
        final alternateWeeklyRate = difference * 7 / alternateDays;
        alternateLabel =
            'ทางเลือก $alternateDays วัน (~${alternateWeeklyRate.toStringAsFixed(2)} กก./สัปดาห์, $alternateCalories kcal/วัน)';
      }
    }
    return 'แนะนำ $selectedDays วัน ($selectedLabel, $selectedCalories kcal/วัน); '
        '$alternateLabel';
  }

  void _selectHealthGoal(String goal, double? profileWeight) {
    final weight = double.tryParse(_weightCtrl.text.trim()) ?? profileWeight;
    setState(() {
      _pendingGoal = goal;
      if (goal == 'รักษาน้ำหนัก') {
        final targetCtrl = _targetWeightCtrls[goal]!;
        final daysCtrl = _dietDaysCtrls[goal]!;
        if (targetCtrl.text.trim().isEmpty && weight != null) {
          targetCtrl.text = weight.toStringAsFixed(1);
        }
        if (daysCtrl.text.trim().isEmpty) {
          daysCtrl.text = '30';
        }
      }
    });
  }

  Widget _buildGoalSection(
    double? bmr,
    double? tdee,
    double? rawTdee,
    double? weight,
    DateTime? lockedUntil,
    double? savedCaloriesGoal,
  ) {
    Widget goalCard(String goal) {
      final selected = _pendingGoal == goal;
      // ต้องกรอกเป้าหมายน้ำหนัก+จำนวนวัน แล้วกด "คำนวณ" ก่อนถึงจะเห็นตัวเลข
      // บนการ์ด — ไม่ต้องรอกด "บันทึกเป้าหมาย" ด้วย (ผู้ใช้ยืนยันชัดเจน:
      // "บันทึกเป้าหมาย" ล็อกได้แค่ 1 เป้าหมายที่ใช้งานจริง ถ้าบังคับต้อง
      // บันทึกก่อนถึงจะโชว์ จะทำให้ทั้ง 3 การ์ดโชว์พร้อมกันไม่ได้เลย) —
      // การ์ดทั้ง 3 ใบเก็บสถานะคำนวณแยกกันอยู่แล้ว (_dietCalculated เป็น
      // map ต่อเป้าหมาย) กดคำนวณครบทั้ง 3 แท็บ (สลับไปกรอก+คำนวณทีละแท็บ)
      // แล้วทั้ง 3 การ์ดจะโชว์พร้อมกันเอง
      final revealed = _dietCalculated[goal] ?? false;
      // เป้าหมายที่ล็อกอยู่ตอนนี้ ([selected] เมื่อ isLocked) โชว์ค่าที่บันทึก
      // จริง (savedCaloriesGoal) แทนคำนวณสด — ดูคอมเมนต์ที่ตั้ง savedCaloriesGoal
      // ใน build() เป้าหมายอื่นที่ยังไม่ล็อก (พรีวิวก่อนกดบันทึก) ยังคำนวณสดปกติ
      final preview = !revealed
          ? null
          : _dietRecommendedFor(goal, tdee, weight);
      return Expanded(
        child: GestureDetector(
          onTap: () => _selectHealthGoal(goal, weight),
          child: Opacity(
            opacity: 1.0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.teal50 : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.teal500 : AppColors.gray100,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  if (selected)
                    const Icon(
                      Icons.check_circle,
                      color: AppColors.teal500,
                      size: 18,
                    ),
                  if (selected) const SizedBox(height: 4),
                  Text(
                    goal,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.labelBold.copyWith(
                      color: AppColors.gray900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview == null ? '-' : '${preview.round()} kcal',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.gray600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'เป้าหมายสุขภาพ',
            style: AppTextStyles.headingSmall.copyWith(
              color: AppColors.gray900,
            ),
          ),
          const SizedBox(height: 12),
          Row(children: _goalOptions.map(goalCard).toList()),
          // แผนน้ำหนักและจำนวนวันแก้ไขได้เสมอ แม้เป้าหมายหลักยังอยู่ในรอบล็อก
          _buildDietPlanBox(tdee, rawTdee, weight, false, savedCaloriesGoal),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed:
                  (_savingGoal ||
                      _pendingGoal == null ||
                      weight == null ||
                      tdee == null ||
                      !(_dietCalculated[_pendingGoal] ?? false) ||
                      _dietPlanValidationError(_pendingGoal!, weight) != null)
                  ? null
                  : () => _saveGoal(tdee),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal500,
                disabledBackgroundColor: AppColors.gray100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _savingGoal
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'บันทึกเป้าหมาย',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // กล่องวางแผนพลังงาน (อ้างอิง Diet Planning step ของ lovefitt) — โชว์ทุก
  // เป้าหมาย (ลด/รักษา/เพิ่มน้ำหนัก) คนละชุด controller/ผลคำนวณ (ดู
  // _targetWeightCtrls) สูตร 7700 kcal ต่อน้ำหนัก 1 กก. เป็นค่ามาตรฐานทั่วไป
  // บังคับทิศทางน้ำหนักเป้าหมายให้ตรงชื่อแท็บ (ผู้ใช้รายงานจริง: กรอกเลข
  // เดียวกันทั้ง 3 แท็บแล้วงงว่าทำไมได้ผลเท่ากันหมด — เพราะเดิมไม่เช็คทิศทาง
  // เลย) ลดน้ำหนักต้องกรอกเป้าหมายน้อยกว่าปัจจุบัน, เพิ่มน้ำหนักต้องมากกว่า,
  // รักษาน้ำหนักต้องใกล้เคียงปัจจุบัน (คลาดเคลื่อนได้ไม่เกิน 0.5 กก.) — กัน
  // ไม่ให้ 3 แท็บรับค่าเดียวกันแล้วได้ผลเท่ากันแบบข้ามทิศทางกันเองอีก
  // ตรวจน้ำหนักเป้าหมาย+จำนวนวันของ [goal] ว่ากรอกครบ/ถูกทิศทางหรือยัง — คืน
  // null แปลว่าผ่าน ใช้ทั้งกัน "คำนวณ" ตั้ง _dietCalculated=true ทั้งที่ข้อมูล
  // ยังไม่ครบ/ผิด (เดิมกดคำนวณเฉยๆ ก็ตั้ง true ได้ทันทีไม่เช็คอะไรเลย ทำให้
  // ปุ่ม "บันทึกเป้าหมาย" ซึ่งเช็คแค่ _dietCalculated เปิดใช้งานได้ทั้งที่ยัง
  // ไม่ได้กรอกอะไรจริงจัง ส่งค่า null ไป backend ซึ่ง fallback เป็นล็อก 7 วัน
  // ตายตัว+สูตร TDEE±500 เดิมเงียบๆ — ผู้ใช้รายงานจริง) และกันซ้ำอีกชั้นตอน
  // กด "บันทึกเป้าหมาย" เอง
  String? _dietPlanValidationError(String goal, double weight) {
    final targetWeight = double.tryParse(_targetWeightCtrls[goal]!.text.trim());
    final days = int.tryParse(_dietDaysCtrls[goal]!.text.trim());
    if (targetWeight == null ||
        targetWeight <= 0 ||
        targetWeight > 1000 ||
        days == null ||
        days <= 0 ||
        days > 3650) {
      return 'กรอกน้ำหนักเป้าหมายและจำนวนวันให้ถูกต้อง';
    }
    if (goal == 'ลดน้ำหนัก' && targetWeight >= weight) {
      return 'เป้าหมาย "ลดน้ำหนัก" ต้องกรอกน้ำหนักที่น้อยกว่าน้ำหนักปัจจุบัน ($weight กก.)';
    }
    if (goal == 'เพิ่มน้ำหนัก' && targetWeight <= weight) {
      return 'เป้าหมาย "เพิ่มน้ำหนัก" ต้องกรอกน้ำหนักที่มากกว่าน้ำหนักปัจจุบัน ($weight กก.)';
    }
    if (goal == 'รักษาน้ำหนัก' && (targetWeight - weight).abs() > 0.5) {
      return 'เป้าหมาย "รักษาน้ำหนัก" ควรกรอกน้ำหนักใกล้เคียงน้ำหนักปัจจุบัน ($weight กก.) '
          'ถ้าต้องการเปลี่ยนน้ำหนักจริงๆ ให้เลือกแท็บ "ลดน้ำหนัก" หรือ "เพิ่มน้ำหนัก" แทน';
    }
    return null;
  }

  void _showNegativeCaloriesWarning(
    String goal,
    double currentWeight,
    double targetWeight,
    int days,
    double kcal,
  ) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.coral600),
            SizedBox(width: 8),
            Text('ค่าพลังงานที่แนะนำอันตรายเกินไป'),
          ],
        ),
        content: Text(
          'เป้าหมาย $goal\n'
          'น้ำหนักปัจจุบัน: ${currentWeight.toStringAsFixed(1)} กก.\n'
          'เป้าหมายน้ำหนักที่ต้องการ: ${targetWeight.toStringAsFixed(1)} กก.\n'
          'จำนวนวัน: $days วัน\n\n'
          'ค่าพลังงานที่คำนวณได้คือ ${kcal.round()} kcal\n\n'
          'ซึ่งติดลบ/ต่ำกว่าค่าความปลอดภัยมากและอาจเป็นอันตรายต่อสุขภาพ\n\n'
          'กรุณาปรับเป้าหมายน้ำหนักหรือจำนวนวันใหม่ก่อนบันทึก',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('ปรับค่าใหม่'),
          ),
        ],
      ),
    );
  }

  void _showUnsafeWeightGainWarning(
    String goal,
    double currentWeight,
    double targetWeight,
    int days,
    double dailyGainKcal,
  ) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.coral600),
            SizedBox(width: 8),
            Text('ค่าพลังงานที่แนะนำอันตรายเกินไป'),
          ],
        ),
        content: Text(
          'เป้าหมาย $goal\n'
          'น้ำหนักปัจจุบัน: ${currentWeight.toStringAsFixed(1)} กก.\n'
          'เป้าหมายน้ำหนักที่ต้องการ: ${targetWeight.toStringAsFixed(1)} กก.\n'
          'จำนวนวัน: $days วัน\n\n'
          'ค่าพลังงานที่คำนวณได้คือ ${dailyGainKcal.round()} kcal/วัน\n\n'
          'ซึ่งสูงกว่าค่าความปลอดภัยที่แนะนำ (ไม่ควรเกิน 1000 kcal/วัน)\n\n'
          'กรุณาปรับเป้าหมายน้ำหนักหรือจำนวนวันใหม่ก่อนบันทึก',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('ปรับค่าใหม่'),
          ),
        ],
      ),
    );
  }

  void _showUnsafeMaintenanceWarning(
    String goal,
    double currentWeight,
    double targetWeight,
    int days,
    double dailyDeltaKcal,
  ) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.coral600),
            SizedBox(width: 8),
            Text('ค่าพลังงานที่แนะนำอันตรายเกินไป'),
          ],
        ),
        content: Text(
          'เป้าหมาย $goal\n'
          'น้ำหนักปัจจุบัน: ${currentWeight.toStringAsFixed(1)} กก.\n'
          'เป้าหมายน้ำหนักที่ต้องการ: ${targetWeight.toStringAsFixed(1)} กก.\n'
          'จำนวนวัน: $days วัน\n\n'
          'ค่าพลังงานที่คำนวณได้คือ ${dailyDeltaKcal.round()} kcal/วัน\n\n'
          'ซึ่งสูง/ต่ำกว่าค่าความปลอดภัยมากและอาจเป็นอันตรายต่อสุขภาพ\n\n'
          'กรุณาปรับเป้าหมายน้ำหนักหรือจำนวนวันใหม่ก่อนบันทึก',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('ปรับค่าใหม่'),
          ),
        ],
      ),
    );
  }

  String? _dietSafetyError(String goal, double weight, double? tdee) {
    final targetWeight = double.tryParse(_targetWeightCtrls[goal]!.text.trim());
    final days = int.tryParse(_dietDaysCtrls[goal]!.text.trim());
    if (targetWeight == null || targetWeight <= 0 || days == null || days <= 0)
      return null;

    final perDay = ((targetWeight - weight) * 7700) / days;
    if (perDay.abs() > 1000) {
      return 'แผนนี้ต้องปรับพลังงานเกิน 1000 kcal/วัน กรุณาเพิ่มจำนวนวันหรือปรับน้ำหนักเป้าหมาย';
    }

    if (goal == 'ลดน้ำหนัก' && tdee != null) {
      final floor = _gender == 'หญิง' ? 1200 : 1500;
      if (tdee + perDay < floor) {
        return 'พลังงานที่แนะนำต่ำกว่าขั้นต่ำที่ปลอดภัย ($floor kcal/วัน) กรุณาเพิ่มจำนวนวันหรือปรับน้ำหนักเป้าหมาย';
      }
    }

    if (goal == 'รักษาน้ำหนัก') {
      return null;
    }

    return null;
  }

  Widget _buildDietPlanBox(
    double? tdee,
    double? rawTdee,
    double? weight,
    bool isLocked,
    double? savedCaloriesGoal,
  ) {
    final goal = _pendingGoal;
    if (goal == null || tdee == null || weight == null)
      return const SizedBox.shrink();
    final targetCtrl = _targetWeightCtrls[goal]!;
    final daysCtrl = _dietDaysCtrls[goal]!;
    final calculated = _dietCalculated[goal] ?? false;

    final targetWeight = double.tryParse(targetCtrl.text.trim());
    final days = int.tryParse(daysCtrl.text.trim());
    final recommendationHint = _dietDaysRecommendationText(
      goal,
      weight,
      targetWeight,
      tdee,
      rawTdee,
    );

    double? perDay; // ลบ = ต้องลด, บวก = ต้องเพิ่ม, 0 = ไม่ต้องปรับ
    double? recommended;
    String? error;
    if (calculated) {
      error = _dietPlanValidationError(goal, weight);
      if (error == null) {
        perDay = ((targetWeight! - weight) * 7700) / days!;
        // เป้าหมายนี้ล็อกอยู่ -> โชว์ค่าที่บันทึกจริง ไม่คำนวณสด (ดูคอมเมนต์
        // เดียวกับใน goalCard() ด้านบน — สาเหตุเดียวกัน)
        recommended = (isLocked && savedCaloriesGoal != null)
            ? savedCaloriesGoal
            : _dietRecommendedFor(goal, tdee, weight);
      }
    }

    String adjustLabel = 'พลังงานที่ต้องปรับต่อวัน (kcal)';
    double? adjustValue = perDay;
    if (perDay != null) {
      if (perDay < -1) {
        adjustLabel = 'พลังงานที่ต้องลดต่อวัน (kcal)';
        adjustValue = -perDay;
      } else if (perDay > 1) {
        adjustLabel = 'พลังงานที่ต้องเพิ่มต่อวัน (kcal)';
        adjustValue = perDay;
      } else {
        adjustLabel = 'ไม่ต้องปรับพลังงาน (kcal)';
        adjustValue = 0;
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'วางแผนพลังงาน',
            style: AppTextStyles.labelBold.copyWith(color: AppColors.gray900),
          ),
          const SizedBox(height: 8),
          if (goal == 'ลดน้ำหนัก' || goal == 'เพิ่มน้ำหนัก') ...[
            Text(
              'เลือกอัตราแคลอรีจาก BMR / TDEE',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [500, 1000].map((rate) {
                final calories = _goalCaloriesForRate(goal, rawTdee, rate);
                final safetyError = _goalRateSafetyError(
                  goal,
                  rate,
                  tdee,
                  rawTdee,
                );
                final rateLabel = rate == 500 ? '0.5' : '1';
                return ChoiceChip(
                  label: Text(
                    calories == null
                        ? '... kcal/วัน (~$rateLabel กก./สัปดาห์)'
                        : '${calories.round()} kcal/วัน (~$rateLabel กก./สัปดาห์)'
                              '${safetyError == null ? '' : ' • ไม่ปลอดภัย'}',
                  ),
                  selected: _dietCalorieAdjustments[goal] == rate,
                  onSelected: isLocked || safetyError != null
                      ? null
                      : (_) => _selectDietCalorieAdjustment(
                          goal,
                          rate,
                          tdee,
                          rawTdee,
                        ),
                );
              }).toList(),
            ),
            if ([500, 1000].any(
              (rate) => _goalRateSafetyError(goal, rate, tdee, rawTdee) != null,
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'ตัวเลือกที่ต่ำกว่าขั้นต่ำปลอดภัยหรือไม่สอดคล้องกับ TDEE จะเลือกใช้ไม่ได้',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.coral600,
                  ),
                ),
              ),
          ],
          // ล็อกช่องกรอก+ปุ่ม "คำนวณ" ตอนเป้าหมายถูกล็อกอยู่ (isLocked) —
          // เดิมล็อกแค่การ์ดเป้าหมาย 3 ใบด้านบนกับปุ่ม "บันทึกเป้าหมาย" แต่
          // กล่องนี้ยังแก้ไข/กดคำนวณได้อยู่เฉยๆ ทั้งที่กดบันทึกจริงไม่ได้แล้ว
          // (ผู้ใช้รายงานจริง — ดูเหมือนแก้ไขแผนได้แต่จริงๆ ไม่มีผลอะไรเลย)
          TextField(
            controller: targetCtrl,
            enabled: !isLocked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _decoration(
              'เป้าหมายน้ำหนักที่ต้องการ',
              suffixText: 'kg.',
            ),
            onChanged: (value) {
              final target = double.tryParse(value.trim());
              final suggestedDays = _recommendedDietDays(
                goal,
                weight,
                target,
                tdee,
                rawTdee,
              );
              setState(() {
                if (goal != 'รักษาน้ำหนัก') {
                  if (suggestedDays == null) {
                    daysCtrl.clear();
                  } else {
                    daysCtrl.text = suggestedDays.toString();
                  }
                }
                _dietCalculated[goal] = false;
              });
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: daysCtrl,
            enabled: !isLocked,
            keyboardType: TextInputType.number,
            decoration: _decoration(
              'จำนวนวัน',
            ).copyWith(helperText: recommendationHint, helperMaxLines: 3),
            onChanged: (_) => setState(() => _dietCalculated[goal] = false),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ElevatedButton(
              onPressed: isLocked
                  ? null
                  : () {
                      final err = _dietPlanValidationError(goal, weight);
                      if (err != null) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(err)));
                        return;
                      }

                      final recommendation = _dietRecommendedFor(
                        goal,
                        tdee,
                        weight,
                      );
                      final calorieFloor = _gender == 'หญิง' ? 1200 : 1500;
                      if (recommendation != null &&
                          (recommendation <= 0 ||
                              (goal == 'ลดน้ำหนัก' &&
                                  recommendation < calorieFloor))) {
                        _showNegativeCaloriesWarning(
                          goal,
                          weight,
                          targetWeight!,
                          days!,
                          recommendation,
                        );
                        return;
                      }

                      final safetyErr = _dietSafetyError(goal, weight, tdee);
                      if (safetyErr != null) {
                        final targetWeight = double.tryParse(
                          targetCtrl.text.trim(),
                        );
                        final days = int.tryParse(daysCtrl.text.trim());
                        if (targetWeight != null && days != null && days > 0) {
                          final dailyDelta =
                              ((targetWeight - weight) * 7700) / days;
                          if (goal == 'รักษาน้ำหนัก') {
                            _showUnsafeMaintenanceWarning(
                              goal,
                              weight,
                              targetWeight,
                              days,
                              dailyDelta,
                            );
                          } else if (goal == 'เพิ่มน้ำหนัก' &&
                              targetWeight > weight) {
                            _showUnsafeWeightGainWarning(
                              goal,
                              weight,
                              targetWeight,
                              days,
                              dailyDelta,
                            );
                          } else {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(safetyErr)));
                          }
                        } else {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(safetyErr)));
                        }
                        return;
                      }

                      setState(() => _dietCalculated[goal] = true);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal500,
                disabledBackgroundColor: AppColors.gray100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'คำนวณ',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (calculated) ...[
            const SizedBox(height: 12),
            if (error != null)
              Text(
                error,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.coral600,
                ),
              )
            else ...[
              _dietResultTile(adjustLabel, adjustValue),
              const SizedBox(height: 8),
              _dietResultTile('พลังงานที่แนะนำต่อวัน (kcal)', recommended),
            ],
          ],
        ],
      ),
    );
  }

  Widget _dietResultTile(String label, double? value) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.teal500),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(color: AppColors.gray600),
        ),
        const SizedBox(height: 4),
        Text(
          value == null ? '-' : '${value.round()} kcal',
          style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900),
        ),
      ],
    ),
  );

  /// หาแถวที่ใกล้ที่สุด (ไม่เกิน) วันที่ [daysAgo] ก่อนแถวล่าสุด — ถ้าไม่มี
  /// ข้อมูลเก่าขนาดนั้นจริง (user เพิ่งเริ่มบันทึก) fallback ไปแถวแรกสุดที่มี
  /// แทน (ยังโชว์ delta ที่มีความหมายได้ แค่เป็น "ตั้งแต่เริ่มติดตาม" ไม่ใช่
  /// เป๊ะ 7/30 วันตรงตัว)
  WeightLogEntry? _referenceEntry(int daysAgo) {
    if (_weightLogs.isEmpty) return null;
    final target = _weightLogs.last.loggedAt.subtract(Duration(days: daysAgo));
    WeightLogEntry? best;
    for (final e in _weightLogs) {
      if (!e.loggedAt.isAfter(target)) {
        if (best == null || e.loggedAt.isAfter(best.loggedAt)) best = e;
      }
    }
    return best ?? _weightLogs.first;
  }

  Widget _weightDeltaRow(String label, int daysAgo, String? healthGoal) {
    if (_weightLogs.length < 2) return const SizedBox.shrink();
    final latest = _weightLogs.last;
    // ถ้าแถวแรกสุดที่มีก็ยังใหม่กว่า daysAgo วันก่อนอยู่ดี แปลว่ายังไม่มี
    // ข้อมูลย้อนไปไกลขนาดนั้นจริง — เดิม _referenceEntry จะ fallback ไปแถว
    // แรกสุดแทนแล้วโชว์ label "X วันก่อน" ทั้งที่จริงเทียบจากแค่วันเริ่มบันทึก
    // (บั๊กที่ผู้ใช้รายงานจริง: ดูเหมือนน้ำหนักเปลี่ยนเร็วผิดปกติ) ซ่อนแถวนี้
    // ไปเลยแทนจนกว่าจะมีข้อมูลย้อนหลังจริงครบตามที่ label บอก
    if (_weightLogs.first.loggedAt.isAfter(
      latest.loggedAt.subtract(Duration(days: daysAgo)),
    )) {
      return const SizedBox.shrink();
    }
    final ref = _referenceEntry(daysAgo);
    if (ref == null || ref.loggedAt == latest.loggedAt)
      return const SizedBox.shrink();
    final delta = latest.weight - ref.weight;
    final color = _weightDeltaColor(delta, healthGoal);
    final sign = delta > 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$sign${delta.toStringAsFixed(1)} kg $label',
        style: AppTextStyles.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildWeightHistorySection(String? healthGoal) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'น้ำหนักย้อนหลัง',
                style: AppTextStyles.headingSmall.copyWith(
                  color: AppColors.gray900,
                ),
              ),
              TextButton(
                onPressed: _openLogWeightSheet,
                child: const Text('+ บันทึกวันนี้'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingWeightLogs)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: AppSkeletonLoader(),
            )
          else if (_weightLogsError != null)
            AppErrorBanner(message: _weightLogsError!, onRetry: _loadWeightLogs)
          else if (_weightLogs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'ยังไม่มีข้อมูลน้ำหนัก — กด "+ บันทึกวันนี้" เพื่อเริ่มติดตาม',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.gray600,
                ),
              ),
            )
          else if (_weightLogs.length == 1) ...[
            // จุดเดียวลากกราฟแนวโน้มไม่ได้ (AppLineChart/AppBarChart ทั้งคู่
            // ออกแบบมาสำหรับหลายจุด) — โชว์เป็นวงกลมค่าเดียวกึ่งกลาง card
            // แทนแทนการฝืนวาดกราฟจากจุดเดียว
            Center(
              child: Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.teal50,
                  border: Border.all(color: AppColors.teal500, width: 5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _weightLogs.first.weight.toStringAsFixed(1),
                      style: AppTextStyles.headingSmall.copyWith(
                        color: AppColors.teal700,
                      ),
                    ),
                    Text(
                      'กก.',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.teal700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                '${_weightLogs.first.loggedAt.day}/${_weightLogs.first.loggedAt.month}',
                style: AppTextStyles.caption.copyWith(color: AppColors.gray400),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'บันทึกน้ำหนักวันนี้แล้ว (${_weightLogs.first.weight.toStringAsFixed(1)} กก.) — '
              'บันทึกอีกอย่างน้อย 1 วันเพื่อดูกราฟแนวโน้ม',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
            ),
          ] else ...[
            AppLineChart(
              points: _weightLogs
                  .map(
                    (e) => AppLineChartPoint(date: e.loggedAt, value: e.weight),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            _weightDeltaRow('จาก 7 วันก่อน', 7, healthGoal),
            _weightDeltaRow('จาก 30 วันก่อน', 30, healthGoal),
            const SizedBox(height: 12),
            Text(
              'บันทึกล่าสุด',
              style: AppTextStyles.labelBold.copyWith(color: AppColors.gray900),
            ),
            const SizedBox(height: 4),
            // เอาแค่ 5 รายการล่าสุด (ใหม่สุดอยู่บนสุด) กันลิสต์ยาวเกินถ้า
            // บันทึกครบทุกวันในช่วง 30 วันที่ดึงมา
            ..._weightLogs.reversed
                .take(5)
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${e.loggedAt.day.toString().padLeft(2, '0')}/${e.loggedAt.month.toString().padLeft(2, '0')}/${e.loggedAt.year}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.gray600,
                          ),
                        ),
                        Text(
                          '${e.weight.toStringAsFixed(1)} กก.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.gray900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _buildExportSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ส่งออกประวัติ',
                  style: AppTextStyles.headingSmall.copyWith(
                    color: AppColors.gray900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ดาวน์โหลดประวัติการกินเป็นไฟล์ CSV หรือ PDF',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.gray600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _openExportSheet,
            child: const Text('ดาวน์โหลด'),
          ),
        ],
      ),
    );
  }

  Future<void> _openExportSheet() async {
    String format = 'csv';
    DateTime? from;
    DateTime? to;
    bool submitting = false;
    String? error;

    Future<void> pickDate(
      void Function(DateTime) onPicked,
      DateTime? initial,
    ) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
      );
      if (picked != null) onPicked(picked);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ดาวน์โหลดประวัติ',
                style: AppTextStyles.headingMedium.copyWith(
                  color: AppColors.gray900,
                ),
              ),
              const SizedBox(height: 16),
              if (error != null) ...[
                Text(
                  error!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.coral600,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('CSV'),
                    selected: format == 'csv',
                    onSelected: (_) => setSheetState(() => format = 'csv'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('PDF'),
                    selected: format == 'pdf',
                    onSelected: (_) => setSheetState(() => format = 'pdf'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          pickDate((d) => setSheetState(() => from = d), from),
                      child: Text(
                        from == null
                            ? 'จากวันที่ (ทั้งหมด)'
                            : 'จาก ${_ymd(from!)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          pickDate((d) => setSheetState(() => to = d), to),
                      child: Text(
                        to == null ? 'ถึงวันที่ (ทั้งหมด)' : 'ถึง ${_ymd(to!)}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          setSheetState(() {
                            submitting = true;
                            error = null;
                          });
                          final result = await _exportService.exportHistory(
                            format: format,
                            from: from,
                            to: to,
                          );
                          await result.when(
                            ok: (file) async {
                              try {
                                await FilePicker.saveFile(
                                  dialogTitle: 'บันทึกไฟล์ประวัติ',
                                  fileName: file.fileName,
                                  bytes: file.bytes,
                                );
                              } catch (_) {}
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            },
                            err: (e) async => setSheetState(() {
                              submitting = false;
                              error = e.toUserMessage();
                            }),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teal500,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'ดาวน์โหลด',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'รายงานปัญหา',
                style: AppTextStyles.headingSmall.copyWith(
                  color: AppColors.gray900,
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _openTicketHistory,
                    child: const Text('ดูประวัติ'),
                  ),
                  TextButton(
                    onPressed: _openNewReportSheet,
                    child: const Text('+ รายงานปัญหาใหม่'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingReports)
            Column(
              children: List.generate(
                2,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: AppSkeletonLoader(
                    variant: AppSkeletonVariant.listItem,
                  ),
                ),
              ),
            )
          else if (_reportsError != null)
            AppErrorBanner(message: _reportsError!, onRetry: _loadReports)
          else if (_reports.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'ไม่มีเรื่องที่กำลังดำเนินการ',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.gray600,
                ),
              ),
            )
          else
            ..._reports.map(
              // ListTile ต้องมี Material เป็นบรรพบุรุษถึงจะวาด ink splash/พื้น
              // หลังตอนแตะได้ถูกต้อง — Container ด้านนอกมี decoration (สีขาว
              // + bo มุมโค้ง) ทำให้กลายเป็น DecoratedBox ซึ่งไม่ใช่ Material
              // บัง ink splash ของ ListTile ไว้ (เจอจริงจาก Flutter assertion)
              // ห่อด้วย Material(type: transparency) เพิ่มอีกชั้นแก้ได้ตรงๆ
              // โดยไม่กระทบพื้นหลังสีขาวของ Container เดิม
              (r) => Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    r.title.isEmpty ? '-' : r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    r.createdAt == null
                        ? '-'
                        : '${r.createdAt!.day.toString().padLeft(2, '0')}/${r.createdAt!.month.toString().padLeft(2, '0')}/${r.createdAt!.year}',
                    style: AppTextStyles.caption,
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.teal50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      r.status.labelTh,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.teal700,
                      ),
                    ),
                  ),
                  onTap: () => _openTicketChat(r),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
