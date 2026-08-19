import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/notification/notification_helper.dart';
import '../models/app_error.dart';
import '../models/food_item.dart';
import '../models/meal_log.dart';
import '../models/result.dart';
import 'auth_service.dart';
import 'data_events.dart';
import 'typed_api_client.dart';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// ผลของ [MealLogService.getOrCreateLog] — แยกให้ชัดว่ามื้อนี้เพิ่งสร้างใหม่
/// หรือมีอยู่แล้ว (backend ตอบ 409) เพื่อให้ UI แจ้งข้อความที่ต่างกันได้
@immutable
class MealLogFetchOutcome {
  final MealLog log;
  final bool alreadyExisted;
  const MealLogFetchOutcome({required this.log, required this.alreadyExisted});
}

/// สัญญา (interface) ของ service บันทึกมื้ออาหาร — คุย /meal-logs* จริง
abstract class MealLogService {
  /// สร้าง log มื้อนี้ของวันนี้ (หรือวันที่ระบุ) — ถ้ามีอยู่แล้ว (409) จะคืน
  /// log เดิมกลับมาแทนที่จะ error ทิ้งไปเฉยๆ (ผู้ใช้ยังกดเพิ่มเมนูต่อได้)
  /// [MealLogFetchOutcome.alreadyExisted] บอกว่าเจอ 409 หรือสร้างสำเร็จใหม่
  Future<Result<MealLogFetchOutcome>> getOrCreateLog({required MealType mealType, DateTime? date});

  /// [notify] = false ข้าม `MealLogEvents.changed()` — ใช้ตอนเรียกเป็น loop
  /// หลายรายการรวด (เช่น ยืนยันตะกร้าหลายเมนูใน FoodBrowserPage) กันแต่ละ
  /// รายการยิง event รีเฟรชทั้งแอปซ้ำจนถล่ม dev server ผู้เรียกที่ทำแบบนี้
  /// ต้องเรียก `MealLogEvents.instance.changed()` เองครั้งเดียวหลัง loop จบ
  Future<Result<MealLog>> addItem({
    required int logId,
    required int foodItemId,
    int? servingSizeId,
    double quantity,
    bool notify = true,
  });

  /// [notify] — ดูเหตุผลเดียวกับ [addItem]
  Future<Result<MealLog>> markItemEaten(int itemId, {bool notify = true});

  /// ยกเลิก "ทานแล้ว" ได้ภายใน 5 นาทีหลังกด — เกินเวลาแล้ว backend คืน
  /// 400 EATEN_UNDO_EXPIRED (โผล่เป็น ServerError ที่มีข้อความจริงจาก server
  /// อยู่แล้ว ดู models/app_error.dart)
  Future<Result<MealLog>> undoItemEaten(int itemId);

  /// ลบเมนูที่เลือกผิด/อยากเปลี่ยนออกจากมื้อ — ใช้ตอน "แก้ไขเมนู" ของมื้อที่
  /// บันทึกไปแล้ว (ดู MealSelectSheet) ไม่จำกัดเวลาเหมือน undoItemEaten
  Future<Result<MealLog>> deleteItem(int itemId);

  Future<Result<List<MealLog>>> fetchLogs({DateTime? date, DateTime? from, DateTime? to});

  /// เมนูล่าสุดที่เคยเลือก (ไม่ซ้ำ) เรียงจากมื้อล่าสุดก่อน — ใช้ทำแถว "ล่าสุด"
  /// บน FoodBrowserPage ให้เลือกซ้ำเมนูเดิมได้เร็วโดยไม่ต้องค้นหาใหม่
  Future<Result<List<FoodItem>>> fetchRecentItems({int limit = 5});
}

class HttpMealLogService implements MealLogService {
  final TypedApiClient _client;
  const HttpMealLogService(this._client);

