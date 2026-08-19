import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/app_error.dart';
import '../models/result.dart';

// หมายเหตุสถาปัตยกรรม: โปรเจคนี้มี lib/services/api_client.dart (class ApiClient
// แบบ dio) อยู่แล้ว และหน้าจออื่นๆ อีกหลายหน้าเรียกใช้อยู่ (main.dart,
// choose_food_type_page.dart, login_page.dart ฯลฯ) จึงตั้งชื่อไฟล์/คลาสนี้ว่า
// TypedApiClient แทนที่จะทับชื่อเดิม เพื่อไม่ต้องแก้โค้ด UI หน้าอื่นที่ใช้
// ApiClient เดิมอยู่ (ขัดกับเงื่อนไข "ห้ามแตะ UI widget ใดๆ ในงานนี้")

/// อ่าน base URL จาก --dart-define=API_URL ก่อนเสมอ ถ้าไม่ระบุ fallback ตาม
/// platform (Android emulator เข้าถึง localhost ของเครื่อง host ผ่าน 10.0.2.2
/// เสมอ ต่างจาก Windows/iOS ที่ใช้ localhost ตรงๆ ได้)
class ApiConfig {
  ApiConfig._();

  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    // แก้จาก 8000 เป็น 5000: ตรวจ backend/api.py จริงแล้วพบว่าเป็น Flask ที่รัน
    // app.run(port=5000) ไม่ใช่ 8000 ตามที่สมมติไว้ตอนแรก — ให้ตรงกับ
    // getApiBase() ใน services/app_config.dart ที่ทั้งแอปใช้อยู่แล้วจริงๆ
    return defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:5000'
        : 'http://localhost:5000';
  }
}

/// HTTP client กลางที่ทุก method คืน [Result] แทนการปล่อย exception ดิบขึ้นไป
/// ถึง UI — รับ [http.Client] และ [tokenProvider] ผ่าน constructor (DI) เพื่อให้
/// mock ได้ตรงๆ ใน unit test โดยไม่ต้องพึ่ง network จริงหรือ AuthService singleton
class TypedApiClient {
  final String baseUrl;
  final http.Client _client;
  final String? Function() tokenProvider;
  final Duration timeout;

  TypedApiClient({
    String? baseUrl,
    http.Client? client,
    String? Function()? tokenProvider,
    this.timeout = const Duration(seconds: 10),
  }) : baseUrl = baseUrl ?? ApiConfig.baseUrl,
       _client = client ?? http.Client(),
       tokenProvider = tokenProvider ?? (() => null);

