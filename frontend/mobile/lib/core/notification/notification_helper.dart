import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../../models/meal_log.dart';

/// จุดเดียวที่คุยกับ flutter_local_notifications ตรงๆ ในทั้งแอป — ที่อื่น
/// ห้ามเรียก plugin ตรง เรียกผ่าน static methods ของคลาสนี้เท่านั้น (กันโค้ด
/// ตั้งเวลา/ยกเลิก notification กระจายหลายที่จนซิงก์กันไม่ได้)
///
/// ขอบเขตที่ตั้งใจ: โปรเจกต์นี้ไม่มี Firebase/FCM — นี่คือ local notification
/// ที่ตั้งเวลาจากในเครื่องเท่านั้น ไม่ใช่การแจ้งเตือนที่รับประกันได้แม้ปิดแอป
/// สนิท (ดูรายละเอียดข้อจำกัดที่ [scheduleMealReminders])
class NotificationHelper {
  NotificationHelper._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // id คงที่ ห้ามสุ่ม — เพื่อให้ cancel/reschedule แทนที่ของเดิมถูกตัวเสมอ
  // ไม่ใช่สร้างซ้อนกันเรื่อยๆ ทุกครั้งที่เรียก
  static const int _idBreakfast = 9001;
  static const int _idLunch = 9002;
  static const int _idDinner = 9003;

  static int _idForMealType(MealType type) => switch (type) {
    MealType.breakfast => _idBreakfast,
    MealType.lunch => _idLunch,
    MealType.dinner => _idDinner,
  };

  static int _idForTicketReply(int reportId) => 9100 + (reportId % 900);

  static const AndroidNotificationDetails _mealChannelDetails =
      AndroidNotificationDetails(
        'meal_reminders',
        'เตือนมื้ออาหาร',
        channelDescription: 'แจ้งเตือนก่อนช่วงเวลาบันทึกมื้ออาหารจะปิด',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );

  static const AndroidNotificationDetails _ticketChannelDetails =
      AndroidNotificationDetails(
        'ticket_replies',
        'ข้อความจากแอดมิน',
        channelDescription: 'แจ้งเตือนเมื่อแอดมินตอบเรื่องที่แจ้งปัญหาไว้',
        importance: Importance.high,
        priority: Priority.high,
      );

