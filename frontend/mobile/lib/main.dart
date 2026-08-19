import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/api_client.dart';
import 'services/responsive_helper.dart';
import 'services/report_service.dart';
import 'models/meal_log.dart';
import 'theme/app_theme.dart';
// Design system กลางใหม่ (lib/core/theme) — ใช้ prefix กันชนชื่อ AppColors/
// AppTheme กับ theme/app_theme.dart เดิมที่หน้าที่ยังไม่ redesign ใช้ค่าสี
// ของตัวเอง (hardcoded, ไม่ผ่าน Theme.of(context)) จึงไม่กระทบเมื่อสลับ
// MaterialApp.theme มาใช้ตัวนี้แทน — ดู core/theme/app_theme.dart
import 'core/theme/app_colors.dart' as core_theme;
import 'core/theme/app_text_styles.dart' as core_theme;
import 'core/theme/app_theme.dart' as core_theme;
import 'core/widgets/widgets.dart';
import 'core/notification/notification_helper.dart';
import 'app_categories.dart';
import 'router/app_router.dart';
import 'page/dashboard_page.dart';
import 'services/dashboard_service_factory.dart';
import 'page/meal_log_flow.dart';
import 'services/meal_log_service.dart';
import 'services/food_item_service.dart';
import 'page/class_food_page.dart';
import 'page/personal_information_page.dart';
import 'page/profile_page.dart';
import 'page/choose_a_health_goal.dart';
import 'page/report_problem_page.dart';
import 'page/ticket_chat_page.dart';
// unused page imports removed (analyzer flagged unused_import)
import 'page/register_login_page.dart';
import 'page/change_password_page.dart';
import 'page/pdpa_consent_page.dart';
import 'services/consent_service.dart';

// เคยลองทั้งเทียบ PID และเทียบ VM service URI ของโปรเซสปัจจุบัน สมมติว่า
// hot restart รันอยู่ในโปรเซส/VM instance เดิมเสมอ — แต่ทดสอบจริงบน Windows
// desktop แล้วพบว่า hot restart ได้ทั้ง PID ใหม่ และพอร์ต VM service ใหม่
// ด้วย (เครื่องนี้ hot restart จริงๆ คือ relaunch โปรเซสลูกใหม่ทั้งหมด ไม่ใช่
// แค่รีเซ็ต isolate ในโปรเซสเดิมแบบที่ platform อื่นเป็น) เลยไม่มีทาง
// พึ่งอัตลักษณ์ระดับ OS process/VM ของแอปเองได้เลยบนเครื่องนี้ (บั๊กที่
// ผู้ใช้รายงานจริงว่ายังไม่หายทั้ง 2 รอบที่ลองมา) เปลี่ยนแนวทางทั้งหมด:
// ใช้ "heartbeat" เขียนเวลาปัจจุบันลงไฟล์ทุก 1 วินาทีตลอดที่แอปยังรันอยู่
// แทน — hot restart เสร็จในเสี้ยววินาที (log จริงที่เจอ: "Restarted
// application in 471-538ms") ส่วนปิดแอปจริงแล้วเปิดใหม่ต่อให้เร็วที่สุดก็ยัง
// กินเวลานานกว่านี้มาก (แค่ build step ในนี้เจอจริงก็ ~10 วินาทีแล้ว) เช็ค
// แค่ "เวลาบันทึกล่าสุดในไฟล์ห่างจากตอนนี้ไม่เกิน threshold ไหม" ไม่ต้องรู้
// อะไรเกี่ยวกับ PID/พอร์ต/process tree เลย ใช้ได้ทุกแพลตฟอร์มเหมือนกันด้วย
File _sessionMarkerFile() =>
    File('${Directory.systemTemp.path}${Platform.pathSeparator}.nutrition_app_heartbeat');

const _heartbeatInterval = Duration(seconds: 1);
const _staleThreshold = Duration(seconds: 5);

Future<void> _touchHeartbeat() async {
  try {
    await _sessionMarkerFile().writeAsString(DateTime.now().millisecondsSinceEpoch.toString());
  } catch (_) {}
}

