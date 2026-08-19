import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';
import 'dart:io';
import 'dart:async';
import 'api_client.dart';
import 'package:dio/dio.dart';
import 'app_config.dart';

/// Dio โยน DioException ทิ้งทุก non-2xx (ยกเว้น 401/403 ที่ ApiClient ดักคืน
/// ApiResponse ปกติแล้ว) ทำให้ error message จริงจาก backend (เช่น "invalid
/// otp", "กรอกรหัสผิดเกิน 5 ครั้ง กรุณาขอรหัส OTP ใหม่") หายไปเหลือแค่
/// "request failed" ทั่วๆ ไป (ผู้ใช้รายงานจริง — เห็นแต่ "request failed" ไม่
/// รู้ว่าจริงๆ ผิดกี่ครั้งไปแล้ว/ต้องขอ OTP ใหม่หรือยัง) — แกะ body ที่ Dio
/// แนบมากับ exception ออกมาดึงข้อความจริงแทน
String? _extractServerErrorMessage(dynamic responseData) {
  try {
    final parsed = responseData is String ? jsonDecode(responseData) : responseData;
    if (parsed is Map) {
      final msg = parsed['error'] ?? parsed['message'];
      if (msg != null) return msg.toString();
    }
  } catch (_) {}
  return null;
}

