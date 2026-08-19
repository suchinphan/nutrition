import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'login_page.dart';
import '../services/auth_service.dart';
import '../utils/password_validator.dart';

class ChangePasswordPage extends StatefulWidget {
  final String? initialUsername;
  final String? initialEmail;

  const ChangePasswordPage({
    super.key,
    this.initialUsername,
    this.initialEmail,
  });

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();

  bool _loading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;

  final Color primaryGreen = AppColors.leaf;

  @override
  void dispose() {
    _userCtrl.dispose();
    _emailCtrl.dispose();
    _currentCtrl.dispose();
    _newCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialUsername != null) _userCtrl.text = widget.initialUsername!;
    if (widget.initialEmail != null) _emailCtrl.text = widget.initialEmail!;
  }

  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final currentText = _currentCtrl.text.trim();
      final newPasswordText = _newCtrl.text.trim();

      if (currentText == newPasswordText) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านปัจจุบัน'),
          ),
        );
        return;
      }

      final result = await AuthService().changePassword(
        username: _userCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        oldPassword: currentText,
        newPassword: newPasswordText,
      );

      if (!mounted) return;
      setState(() => _loading = false);

      if (result['statusCode'] == 200 || result['statusCode'] == 201) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('สำเร็จ'),
            content: const Text('รหัสผ่านถูกเปลี่ยนเรียบร้อยแล้ว'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context, rootNavigator: true).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  );
                },
                child: const Text('ตกลง'),
              ),
            ],
          ),
        );
      } else {
        // Map backend errors to user-friendly Thai messages
        String msg = 'ไม่สามารถเปลี่ยนรหัสผ่านได้';

        final err = (result['error'] ?? result['message'] ?? '').toString();

        if (result['statusCode'] == 401) {
          // Distinguish between not-logged-in vs wrong current password
          final lowErr = err.toLowerCase();
          if (lowErr.contains('invalid current password') || lowErr.contains('current password') || lowErr.contains('invalid current')) {
            msg = 'รหัสผ่านเดิมไม่ถูกต้อง';
          } else if (err.contains('กรุณาเข้าสู่ระบบ') || lowErr.contains('authorization') || lowErr.contains('token')) {
            msg = 'กรุณาเข้าสู่ระบบใหม่';
          } else {
            msg = 'รหัสผ่านเดิมหรือ token ไม่ถูกต้อง';
          }
        } else {
          msg = err.isNotEmpty ? err : msg;
        }

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('เกิดข้อผิดพลาด')));
    }
  }

  // ponytail: ธีมกลาง (AppTheme.inputDecorationTheme) จัดสี/ขอบ/มุมโค้งให้แล้ว
  InputDecoration _inputDecoration(String label) {
    return InputDecoration(labelText: label);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  GestureDetector(
                    // เดิม pushReplacement ไป LoginPage ตรงๆ ไม่ว่ากด back
                    // ตอนไหน (บั๊กที่เจอจริง — BUG-001: ทำให้ดูเหมือนถูก
                    // เด้งออกจากระบบทั้งที่ยังไม่ได้กดยืนยันเปลี่ยนรหัสผ่าน
                    // เลย) แก้เป็น pop กลับไปหน้าเดิมตามปกติ — ไปหน้า
                    // LoginPage เฉพาะตอนเปลี่ยนรหัสผ่าน "สำเร็จ" เท่านั้น
                    // (ดู dialog ใน _onSubmit)
                    onTap: () => Navigator.of(context, rootNavigator: true).pop(),
                    child: Icon(Icons.arrow_back, color: primaryGreen, size: 26),
                  ),
                  const Expanded(child: SizedBox()),
                  Text('เปลี่ยนรหัสผ่าน', style: Theme.of(context).textTheme.titleMedium),
                  const Expanded(child: SizedBox()),
                  const SizedBox(width: 26),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Container(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: AppRadius.rLg,
                    boxShadow: AppShadow.card,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _userCtrl,
                          readOnly: true,
                          decoration: _inputDecoration('ชื่อผู้ใช้งาน'),
                          validator: (v) {
                            final s = (v ?? '').trim();
                            if (s.isEmpty) return 'กรุณากรอกชื่อผู้ใช้งาน';

                            final usernameRegex = RegExp(r'^[a-zA-Z0-9_]{4,}$');
                            if (!usernameRegex.hasMatch(s)) {
                              return 'ชื่อผู้ใช้งานต้องมีอย่างน้อย 4 ตัว และมีเฉพาะ a-z, A-Z, 0-9 หรือ _';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          readOnly: true,
                          decoration: _inputDecoration('อีเมล์'),
                          validator: (v) {
                            final s = (v ?? '').trim();
                            if (s.isEmpty) return 'กรุณากรอกอีเมล์';
                            final emailRegex = RegExp(
                              r"^[^@\s]+@[^@\s]+\.[^@\s]+$",
                            );
                            if (!emailRegex.hasMatch(s)) {
                              return 'รูปแบบอีเมล์ไม่ถูกต้อง';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _currentCtrl,
                          obscureText: _obscureCurrent,
                          decoration: _inputDecoration('รหัสผ่านเดิม').copyWith(
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscureCurrent = !_obscureCurrent,
                              ),
                              icon: Icon(
                                _obscureCurrent
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if ((v ?? '').isEmpty) {
                              return 'กรุณากรอกรหัสผ่านเดิม';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _newCtrl,
                          obscureText: _obscureNew,
                          decoration: _inputDecoration('รหัสผ่านใหม่').copyWith(
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscureNew = !_obscureNew),
                              icon: Icon(
                                _obscureNew
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                          validator: (v) {
                            final s = v ?? '';
                            final policyError = validatePassword(s);
                            if (policyError != null) return policyError;
                            final old = _currentCtrl.text.trim();
                            if (old.isNotEmpty && old == s) {
                              return 'ห้ามใช้รหัสผ่านซ้ำกับรหัสเดิม';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            'อย่างน้อย 8 ตัว มีพิมพ์ใหญ่ พิมพ์เล็ก ตัวเลข และอักขระพิเศษ',
                            style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _loading
                                ? null
                                : () {
                                    if (_formKey.currentState?.validate() ?? false) {
                                      _onSubmit();
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryGreen,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              elevation: 0,
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'ตกลง',
                                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