  @override
  Future<Result<MealLogFetchOutcome>> getOrCreateLog({
    required MealType mealType,
    DateTime? date,
  }) async {
    final result = await _client.postJson<MealLog>(
      '/meal-logs',
      body: {
        'meal_type': mealType.apiValue,
        if (date != null) 'log_date': _ymd(date),
      },
      decode: (json) => MealLog.fromJson(json as Map<String, dynamic>),
    );
    final Result<MealLogFetchOutcome> outcome = result.when(
      ok: (log) => Ok(MealLogFetchOutcome(log: log, alreadyExisted: false)),
      err: (error) {
        // 409 = บันทึกมื้อนี้ไว้แล้ว — ใช้ log เดิมต่อแทนที่จะดันเป็น error
        if (error is ConflictError && error.body is Map) {
          final existing = (error.body as Map)['meal_log'];
          if (existing is Map<String, dynamic>) {
            return Ok(MealLogFetchOutcome(log: MealLog.fromJson(existing), alreadyExisted: true));
          }
        }
        return Err(error);
      },
    );
    if (outcome is Ok<MealLogFetchOutcome>) {
      MealLogEvents.instance.changed();
      // มื้อนี้ถูกบันทึกแล้ว (สร้างใหม่ หรือมีอยู่แล้วก็ตาม) — ยกเลิกเตือนทันที
      // ไม่ต้องรอรอบ schedule ถัดไป (จุดเดียวที่ POST /meal-logs สำเร็จเสมอ
      // ไม่ว่าเรียกจากหน้าไหน กันไม่ต้อง hook ซ้ำหลายจุด)
      unawaited(NotificationHelper.cancelMealReminder(outcome.value.log.mealType.apiValue));
    }
    return outcome;
  }

  @override
  Future<Result<MealLog>> addItem({
    required int logId,
    required int foodItemId,
    int? servingSizeId,
    double quantity = 1.0,
    bool notify = true,
  }) async {
    final result = await _client.postJson<MealLog>(
      '/meal-logs/$logId/items',
      body: {
        'food_item_id': foodItemId,
        if (servingSizeId != null) 'serving_size_id': servingSizeId,
        'quantity': quantity,
      },
      decode: (json) => MealLog.fromJson(json as Map<String, dynamic>),
    );
    if (result is Ok<MealLog> && notify) MealLogEvents.instance.changed();
    return result;
  }

  @override
  Future<Result<MealLog>> markItemEaten(int itemId, {bool notify = true}) async {
    final result = await _client.patchJson<MealLog>(
      '/meal-log-items/$itemId/eaten',
      decode: (json) => MealLog.fromJson(json as Map<String, dynamic>),
    );
    if (result is Ok<MealLog>) {
      if (notify) MealLogEvents.instance.changed();
      unawaited(NotificationHelper.cancelMealReminder(result.value.mealType.apiValue));
    }
    return result;
  }

  @override
  Future<Result<MealLog>> undoItemEaten(int itemId) async {
    final result = await _client.patchJson<MealLog>(
      '/api/meal-log-items/$itemId/undo-eaten',
      decode: (json) => MealLog.fromJson(json as Map<String, dynamic>),
    );
    if (result is Ok<MealLog>) MealLogEvents.instance.changed();
    return result;
  }

  @override
  Future<Result<MealLog>> deleteItem(int itemId) async {
    final result = await _client.deleteJson<MealLog>(
      '/meal-log-items/$itemId',
      decode: (json) => MealLog.fromJson(json as Map<String, dynamic>),
    );
    if (result is Ok<MealLog>) MealLogEvents.instance.changed();
    return result;
  }

  @override
  Future<Result<List<MealLog>>> fetchLogs({DateTime? date, DateTime? from, DateTime? to}) {
    final params = <String, String>{
      if (date != null) 'date': _ymd(date),
      if (from != null) 'from': _ymd(from),
      if (to != null) 'to': _ymd(to),
    };
    final query = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
    return _client.getJson<List<MealLog>>(
      '/meal-logs$query',
      decode: (json) => ((json as Map<String, dynamic>)['meal_logs'] as List)
          .map((l) => MealLog.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<Result<List<FoodItem>>> fetchRecentItems({int limit = 5}) {
    return _client.getJson<List<FoodItem>>(
      '/api/meal-logs/recent-items?limit=$limit',
      decode: (json) => ((json as Map<String, dynamic>)['items'] as List)
          .map((i) => FoodItem.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
}

MealLogService createMealLogService() {
  final client = TypedApiClient(tokenProvider: () => AuthService().token);
  return HttpMealLogService(client);
}