class AuthService with ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal() {
    // Kick off background cleanup of any previously renamed/locked secure files
    // so leftover `.deleted_<timestamp>` files don't accumulate.
    unawaited(_cleanupRenamedSecureFiles());
  }

  final StorageService _storage = StorageService();
  String? _token;
  Map<String, dynamic>? _user;
  // Track whether loadToken has already printed to avoid noisy repeated logs
  bool _loadedOnce = false;
  bool _isGuest = false;
  bool _guestUsed = false;
  DateTime? _guestSelectionUntil;
  String? _anonId;
  Map<String, dynamic>? _guestPersonal;
  Map<String, dynamic>? _guestSelections;

  String _authUserKeyForId(dynamic id) {
    if (id == null) return 'auth_user';
    try {
      final s = id.toString();
      if (s.isEmpty) return 'auth_user';
      return 'auth_user_$s';
    } catch (_) {
      return 'auth_user';
    }
  }

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  bool get isGuest => _isGuest;
  bool get guestUsed => _guestUsed;

  bool get isGuestLocked {
    if (!_isGuest) return false;
    // If there's a selection expiry set, consider the lock active only
    // while the expiry is in the future.
    if (_guestSelectionUntil != null) {
      if (!DateTime.now().toUtc().isBefore(_guestSelectionUntil!)) {
        return false;
      }
    } else {
      if (!_guestUsed) return false;
    }

    final Map<String, dynamic>? p = _guestPersonal;
    if (p == null) return false;
    try {
      final g = (p['gender'] ?? '').toString().trim();
      final a = (p['age'] ?? '').toString().trim();
      final w = (p['weight'] ?? '').toString().trim();
      final h = (p['height'] ?? '').toString().trim();
      return g.isNotEmpty && a.isNotEmpty && w.isNotEmpty && h.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool get canUseGuest => _isGuest && !_guestUsed;

  Future<void> loadToken({bool force = false}) async {
    // main() ใน main.dart await loadToken() ครั้งเดียวไว้ให้แล้วตั้งแต่ก่อน
    // runApp() — แต่ RootShell/HistoryPage/ProfilePage ฯลฯ ทุกหน้าเรียก
    // loadToken() ซ้ำอีกใน initState/_init ของตัวเอง เดิมไม่มีการข้าม เลย
    // อ่าน flutter_secure_storage พร้อมกันหลายหน้าตอนแอปเพิ่งเปิด (ทุกแท็บใน
    // IndexedStack build state พร้อมกันหมด) การอ่านบน Windows เป็นๆ ถอยๆ ได้
    // (DPAPI CryptUnprotectData glitch —ดู comment เดิมด้านล่าง) พอมีหลาย
    // หน้าแย่งกันอ่านพร้อมกัน แต่ละหน้า resolve ไม่พร้อมกันแล้วยิง
    // notifyListeners() ของตัวเอง ทำให้ทั้งแอป rebuild ถี่ๆ ตอนเปิด เห็นเป็น
    // จอกะพริบสลับหน้าหลายรอบก่อนจะนิ่ง (บั๊กที่ผู้ใช้รายงานจริง) — ข้ามการ
    // อ่านซ้ำถ้าโหลดไปแล้วรอบนึง เว้นแต่ผู้เรียกตั้งใจสั่ง force:true จริงๆ
    if (_loadedOnce && !force) return;
    try {
      // 1. โหลด Token เดิมที่เก็บไว้ในเครื่อง
      // loadToken() is re-run every time a page like History reopens, and
      // flutter_secure_storage reads can transiently fail/return empty on
      // Windows (DPAPI CryptUnprotectData glitches — see StorageService).
      // A momentary empty read must NOT nuke a token we already have live
      // in memory, or a working session gets silently logged out.
      try {
        final stored = await _storage.read(key: 'auth_token');
        if (stored != null && stored.isNotEmpty) {
          _token = stored;
        } else {
          _token ??= stored;
        }
      } catch (e) {
        // Keep whatever token is already in memory; only a real read
        // failure with nothing cached in memory means we're logged out.
        await _handleSecureStorageError(e);
      }

      // 2. ดึงข้อมูล User จาก storage (ถ้ามี) เพื่อให้ _user คืนค่าหลังจากเปิดแอป
      try {
        final String? userStr = await _storage.read(key: 'auth_user');
        if (userStr != null && userStr.isNotEmpty) {
          _user = jsonDecode(userStr) as Map<String, dynamic>?;
        }
      } catch (e) {
        // Keep whatever user is already in memory on a transient read error.
        await _handleSecureStorageError(e);
      }

      // 3. โหลดค่าอื่นๆ ของระบบตามเดิม (anon id, guest selections)
      try {
        _anonId = await _storage.read(key: 'anon_id');
      } catch (e) { await _handleSecureStorageError(e); }

      try {
        final gs = await _storage.read(key: 'auth_guest_selections');
        if (gs != null && gs.isNotEmpty) {
          try {
            final parsedG = jsonDecode(gs) as Map<String, dynamic>?;
            // If guest selections are tagged to a user_id, ensure they
            // belong to the currently loaded user; otherwise discard.
            final storedUid = parsedG?['user_id']?.toString();
            final currentUid = _user == null ? null : _user!['id']?.toString();
            if (parsedG != null && (storedUid == null || currentUid == null || storedUid == currentUid)) {
              _guestSelections = parsedG;
            } else {
              _guestSelections = null;
            }
          } catch (_) {
            _guestSelections = null;
          }
        } else {
          // backward compatibility: check older key
          final gs2 = await _storage.read(key: 'guest_selections');
          if (gs2 != null && gs2.isNotEmpty) {
            try {
              final parsedG2 = jsonDecode(gs2) as Map<String, dynamic>?;
              _guestSelections = parsedG2;
            } catch (_) {
              _guestSelections = null;
            }
          }
        }
      } catch (e) { await _handleSecureStorageError(e); }

      // Load persisted guest personal info so activity and medical fields survive restarts
      try {
        final gp = await _storage.read(key: 'auth_guest_personal');
        if (gp != null && gp.isNotEmpty) {
          try {
            final parsedGP = jsonDecode(gp) as Map<String, dynamic>?;
            _guestPersonal = parsedGP;
          } catch (_) {
            _guestPersonal = null;
          }
        }
      } catch (e) {
        await _handleSecureStorageError(e);
      }

      // Load persisted temporary selections (from recent UI saves)
      try {
        final ts = await _storage.read(key: 'auth_temp_selections');
        if (ts != null && ts.isNotEmpty) {
          try {
            final parsed = jsonDecode(ts) as Map<String, dynamic>?;
            final storedUid = parsed?['user_id']?.toString();
            final currentUid = _user == null ? null : _user!['id']?.toString();
            if (parsed != null && (storedUid == null || currentUid == null || storedUid == currentUid)) {
              _tempSelections = parsed;
            } else {
              if (kDebugMode) debugPrint('AuthService.loadToken: discarded auth_temp_selections for other user');
              _tempSelections = null;
            }
          } catch (_) {
            _tempSelections = null;
          }
        }
      } catch (_) {}

      _loadedOnce = true;
      if (kDebugMode) debugPrint('AuthService: loadToken completed. hasToken=${_token != null} hasUser=${_user != null}');
    } catch (e) {
      debugPrint('AuthService.loadToken ERROR: $e');
    }
    notifyListeners();
  }

  /// Compatibility: called by some pages via `dynamic` casts.
  /// Extensions are not callable via `dynamic`, so provide a real
  /// instance method to avoid `NoSuchMethodError` at runtime.
  Future<void> markUserSavedSubmission() async {
    try {
      final token = _token ?? await _storage.read(key: 'auth_token');
      Map<String, dynamic>? userMap = _user;
      if (userMap == null) {
        final userJson = await _storage.read(key: 'auth_user');
        if (userJson != null && userJson.isNotEmpty) {
          try {
            userMap = jsonDecode(userJson) as Map<String, dynamic>?;
          } catch (_) {
            userMap = null;
          }
        }
      }
      final intId = userMap == null ? null : int.tryParse((userMap['id'] ?? userMap['user_id'] ?? '').toString());
      if (token == null || token.isEmpty || intId == null) return;
      final api = ApiClient(getApiBase());
      await api.post('/user/$intId/mark-saved', headers: {'Authorization': 'Bearer $token'}, body: <String, dynamic>{}, timeoutSeconds: 3);
    } catch (_) {}
  }

  Future<void> saveToken(String token) async {
    _token = token;
    try {
      await _storage.write(key: 'auth_token', value: token);
      debugPrint('AuthService.saveToken: wrote auth_token');
    } catch (e) {
      debugPrint('AuthService.saveToken ERROR: $e');
    }
    _isGuest = false;
    _guestUsed = false;
    await _storage.delete(key: 'auth_guest');
    await _storage.delete(key: 'auth_guest_used');
    notifyListeners();
  }

  /// [syncToServer] = false ข้ามขั้นตอนส่ง PATCH ฟิลด์โปรไฟล์ที่อนุญาต
  /// (name/gender/weight/... ) กลับไปเซิร์ฟเวอร์ซ้ำ — ใช้ตอนแค่อยาก merge
  /// ข้อมูลที่เซิร์ฟเวอร์อัปเดตให้แล้วจริงๆ เข้า local state (เช่นหลังอัปโหลด
  /// avatar ที่ endpoint อื่นเซฟให้เสร็จแล้ว) ไม่งั้นจะมี POST `/user/{id}`
  /// ซ้ำอีกรอบโดยไม่จำเป็น เสี่ยง race กับข้อมูลที่เพิ่งได้มา
  /// Returns false when a server sync was attempted but failed (network
  /// error or non-2xx) — the local/offline save above still happened, but
  /// callers that report "saved" to the user should check this: on false,
  /// the edit only lives on-device and a later refreshProfile()/GET will
  /// overwrite it with the server's stale (pre-edit) value, silently
  /// reverting what the user just entered (ผู้ใช้รายงานจริง: กรอกโรค
  /// ประจำตัว/แพ้อาหารแล้วเห็น snackbar "บันทึกแล้ว" แต่กลับมาหน้าเดิม
  /// ข้อมูลหายไป — สาเหตุคือ error จาก sync ถูก debugPrint เงียบๆ ไม่ส่งต่อ
  /// ให้ผู้เรียกรู้เลย). Returns true when no sync was needed/attempted
  /// (guest, no token, syncToServer:false) since there is nothing to fail.
  Future<bool> saveUser(Map<String, dynamic> u, {bool syncToServer = true}) async {
    bool syncOk = true;
    // 1. ดึงข้อมูล User ปัจจุบันจาก RAM ก่อน
    Map<String, dynamic>? existing = _user;
    
    // ถ้าใน RAM ไม่มี ให้พยายามอ่านจาก Storage (เผื่อแอปเพิ่งเปิด)
    if (existing == null) {
      try {
        final userJson = await _storage.read(key: 'auth_user');
        if (userJson != null && userJson.isNotEmpty) {
          existing = jsonDecode(userJson) as Map<String, dynamic>?;
        }
      } catch (_) {}
    }

    // 2. ตรวจสอบ ID ของคนเก่า และคนใหม่ที่ส่งมา
    final oldId = existing?['id']?.toString() ?? existing?['user_id']?.toString() ?? existing?['userid']?.toString();
    final newId = u['id']?.toString() ?? u['user_id']?.toString() ?? u['userid']?.toString();

    final Map<String, dynamic> merged = {};

    // --- ส่วนแก้ไขสำคัญ: Logic การตัดสินใจว่าจะ Merge หรือเริ่มใหม่ ---
    if (existing != null) {
      // ถ้ามี ID ใหม่ส่งมา และ ID นั้นไม่ตรงกับคนเดิม -> ให้ "เริ่มใหม่" (Clear ของเก่า)
      if (newId != null && oldId != null && newId != oldId) {
        debugPrint('AuthService.saveUser: Different User ID ($newId != $oldId). Clearing old data.');
        // ไม่ใส่ existing เข้าไปใน merged เพื่อล้างขยะของคนเก่าทิ้ง
      } else {
        // ถ้าเป็นคนเดิม หรือข้อมูลใหม่ไม่ได้ส่ง ID มา (เช่นมาจากหน้ามื้ออาหาร) -> ให้ "Merge ต่อ"
        merged.addAll(existing);
        debugPrint('AuthService.saveUser: Same user or partial update. Merging data.');
      }
    }

    // 3. เอาข้อมูลใหม่ (u) ทับลงไป
    u.forEach((key, value) {
      if (value != null) {
        if (value is String && value.trim().isEmpty) return;
        merged[key] = value;
      }
    });

    // 4. บันทึกผลลัพธ์ลง RAM และ Storage
    _user = Map<String, dynamic>.from(merged);
    final encoded = jsonEncode(_user);
    
    try {
      // บันทึกที่ key หลัก
      try {
        await _storage.write(key: 'auth_user', value: encoded);
      } catch (e) {
        await _handleSecureStorageError(e);
        // Try again after cleanup
        try { await _storage.write(key: 'auth_user', value: encoded); } catch (_) {}
      }
      
      // บันทึกแยกตาม ID เพื่อป้องกันคนอื่นมาทับ (Permanent Storage)
      final useId = newId ?? oldId;
      if (useId != null) {
        final perKey = _authUserKeyForId(useId);
        try {
          await _storage.write(key: perKey, value: encoded);
          await _storage.write(key: 'auth_user_last_id', value: useId.toString());
        } catch (e) {
          await _handleSecureStorageError(e);
          try { await _storage.write(key: perKey, value: encoded); } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('AuthService.saveUser Storage Error: $e');
      await _handleSecureStorageError(e);
    }

    // 5. ส่งข้อมูลไปอัปเดตที่ Backend (Server)
    try {
      final token = _token;
      if (syncToServer && token != null && _user != null) {
        final idVal = _user!['id'] ?? _user!['user_id'] ?? _user!['userid'];
        final intId = idVal == null ? null : int.tryParse(idVal.toString());

        if (intId != null) {
          // เตรียม Data เฉพาะที่จำเป็นต้องส่ง — age/bmi/bmi_status ไม่ส่งอีก
          // ต่อไปแล้ว (backend ใหม่คำนวณสดเสมอ ไม่รับค่าจาก client) และ
          // health_goal ย้ายไปมี endpoint แยกของตัวเองแล้ว (POST
          // /api/user/health-goal ดู saveHealthGoal ด้านล่าง)
          final Map<String, dynamic> dataToSend = {
            'name': _user!['name'],
            'surname': _user!['surname'],
            'gender': _user!['gender'],
            // Ensure date_of_birth sent in ISO YYYY-MM-DD (AD)
            'date_of_birth': (() {
              try {
                final dob = _user!['date_of_birth'];
                if (dob == null) return null;
                if (dob is DateTime) return dob.toIso8601String().split('T').first;
                final s = dob.toString().trim();
                // If already ISO-like yyyy-mm-dd, try parsing
                final tryIso = DateTime.tryParse(s);
                if (tryIso != null) return tryIso.toIso8601String().split('T').first;
                // Accept dd/MM/yyyy or d/M/yyyy -> convert
                if (s.contains('/')) {
                  final parts = s.split('/').map((p) => p.trim()).toList();
                  if (parts.length >= 3) {
                    final d = int.tryParse(parts[0]) ?? 1;
                    final m = int.tryParse(parts[1]) ?? 1;
                    int y = int.tryParse(parts[2]) ?? DateTime.now().year;
                    // Heuristic: Buddhist Era year (>2400) -> convert to AD
                    if (y > 2400) y = y - 543;
                    try {
                      final dt = DateTime(y, m, d);
                      return dt.toIso8601String().split('T').first;
                    } catch (_) {
                      return null;
                    }
                  }
                }
                return null;
              } catch (_) {
                return null;
              }
            })(),
            'weight': _user!['weight'],
            'height': _user!['height'],
            'activity_level': _user!['activity_level'],
          };

          // chronic_diseases/food_allergies: ส่งเฉพาะตอนที่ _user มีค่าเป็น
          // List จริง (แปลว่าผู้เรียก saveUser() ตั้งใจส่งมาอัปเดต เช่น
          // ProfilePage._saveProfile()) — ห้าม default เป็น [] เหมือนฟิลด์
          // อื่นแล้วส่งไปทับ เพราะ 'chronic_diseases' in data ฝั่ง backend
          // ถือว่า [] คือ "ตั้งใจล้างค่า" เหมือนกับค่าจริง ถ้า _user ไม่มี
          // ฟิลด์นี้เลย (เช่น login_page.dart เรียก saveUser({id,username,
          // email}) ทันทีหลัง login ก่อนดึง full profile) ต้องไม่ส่ง key นี้
          // ไปเลย ไม่งั้นจะไปล้างข้อมูลที่มีอยู่แล้วในเซิร์ฟเวอร์ทันที (บั๊กที่
          // ผู้ใช้รายงานจริง: บันทึกโรคประจำตัว/แพ้อาหารไว้ พอ logout แล้ว
          // login ใหม่ข้อมูลหายหมด)
          if (_user!['chronic_diseases'] is List) {
            dataToSend['chronic_diseases'] = _user!['chronic_diseases'];
          }
          if (_user!['food_allergies'] is List) {
            dataToSend['food_allergies'] = _user!['food_allergies'];
          }

          // ลบค่าที่เป็น null ออกก่อนส่ง
          dataToSend.removeWhere((k, v) => v == null);

          if (dataToSend.isNotEmpty) {
            final api = ApiClient(getApiBase());
            final resp = await api.post(
              '/user/$intId',
              headers: {'Authorization': 'Bearer $token'},
              body: dataToSend,
              timeoutSeconds: 5,
            );

            // ถ้า Server ตอบกลับข้อมูลอัปเดตล่าสุดมา ให้เก็บลงเครื่องด้วย
            if (resp.statusCode >= 200 && resp.statusCode < 300) {
              if (resp.body.isNotEmpty) {
                final Map<String, dynamic> remote = jsonDecode(resp.body);
                // อัปเดตข้อมูลที่ Server คำนวณให้กลับลง RAM
                remote.forEach((key, value) {
                  if (value != null) _user![key] = value;
                });
                // บันทึกลง Storage อีกครั้งหลัง Merge จาก Server
                await _storage.write(key: 'auth_user', value: jsonEncode(_user));
                // If server-returned temporary lock has already expired,
                // clear it and reset user selections so the UI becomes editable.
                try {
                  final rawUntil = _user!['temporary_lock_until'];
                  if (rawUntil != null) {
                    final parsed = _parseFlexibleDate(rawUntil.toString());
                    if (parsed != null) {
                      // Normalize stored format to ISO so subsequent reads are consistent
                      _user!['temporary_lock_until'] = parsed.toUtc().toIso8601String();
                      if (DateTime.now().toUtc().isAfter(parsed.toUtc())) {
                        if (kDebugMode) debugPrint('AuthService.saveUser: detected expired temporary lock -> clearing');
                        await clearUserTemporaryLockAndReset();
                      }
                    }
                  }
                } catch (_) {}
              }
            } else {
              syncOk = false;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('AuthService.saveUser Remote Sync Error: $e');
      syncOk = false;
    }

    notifyListeners();
    return syncOk;
  }

  /// อัปโหลดรูปโปรไฟล์ — รับ [imageBytes] ตรงๆ (เช่นผลลัพธ์จากหน้า crop วงกลม
  /// ที่ตัดมาแล้ว) แทนการรับ File เพื่อไม่ต้องเขียนไฟล์ชั่วคราวลงดิสก์ก่อน
  /// คืน error message (String) ถ้าไม่สำเร็จ, null ถ้าสำเร็จ (สำเร็จแล้วจะ
  /// merge avatar_url ใหม่เข้า _user + notifyListeners ให้เองผ่าน saveUser
  /// เพื่อให้ UI ที่ผูกกับ AuthService รีเฟรชรูปทันที)
  Future<String?> uploadAvatar(Uint8List imageBytes) async {
    final token = _token;
    final idVal = _user?['id'] ?? _user?['user_id'] ?? _user?['userid'];
    final intId = idVal == null ? null : int.tryParse(idVal.toString());
    if (token == null || token.isEmpty || intId == null) {
      return 'กรุณาเข้าสู่ระบบก่อนอัปโหลดรูป';
    }

    try {
      final api = ApiClient(getApiBase());
      final formData = FormData.fromMap({
        'avatar': MultipartFile.fromBytes(imageBytes, filename: 'avatar.jpg'),
      });
      final resp = await api.post(
        '/user/$intId/avatar',
        headers: {'Authorization': 'Bearer $token'},
        body: formData,
        timeoutSeconds: 20,
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body.isNotEmpty) {
        final Map<String, dynamic> remote = jsonDecode(resp.body);
        // syncToServer: false — endpoint นี้เซฟ avatar_url ที่เซิร์ฟเวอร์ให้
        // เสร็จแล้ว ไม่ต้องให้ saveUser() ยิง POST /user/<id> ซ้ำอีกรอบ (ของเดิม
        // ยิงซ้ำเสมอ เสี่ยง response ที่สองมาช้ากว่าหรือ merge ทับ avatar_url
        // ที่เพิ่งได้จนดูเหมือนอัปโหลดแล้วไม่อัปเดต)
        await saveUser(remote, syncToServer: false);
        return null;
      }
      try {
        final j = jsonDecode(resp.body);
        if (j is Map && j['error'] != null) return j['error'].toString();
      } catch (_) {}
      return 'อัปโหลดรูปไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
    } catch (e) {
      debugPrint('AuthService.uploadAvatar ERROR: $e');
      return 'ไม่สามารถติดต่อเซิร์ฟเวอร์ได้';
    }
  }

  Future<void> saveGuest() async {
    try {
      _isGuest = true;
      try {
        await _storage.write(key: 'auth_guest', value: '1');
        debugPrint('AuthService.saveGuest: persisted auth_guest=1');
      } catch (e) {
        debugPrint('AuthService.saveGuest: failed to persist auth_guest: $e');
      }
      _guestUsed = false;
      if (_anonId == null) {
        final rnd = Random();
        _anonId =
            '${DateTime.now().millisecondsSinceEpoch}_${rnd.nextInt(1 << 31)}';
      }
    } catch (e) {
      debugPrint('AuthService.saveGuest ERROR: $e');
    }
    notifyListeners();
  }

  Future<void> clearGuest() async {
    debugPrint('AuthService.clearGuest: clearing guest-only state');
    _guestUsed = false;
    _guestPersonal = null;
    _guestSelections = null;
    _anonId = null;
    try {
      await _storage.delete(key: 'auth_guest');
      await _storage.delete(key: 'auth_guest_used');
      await _storage.delete(key: 'auth_guest_personal');
      await _storage.delete(key: 'auth_guest_selections');
      debugPrint('AuthService.clearGuest: removed persisted guest markers');
    } catch (e) {
      debugPrint('AuthService.clearGuest ERROR: $e');
    }
    _isGuest = false;
    notifyListeners();
  }

  Future<void> _handleSecureStorageError(Object e) async {
    try {
      final msg = e.toString();
      debugPrint('AuthService: secure storage error detected: $msg');
      // If the platform-specific secure storage file path appears in the message,
      // try to extract and delete it. Common error contains full path to .dat
      final regex = RegExp(r'([A-Za-z]:\\[^\n\r]+?\.dat)', caseSensitive: false);
      final match = regex.firstMatch(msg);
      if (match != null) {
        final path = match.group(1);
        if (path != null) {
          try {
            final f = File(path);
            if (await f.exists()) {
              // Retry a few times if file is locked by another process
              int attempts = 0;
              while (attempts < 6) {
                try {
                  await f.delete();
                  debugPrint('AuthService: deleted corrupt secure file: $path');
                  break;
                } catch (ex) {
                  attempts += 1;
                  // If last attempt, log and rethrow
                  if (attempts >= 6) {
                    debugPrint('AuthService: failed deleting secure file $path after retries: $ex');
                    // Fallback: try renaming the locked file so the original path
                    // is freed for future writes and the file can be removed later.
                    try {
                      final newPath = '$path.deleted_${DateTime.now().millisecondsSinceEpoch}';
                      final renamed = await f.rename(newPath);
                      debugPrint('AuthService: renamed locked secure file to ${renamed.path}');
                    } catch (renameEx) {
                      debugPrint('AuthService: failed renaming locked secure file $path: $renameEx');
                    }
                    break;
                  }
                  // Wait a bit and retry
                  await Future.delayed(const Duration(milliseconds: 200));
                }
              }
            }
          } catch (ex) {
            debugPrint('AuthService: failed deleting secure file $path: $ex');
          }
        }
      } else {
        // Try common Roaming path for flutter_secure_storage
        try {
          final userProfile = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
          if (userProfile != null && userProfile.isNotEmpty) {
            final candidate = '${Directory(userProfile).path}${Platform.pathSeparator}AppData${Platform.pathSeparator}Roaming';
            // Search for flutter_secure_storage.dat under roaming
            final roam = Directory(candidate);
            if (await roam.exists()) {
              final files = roam.listSync(recursive: true).whereType<File>();
              for (final f in files) {
                if (f.path.toLowerCase().endsWith('flutter_secure_storage.dat')) {
                  try {
                    int attempts = 0;
                    while (attempts < 6) {
                      try {
                        await f.delete();
                        debugPrint('AuthService: deleted corrupt secure file: ${f.path}');
                        break;
                      } catch (ex) {
                        attempts += 1;
                        if (attempts >= 6) {
                            debugPrint('AuthService: failed deleting secure file ${f.path} after retries: $ex');
                            try {
                              final newPath = '${f.path}.deleted_${DateTime.now().millisecondsSinceEpoch}';
                              final renamed = await f.rename(newPath);
                              debugPrint('AuthService: renamed locked secure file to ${renamed.path}');
                            } catch (renameEx) {
                              debugPrint('AuthService: failed renaming locked secure file ${f.path}: $renameEx');
                            }
                          break;
                        }
                        await Future.delayed(const Duration(milliseconds: 200));
                      }
                    }
                    break;
                  } catch (ex) {
                    debugPrint('AuthService: failed deleting secure file ${f.path}: $ex');
                  }
                }
              }
            }
          }
        } catch (_) {}
      }

      // As a last resort, DO NOT automatically delete all secure storage keys
      // (doing so causes the app to lose persisted auth and log the user out).
      // Instead, attempt to preserve the `auth_token` in memory so the UI
      // remains signed-in while the app can surface a recovery path to the user.
      try {
        try {
          final all = await _storage.readAll();
          if (_token == null && all.containsKey('auth_token')) {
            _token = all['auth_token'];
            debugPrint('AuthService: preserved auth_token in memory after secure storage error');
          }
        } catch (ex) {
          debugPrint('AuthService: failed to read backup keys: $ex');
        }

        // Mark that secure storage may be compromised so caller code can
        // show a user-facing recovery (not implemented here). We avoid
        // deleting everything automatically to prevent data loss.
        debugPrint('AuthService: secure storage error handled; manual recovery may be required');
      } catch (ex) {
        debugPrint('AuthService: unexpected during secure-storage fallback: $ex');
      }
    } catch (_) {}
  }

  Future<void> _cleanupRenamedSecureFiles() async {
    try {
      final userProfile = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (userProfile == null || userProfile.isEmpty) return;
      final candidate = '${Directory(userProfile).path}${Platform.pathSeparator}AppData${Platform.pathSeparator}Roaming';
      final roam = Directory(candidate);
      if (!await roam.exists()) return;
      await for (final entity in roam.list(recursive: true, followLinks: false)) {
        try {
          if (entity is File) {
            final p = entity.path.toLowerCase();
            if (p.contains('flutter_secure_storage.dat.deleted_') || p.contains('flutter_secure_storage.dat.deleted')) {
              try {
                await entity.delete();
                debugPrint('AuthService: cleanup removed renamed secure file: ${entity.path}');
              } catch (ex) {
                debugPrint('AuthService: cleanup failed removing ${entity.path}: $ex');
              }
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> handleAuthSuccess(String token, Map<String, dynamic> u) async {
    // --- จุดที่ต้องเพิ่ม/แก้ไขบรรทัดนี้ ---
    await clearToken(force: true); 
    // ---------------------------------

    await clearGuest();
    _isGuest = false;
    await saveToken(token);

    try {
      final idVal = u['id'] ?? u['user_id'] ?? u['userid'];
      final intId = idVal == null ? null : int.tryParse(idVal.toString());
      if (intId != null) {
        final api = ApiClient(getApiBase());
        try {
          final resp = await api.get('/user/$intId');
          if (resp.statusCode == 200) {
            final Map<String, dynamic> full = jsonDecode(resp.body);

            // เพิ่ม: ล้างค่าในตัวแปร RAM ก่อนเซฟ
            _user = null;
            // syncToServer: false — [full] เพิ่ง GET มาจาก server ตรงๆ ไม่ต้อง
            // POST เซฟกลับไปซ้ำ (ผู้ใช้รายงานจริง: สมัครสมาชิกกรอกชื่อ-นามสกุล
            // เสร็จ backend ยังไม่ได้ชื่อ-นามสกุลตอนนี้เพราะ /register ไม่รับ
            // ฟิลด์นี้ RegisterPage เลยต้องเรียก saveUser({name, surname}) แยก
            // อีกรอบทันทีหลังจากนี้ — ถ้า saveUser(full) ตรงนี้ sync กลับไปหา
            // server ด้วย (ของเดิม) กลายเป็นยิง POST ไปพร้อมกัน 2 ก้อนแข่งกัน
            // (ก้อนนี้ยังไม่มีชื่อ-นามสกุลเพราะ full ตอนนี้ยังไม่มี ก้อนของ
            // RegisterPage มีชื่อ-นามสกุลจริง) — ผ่าน Flask dev server แบบ
            // single-threaded คำขอไหนตอบกลับ/ประมวลผลก่อนหลังไม่แน่นอน ถ้าก้อน
            // นี้ (ไม่มีชื่อ-นามสกุล) ประมวลผลทีหลังก้อนที่มีชื่อ-นามสกุลจริง
            // จะไปเขียนทับชื่อ-นามสกุลที่เพิ่งบันทึกถูกต้องกลับเป็นค่างเปล่า
            // ทันที (บั๊กที่ผู้ใช้รายงานจริง) — ข้อมูลที่เพิ่ง GET มาจาก server
            // เองไม่มีเหตุผลต้อง POST กลับไปหา server อยู่แล้วในทุกกรณี
            await saveUser(full, syncToServer: false);
            notifyListeners();
            return;
          }
        } catch (e) {
          debugPrint('Profile fetch error: $e');
        }
      }
    } catch (_) {}

    // Fallback: ล้างค่าในตัวแปร RAM ก่อนเซฟ
    _user = null; 
    await saveUser(u);
    notifyListeners();
  }

  /// Fetch full profile from server (if token+id available) and persist.
  Future<bool> refreshProfile() async {
    try {
      final tokenLocal = _token ?? await _storage.read(key: 'auth_token');
      if (tokenLocal == null || tokenLocal.isEmpty) return false;
      Map<String, dynamic>? userMap = _user;
      if (userMap == null) {
        final userJson = await _storage.read(key: 'auth_user');
        if (userJson != null && userJson.isNotEmpty) {
          try {
            userMap = jsonDecode(userJson) as Map<String, dynamic>?;
          } catch (_) {
            userMap = null;
          }
        }
      }
      final idVal = userMap == null ? null : (userMap['id'] ?? userMap['user_id'] ?? userMap['userid']);
      final intId = idVal == null ? null : int.tryParse(idVal.toString());
      if (intId == null) return false;
      final api = ApiClient(getApiBase());
      final resp = await api.get('/user/$intId');
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        try {
          final Map<String, dynamic> full = jsonDecode(resp.body) as Map<String, dynamic>;
          // syncToServer: false — เหตุผลเดียวกับใน handleAuthSuccess() ด้านบน:
          // [full] เพิ่ง GET มาจาก server ตรงๆ ไม่มีเหตุผลต้อง POST เซฟกลับไป
          // ซ้ำ (ยิ่งอันตรายเพราะ refreshProfile() ถูกเรียกพร่ำเพรื่อกว่า
          // handleAuthSuccess มาก — เช่น ProfilePage._init() เรียกทุกครั้งที่
          // เปิดหน้า — ยิ่งเปิดช่องให้ POST คู่แข่งกับการบันทึกจริงที่กำลัง
          // ทำอยู่พร้อมกันบ่อยขึ้น เขียนทับข้อมูลที่เพิ่งบันทึกด้วยของเก่า)
          await saveUser(full, syncToServer: false);
          return true;
        } catch (_) {
          return false;
        }
      }
    } catch (_) {}
    return false;
  }

  String? get anonId => _anonId;
  Map<String, dynamic>? get guestPersonal => _guestPersonal;
  Map<String, dynamic>? get guestSelections => _guestSelections;
  DateTime? get guestSelectionUntil => _guestSelectionUntil;
  Map<String, dynamic>? _tempPersonal;
  Map<String, dynamic>? _tempSelections;

  Map<String, dynamic>? get tempPersonal => _tempPersonal;
  Map<String, dynamic>? get tempSelections => _tempSelections;

  void setTempPersonal(Map<String, dynamic> p) {
    _tempPersonal = Map<String, dynamic>.from(p);
    notifyListeners();
  }

  void setTempSelections(Map<String, dynamic> s) {
    _tempSelections = Map<String, dynamic>.from(s);
    try {
      // Ensure temp selections are tagged with the current user id when
      // a user is logged in. This prevents selections from one account
      // being reused by another account.
      try {
        if (_user != null && _user!['id'] != null) {
          _tempSelections!['user_id'] = _user!['id'];
        }
      } catch (_) {}

      final encoded = jsonEncode(_tempSelections);
      _storage.write(key: 'auth_temp_selections', value: encoded);
      debugPrint('AuthService.setTempSelections: persisted auth_temp_selections');
    } catch (_) {}
    notifyListeners();
  }

  Future<void> saveGuestPersonal(Map<String, dynamic> p) async {
    _guestPersonal = Map<String, dynamic>.from(p);
    try {
      final encoded = jsonEncode(_guestPersonal);
      await _storage.write(key: 'auth_guest_personal', value: encoded);
      debugPrint(
        'AuthService.saveGuestPersonal: persisted auth_guest_personal',
      );
    } catch (e) {
      debugPrint('AuthService.saveGuestPersonal ERROR: $e');
    }
    notifyListeners();
  }

  Future<void> saveGuestSelections(Map<String, dynamic> s) async {
    // 🔒 ป้องกัน guest ใช้ซ้ำ
    // Deprecated: prefer saveGuestSelectionsWithExpiry to set temporary lock
    if (_guestUsed) {
      debugPrint('Guest already used — skip saving selections');
      return;
    }

    _guestSelections = Map<String, dynamic>.from(s);
    try {
      final encoded = jsonEncode(_guestSelections);
      await _storage.write(key: 'auth_guest_selections', value: encoded);
    } catch (_) {}
    notifyListeners();
  }

  /// Save guest selections with an expiry datetime so the selection lock
  /// is temporary. `until` should be an absolute UTC datetime.
  Future<void> saveGuestSelectionsWithExpiry(
      Map<String, dynamic> s, DateTime until) async {
    _guestSelections = Map<String, dynamic>.from(s);
    _guestSelectionUntil = until.toUtc();
    _guestUsed = true;
    try {
      final encoded = jsonEncode(_guestSelections);
      await _storage.write(key: 'auth_guest_selections', value: encoded);
      await _storage.write(
          key: 'auth_guest_selection_until', value: _guestSelectionUntil!.toIso8601String());
      await _storage.write(key: 'auth_guest_used', value: '1');
      debugPrint('AuthService.saveGuestSelectionsWithExpiry: persisted selections + expiry');
    } catch (e) {
      debugPrint('AuthService.saveGuestSelectionsWithExpiry ERROR: $e');
    }
    notifyListeners();
  }

  Future<void> ensureAnonId() async {
    if (_anonId != null) return;
    final rnd = Random();
    _anonId =
        '${DateTime.now().millisecondsSinceEpoch}_${rnd.nextInt(1 << 31)}';
  }

  Future<void> markGuestUsed() async {
    if (!_isGuest) return;
    if (_guestUsed) return;
    _guestUsed = true;
    try {
      await _storage.write(key: 'auth_guest_used', value: '1');
      debugPrint('AuthService.markGuestUsed: persisted auth_guest_used=1');
    } catch (e) {
      debugPrint('AuthService.markGuestUsed ERROR: $e');
    }
    notifyListeners();
  }

  Future<void> resetGuestUsed() async {
    _guestUsed = false;
    try {
      await _storage.delete(key: 'auth_guest_used');
      debugPrint(
        'AuthService.resetGuestUsed: removed persisted auth_guest_used',
      );
    } catch (e) {
      debugPrint('AuthService.resetGuestUsed ERROR: $e');
    }
    notifyListeners();
  }

  // Returns whether the current persisted user is locked (server-side or local flag)
  bool get userLocked {
    try {
      if (_user == null) return false;
      final v = _user!['health_goal_locked'];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v.toLowerCase() == 'true' || v != '0';
      // fallback to manual flag stored on user map
      final manual = _user!['userLocked'];
      if (manual is bool) return manual;
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Whether the server reports a temporary (system-wide) lock for selections
  bool get temporaryLocked {
    try {
      if (_user == null) return false;
      final v = _user!['temporary_locked'];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v.toLowerCase() == 'true' || v != '0';
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markUserLocked() async {
    try {
      if (_user == null) return;
      _user = Map<String, dynamic>.from(_user!);
      _user!['userLocked'] = true;
      try {
        final enc = jsonEncode(_user);
        await _storage.write(key: 'auth_user', value: enc);
        try {
          final idValLocal = _user?['id'] ?? _user?['user_id'] ?? _user?['userid'];
          if (idValLocal != null) {
            final perKeyLocal = _authUserKeyForId(idValLocal);
            await _storage.write(key: perKeyLocal, value: enc);
          }
        } catch (_) {}
      } catch (_) {}
      notifyListeners();
    } catch (_) {}
  }

  /// Clear the local/manual user lock written by `markUserLocked()`.
  /// This is used by the meal/duration submission flow to convert a
  /// previously set permanent local lock into a server-controlled
  /// temporary lock (if the backend returns one).
  Future<void> clearUserLocked() async {
    try {
      if (_user == null) return;
      _user = Map<String, dynamic>.from(_user!);
      if (_user!.containsKey('userLocked')) _user!.remove('userLocked');
      try {
        final enc = jsonEncode(_user);
        await _storage.write(key: 'auth_user', value: enc);
        try {
          final idValLocal = _user?['id'] ?? _user?['user_id'] ?? _user?['userid'];
          if (idValLocal != null) {
            final perKeyLocal = _authUserKeyForId(idValLocal);
            await _storage.write(key: perKeyLocal, value: enc);
          }
        } catch (_) {}
      } catch (_) {}
      notifyListeners();
    } catch (_) {}
  }

  /// Returns whether selections/goals are effectively locked right now.
  /// Considers server-side `health_goal_locked`, manual `userLocked`, and
  /// server `temporary_locked` with `temporary_lock_until` expiry.
  /// ตรวจสอบว่าขณะนี้ User ถูกล็อกหรือไม่
  bool get effectivelyLocked {
    try {
      if (_user == null) return false;

      // 1. เช็คจาก Server (ตัวแปรใหม่ที่เราเพิ่มใน Backend)
      final bool serverHealthLock = _user!['health_goal_locked'] == true || 
                                   _user!['health_goal_locked'] == 1 ||
                                   _user!['health_goal_locked'] == "1";
      if (serverHealthLock) return true;

      // 2. เช็คจาก Local Lock (ที่เขียนลงเครื่องเองด้วย markUserLocked)
      final bool manualLock = _user!['userLocked'] == true;
      if (manualLock) return true;

      // 3. เช็คระบบ Lock ชั่วคราวแบบมีวันหมดอายุ
      if (temporaryLocked) {
        final raw = _user!['temporary_lock_until'];
        if (raw != null) {
          final dt = _parseFlexibleDate(raw.toString());
          if (dt != null) {
            return DateTime.now().toUtc().isBefore(dt.toUtc());
          }
        }
        return true; // ถ้ามี flag แต่ไม่มีเวลาหมดอายุ ให้ล็อกไว้ก่อน
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markGuestSelectionLocked() async {
    try {
      if (!_isGuest) return;
      _guestUsed = true;
      try {
        await _storage.write(key: 'auth_guest_used', value: '1');
      } catch (_) {}
      notifyListeners();
    } catch (_) {}
  }

  // backward-compatible method used by UI code
  bool isUserLocked() {
    return userLocked;
  }

  Future<void> clearToken({bool force = false}) async {
  // 1. ถ้าไม่ใช่ guest หรือสั่ง force ให้ทำงานต่อ
  if (_isGuest && !force) {
    debugPrint('AuthService.clearToken skipped: Guest session');
    return;
  }

  debugPrint('AuthService.clearToken: clearing auth state (force=$force)');

  // 2. จุดสำคัญ: ต้องล้างค่าใน RAM ทันที
  _token = null;
  _user = null;      // บังคับลบข้อมูล user ทิ้งเลย ไม่ต้องรอเช็ค force
  _isGuest = false;
  _guestUsed = false;
  _guestPersonal = null;
  _guestSelections = null;
  _anonId = null;

  try {
    // 3. ล้างข้อมูลใน Storage ให้เกลี้ยง
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'auth_user'); // ลบ key หลักที่เก็บข้อมูล user
      // Remove temporary selections and any per-session keys so data
      // from previous account does not leak into a new login/session.
      try { await _storage.delete(key: 'auth_temp_selections'); } catch (_) {}
      try { await _storage.delete(key: 'auth_user_last_id'); } catch (_) {}
    await _storage.delete(key: 'auth_guest');
    await _storage.delete(key: 'auth_guest_used');
    await _storage.delete(key: 'auth_guest_personal');
    await _storage.delete(key: 'auth_guest_selections');
    await _storage.delete(key: 'anon_id');

    // 4. ล้างข้อมูลตาม ID (ถ้ามีค้างอยู่)
    // ลบทุกอย่างใน storage ที่ขึ้นต้นด้วย auth_user_
    final allKeys = await _storage.readAll();
    for (var key in allKeys.keys) {
      if (key.startsWith('auth_user_')) {
        await _storage.delete(key: key);
      }
    }

    debugPrint('AuthService.clearToken: ALL storage keys cleared');
  } catch (e) {
    debugPrint('AuthService.clearToken ERROR: $e');
  }

  if (force) {
    // deleteAll() ล้างทุก key แบบไม่เลือกหน้า รวมถึง key ระดับ "เครื่อง/แอป"
    // ที่ไม่ผูกกับบัญชีไหนเลย (เช่น notification_permission_asked ที่ตั้งใจ
    // ให้ถามครั้งเดียวตลอดอายุแอป — ดู dashboard_page.dart) ทำให้ logout
    // หรือ handleAuthSuccess (ที่เรียก force:true) ทุกครั้งรีเซ็ต flag นี้
    // กลับไปเป็น "ยังไม่เคยถาม" โดยไม่ตั้งใจ ผู้ใช้จริงเจอ dialog เด้งซ้ำทุก
    // รอบ logout/login — จำค่าไว้ก่อนล้าง แล้วเขียนกลับหลังล้าง (ยังคง wipe
    // ข้อมูลผูกบัญชีเดิมทั้งหมดเหมือนเดิม แค่ไม่ลาก preference ระดับเครื่องไปด้วย)
    const notificationAskedKey = 'notification_permission_asked';
    final preservedNotificationAsked = await _storage.read(key: notificationAskedKey);
    try {
      await _storage.deleteAll();
      if (kDebugMode) debugPrint('AuthService.clearToken: deleteAll() executed (force)');
    } catch (e) {
      debugPrint('AuthService.clearToken: deleteAll failed: $e');
    }
    if (preservedNotificationAsked != null) {
      try {
        await _storage.write(key: notificationAskedKey, value: preservedNotificationAsked);
      } catch (_) {}
    }
  }

  notifyListeners(); // แจ้งเตือน UI ให้วาดใหม่ (หน้าจอจะกลายเป็นว่างเปล่า)
}

  /// Set a temporary lock on the current persisted user until [until].
  /// This writes `temporary_locked` and `temporary_lock_until` into the
  /// persisted `auth_user` blob so other app instances can read it.
  Future<void> setUserTemporaryLockUntil(DateTime until) async {
    try {
      if (_user == null) return;
      _user = Map<String, dynamic>.from(_user!);
      _user!['temporary_locked'] = true;
      _user!['temporary_lock_until'] = until.toUtc().toIso8601String();
      try {
        final enc = jsonEncode(_user);
        await _storage.write(key: 'auth_user', value: enc);
        try {
          final idValLocal = _user?['id'] ?? _user?['user_id'] ?? _user?['userid'];
          if (idValLocal != null) {
            final perKeyLocal = _authUserKeyForId(idValLocal);
            await _storage.write(key: perKeyLocal, value: enc);
          }
        } catch (_) {}
        debugPrint('AuthService: set temporary_lock_until=${_user!['temporary_lock_until']}');
      } catch (e) {
        debugPrint('AuthService.setUserTemporaryLockUntil ERROR: $e');
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Try parsing various date formats used by backend.
  /// Returns a DateTime in UTC or null if parsing fails.
  DateTime? _parseFlexibleDate(String s) {
    if (s.trim().isEmpty) return null;
    // Try ISO first
    try {
      final dIso = DateTime.tryParse(s);
      if (dIso != null) return dIso.toUtc();
    } catch (_) {}

    // Try common DD/MM/YYYY[ hh:mm[:ss]] patterns
    try {
      final re = RegExp(r"^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?");
      final m = re.firstMatch(s.trim());
      if (m != null) {
        final d = int.tryParse(m.group(1)!) ?? 1;
        final mo = int.tryParse(m.group(2)!) ?? 1;
        var y = int.tryParse(m.group(3)!) ?? DateTime.now().year;
        // Buddhist Era heuristic (years > 2400)
        if (y > 2400) y = y - 543;
        final hh = m.group(4) != null ? int.tryParse(m.group(4)!) ?? 0 : 0;
        final mm = m.group(5) != null ? int.tryParse(m.group(5)!) ?? 0 : 0;
        final ss = m.group(6) != null ? int.tryParse(m.group(6)!) ?? 0 : 0;
        try {
          final dt = DateTime.utc(y, mo, d, hh, mm, ss);
          return dt.toUtc();
        } catch (_) {}
      }
    } catch (_) {}

    return null;
  }

  /// Clear temporary lock and reset saved selections/health_goal locally.
  /// If possible this will also attempt to clear the server-side health_goal
  /// for logged-in users so the account fully resets when the temporary
  /// period expires.
  Future<void> clearUserTemporaryLockAndReset({bool remote = true}) async {
    try {
      // Attempt to clear remote health_goal first (best-effort).
      String? tokenLocal = _token ?? await _storage.read(key: 'auth_token');
      int? intId;
      try {
        if (_user != null) {
          final idVal = _user!['id'] ?? _user!['user_id'] ?? _user!['userid'];
          intId = idVal == null ? null : int.tryParse(idVal.toString());
        }
      } catch (_) {
        intId = null;
      }
      try {
        final api = ApiClient(getApiBase());
        // send an empty health_goal to clear server-side value (best-effort)
        if (intId != null && tokenLocal != null && tokenLocal.isNotEmpty) {
          try {
            await api.post('/user/$intId', headers: {'Authorization': 'Bearer $tokenLocal'}, body: {'health_goal': ''}, timeoutSeconds: 3);
          } catch (_) {}
        }
      } catch (_) {}

      // Now clear local persisted fields
      if (_user != null) {
        _user = Map<String, dynamic>.from(_user!);
        _user!.remove('health_goal');
        _user!.remove('health_goal_group');
        if (_user!.containsKey('temporary_locked')) _user!.remove('temporary_locked');
        if (_user!.containsKey('temporary_lock_until')) _user!.remove('temporary_lock_until');
        if (_user!.containsKey('temporary_partial_lock')) _user!.remove('temporary_partial_lock');
        try {
          final enc = jsonEncode(_user);
          await _storage.write(key: 'auth_user', value: enc);
          try {
            final idValLocal = _user?['id'] ?? _user?['user_id'] ?? _user?['userid'];
            if (idValLocal != null) {
              final perKeyLocal = _authUserKeyForId(idValLocal);
              await _storage.write(key: perKeyLocal, value: enc);
            }
          } catch (_) {}
          debugPrint('AuthService.clearUserTemporaryLockAndReset: cleared local persisted user lock/goal');
        } catch (e) {
          debugPrint('AuthService.clearUserTemporaryLockAndReset ERROR: $e');
        }
      }

      // Clear temp selections so UI allows re-entry
      _tempSelections = null;
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService.clearUserTemporaryLockAndReset EX: $e');
    }
  }

  Future<void> logout() async {
    debugPrint('🔥 LOGOUT CALLED 🔥');
    try {
      debugPrint('Logout stack:\n${StackTrace.current}');
    } catch (_) {}
    // Fully clear persisted auth state when logging out so next account
    // starts with a clean slate.
    await clearToken(force: true);
    // ✅ เพิ่ม 3 บรรทัดนี้เพื่อล้างข้อมูลค้างคา
    _token = null;
    _user = null;
    _tempSelections = null;
    
    notifyListeners(); // แจ้งแอปว่าข้อมูลเปลี่ยนแล้วนะ
  }

  // 🔥 FIXED CHANGE PASSWORD
  Future<Map<String, dynamic>> changePassword({
    required String username,
    required String email,
    required String oldPassword,
    required String newPassword,
    bool useAuth = true,
  }) async {
    // ✅ โหลด token จาก memory หรือ storage (แต่ไม่บังคับให้ต้องมี)
    if (_token == null || _token!.isEmpty) {
      _token = await _storage.read(key: 'auth_token');
    }

    final api = ApiClient(getApiBase());

    final body = jsonEncode({
      'username': username,
      'email': email,
      'old_password': oldPassword,
      'new_password': newPassword,
    });

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (useAuth) {
      if (_token != null && _token!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_token';
      }
    }

    ApiResponse respRaw;
    try {
      final resp = await api.post(
        '/change-password',
        headers: headers,
        body: body,
      );
      respRaw = resp;
    } catch (e) {
      if (e is DioException) {
        final status = e.response?.statusCode ?? 0;
        final bodyStr = e.response?.data is String ? e.response?.data as String : (e.response?.data != null ? jsonEncode(e.response?.data) : '');
        return {'error': _extractServerErrorMessage(e.response?.data) ?? 'request failed', 'statusCode': status, 'detail': bodyStr};
      }
      return {'error': 'request failed', 'statusCode': 0};
    }

    final decoded = <String, dynamic>{};

    try {
      if (respRaw.body.isNotEmpty) {
        final d = jsonDecode(respRaw.body);
        if (d is Map<String, dynamic>) {
          decoded.addAll(d);
        }
      }
    } catch (_) {}

    decoded['statusCode'] = respRaw.statusCode;
    return decoded;
  }

  // ==========================================================
  // 🔥 RESET PASSWORD (ใช้ reset_token + current_password)
  // Backend ต้องการ:
  // reset_token
  // current_password
  // new_password
  // ==========================================================
  Future<Map<String, dynamic>> resetPassword({
    required String resetToken,
    required String newPassword,
  }) async {
    // Client-side validation: token must be present and non-empty
    if (resetToken.trim().isEmpty) {
      return {'error': 'reset_token required', 'statusCode': 400};
    }

    final api = ApiClient(getApiBase());

    final body = jsonEncode({
      'reset_token': resetToken.trim(),
      'new_password': newPassword,
    });

    final resp = await api.post(
      '/reset-password',
      headers: {'Content-Type': 'application/json', 'X-Skip-Auth': '1'},
      body: body,
    );

    final decoded = <String, dynamic>{};

    try {
      if (resp.body.isNotEmpty) {
        final d = jsonDecode(resp.body);
        if (d is Map<String, dynamic>) {
          decoded.addAll(d);
        }
      }
    } catch (_) {}

    decoded['statusCode'] = resp.statusCode;
    return decoded;
  }

  // New: reset via OTP (forgot-password flow)
  Future<Map<String, dynamic>> resetPasswordWithOtp({
    required String resetToken,
    required String otp,
    required String newPassword,
    String? username,
    String? email,
  }) async {
    final t = resetToken.trim();
    final o = otp.trim();
    final u = username?.trim();
    final e = email?.trim();
    if (t.isEmpty) return {'error': 'reset_token required', 'statusCode': 400};
    if (o.isEmpty) return {'error': 'otp required', 'statusCode': 400};

    final api = ApiClient(getApiBase());
    final bodyMap = {'reset_token': t, 'otp': o, 'new_password': newPassword};
    if (u != null && u.isNotEmpty) bodyMap['username'] = u;
    if (e != null && e.isNotEmpty) bodyMap['email'] = e;
    final body = jsonEncode(bodyMap);

    ApiResponse respRaw;
    try {
      respRaw = await api.post(
        '/reset-password',
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
    } catch (ex) {
      if (ex is DioException) {
        final status = ex.response?.statusCode ?? 0;
        final bodyStr = ex.response?.data is String ? ex.response?.data as String : (ex.response?.data != null ? jsonEncode(ex.response?.data) : '');
        return {'error': _extractServerErrorMessage(ex.response?.data) ?? 'request failed', 'statusCode': status, 'detail': bodyStr};
      }
      return {'error': 'request failed', 'statusCode': 0};
    }

    final decoded = <String, dynamic>{};
    try {
      if (respRaw.body.isNotEmpty) {
        final d = jsonDecode(respRaw.body);
        if (d is Map<String, dynamic>) decoded.addAll(d);
      }
    } catch (_) {}
    decoded['statusCode'] = respRaw.statusCode;
    return decoded;
  }

  /// เช็ค OTP กับ backend จริงโดยไม่เปลี่ยนรหัสผ่าน — ใช้ที่ step 2 ของ
  /// ForgotPasswordPage (ปุ่ม "ยืนยัน OTP") เดิมหน้านั้นเช็คแค่ความยาว 6 หลัก
  /// ไม่ได้เทียบกับค่าจริงเลย กรอกเลขอะไรก็ผ่านไป step 3 ได้ (ผู้ใช้รายงานจริง)
  Future<Map<String, dynamic>> verifyResetOtp({
    required String resetToken,
    required String otp,
    String? username,
    String? email,
  }) async {
    final t = resetToken.trim();
    final o = otp.trim();
    final u = username?.trim();
    final e = email?.trim();
    if (t.isEmpty) return {'error': 'reset_token required', 'statusCode': 400};
    if (o.isEmpty) return {'error': 'otp required', 'statusCode': 400};

    final api = ApiClient(getApiBase());
    final bodyMap = {'reset_token': t, 'otp': o};
    if (u != null && u.isNotEmpty) bodyMap['username'] = u;
    if (e != null && e.isNotEmpty) bodyMap['email'] = e;
    final body = jsonEncode(bodyMap);

    ApiResponse respRaw;
    try {
      respRaw = await api.post(
        '/verify-reset-otp',
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
    } catch (ex) {
      if (ex is DioException) {
        final status = ex.response?.statusCode ?? 0;
        final bodyStr = ex.response?.data is String ? ex.response?.data as String : (ex.response?.data != null ? jsonEncode(ex.response?.data) : '');
        return {'error': _extractServerErrorMessage(ex.response?.data) ?? 'request failed', 'statusCode': status, 'detail': bodyStr};
      }
      return {'error': 'request failed', 'statusCode': 0};
    }

    final decoded = <String, dynamic>{};
    try {
      if (respRaw.body.isNotEmpty) {
        final d = jsonDecode(respRaw.body);
        if (d is Map<String, dynamic>) decoded.addAll(d);
      }
    } catch (_) {}
    decoded['statusCode'] = respRaw.statusCode;
    return decoded;
  }

  // Compatibility wrapper: some pages still call `resetPassword` with the
  // change-password parameter names (username/email/oldPassword/newPassword).
  // The compatibility extension is placed after the class closing brace.

  Future<bool> saveSelection(Map<String, dynamic> data) async {
    try {
      // Sanitize incoming selection payload: do not forward sentinel or
      // non-positive numeric ids (0, -999999, etc.). Convert unparsable
      // id strings to null as well.
      Map<String, dynamic> sanitize(Map<String, dynamic> src) {
        final out = Map<String, dynamic>.from(src);
        const idKeys = [
          'food_type_id',
          'category_id',
          'menu_id',
          'dessert_menu_id',
          'drink_type_id',
          'drink_menu_id',
        ];
        for (final k in idKeys) {
          if (!out.containsKey(k)) continue;
          final v = out[k];
          int? iv;
          if (v is int) {
            iv = v;
          } else if (v is String) {
            iv = int.tryParse(v);
          }
          if (iv == null || iv <= 0) {
            out[k] = null;
          } else {
            out[k] = iv;
          }
        }
        return out;
      }

      final sanitized = sanitize(data);

      // ensure token loaded
      if (_token == null || _token!.isEmpty) {
        _token = await _storage.read(key: 'auth_token');
      }
      if (_token == null || _token!.isEmpty) return false;

      final api = ApiClient(getApiBase());

      // Remove keys that are null to avoid sending null ids which some
      // backends treat as invalid; send only present non-null fields.
      final payload = Map<String, dynamic>.from(sanitized)
        ..removeWhere((k, v) => v == null);

      final resp = await api.post(
        '/save-selection',
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
        timeoutSeconds: 7,
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        try {
          if (resp.body.isNotEmpty) {
            final Map<String, dynamic> remote = jsonDecode(resp.body) as Map<String, dynamic>;
            if (kDebugMode) {
              try {
                debugPrint('AuthService.saveSelection: remote=${jsonEncode(remote)}');
              } catch (_) {}
            }
            // Persist any server-returned user/selection fields into local user storage
            try {
              // Merge server-returned fields into persisted user map where appropriate
              await saveUser(remote);
            } catch (_) {}

            // Also set tempSelections so UI can reflect meal/duration and lock metadata immediately
            final Map<String, dynamic> sels = {};
            if (remote.containsKey('meal')) sels['meal'] = remote['meal'];
            if (remote.containsKey('duration')) sels['duration'] = remote['duration'];
            if (remote.containsKey('start_date')) sels['start_date'] = remote['start_date'];
            if (remote.containsKey('end_date')) sels['end_date'] = remote['end_date'];
            if (remote.containsKey('is_fulllock')) sels['is_fulllock'] = remote['is_fulllock'];
            if (remote.containsKey('next_meal_open_at')) sels['next_meal_open_at'] = remote['next_meal_open_at'];
            // Persist server-returned menu/name fields so UI can show localized names
            if (remote.containsKey('food_name_th')) sels['food_name_th'] = remote['food_name_th'];
            if (remote.containsKey('dessert_name_th')) sels['dessert_name_th'] = remote['dessert_name_th'];
            if (remote.containsKey('drink_name_th')) sels['drink_name_th'] = remote['drink_name_th'];
            // Persist health-goal related fields if server provided them
            if (remote.containsKey('health_goal_group')) sels['health_goal_group'] = remote['health_goal_group'];
            if (remote.containsKey('health_goal')) sels['health_goal'] = remote['health_goal'];
            if (remote.containsKey('health_goal_drink')) sels['health_goal_drink'] = remote['health_goal_drink'];
            if (remote.containsKey('health_goal_drink_types')) sels['health_goal_drink_types'] = remote['health_goal_drink_types'];
            if (remote.containsKey('menu_id')) sels['menu_id'] = remote['menu_id'];
            if (remote.containsKey('dessert_menu_id')) sels['dessert_menu_id'] = remote['dessert_menu_id'];
            if (remote.containsKey('drink_menu_id')) sels['drink_menu_id'] = remote['drink_menu_id'];
            if (remote.containsKey('category_id')) sels['category_id'] = remote['category_id'];
            if (remote.containsKey('food_type_id')) sels['food_type_id'] = remote['food_type_id'];
            if (sels.isNotEmpty) {
              _tempSelections = Map<String, dynamic>.from(sels);
              if (kDebugMode) {
                try {
                  debugPrint('AuthService.saveSelection: tempSelections=${jsonEncode(_tempSelections)}');
                } catch (_) {}
              }
              notifyListeners();
            }

            
          }
        } catch (_) {}
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