  /// GET ที่ decode response body เป็น [T] ผ่าน [decode] ที่ผู้เรียกกำหนดเอง
  Future<Result<T>> getJson<T>(
    String path, {
    required T Function(dynamic json) decode,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final requestHeaders = _buildHeaders(headers);
    _log('-> GET $uri');
    try {
      final response = await _client
          .get(uri, headers: requestHeaders)
          .timeout(timeout);
      return _handleResponse<T>(response, decode);
    } on TimeoutException {
      _log('<- GET $uri timed out after $timeout');
      return const Err(NetworkError());
    } on SocketException {
      _log('<- GET $uri socket error');
      return const Err(NetworkError());
    } catch (e) {
      _log('<- GET $uri unexpected error: $e');
      return const Err(NetworkError());
    }
  }

  /// GET ที่คืนไบต์ดิบตรงๆ (ไม่ decode เป็น JSON) — ใช้กับ endpoint ที่ตอบไฟล์
  /// แนบกลับมา เช่น /api/export/history (CSV/PDF)
  Future<Result<Uint8List>> getBytes(String path, {Map<String, String>? headers}) async {
    final uri = Uri.parse('$baseUrl$path');
    final requestHeaders = _buildHeaders(headers);
    _log('-> GET(bytes) $uri');
    try {
      final response = await _client.get(uri, headers: requestHeaders).timeout(timeout);
      _log('<- ${response.statusCode} (${response.bodyBytes.length} bytes)');
      if (response.statusCode == 401 || response.statusCode == 403) {
        return const Err(AuthError());
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return Err(ServerError(response.statusCode, _extractMessage(utf8.decode(response.bodyBytes, allowMalformed: true))));
      }
      return Ok(response.bodyBytes);
    } on TimeoutException {
      _log('<- GET $uri timed out after $timeout');
      return const Err(NetworkError());
    } on SocketException {
      _log('<- GET $uri socket error');
      return const Err(NetworkError());
    } catch (e) {
      _log('<- GET $uri unexpected error: $e');
      return const Err(NetworkError());
    }
  }

  /// POST ที่ decode response body เป็น [T] ผ่าน [decode] — คืน [ConflictError]
  /// แยกจาก [ServerError] เมื่อได้ 409 (เช่น POST /meal-logs ซ้ำมื้อ/วันเดียวกัน)
  /// เพื่อให้ผู้เรียกดึงข้อมูลเดิมจาก body ไปใช้ต่อได้โดยไม่ต้องยิงซ้ำ
  Future<Result<T>> postJson<T>(
    String path, {
    Object? body,
    required T Function(dynamic json) decode,
    Map<String, String>? headers,
  }) => _sendJson('POST', path, body: body, decode: decode, headers: headers);

  Future<Result<T>> patchJson<T>(
    String path, {
    Object? body,
    required T Function(dynamic json) decode,
    Map<String, String>? headers,
  }) => _sendJson('PATCH', path, body: body, decode: decode, headers: headers);

  Future<Result<T>> deleteJson<T>(
    String path, {
    Object? body,
    required T Function(dynamic json) decode,
    Map<String, String>? headers,
  }) => _sendJson('DELETE', path, body: body, decode: decode, headers: headers);

  Future<Result<T>> _sendJson<T>(
    String method,
    String path, {
    Object? body,
    required T Function(dynamic json) decode,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final requestHeaders = _buildHeaders(headers);
    final encodedBody = body == null ? null : jsonEncode(body);
    _log('-> $method $uri');
    try {
      final request = http.Request(method, uri)..headers.addAll(requestHeaders);
      if (encodedBody != null) request.body = encodedBody;
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      return _handleResponse<T>(response, decode);
    } on TimeoutException {
      _log('<- $method $uri timed out after $timeout');
      return const Err(NetworkError());
    } on SocketException {
      _log('<- $method $uri socket error');
      return const Err(NetworkError());
    } catch (e) {
      _log('<- $method $uri unexpected error: $e');
      return const Err(NetworkError());
    }
  }

  Map<String, String> _buildHeaders(Map<String, String>? extra) {
    final token = tokenProvider();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (extra != null) ...extra,
    };
  }

  Result<T> _handleResponse<T>(
    http.Response response,
    T Function(dynamic json) decode,
  ) {
    _log('<- ${response.statusCode} (${response.body.length} bytes)');
    if (response.statusCode == 401 || response.statusCode == 403) {
      return const Err(AuthError());
    }
    if (response.statusCode == 409) {
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }
      return Err(ConflictError(decoded));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return Err(
        ServerError(response.statusCode, _extractMessage(response.body)),
      );
    }
    try {
      final json = jsonDecode(response.body);
      return Ok(decode(json));
    } catch (_) {
      return const Err(ParseError());
    }
  }

  String _extractMessage(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json['message'] is String) {
        return json['message'] as String;
      }
      if (json is Map && json['error'] is String) {
        return json['error'] as String;
      }
    } catch (_) {
      // body ไม่ใช่ JSON — ใช้ทั้งก้อนเป็นข้อความแทน
    }
    return body;
  }

  void _log(String message) {
    // log request/response เฉพาะตอน debug เท่านั้น ตามที่กำหนด
    if (kDebugMode) debugPrint('TypedApiClient: $message');
  }

  void dispose() => _client.close();
}