  /// เริ่ม plugin + ตั้ง timezone ให้ตรงกับ backend เสมอ — เรียกครั้งเดียวพอ
  /// (เมธอดอื่นในคลาสนี้เรียก init() เองถ้ายังไม่เคย init มาก่อน)
  static Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    // ห้ามพึ่ง timezone ของเครื่องผู้ใช้ (tz.local จาก platform default) —
    // ต้องตรงกับ backend (Asia/Bangkok, UTC+7) เป๊ะเสมอไม่ว่าเครื่องจะตั้ง
    // โซนเวลาอะไรไว้ก็ตาม ไม่งั้นเวลาที่คำนวณ "30 นาทีก่อนมื้อปิด" จะเพี้ยน
    tz.setLocalLocation(tz.getLocation('Asia/Bangkok'));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      // ไม่ขอ permission ตรงนี้ตอน initialize — ขอแยกผ่าน requestPermission()
      // ตอนถึงจังหวะ UX ที่เหมาะสม (หลัง login สำเร็จ ไม่ใช่ตอนเปิดแอปครั้งแรก)
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    // งานนี้ระบุแค่ Android/iOS แต่โปรเจกต์นี้ build เป็น Windows desktop ด้วย
    // (เครื่องที่ใช้ทดสอบทั้ง session ไม่มี Android/iOS device จริง) —
    // ไม่ใส่ windows: แล้ว initialize() จะ throw ทันทีตอนรันบน Windows
    // (ทดสอบจริงแล้วเจอ) จึงต้องใส่ให้ครบกันแอป crash ตั้งแต่เปิด
    const windowsInit = WindowsInitializationSettings(
      appName: 'frontend',
      appUserModelId: 'com.example.frontend.NotificationHelper',
      guid: '8f14e45f-ceea-467e-bd36-6d3a7a5b1a2c',
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
        windows: windowsInit,
      ),
    );
    _initialized = true;
  }

  /// ขอ permission แจ้งเตือนจากผู้ใช้ — คืน true ถ้าอนุญาต
  static Future<bool> requestPermission() async {
    if (!_initialized) await init();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return false;
  }

  /// ตั้งเตือน "30 นาทีก่อนช่วงมื้อนั้นจะปิด" เฉพาะมื้อที่ (ก) ยังไม่เลย
  /// ช่วงเวลาไปแล้ว และ (ข) ยังไม่ logged วันนี้ — ยกเลิกของเดิมก่อนเสมอ
  /// แล้วค่อยตั้งใหม่ ป้องกันซ้อนกัน
  ///
  /// [loggedStatus] เช่น {'breakfast': true, 'lunch': false, 'dinner': false}
  /// — key ต้องเป็นค่าเดียวกับ MealType.apiValue ('breakfast'/'lunch'/'dinner')
  ///
  /// เป็น one-time schedule สำหรับ "วันนี้" เท่านั้น (ไม่ใช้ repeating
  /// notification) เพราะต้องเช็คเงื่อนไข logged/not-logged แบบไดนามิกทุกครั้ง
  /// ที่เรียก ซึ่ง repeating notification ของ plugin นี้ทำแบบมีเงื่อนไขไม่ได้
  /// (แค่ยิงซ้ำตามเวลาเปล่าๆ ไม่รู้ว่าผู้ใช้บันทึกมื้อนั้นไปหรือยัง)
  ///
  /// ข้อจำกัดที่ทราบแล้ว (ไม่ต้องแก้ อยู่นอกขอบเขตงานนี้): ฟังก์ชันนี้ถูก
  /// เรียกเฉพาะตอนแอป foreground เท่านั้น (initState + didChangeAppLifecycle
  /// State resumed ของ widget ที่ host bottom navigation) ถ้าผู้ใช้ไม่เปิด
  /// แอปเลยทั้งวัน จะไม่มีการเตือนเกิดขึ้น เพราะไม่มี server-side push (FCM)
  /// มา trigger การตั้งเวลาให้ตอนแอปปิดอยู่ — ต้องมี FCM ถึงจะรับประกันได้
  /// จริง ซึ่งเป็นงานแยกต่างหากนอกขอบเขต prompt นี้
  static Future<void> scheduleMealReminders(
    Map<String, bool> loggedStatus,
  ) async {
    if (!_initialized) await init();

    final now = tz.TZDateTime.now(tz.local);

    for (final type in MealType.values) {
      final key = type.apiValue;
      final logged = loggedStatus[key] ?? false;
      final window = kMealTimeWindows[type]!;
      final windowPassed = now.hour >= window.$2;
      final reminderTime = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        window.$2,
        0,
      ).subtract(const Duration(minutes: 30));

      // ยกเลิกของเดิมก่อนเสมอ ไม่ว่าจะตั้งใหม่ต่อหรือไม่ก็ตาม — กันเตือนค้าง
      // ถ้ามื้อนี้เพิ่ง logged/เลยเวลาไปแล้วหลังจากที่เคยตั้งไว้ก่อนหน้า
      await cancelMealReminder(key);

      if (logged || windowPassed || !reminderTime.isAfter(now)) continue;

      await _plugin.zonedSchedule(
        id: _idForMealType(type),
        title: 'ใกล้หมดเวลาบันทึกมื้อ${type.labelTh}แล้ว',
        body:
            'อย่าลืมบันทึกมื้อ${type.labelTh}ก่อน '
            '${window.$2.toString().padLeft(2, '0')}:00 น.',
        scheduledDate: reminderTime,
        notificationDetails: const NotificationDetails(
          android: _mealChannelDetails,
        ),
        // inexact พอ — เตือนล่วงหน้าไม่ต้องแม่นระดับวินาที และไม่ต้องขอ
        // SCHEDULE_EXACT_ALARM permission เพิ่ม (Play Store ตรวจเข้มกว่าปกติ
        // ถ้าขอ exact alarm โดยไม่มีเหตุผลจำเป็นจริงๆ)
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  /// ยกเลิกเตือนของมื้อนี้ทันที — เรียกทันทีหลัง POST /meal-logs หรือ
  /// PATCH eaten สำเร็จ ไม่ต้องรอรอบ schedule ถัดไป
  static Future<void> cancelMealReminder(String mealType) async {
    if (!_initialized) await init();
    await _plugin.cancel(id: _idForMealType(mealTypeFromApi(mealType)));
  }

  /// แจ้งเตือนทันทีว่าแอดมินตอบ ticket แล้ว — [reportId] ใช้คำนวณ
  /// notification id ตาม scheme (9100 + reportId % 900) กันแจ้งเตือนของ
  /// ticket คนละเรื่องมาทับ id เดียวกัน
  static Future<void> showTicketReplyNotification({
    required String title,
    required String preview,
    required int reportId,
  }) async {
    if (!_initialized) await init();
    await _plugin.show(
      id: _idForTicketReply(reportId),
      title: title,
      body: preview,
      notificationDetails: const NotificationDetails(
        android: _ticketChannelDetails,
      ),
    );
  }

  static Future<void> cancelAll() async {
    if (!_initialized) await init();
    await _plugin.cancelAll();
  }
}