Future<bool> _isFreshProcessLaunch() async {
  var isFresh = true;
  try {
    final marker = _sessionMarkerFile();
    if (await marker.exists()) {
      final lastSeen = int.tryParse((await marker.readAsString()).trim());
      if (lastSeen != null) {
        final elapsedMs = DateTime.now().millisecondsSinceEpoch - lastSeen;
        if (kDebugMode) debugPrint('_isFreshProcessLaunch: elapsed since last heartbeat = ${elapsedMs}ms');
        if (elapsedMs >= 0 && elapsedMs < _staleThreshold.inMilliseconds) {
          isFresh = false;
        }
      }
    } else if (kDebugMode) {
      debugPrint('_isFreshProcessLaunch: no heartbeat file yet');
    }
  } catch (e) {
    if (kDebugMode) debugPrint('_isFreshProcessLaunch: error $e -> treat as fresh');
  }
  await _touchHeartbeat();
  // เริ่มนับ heartbeat ต่อเนื่อง กัน "เปิดแอปทิ้งไว้นานเกิน threshold โดยไม่
  // เคย hot restart เลย" แล้วพอ hot restart ครั้งแรกดันเข้าใจผิดว่าเก่า
  Timer.periodic(_heartbeatInterval, (_) => _touchHeartbeat());
  return isFresh;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ========== EMULATOR SUPPORT CONFIGURATION ==========
  // Set preferred orientations (portrait only for better emulator support)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Configure system UI overlay (for notches and safe areas)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // ====================================================

  final auth = AuthService();
  await auth.loadToken();
  // สำคัญ: ต้องเรียก _isFreshProcessLaunch() เสมอไม่ว่า isLoggedIn จะเป็น
  // อะไร (ห้ามเอาไปต่อท้าย && เดิม) เพราะฟังก์ชันนี้ "บันทึก" ค่าประจำเซสชัน
  // ปัจจุบันลง marker ด้วยเป็นผลข้างเคียง — เดิมเขียนเป็น
  // `auth.isLoggedIn && await _isFreshProcessLaunch()` ทำให้ตอนเปิดแอปครั้ง
  // แรก (ยังไม่ login, hasToken=false) ข้ามการเรียกไปเลยจาก short-circuit
  // ของ && เลยไม่เคยบันทึกค่าประจำเซสชันนี้ไว้ พอ login แล้วค่อยกด hot
  // restart การเช็คครั้งแรกที่เกิดขึ้นจริงกลับไปเทียบกับค่าค้างจาก
  // `flutter run` รอบก่อนหน้าแทน (คนละเซสชัน) เลยไม่ตรงกันเสมอ กลายเป็น
  // force logout ทุกครั้ง (บั๊กที่ผู้ใช้รายงานจริงว่ายังไม่หาย) แยกการ
  // "บันทึก/เช็ค" ออกจากการ "ตัดสินใจ logout" ให้ชัดเจน
  final isFreshLaunch = await _isFreshProcessLaunch();
  if (auth.isLoggedIn && isFreshLaunch) {
    await auth.clearToken(force: true);
  }
  await NotificationHelper.init();
  runApp(ChangeNotifierProvider.value(value: auth, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        return MaterialApp(
          title: 'Nutrition App',
          debugShowCheckedModeBanner: false,
          theme: core_theme.AppTheme.light,
          // ========== EMULATOR SUPPORT: Device constraints ==========
          // Use the full available width on tablets and emulators so the
          // UI fills the window. No max-width cap is applied here.
          builder: (context, child) {
            return child ?? const SizedBox.shrink();
          },
          // =====================================================
          home: _decideStartPage(auth),
          onGenerateRoute: AppRouter.onGenerateRoute,
        );
      },
    );
  }

  Widget _decideStartPage(AuthService auth) {
    // Always start at the main screen (inside RootShell). Login/register is
    // reachable from the top-right control so guests can use the app
    // immediately.
    return const RootShell();
  }
}

