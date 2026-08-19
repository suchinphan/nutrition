// removed unused import: dart:convert
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'auth_service.dart';

class ApiResponse {
  final int statusCode;
  final String body;
  ApiResponse(this.statusCode, this.body);
}

class ApiClient {
  final String baseUrl;
  final Dio _dio;
  final Map<String, CancelToken> _tokens = {};

  ApiClient(this.baseUrl)
      : _dio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));

  /// Cancel any previous request associated with [cancelKey] and start a new one.
  void _replaceCancelToken(String? cancelKey, CancelToken token) {
    if (cancelKey == null) return;
    try {
      final prev = _tokens[cancelKey];
      if (prev != null && !prev.isCancelled) {
        prev.cancel('cancelled-by-new-request');
      }
    } catch (_) {}
    _tokens[cancelKey] = token;
  }

  Future<ApiResponse> get(
    String path, {
    Map<String, String>? headers,
    int timeoutSeconds = 8,
    String? cancelKey,
  }) async {
    return _send('GET', path, headers: headers, timeoutSeconds: timeoutSeconds, cancelKey: cancelKey);
  }

  Future<ApiResponse> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
    int timeoutSeconds = 8,
    String? cancelKey,
  }) async {
    return _send('POST', path, headers: headers, body: body, timeoutSeconds: timeoutSeconds, cancelKey: cancelKey);
  }

  Future<ApiResponse> _send(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
    int timeoutSeconds = 8,
    String? cancelKey,
  }) async {
    final authToken = AuthService().token;
    final bool isMultipart = body is FormData;
    final h = <String, String>{
      if (headers != null) ...headers,
      if (!isMultipart) 'Content-Type': 'application/json',
    };
    final skipAuth = headers != null && (headers['X-Skip-Auth'] == '1' || headers['X-Skip-Auth'] == 'true');
    if (h.containsKey('X-Skip-Auth')) h.remove('X-Skip-Auth');
    if (!skipAuth && authToken != null && !h.containsKey('Authorization')) {
      h['Authorization'] = 'Bearer $authToken';
    }

    final uri = '$baseUrl$path';
    final token = CancelToken();
    _replaceCancelToken(cancelKey, token);

    // Guard: common mistake is calling '/user/' without an id — return a clear ApiResponse
    try {
      final p = path.toString();
      if (p == '/user' || p == '/user/' || RegExp(r'^/user\/?\s*\$').hasMatch(p)) {
        if (kDebugMode) debugPrint('ApiClient: prevented request to $uri (missing user id)');
        return ApiResponse(400, jsonEncode({'error': 'missing_user_id'}));
      }
    } catch (_) {}

    try {
      // Log request metadata. For POST we will log the definitive JSON
      // later to avoid interleaved/duplicated output that can look corrupted.
      if (kDebugMode) {
        if (method == 'POST') {
          debugPrint('ApiClient: POST $uri headers=$h');
        } else {
          String bodyPreview = '';
          try {
            if (body == null) {
              bodyPreview = '';
            } else if (body is String) {
              bodyPreview = body;
            } else {
              bodyPreview = jsonEncode(body);
            }
          } catch (_) {
            bodyPreview = body.toString();
          }
          debugPrint('ApiClient: $method $uri headers=$h body=$bodyPreview');
        }
      }

      Response resp;
      if (method == 'POST') {
        // For safety, when the caller provides a Map/List, produce the
        // definitive JSON string here via jsonEncode and send that exact
        // string as the body. This guarantees the bytes sent match the
        // logged preview and avoids any intermediate mutation.
        dynamic dataToSend = body;
        String finalJson = '';
        try {
          if (body is FormData) {
            dataToSend = body;
          } else if (body is Map || body is List) {
            finalJson = jsonEncode(body);
            dataToSend = finalJson;
          } else if (body is String) {
            finalJson = body;
            try {
              jsonDecode(finalJson);
            } catch (_) {}
          } else if (body == null) {
            dataToSend = null;
          } else {
            try {
              finalJson = jsonEncode(body);
              dataToSend = finalJson;
            } catch (_) {
              dataToSend = body;
            }
          }
        } catch (_) {
          dataToSend = body;
        }
        if (finalJson.isNotEmpty && kDebugMode) {
          debugPrint('ApiClient: final JSON body to send=$finalJson');
          try {
            final parsed = jsonDecode(finalJson);
            if (parsed is Map<String, dynamic>) {
              parsed.forEach((kk, vv) {
                try {
                  debugPrint('ApiClient: send key="$kk" codeUnits=${kk.toString().codeUnits}');
                } catch (_) {}
                if (vv is String) {
                  try {
                    debugPrint('ApiClient: send value for "$kk" codeUnits=${vv.codeUnits}');
                  } catch (_) {}
                }
              });
            }
          } catch (_) {}
        }
        final opts = Options(
          method: 'POST',
          headers: h,
          contentType: body is FormData ? null : Headers.jsonContentType,
        );
        resp = await _dio.request(path,
          data: dataToSend,
          options: opts,
          cancelToken: token);
      } else {
        final opts = Options(method: 'GET', headers: h, contentType: Headers.jsonContentType);
        resp = await _dio.request(path,
          options: opts,
          cancelToken: token);
      }

      final bodyStr = resp.data is String ? resp.data as String : jsonEncode(resp.data);
      if (kDebugMode) debugPrint('ApiClient: response ${resp.statusCode} body=$bodyStr');
      return ApiResponse(resp.statusCode ?? 0, bodyStr);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        if (kDebugMode) debugPrint('ApiClient: request cancelled $method $uri');
        return ApiResponse(0, '');
      }

      // Only a 401 with a token we actually sent means the *session* itself
      // is dead (expired/revoked) — clear it so the app can present a login
      // flow. A 403 is a business-rule/authorization failure (e.g. "not your
      // resource", "admin only", "already used") that has nothing to do with
      // session validity, and a 401 with no token attached just means this
      // particular request forgot to send one — neither should nuke a
      // perfectly valid saved session.
      try {
        final status = e.response?.statusCode ?? 0;
        if (status == 401 && authToken != null && authToken.isNotEmpty) {
          if (kDebugMode) debugPrint('ApiClient: received $status — clearing local token');
          try {
            await AuthService().clearToken(force: true);
          } catch (_) {}
        }
        if (status == 401 || status == 403) {
          final bodyStr = e.response?.data is String
              ? e.response?.data as String
              : (e.response?.data != null ? jsonEncode(e.response?.data) : '');
          return ApiResponse(status, bodyStr);
        }
      } catch (_) {}

      if (kDebugMode) debugPrint('ApiClient: DioException $e');
      rethrow;
    } on TimeoutException {
      if (kDebugMode) debugPrint('ApiClient: request timeout $method $uri');
      rethrow;
    }
  }
}