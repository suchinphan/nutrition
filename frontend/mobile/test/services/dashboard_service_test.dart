import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:frontend/models/app_error.dart';
import 'package:frontend/models/dashboard_data.dart';
import 'package:frontend/models/result.dart';
import 'package:frontend/services/dashboard_service.dart';
import 'package:frontend/services/typed_api_client.dart';

/// http.Client ปลอมที่คืนค่าที่กำหนดไว้ล่วงหน้า — ไม่ยิง network จริง
/// (ไม่ต้องเพิ่ม package mock ใหม่ package:http เปิดให้ extend BaseClient ได้ตรงๆ)
class _FakeClient extends http.BaseClient {
  final int statusCode;
  final String body;
  final Duration? delay;
  _FakeClient({required this.statusCode, required this.body, this.delay});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (delay != null) await Future.delayed(delay!);
    return http.StreamedResponse(Stream.value(utf8.encode(body)), statusCode);
  }
}

// รูปแบบ JSON ตรงกับ GET /dashboard/summary จริง (ดู backend/api.py
// _dashboard_summary_for_user) — schema ใหม่ตัด weight_delta_kg/sodium/
// sugar ออก (ไม่มีตารางเก็บประวัติย้อนหลังให้คำนวณ) และแยก planned/eaten
// ชัดเจนแทน calories_consumed เดี่ยวๆ แบบเดิม
Map<String, dynamic> _validDashboardJson() => {
  'eaten_calories': 1400.0,
  'planned_calories': 1650.0,
  'calories_goal': 2000.0,
  'meals': [
    {'meal_type': 'breakfast', 'status': 'logged'},
  ],
  'weight_kg': 65.0,
  'bmi': 22.0,
  'bmi_status': 'ปกติ',
  'last_7_days': [
    {'date': '2026-07-13', 'eaten_calories': 1800.0},
  ],
};

HttpDashboardService _serviceWith({
  required int statusCode,
  required String body,
  Duration? delay,
  Duration timeout = const Duration(seconds: 10),
}) {
  final client = TypedApiClient(
    baseUrl: 'http://test.local',
    client: _FakeClient(statusCode: statusCode, body: body, delay: delay),
    timeout: timeout,
  );
  return HttpDashboardService(client);
}

void main() {
  group('HttpDashboardService.fetchDashboard', () {
    test('success: 200 + valid json -> Ok(DashboardData)', () async {
      final service = _serviceWith(
        statusCode: 200,
        body: jsonEncode(_validDashboardJson()),
      );

      final result = await service.fetchDashboard('u1');

      expect(result, isA<Ok<DashboardData>>());
      result.when(
        ok: (data) {
          expect(data.caloriesConsumed, 1400.0);
          expect(data.meals.single.status, MealStatus.done);
          expect(data.bmiStatus, BmiStatus.normal);
          expect(data.last7Days, hasLength(1));
        },
        err: (e) => fail('expected Ok, got error: ${e.toUserMessage()}'),
      );
    });

    test('network timeout -> Err(NetworkError)', () async {
      final service = _serviceWith(
        statusCode: 200,
        body: '{}',
        delay: const Duration(milliseconds: 200),
        timeout: const Duration(milliseconds: 30),
      );

      final result = await service.fetchDashboard('u1');

      result.when(
        ok: (_) => fail('expected Err(NetworkError)'),
        err: (e) => expect(e, isA<NetworkError>()),
      );
    });

    test('server 500 -> Err(ServerError(500, ...))', () async {
      final service = _serviceWith(
        statusCode: 500,
        body: jsonEncode({'error': 'internal error'}),
      );

      final result = await service.fetchDashboard('u1');

      result.when(
        ok: (_) => fail('expected Err(ServerError)'),
        err: (e) {
          expect(e, isA<ServerError>());
          final serverError = e as ServerError;
          expect(serverError.code, 500);
          expect(serverError.message, 'internal error');
        },
      );
    });

    test('malformed json body -> Err(ParseError)', () async {
      final service = _serviceWith(statusCode: 200, body: 'not-json-at-all');

      final result = await service.fetchDashboard('u1');

      result.when(
        ok: (_) => fail('expected Err(ParseError)'),
        err: (e) => expect(e, isA<ParseError>()),
      );
    });

    test('valid json but missing required field -> Err(ParseError)', () async {
      final incomplete = _validDashboardJson()..remove('bmi');
      final service = _serviceWith(
        statusCode: 200,
        body: jsonEncode(incomplete),
      );

      final result = await service.fetchDashboard('u1');

      result.when(
        ok: (_) => fail('expected Err(ParseError)'),
        err: (e) => expect(e, isA<ParseError>()),
      );
    });

    test('401 -> Err(AuthError)', () async {
      final service = _serviceWith(
        statusCode: 401,
        body: jsonEncode({'error': 'invalid or expired token'}),
      );

      final result = await service.fetchDashboard('u1');

      result.when(
        ok: (_) => fail('expected Err(AuthError)'),
        err: (e) => expect(e, isA<AuthError>()),
      );
    });
  });

  group('MockDashboardService.fetchDashboard', () {
    test('default -> Ok with sample data', () async {
      const service = MockDashboardService();
      final result = await service.fetchDashboard('u1');
      expect(result, isA<Ok<DashboardData>>());
    });

    test('simulateError -> Err(NetworkError)', () async {
      const service = MockDashboardService(simulateError: true);
      final result = await service.fetchDashboard('u1');
      result.when(
        ok: (_) => fail('expected Err'),
        err: (e) => expect(e, isA<NetworkError>()),
      );
    });

    test('simulateEmpty -> Ok with empty data', () async {
      const service = MockDashboardService(simulateEmpty: true);
      final result = await service.fetchDashboard('u1');
      result.when(
        ok: (data) => expect(data.isEmpty, isTrue),
        err: (e) => fail('expected Ok, got error: ${e.toUserMessage()}'),
      );
    });
  });
}