/// เชลล์หลักของแอป: ถือ bottom navigation แบบถาวรและ Navigator แยกของแต่ละ
/// tab ที่ต้อง persist สถานะ (หน้าหลัก/ประวัติ/โปรไฟล์) ปุ่ม "บันทึก" กลาง
/// เป็น FAB ที่เริ่ม startMealLogFlow ผ่าน root navigator เสมอ (เริ่มบันทึกมื้อ
/// ใหม่ทุกครั้งที่กด ไม่ใช่ tab ที่ต้อง persist สถานะกลับไปกลับมา)
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  // slot 0 = หน้าหลัก, 1 = ประวัติ, 2 = โปรไฟล์ — 3 tab ที่มี Navigator/
  // สถานะของตัวเองแบบถาวร (คงอยู่ผ่าน IndexedStack แม้สลับ tab ไปมา)
  int _tabSlot = 0;
  final _homeNavKey = GlobalKey<NavigatorState>();
  final _historyNavKey = GlobalKey<NavigatorState>();
  final _profileNavKey = GlobalKey<NavigatorState>();

  // ticket unread badge — poll เฉพาะตอนแอป foreground เท่านั้น (หยุด/เริ่ม
  // ตาม lifecycle ใน didChangeAppLifecycleState ด้านล่าง)
  Timer? _unreadPollTimer;
  int _unreadTicketCount = 0;
  Set<int> _lastUnreadReportIds = {};

  // gate ยินยอม PDPA — กันเปิดซ้ำซ้อนตอน AuthService.notifyListeners() ยิงถี่
  // (เช่น ระหว่าง refreshProfile) ไม่ได้แปลว่าเช็คแค่ครั้งเดียวทั้ง session:
  // ทุก build ที่ auth เปลี่ยนจะเช็คซ้ำเสมอ แต่ query เบามาก (แค่ GET status)
  // และ endpoint เองก็ idempotent อยู่แล้วถ้ายินยอมไปแล้วจะไม่เด้งซ้ำ
  bool _consentGateActive = false;
  // เดิม build() เช็ค gate ทุกครั้งที่ auth เปลี่ยนแม้ isLoggedIn ไม่ได้
  // เปลี่ยนเลย (เช่นตอนสมัครสมาชิก handleAuthSuccess + saveUser ยิง
  // notifyListeners หลายรอบติดกัน) แต่ละรอบ schedule เช็คซ้อนกันเข้าไปแข่งกับ
  // RegisterPage.popUntil ที่ปิด PdpaConsentPage ที่เพิ่ง push ไปกลางทางโดย
  // ไม่ตั้งใจ ทำให้เด้งซ้ำ 2 รอบ (บั๊กที่ผู้ใช้รายงานจริง) — เช็คเฉพาะตอน
  // isLoggedIn เปลี่ยนสถานะจริงๆ เท่านั้นพอ
  bool _wasLoggedIn = AuthService().isLoggedIn && !AuthService().isGuest;

  List<GlobalKey<NavigatorState>> get _navKeys => [_homeNavKey, _historyNavKey, _profileNavKey];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshMealReminders());
    _startUnreadPolling();
    unawaited(_maybeShowConsentGate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unreadPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // schedule เตือนมื้ออาหารใหม่ทุกครั้งที่กลับมา foreground เท่านั้น — ดู
    // ข้อจำกัดที่คอมเมนต์ไว้ใน NotificationHelper.scheduleMealReminders
    // (ไม่มี server-side trigger ตอนแอปปิดอยู่) poller ของ ticket ก็หยุด/
    // เริ่มตาม foreground/background ไปด้วยกัน กัน poll ทิ้งเปล่าตอนไม่ได้ใช้
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshMealReminders());
      _startUnreadPolling();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _unreadPollTimer?.cancel();
      _unreadPollTimer = null;
    }
  }

  Future<void> _refreshMealReminders() async {
    if (!AuthService().isLoggedIn || AuthService().isGuest) return;
    final result = await createMealLogService().fetchLogs(date: DateTime.now());
    final logs = result.when(ok: (l) => l, err: (_) => <MealLog>[]);
    final loggedTypes = logs.map((l) => l.mealType.apiValue).toSet();
    await NotificationHelper.scheduleMealReminders({
      'breakfast': loggedTypes.contains('breakfast'),
      'lunch': loggedTypes.contains('lunch'),
      'dinner': loggedTypes.contains('dinner'),
    });
  }

  void _startUnreadPolling() {
    _unreadPollTimer?.cancel();
    unawaited(_pollUnreadCount());
    _unreadPollTimer = Timer.periodic(const Duration(seconds: 45), (_) => _pollUnreadCount());
  }

  Future<void> _pollUnreadCount() async {
    if (!AuthService().isLoggedIn || AuthService().isGuest) return;
    final result = await createReportService().fetchUnreadCount();
    result.when(
      ok: (status) {
        // ticket ที่ "เพิ่งกลายเป็นยังไม่อ่าน" ใหม่ตั้งแต่รอบก่อน (ไม่ใช่แค่
        // unreadCount เพิ่มขึ้นเฉยๆ) — ยิง system notification เฉพาะตอนมี
        // ของใหม่จริงๆ ไม่ใช่ทุกรอบ poll
        final newIds = status.unreadReportIds.toSet().difference(_lastUnreadReportIds);
        if (newIds.isNotEmpty) {
          unawaited(NotificationHelper.showTicketReplyNotification(
            title: 'แอดมินตอบข้อความใหม่',
            preview: 'มีข้อความใหม่จากแอดมินในเรื่องที่คุณแจ้งไว้ — แตะเพื่อดูรายละเอียด',
            reportId: newIds.first,
          ));
          // system notification (ด้านบน) เด้งเฉพาะตอนแอปอยู่พื้นหลัง/ปิดอยู่
          // ตามพฤติกรรมปกติของ OS — ตอนแอปเปิดอยู่ (foreground) ผู้ใช้อาจไม่
          // เห็นเลยถ้า OS ไม่โชว์ banner ทับหน้าจอที่กำลังใช้อยู่ จึงต้องมี
          // SnackBar ในแอปเองด้วย ให้เห็นแน่ๆ ไม่ว่าแอปจะ foreground หรือไม่
          if (mounted) {
            // SnackBar ของ Flutter เอง (ดู ScaffoldMessengerState.build() ใน
            // scaffold.dart) จะ "เริ่มนับเวลา" ก็ต่อเมื่อ route ที่โชว์ตอนนั้น
            // ยังเป็น route บนสุดอยู่เท่านั้น (route.isCurrent) — พอผู้ใช้กด
            // เข้าไปดูหน้าอื่น (เช่นหน้า "การแจ้งเตือน" ที่เพิ่ง push ทับ) นับ
            // เวลาจะหยุดค้างทันที ไม่นับต่อจนกว่าจะย้อนกลับมาหน้าเดิม ทำให้ดู
            // เหมือนค้างอยู่ตลอดไม่มีวันหาย (ผู้ใช้รายงานจริง — ทดสอบด้วยการ
            // กดเข้าไปดูหน้าแจ้งเตือนนั่นแหละที่ทำให้นับเวลาหยุด) ไม่ใช้
            // duration ของ SnackBar เลย ตั้งเวลาเองแล้วสั่งซ่อนตรงๆ แทน ซึ่งไม่
            // เช็ค route.isCurrent เลย นับจริงตามเวลานาฬิกาเสมอไม่ว่าจะอยู่
            // หน้าไหนก็ตาม
            final messenger = ScaffoldMessenger.of(context);
            messenger.removeCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(
                content: const Text('แอดมินตอบข้อความใหม่ — มีข้อความใหม่ในเรื่องที่คุณแจ้งไว้'),
                action: SnackBarAction(label: 'ดู', onPressed: () => _openTicket(newIds.first)),
                duration: const Duration(days: 1), // ปิดตัวนับเวลาในตัวไปเลย ใช้ของเราแทนด้านล่าง
              ),
            );
            Future.delayed(const Duration(seconds: 10), () {
              if (mounted) messenger.hideCurrentSnackBar();
            });
          }
        }
        if (mounted) {
          setState(() {
            _unreadTicketCount = status.unreadCount;
            _lastUnreadReportIds = status.unreadReportIds.toSet();
          });
        }
      },
      // เงียบไว้ตอน poll พลาดชั่วคราว (เช่นเน็ตหลุดแป๊บเดียว) — ไม่ต้องกวน
      // error ทุก 45 วินาที ตัวเลข badge เดิมยังโชว์ค้างไว้ได้ปกติ
      err: (_) {},
    );
  }

  /// เช็คสถานะ PDPA consent ทุกครั้งที่สถานะล็อกอินเปลี่ยน — ถ้ายังไม่ยินยอม
  /// (หรือยินยอมเวอร์ชันเก่าที่ backend bump ทิ้งไปแล้ว) บังคับเปิด
  /// PdpaConsentPage แบบปิดด้วยปุ่ม back ไม่ได้ทับ RootShell ทั้งอัน จนกว่าจะ
  /// ยินยอม หรือเลือกออกจากระบบจากในหน้านั้นเอง (ดู pdpa_consent_page.dart)
  Future<void> _maybeShowConsentGate() async {
    if (!mounted || _consentGateActive) return;
    if (!AuthService().isLoggedIn || AuthService().isGuest) return;
    _consentGateActive = true;
    try {
      final result = await createConsentService().fetchStatus();
      if (!mounted) return;
      final needsConsent = result.when(ok: (s) => !s.consented, err: (_) => false);
      if (needsConsent && mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        // ตอนสมัครสมาชิก/ล็อกอินเสร็จ RegisterPage/LoginPage ยังไม่ทัน
        // popUntil(isFirst) ปิดตัวเอง — ถ้า push หน้ายินยอมตอนนั้นเลย จะโดน
        // popUntil ของหน้าเหล่านั้นเผลอปิดทิ้งก่อนผู้ใช้ทันได้กด (บั๊กที่
        // ผู้ใช้รายงานจริง: หน้ายินยอมหายไปเองโดยไม่ทันกด) รอให้ RootShell
        // เป็นหน้าบนสุดจริงๆ ก่อน (ไม่มีอะไรค้างเหนือมันแล้ว) ค่อย push
        var waited = 0;
        while (mounted && rootNav.canPop() && waited < 25) {
          await Future.delayed(const Duration(milliseconds: 200));
          waited++;
        }
        if (!mounted) return;
        await rootNav.push(
          MaterialPageRoute(builder: (_) => const PdpaConsentPage(), fullscreenDialog: true),
        );
      }
    } finally {
      _consentGateActive = false;
    }
  }

  /// สลับไป tab ที่เลือก หรือถ้าเลือก tab เดิมซ้ำ ให้ pop กลับไปหน้ารากของ
  /// tab นั้น (iOS convention) แทนการทำอะไรซ้ำ
  void _switchOrPopToRoot(int slot) {
    if (_tabSlot == slot) {
      _navKeys[slot].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _tabSlot = slot);
    }
  }

  /// ปุ่ม "ดู" บน SnackBar แจ้งแอดมินตอบข้อความ — เดิมสลับไปแค่แท็บโปรไฟล์
  /// เฉยๆ (_switchOrPopToRoot(2)) ผู้ใช้ต้องไปหา ticket ที่ถูกตอบเองต่ออีกที
  /// (บั๊กที่ผู้ใช้รายงานจริง) ทั้งที่รู้ reportId ที่ตอบใหม่อยู่แล้วจาก
  /// _pollUnreadCount — ดึงรายการ ticket ที่ยังไม่ปิดมาหาอันที่ id ตรงกันแล้ว
  /// เปิดหน้าแชทให้ตรงเรื่องเลย
  Future<void> _openTicket(int reportId) async {
    _switchOrPopToRoot(2);
    final reportService = createReportService();
    final result = await reportService.fetchMyReports(scope: 'open');
    if (!mounted) return;
    final report = result.when(
      ok: (list) => list.where((r) => r.id == reportId).firstOrNull,
      err: (_) => null,
    );
    if (report == null || !mounted) return;
    _navKeys[2].currentState?.push(
      MaterialPageRoute(
        builder: (_) => TicketChatPage(report: report, reportService: reportService),
      ),
    );
  }

  void _openMealLog() {
    startMealLogFlow(
      context,
      mealLogService: createMealLogService(),
      foodItemService: createFoodItemService(),
    );
  }

  /// Android back gesture/ปุ่ม back: pop ภายใน tab ปัจจุบันก่อนถ้ายัง pop ได้
  /// ถ้า pop ไม่ได้แล้วและไม่ได้อยู่ tab หน้าหลัก ให้กลับไป tab หน้าหลักก่อน
  /// ออกแอปจริงๆ ก็ต่อเมื่ออยู่ที่รากของ tab หน้าหลักแล้วเท่านั้น
  Future<void> _handleBack() async {
    final currentNav = _navKeys[_tabSlot].currentState;
    if (currentNav != null && currentNav.canPop()) {
      currentNav.pop();
      return;
    }
    if (_tabSlot != 0) {
      setState(() => _tabSlot = 0);
      return;
    }
    final rootNav = Navigator.of(context, rootNavigator: true);
    if (rootNav.canPop()) {
      rootNav.pop();
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // watch (ไม่ใช่แค่ read) เพื่อให้ build ใหม่ทุกครั้งที่ login/logout —
    // เป็นจังหวะเดียวที่ต้องเช็ค consent gate ใหม่ (ล็อกอินใหม่/สลับ user)
    final auth = context.watch<AuthService>();
    final nowLoggedIn = auth.isLoggedIn && !auth.isGuest;
    if (nowLoggedIn != _wasLoggedIn) {
      _wasLoggedIn = nowLoggedIn;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowConsentGate());
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tabSlot,
          children: [
            Navigator(
              key: _homeNavKey,
              initialRoute: AppRoutes.home,
              onGenerateRoute: (settings) {
                // AppRoutes.home ผูกกับ DashboardPage ตรงนี้แทนที่จะอยู่ใน
                // AppRouter กลาง เพื่อกัน circular import — แดชบอร์ดคือหน้า
                // แรกที่เห็นตอนเปิดแอปแล้ว (ไม่ใช่ grid หมวดหมู่ MainScreen
                // เดิมอีกต่อไป) MainScreen ยังอยู่ในไฟล์นี้เผื่อใช้ภายหลัง
                // แต่ไม่มีจุดเข้าอ้างอิงแล้ว
                if (settings.name == AppRoutes.home) {
                  return MaterialPageRoute(
                    builder: (_) => DashboardPage(
                      dashboardService: createDashboardService(),
                      mealLogService: createMealLogService(),
                      foodItemService: createFoodItemService(),
                    ),
                    settings: settings,
                  );
                }
                return AppRouter.onGenerateRoute(settings);
              },
            ),
            Navigator(
              key: _historyNavKey,
              initialRoute: AppRoutes.history,
              onGenerateRoute: AppRouter.onGenerateRoute,
            ),
            Navigator(
              key: _profileNavKey,
              initialRoute: AppRoutes.personalInfo,
              onGenerateRoute: AppRouter.onGenerateRoute,
            ),
          ],
        ),
        // เดิมปุ่ม "บันทึก" เป็น FloatingActionButton ลอยกลางแถบล่าง (แบบ
        // notch) ทำให้บังเนื้อหา/ปุ่มอื่นที่อยู่ใกล้ขอบล่างของหน้า (เช่น
        // bottom sheet) — ย้ายมาเป็นไอคอนปกติในแถวเดียวกับอีก 3 ตัวแทน ไม่มี
        // FAB ลอยอีกต่อไป
        bottomNavigationBar: BottomAppBar(
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavBarItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                label: 'หน้าหลัก',
                selected: _tabSlot == 0,
                onTap: () => _switchOrPopToRoot(0),
              ),
              _NavBarItem(
                icon: Icons.add_circle_outline,
                selectedIcon: Icons.add_circle_outline,
                label: 'บันทึก',
                selected: false,
                onTap: _openMealLog,
              ),
              _NavBarItem(
                icon: Icons.receipt_long_outlined,
                selectedIcon: Icons.receipt_long,
                label: 'ประวัติ',
                selected: _tabSlot == 1,
                onTap: () => _switchOrPopToRoot(1),
              ),
              _NavBarItem(
                icon: Icons.person_outline,
                selectedIcon: Icons.person,
                label: 'โปรไฟล์',
                selected: _tabSlot == 2,
                onTap: () => _switchOrPopToRoot(2),
                badgeCount: _unreadTicketCount,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ปุ่มแท็บหนึ่งอันในแถบล่าง — ใช้สี/ตัวอักษรจาก design system กลาง
/// (lib/core/theme) ไม่ hardcode ค่าใดๆ ในนี้
class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  const _NavBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    // อ้างสี/ตัวอักษรจาก design system กลางใหม่ตรงๆ (lib/core/theme) แทนการ
    // สลับ MaterialApp.theme ทั้งแอป — ตามขอบเขตงานนี้ที่ยังไม่แตะหน้าเดิม
    final color = selected ? core_theme.AppColors.teal500 : core_theme.AppColors.gray400;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBadgeIcon(
              count: badgeCount,
              child: Icon(selected ? selectedIcon : icon, color: color, size: 24),
            ),
            const SizedBox(height: 2),
            Text(label, style: core_theme.AppTextStyles.caption.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final Color accentGreen = AppColors.leaf;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<Map<String, dynamic>> _suggestions = [];
  bool _hasCheckedSummary = false;

  @override
  void initState() {
    super.initState();
    // ========== EMULATOR SUPPORT: Initialize responsive helper ==========
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ResponsiveHelper.init(context);
        debugPrint('[Emulator Support] Responsive initialized');
        debugPrint('Screen: ${ResponsiveHelper.screenWidth}x${ResponsiveHelper.screenHeight}');
        debugPrint('Is Small Screen (Emulator?): ${ResponsiveHelper.isSmallScreen}');
        debugPrint('Is Tablet: ${ResponsiveHelper.isTablet}');
      }
      _checkMainPageSummary();
    });
    // ====================================================================
  }

  // รายการหมวดหมู่สำหรับค้นหา (label ต้องตรงกับคำที่ผู้ใช้จะพิมพ์)
  // ย้ายไปประกาศที่ lib/app_categories.dart แล้ว ให้ SearchPage/CategoriesPage
  // ใช้ข้อมูลชุดเดียวกัน ไม่ต้องประกาศซ้ำ
  final List<Map<String, dynamic>> _categories = buildAppCategories();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _checkMainPageSummary() async {
    if (_hasCheckedSummary || !mounted) return;
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final token = auth.token;
      if (token == null || token.isEmpty) return;

      final client = ApiClient('http://127.0.0.1:5000');
      final response = await client.get(
        '/api/check_main_page_summary',
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted || response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      if (data['show_dialog'] == true) {
        _hasCheckedSummary = true;
        _displayMidnightAlert(
          data['result'] ?? 'FAILED',
          data['day_number'] ?? 1,
        );
      }
    } catch (e) {
      if (mounted) {
        debugPrint('MainScreen summary check failed: $e');
      }
    }
  }

  void _displayMidnightAlert(String result, dynamic dayNumber) {
    if (!mounted) return;
    final isSuccess = result.toString().toUpperCase() == 'SUCCESS';
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isSuccess ? Icons.stars : Icons.error,
              color: isSuccess ? Colors.amber : Colors.red,
            ),
            const SizedBox(width: 10),
            Text(
              isSuccess
                  ? 'เป้าหมายสำเร็จ วันที่ $dayNumber!'
                  : 'เป้าหมายไม่สำเร็จวันที่ $dayNumber',
            ),
          ],
        ),
        content: Text(
          isSuccess
              ? 'ยินดีด้วยครับ! คุณกรอกข้อมูลเมนูอาหารครบถ้วนตามแผนงานประจำวันที่ $dayNumber เรียบร้อยแล้ว'
              : 'เป้าหมายประจำวันที่ $dayNumber ยังไม่สำเร็จเนื่องจากข้อมูลมื้ออาหารไม่ครบถ้วน พยายามใหม่อีกครั้งในวันถัดไปนะ',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (mounted) Navigator.of(ctx).pop();
            },
            child: const Text('ตกลงเพื่อเริ่มวันถัดไป'),
          ),
        ],
      ),
    );
  }

  bool _canOpenMealPage(AuthService a) {
    try {
      final personal = a.user ?? a.tempPersonal ?? a.guestPersonal ?? {};
      final hasPersonal =
          (personal['gender'] != null &&
              personal['age'] != null &&
              personal['weight'] != null &&
              personal['height'] != null) ||
          a.tempPersonal != null;
      final sels = a.tempSelections ?? a.guestSelections ?? {};
      // Consider both food goals and drink-only goals as valid health goals.
      final hasGoal =
          sels.containsKey('health_goal') ||
          sels.containsKey('health_goal_drink') ||
          sels.containsKey('health_goal_group') ||
          (a.user != null && (
            a.user!['health_goal'] != null ||
            a.user!['health_goal_drink'] != null ||
            a.user!['health_goal_group'] != null
          ));
      if (kDebugMode && !(hasPersonal && hasGoal)) {
        debugPrint('[_canOpenMealPage] blocked -> hasPersonal=$hasPersonal hasGoal=$hasGoal');
        try {
          debugPrint('[_canOpenMealPage] tempSelections=${a.tempSelections}');
          debugPrint('[_canOpenMealPage] guestSelections=${a.guestSelections}');
          debugPrint('[_canOpenMealPage] user=${a.user}');
        } catch (_) {}
      }
      return hasPersonal && hasGoal;
    } catch (_) {
      return false;
    }
  }

  void _showMissingDataDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ข้อมูลไม่ครบ'),
        content: const Text(
          'กรุณากลับไปกรอกข้อมูลส่วนบุคคลและเลือกเป้าหมายสุขภาพก่อน',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PersonalInformationPage()),
              );
            },
            child: const Text('ไปกรอกข้อมูล'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChooseAHealthGoal()),
              );
            },
            child: const Text('ไปเลือกเป้าหมาย'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  Future<void> _performSearch(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาพิมพ์คำที่ต้องการค้นหา')),
      );
      return;
    }
    final matches = _categories
        .where((c) => (c['label'] as String).toLowerCase().contains(q))
        .toList();
    if (matches.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ไม่พบผลการค้นหา')));
      setState(() => _suggestions = []);
      return;
    }
    // If exactly one match, navigate directly
      if (matches.length == 1) {
      final label = matches.first['label'] as String;
      final page = matches.first['page'];
      if (label == 'เลือกมื้ออาหารและระยะเวลา') {
        final auth = Provider.of<AuthService>(context, listen: false);
        if (_canOpenMealPage(auth)) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
        } else {
          // Try to refresh profile from server once (in case a recent save
          // updated the user but local cache is stale), then re-evaluate.
          try {
            final token = auth.token;
            if (token != null && token.isNotEmpty) {
              await auth.refreshProfile();
            }
          } catch (_) {}
          if (!mounted) return;
          if (_canOpenMealPage(auth)) {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
          } else {
            _showMissingDataDialog();
          }
        }
      } else {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
      }
      setState(() => _suggestions = []);
      return;
    }
    // Multiple matches -> show choices in a bottom sheet
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView.separated(
        padding: const EdgeInsets.all(8),
        itemBuilder: (_, i) {
          final c = matches[i];
          final label = c['label'] as String;
          final asset = c['asset'] as String?;
          return ListTile(
            leading: asset != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      asset,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, st) {
                        try {
                          // ignore: avoid_print
                          print('Image.asset failed for $asset: $err');
                        } catch (_) {}
                        return Icon(Icons.image, color: accentGreen);
                      },
                    ),
                  )
                : Icon(Icons.folder, color: accentGreen),
            title: Text(label),
            onTap: () {
              Navigator.of(ctx).pop();
              final label = c['label'] as String;
              final page = c['page'];
              if (label == 'เลือกมื้ออาหารและระยะเวลา') {
                final auth = Provider.of<AuthService>(context, listen: false);
                if (_canOpenMealPage(auth)) {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => page));
                } else {
                  _showMissingDataDialog();
                }
              } else {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => page));
              }
            },
          );
        },
        separatorBuilder: (_, __) => const Divider(),
        itemCount: matches.length,
      ),
    );
    setState(() => _suggestions = matches.take(5).toList());
  }

  void _updateSuggestions(String input) {
    final q = input.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    final matches = _categories
        .where((c) => (c['label'] as String).toLowerCase().contains(q))
        .toList();
    setState(() => _suggestions = matches.take(5).toList());
  }

  Widget categoryItem(
    IconData icon,
    String label, {
    String? assetPath,
    VoidCallback? onTap,
  }) {
    // Responsive image + label that shrinks on narrow cells to avoid overflow
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final maxW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.of(ctx).size.width / 2;
        // Ensure image fits within the available tile height to avoid vertical overflow
        final availH =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : double.infinity;
        final baseImg = (maxW * 0.5).clamp(24.0, 56.0);
        final maxImgByHeight = (availH - 22.0).clamp(24.0, 56.0);
        final imgSize = math.min(baseImg, maxImgByHeight);

        final imageBox = Container(
          width: imgSize,
          height: imgSize,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: assetPath != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      assetPath,
                      fit: BoxFit.cover,
                      width: imgSize,
                      height: imgSize,
                      errorBuilder: (c, e, s) =>
                          Icon(icon, size: imgSize * 0.5, color: accentGreen),
                    ),
                  )
                : Icon(icon, size: imgSize * 0.5, color: accentGreen),
          ),
        );

        final imageWidget = onTap != null
            ? InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: imageBox,
              )
            : imageBox;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: imgSize, height: imgSize, child: imageWidget),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.leaf,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top row with chat button on left and login/register or user menu on right
              Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.chat_bubble_outline,
                      color: AppColors.leaf,
                      size: 28,
                    ),
                    tooltip: 'รายงานปัญหา',
                    onPressed: () {
                      if (!auth.isLoggedIn) {
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('ต้องเข้าสู่ระบบก่อน'),
                            content: const Text(
                              'คุณยังไม่ได้เข้าสู่ระบบ กรุณาเข้าสู่ระบบหรือสมัครสมาชิกก่อนใช้ฟีเจอร์นี้',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  Navigator.of(context, rootNavigator: true).push(
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterLoginPage(),
                                    ),
                                  );
                                },
                                child: const Text('เข้าสู่ระบบ'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  Navigator.of(context, rootNavigator: true).push(
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterLoginPage(),
                                    ),
                                  );
                                },
                                child: const Text('สมัครสมาชิก'),
                              ),
                            ],
                          ),
                        );
                        return;
                      }

                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ReportProblemPage(),
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  Consumer<AuthService>(
                    builder: (ctx, auth, _) {
                      final style = TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      );
                      // If user is not logged in show login/register button
                      if (!auth.isLoggedIn) {
                        return TextButton(
                          onPressed: () {
                            Navigator.of(context, rootNavigator: true).push(
                              MaterialPageRoute(
                                builder: (_) => RegisterLoginPage(),
                              ),
                            );
                          },
                          child: const Text('เข้าสู่ระบบ/สมัครสมาชิก'),
                        );
                      }

                      // Logged-in user: keep popup with logout
                      return PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'change_password') {
                            Navigator.of(context, rootNavigator: true).push(
                              MaterialPageRoute(
                                builder: (_) => const ChangePasswordPage(),
                              ),
                            );
                            return;
                          }
                          if (value == 'logout') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('ยืนยัน'),
                                content: const Text(
                                  'คุณต้องการออกจากระบบหรือไม่?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('ไม่'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: const Text('ใช่'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              // Preserve persisted `auth_user` so saved selections remain visible after logout.
                              await auth.clearToken();
                              // Force rebuild of this State so Consumer re-evaluates
                              if (mounted) setState(() {});
                              if (!context.mounted) return;
                              Navigator.of(context, rootNavigator: true)
                                  .popUntil((route) => route.isFirst);
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'change_password',
                            child: Text('เปลี่ยนรหัสผ่าน'),
                          ),
                          PopupMenuItem(
                            value: 'logout',
                            child: Text('ออกจากระบบ'),
                          ),
                        ],
                        child: Builder(
                          builder: (ctx) {
                            final u = auth.user;
                            if (u != null) {
                              final username =
                                  u['username'] ??
                                  u['user'] ??
                                  u['name'] ??
                                  u['email'];
                              if (username != null &&
                                  username.toString().isNotEmpty) {
                                return Text(username.toString(), style: style);
                              }
                              final id = u['id'] ?? u['user_id'];
                              if (id != null) {
                                return Text('User $id', style: style);
                              }
                            }
                            return Text('User', style: style);
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Search box (controller + onSubmitted)
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: AppRadius.pill,
                  border: Border.all(color: AppColors.line),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        enabled: !auth.isGuestLocked,
                        decoration: const InputDecoration(
                          hintText: 'ค้นหา....',
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                        onSubmitted: _performSearch,
                        onChanged: _updateSuggestions,
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.search, size: 20),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Suggestions list shown while typing (constrained height to avoid overflow)
              if (_suggestions.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8.0),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: AppRadius.rMd,
                      boxShadow: AppShadow.card,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: _suggestions.map((c) {
                        final label = c['label'] as String;
                        final asset = c['asset'] as String?;
                        return ListTile(
                          leading: asset != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.asset(
                                    asset,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    errorBuilder: (ctx, err, st) {
                                      try {
                                        // ignore: avoid_print
                                        print(
                                          'Image.asset failed for $asset: $err',
                                        );
                                      } catch (_) {}
                                      return Icon(
                                        Icons.image,
                                        color: accentGreen,
                                      );
                                    },
                                  ),
                                )
                              : Icon(Icons.folder, color: accentGreen),
                          title: Text(
                            label,
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () {
                            FocusScope.of(context).unfocus();
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => c['page']),
                            );
                            setState(() => _suggestions = []);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),
              // Title
              Center(
                child: Text(
                  'หมวดหมู่ทั้งหมด',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // (removed top thumbnail strip; images are shown inside each category tile)
              const SizedBox(height: 12),
              // Grid of categories (responsive columns) -- expanded to fill remaining space
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final maxWidth = constraints.maxWidth;
                    // Desired approximate tile width (adjust to taste)
                    const double desiredTileW = 160.0;
                    // Use simple breakpoints so the grid doesn't spread too wide on large screens.
                    // - phone / narrow: 2 columns
                    // - tablet / medium: 3 columns
                    // - large desktop: also 3 columns (kept intentionally limited)
                    int crossAxis;
                    if (maxWidth <= 420) {
                      crossAxis = 2;
                    } else if (maxWidth <= 900) {
                      crossAxis = 3;
                    } else {
                      crossAxis = 3; // cap to 3 to avoid full-width spreading
                    }

                    // Build category widgets list
                    final categoryWidgets = [
                      categoryItem(
                        Icons.dashboard_outlined,
                        'แดชบอร์ด',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DashboardPage(
                              dashboardService: createDashboardService(),
                              mealLogService: createMealLogService(),
                              foodItemService: createFoodItemService(),
                            ),
                          ),
                        ),
                      ),
                      categoryItem(
                        Icons.restaurant_menu,
                        'คลาสอาหาร',
                        assetPath: 'assets/images/คลาสอาหาร.jpg',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ClassFoodPage()),
                        ),
                      ),
                      // 'เมนูอาหาร' ตัดออกจาก grid หน้าหลักตามที่ขอ — เป็น
                      // ฟังก์ชันซ้ำกับ 'คลาสอาหาร' เกือบ 100% (ดูสรุปที่คุย
                      // กันไปก่อนหน้า) ยังเข้าถึงได้ผ่านค้นหา/เมนู (ดู
                      // lib/app_categories.dart ที่ยังไม่ได้ตัดออก)
                      categoryItem(
                        Icons.assignment_ind,
                        'เลือกมื้ออาหารและระยะเวลา',
                        assetPath: 'assets/images/menufood.png',
                        onTap: () async {
                          final a = Provider.of<AuthService>(
                            context,
                            listen: false,
                          );
                          if (_canOpenMealPage(a)) {
                            startMealLogFlow(
                              context,
                              mealLogService: createMealLogService(),
                              foodItemService: createFoodItemService(),
                            );
                          } else {
                            try { await a.refreshProfile(); } catch (_) {}
                            if (!context.mounted) return;
                            if (_canOpenMealPage(a)) {
                              startMealLogFlow(
                                context,
                                mealLogService: createMealLogService(),
                                foodItemService: createFoodItemService(),
                              );
                            } else {
                              _showMissingDataDialog();
                            }
                          }
                        },
                      ),
                      // 'ประวัติการกรอกข้อมูล' ตัดออกจาก grid หน้าหลักตามที่
                      // ขอ — ซ้ำกับ tab "ประวัติ" ใน bottom nav อยู่แล้ว
                      // (ยังเข้าถึงได้ผ่านค้นหา/เมนู เหมือน 'เมนูอาหาร')
                      categoryItem(
                        Icons.assignment_ind,
                        'ตั้งค่าข้อมูลส่วนตัว',
                        assetPath: 'assets/images/การกรอกข้อมูล.jpg',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ProfilePage(),
                          ),
                        ),
                      ),
                    ];

                    // Constrain the grid's maximum width so tiles don't spread too far on very large screens
                    final gridMaxWidth =
                        (crossAxis * desiredTileW) +
                        ((crossAxis - 1) * 12) +
                        32;

                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: gridMaxWidth),
                        child: GridView.count(
                          shrinkWrap: false,
                          crossAxisCount: crossAxis,
                          childAspectRatio: 1.0,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          padding: const EdgeInsets.only(
                            bottom: 80,
                            left: 6,
                            right: 6,
                          ),
                          children: categoryWidgets,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // bottomNavigationBar ย้ายไปอยู่ที่ RootShell แล้ว (ดูด้านล่างของไฟล์นี้)
    // เพราะต้องเป็น bottom nav ถาวรที่คลุมทุก tab ไม่ใช่แค่หน้านี้หน้าเดียว
    // _showAllCategories/_navItem เดิมถูกลบ — แทนที่ด้วย CategoriesPage
    // (ปุ่ม "เมนู") และ SearchPage (ปุ่ม "ค้นหา") ที่ push เต็มหน้าแทน modal
    // sheet/focus-field เดิม (ดู lib/page/categories_page.dart, search_page.dart)
  }
}
