import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// StorageService: attempt to use FlutterSecureStorage; on unrecoverable
/// secure-storage errors (DPAPI failure on Windows) fall back to a
/// plaintext JSON file in the user's Roaming AppData folder. The file
/// is only used as a pragmatic fallback to keep the user signed-in; it is
/// NOT encrypted and therefore less secure. The wrapper minimizes the
/// chance of throwing to callers.
class StorageService {
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  bool _secureAvailable = true;

  File? _fallbackFile;
  Map<String, String> _fallbackCache = {};

  StorageService() {
    _initFallbackFile();
  }

  Future<void> _initFallbackFile() async {
    try {
      final profile = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (profile == null) return;
      final dir = Directory('$profile${Platform.pathSeparator}AppData${Platform.pathSeparator}Roaming${Platform.pathSeparator}com.example${Platform.pathSeparator}frontend');
      if (!await dir.exists()) await dir.create(recursive: true);
      final f = File('${dir.path}${Platform.pathSeparator}plain_storage.json');
      _fallbackFile = f;
      if (await f.exists()) {
        try {
          final txt = await f.readAsString();
          final m = jsonDecode(txt) as Map<String, dynamic>;
          _fallbackCache = m.map((k, v) => MapEntry(k, v?.toString() ?? ''));
        } catch (_) {
          _fallbackCache = {};
        }
      }
    } catch (_) {}
  }

  Future<String?> read({required String key}) async {
    // Try secure storage first
    if (_secureAvailable) {
      try {
        final v = await _secure.read(key: key);
        if (v != null) return v;
        // Secure storage answered but has nothing for this key — a prior
        // write may have gone missing there (keystore reset etc.) while
        // still being mirrored below, so fall through instead of trusting
        // this null.
      } catch (e) {
        final msg = e.toString();
        // If secure-storage is failing with platform-specific DPAPI errors,
        // mark it unavailable and fall through to fallback.
        if (msg.contains('CryptUnprotectData') || msg.contains('CryptUnprotectData()') || msg.contains('Failure on CryptUnprotectData') || msg.contains('PathAccessException')) {
          _secureAvailable = false;
        }
      }
    }

    // Fallback to file-backed cache
    try {
      await _initFallbackFile();
      return _fallbackCache[key];
    } catch (_) {
      return null;
    }
  }

  Future<void> write({required String key, required String value}) async {
    if (_secureAvailable) {
      try {
        await _secure.write(key: key, value: value);
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('CryptUnprotectData') || msg.contains('CryptUnprotectData()') || msg.contains('Failure on CryptUnprotectData') || msg.contains('PathAccessException')) {
          _secureAvailable = false;
        }
      }
    }

    // Always mirror into the fallback cache too, even when the secure write
    // above succeeded — secure storage can still fail on a later *read*
    // (e.g. Android keystore invalidated after the write, mid-session app
    // kill/restart). Without this mirror, that later read failure returns
    // null with no fallback value ever recorded, so one-shot flags like the
    // notification-permission "asked" marker silently forget themselves and
    // the prompt reappears.
    try {
      await _initFallbackFile();
      _fallbackCache[key] = value;
      if (_fallbackFile != null) {
        await _fallbackFile!.writeAsString(jsonEncode(_fallbackCache));
      }
    } catch (_) {}
  }

  Future<void> delete({required String key}) async {
    if (_secureAvailable) {
      try {
        await _secure.delete(key: key);
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('CryptUnprotectData') || msg.contains('CryptUnprotectData()') || msg.contains('Failure on CryptUnprotectData') || msg.contains('PathAccessException')) {
          _secureAvailable = false;
        }
      }
    }

    // Mirror the delete into the fallback cache too — see write() for why
    // the two stores must stay in sync.
    try {
      await _initFallbackFile();
      _fallbackCache.remove(key);
      if (_fallbackFile != null) await _fallbackFile!.writeAsString(jsonEncode(_fallbackCache));
    } catch (_) {}
  }

  Future<Map<String, String>> readAll() async {
    final out = <String, String>{};
    if (_secureAvailable) {
      try {
        final all = await _secure.readAll();
        return all.map((k, v) => MapEntry(k, v));
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('CryptUnprotectData') || msg.contains('Failure on CryptUnprotectData') || msg.contains('PathAccessException')) {
          _secureAvailable = false;
        }
      }
    }

    try {
      await _initFallbackFile();
      return Map<String, String>.from(_fallbackCache);
    } catch (_) {
      return out;
    }
  }

  Future<void> deleteAll() async {
    if (_secureAvailable) {
      try {
        await _secure.deleteAll();
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('CryptUnprotectData') || msg.contains('Failure on CryptUnprotectData') || msg.contains('PathAccessException')) {
          _secureAvailable = false;
        }
      }
    }

    try {
      await _initFallbackFile();
      _fallbackCache.clear();
      if (_fallbackFile != null) await _fallbackFile!.writeAsString(jsonEncode(_fallbackCache));
    } catch (_) {}
  }
}
