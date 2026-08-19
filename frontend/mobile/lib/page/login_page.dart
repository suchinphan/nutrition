// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/widgets.dart';
import 'forgot_your_password_page.dart';
import 'ban_appeal_page.dart';
import 'register_login_page.dart';
import 'register_page.dart';
import '../services/auth_service.dart';
import '../services/app_config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {Widget? suffix}) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecoration(
      labelText: label,
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.gray50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(AppColors.gray100, 1),
      enabledBorder: border(AppColors.gray100, 1),
      focusedBorder: border(AppColors.teal500, 2),
    );
  }

  Future<void> _showBannedDialog(String msg) async {
    if (!mounted) return;
    setState(() => _loading = false);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('บัญชีถูกระงับ'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const RegisterLoginPage()),
                (route) => false,
              );
            },
            child: const Text('สมัครใหม่'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) =>
                      BanAppealPage(initialUsername: _userController.text.trim()),
                ),
              );
            },
            child: const Text('ส่งคำขอปลดแบน'),
          ),
        ],
      ),
    );
  }

  Future<void> _onLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final username = _userController.text.trim();
    final password = _passController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'กรุณากรอกอีเมล/ชื่อผู้ใช้และรหัสผ่าน';
      });
      return;
    }
    final url = Uri.parse('${getApiBase()}/login');
    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
      if (resp.statusCode == 200) {
        final j = jsonDecode(resp.body);

        // Defensive check: do not accept a user that the server marks as deleted.
        if (j is Map && j['is_deleted'] == true) {
          String msg = 'บัญชีของคุณถูกระงับ';
          if (j['delete_reason'] != null) {
            msg = j['delete_reason'].toString();
          }
          await _showBannedDialog(msg);
          return;
        }

        final token =
            j['password_token'] as String? ?? j['authToken'] as String?;
        if (token != null) {
          // handleAuthSuccess() เดียวจบ: saveToken + GET /user/<id> มาโปรไฟล์
          // เต็ม + merge เข้า local (syncToServer:false ในตัวอยู่แล้ว ไม่ POST
          // กลับไปซ้ำ) — เดิมหน้านี้ทำเอง 2 ขั้นตอนแยกจาก handleAuthSuccess
          // (saveUser ค่า minimal ก่อน แล้วยิง GET /user/<id> เองอีกรอบด้วย
          // ตัวเอง) กลายเป็นยิง GET /user/<id> ซ้ำกับที่ handleAuthSuccess ทำ
          // อยู่แล้วเป๊ะ รวม 2 ครั้งต่อการล็อกอิน 1 ครั้ง — ผู้ใช้รายงานจริง:
          // ทดสอบล็อกอิน/ออกจากระบบซ้ำๆ ถี่ๆ ชน rate limit 30 ครั้ง/นาทีของ
          // /user/<id> (เห็น 429 จริงใน log) พอ GET พลาด (429/timeout) ทั้ง
          // handleAuthSuccess() และโค้ดซ้ำตรงนี้ต่างก็ swallow error เงียบๆ
          // แล้ว fallback เป็น user แบบย่อ (แค่ id/username/email ไม่มีชื่อ-
          // นามสกุล) เห็นเป็นข้อมูลส่วนตัวหายทั้งที่เซิร์ฟเวอร์มีข้อมูลถูกต้อง
          // อยู่จริง — ลบโค้ดซ้ำออก ใช้ handleAuthSuccess() ตัวเดียวเหมือนกับ
          // RegisterPage ลดจำนวนคำขอ GET /user/<id> ต่อการล็อกอินลงครึ่งหนึ่ง
          await AuthService().handleAuthSuccess(token, {
            'id': j['id'] ?? j['user_id'],
            'username': j['username'],
            'email': j['email'],
          });
        }
        if (!mounted) return;
        // ปิด flow ล็อกอิน (RegisterLoginPage/LoginPage ที่ push ไว้บน root
        // navigator) กลับไปที่ RootShell เดิม แทนการ push MainScreen() ใหม่
        // ทับซึ่งจะทำให้ RootShell (แถบนำทางล่าง/FAB) หายไปทั้งอัน
        final rootNavigator = Navigator.of(context, rootNavigator: true);
        setState(() => _loading = false);
        rootNavigator.popUntil((route) => route.isFirst);
      } else if (resp.statusCode == 403) {
        String msg = 'บัญชีของคุณถูกระงับ';
        try {
          final j = jsonDecode(resp.body);
          if (j is Map && j['delete_reason'] != null) {
            msg = j['delete_reason'].toString();
          } else if (j is Map && j['error'] != null) {
            msg = j['error'].toString();
          } else if (j is Map && j['message'] != null) {
            msg = j['message'].toString();
          }
        } catch (_) {}
        await _showBannedDialog(msg);
      } else {
        String msg = 'เข้าสู่ระบบไม่สำเร็จ';
        try {
          final j = jsonDecode(resp.body);
          if (j is Map && j['error'] != null) {
            msg = j['error'].toString();
          } else if (j is Map && j['message'] != null) {
            msg = j['message'].toString();
          }
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'ไม่สามารถติดต่อเซิร์ฟเวอร์ได้';
      });
    }
  }

  Future<void> _continueAsGuest() async {
    await AuthService().saveGuest();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Icon(Icons.arrow_back, color: AppColors.gray900, size: 26),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(
                              color: AppColors.teal50,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.eco, color: AppColors.teal500, size: 36),
                          ),
                          const SizedBox(height: 12),
                          Text('NutriTrack',
                              style: AppTextStyles.headingLarge.copyWith(color: AppColors.gray900)),
                          const SizedBox(height: 4),
                          Text(
                            'เข้าสู่ระบบเพื่อเริ่มบันทึกมื้ออาหาร',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_error != null) ...[
                      AppErrorBanner(message: _error!, onRetry: _onLogin),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _userController,
                      decoration: _decoration('อีเมล หรือ ชื่อผู้ใช้'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passController,
                      obscureText: _obscure,
                      onSubmitted: (_) => _loading ? null : _onLogin(),
                      decoration: _decoration(
                        'รหัสผ่าน',
                        suffix: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.gray400,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ForgotPasswordPage()),
                          );
                        },
                        child: Text(
                          'ลืมรหัสผ่าน?',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.teal500,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _onLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.teal500,
                          disabledBackgroundColor: AppColors.teal500,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text(
                                'เข้าสู่ระบบ',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: _loading
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const RegisterPage()),
                                ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.teal500, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'สมัครสมาชิก',
                          style: TextStyle(color: AppColors.teal500, fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: TextButton(
                        onPressed: _loading ? null : _continueAsGuest,
                        child: Text(
                          'ดำเนินการในฐานะผู้เยี่ยมชม',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.gray600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
