import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/widgets.dart';
import '../services/app_config.dart';
import '../services/auth_service.dart';
import '../utils/password_validator.dart';
import 'login_page.dart';

const _otpTtlSeconds = 300; // ตรงกับ TTL 5 นาทีของ token/OTP ฝั่ง backend

/// 3-step flow ลืมรหัสผ่าน: กรอกบัญชี -> ยืนยัน OTP -> ตั้งรหัสผ่านใหม่
class ForgotPasswordPage extends StatefulWidget {
  final String? initialUsername;
  final String? initialEmail;

  const ForgotPasswordPage({
    super.key,
    this.initialUsername,
    this.initialEmail,
  });

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  int _step = 1;
  bool _loading = false;
  String? _error;

  final _userCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;

  String? _resetToken;
  // backend ยังไม่มีระบบส่งอีเมล/SMS จริง (/forgot-password คืน otp มาใน
  // response ตรงๆ) จึงแสดงให้ผู้ใช้เห็นในหน้านี้ชั่วคราว — พฤติกรรมเดิม
  // ของหน้านี้ก่อน redesign ก็เปิดเผยค่านี้เช่นกัน (ผ่าน dialog)
  String? _devOtp;

  Timer? _countdownTimer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialUsername != null) _userCtrl.text = widget.initialUsername!;
    if (widget.initialEmail != null) _emailCtrl.text = widget.initialEmail!;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _userCtrl.dispose();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _secondsLeft = _otpTtlSeconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  String get _countdownLabel {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _requestOtp() async {
    final username = _userCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (username.isEmpty || email.isEmpty) {
      setState(() => _error = 'กรุณากรอกชื่อผู้ใช้และอีเมล');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await http.post(
        Uri.parse('${getApiBase()}/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'email': email}),
      );
      if (!mounted) return;
      final data = resp.body.isNotEmpty ? jsonDecode(resp.body) as Map<String, dynamic> : <String, dynamic>{};
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final token = data['reset_token'] as String?;
        if (token == null || token.isEmpty) {
          setState(() {
            _loading = false;
            _error = 'ไม่พบโทเค่นจากเซิร์ฟเวอร์';
          });
          return;
        }
        setState(() {
          _loading = false;
          _resetToken = token;
          _devOtp = data['otp'] as String?;
          _otpCtrl.clear();
          _step = 2;
        });
        _startCountdown();
      } else {
        setState(() {
          _loading = false;
          _error = (data['error'] ?? 'ไม่สามารถดำเนินการลืมรหัสผ่านได้').toString();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'ไม่สามารถติดต่อเซิร์ฟเวอร์ได้';
      });
    }
  }

  Future<void> _confirmOtpAndContinue() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      setState(() => _error = 'กรุณากรอกรหัส OTP 6 หลัก');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await AuthService().verifyResetOtp(
      resetToken: _resetToken ?? '',
      otp: otp,
      username: _userCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
    );
    if (!mounted) return;
    final statusCode = result['statusCode'];
    if (statusCode == 200 || statusCode == 201) {
      setState(() {
        _loading = false;
        _step = 3;
      });
    } else {
      final msg = (result['error'] ?? result['message'] ?? 'รหัส OTP ไม่ถูกต้อง').toString();
      // ผิดครบ 5 ครั้ง/token หมดอายุ — backend ล้าง reset_token/otp ทิ้งไปแล้ว
      // กรอกใหม่ที่ step นี้ต่อไม่มีทางถูกอีกเลย ต้องกลับไป step 1 ขอ OTP
      // ใหม่จริงๆ เท่านั้น (เดิมค้างอยู่ step 2 ให้กรอกซ้ำได้เรื่อยๆ ทั้งที่
      // token ตายไปแล้ว ผู้ใช้รายงานจริงว่าไม่เห็นทางขอรหัสใหม่)
      if (msg.contains('เกิน 5 ครั้ง') || msg.contains('หมดอายุ') || msg.contains('โทเคน')) {
        _countdownTimer?.cancel();
        setState(() {
          _loading = false;
          _step = 1;
          _resetToken = null;
          _devOtp = null;
          _error = msg;
        });
      } else {
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
    }
  }

  Future<void> _submitNewPassword() async {
    final newPass = _newCtrl.text;
    final confirmPass = _confirmCtrl.text;
    final policyError = validatePassword(newPass);
    if (policyError != null) {
      setState(() => _error = policyError);
      return;
    }
    if (newPass != confirmPass) {
      setState(() => _error = 'กรุณายืนยันรหัสผ่านให้ตรงกัน');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await AuthService().resetPasswordWithOtp(
      resetToken: _resetToken ?? '',
      otp: _otpCtrl.text.trim(),
      newPassword: newPass,
      username: _userCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    final statusCode = result['statusCode'];
    if (statusCode == 200 || statusCode == 201) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('สำเร็จ'),
          content: const Text('ตั้งรหัสผ่านใหม่เรียบร้อยแล้ว'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ตกลง'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      // กลับไปที่ RootShell ก่อน (กัน pushAndRemoveUntil ล้าง RootShell ทิ้ง
      // ไปด้วย) แล้วค่อย push LoginPage สะอาดๆ ทับอีกที ให้ผู้ใช้ล็อกอินด้วย
      // รหัสผ่านใหม่ได้ทันที
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      rootNavigator.popUntil((route) => route.isFirst);
      rootNavigator.push(MaterialPageRoute(builder: (_) => const LoginPage()));
    } else {
      final msg = (result['error'] ?? result['message'] ?? 'ไม่สามารถตั้งรหัสผ่านใหม่ได้').toString();
      setState(() => _error = msg);
      // OTP หมดอายุ/ผิดเกินจำนวน -> พาผู้ใช้กลับไปขอ OTP ใหม่ที่ step 2
      if (msg.contains('OTP') || msg.contains('โทเคน') || msg.contains('หมดอายุ')) {
        setState(() => _step = 2);
      }
    }
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

  void _goBack() {
    if (_step == 1) {
      Navigator.of(context, rootNavigator: true).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } else {
      setState(() {
        _step -= 1;
        _error = null;
      });
    }
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
                    onTap: _goBack,
                    child: const Icon(Icons.arrow_back, color: AppColors.gray900, size: 26),
                  ),
                  const Expanded(child: SizedBox()),
                  Text('ลืมรหัสผ่าน', style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900)),
                  const Expanded(child: SizedBox()),
                  const SizedBox(width: 26),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: AppStepIndicator(
                currentStep: _step,
                totalSteps: 3,
                stepLabels: const ['บัญชี', 'ยืนยัน OTP', 'รหัสผ่านใหม่'],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      AppErrorBanner(
                        message: _error!,
                        onRetry: switch (_step) {
                          1 => _requestOtp,
                          2 => _confirmOtpAndContinue,
                          _ => _submitNewPassword,
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    switch (_step) {
                      1 => _buildStepAccount(),
                      2 => _buildStepOtp(),
                      _ => _buildStepNewPassword(),
                    },
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepAccount() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'กรอกชื่อผู้ใช้และอีเมลที่ใช้สมัครสมาชิก เพื่อขอรหัส OTP สำหรับตั้งรหัสผ่านใหม่',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
        ),
        const SizedBox(height: 20),
        TextField(controller: _userCtrl, decoration: _decoration('ชื่อผู้ใช้งาน')),
        const SizedBox(height: 14),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: _decoration('อีเมล'),
        ),
        const SizedBox(height: 24),
        _primaryButton(label: 'ขอรหัส OTP', onPressed: _requestOtp),
      ],
    );
  }

  Widget _buildStepOtp() {
    final canResend = _secondsLeft <= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'กรอกรหัส OTP 6 หลักที่ได้รับ',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
        ),
        if (_devOtp != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.amber50, borderRadius: BorderRadius.circular(10)),
            child: Text(
              'ระบบยังไม่เชื่อมต่อบริการส่งอีเมล/SMS จริง — รหัส OTP สำหรับทดสอบคือ $_devOtp',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.amber500),
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: _decoration('รหัส OTP'),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _secondsLeft > 0 ? 'รหัสหมดอายุใน $_countdownLabel' : 'รหัส OTP หมดอายุแล้ว',
              style: AppTextStyles.caption.copyWith(
                color: _secondsLeft > 0 ? AppColors.gray400 : AppColors.coral400,
              ),
            ),
            if (canResend)
              TextButton(
                onPressed: _loading ? null : _requestOtp,
                child: const Text('ขอ OTP ใหม่'),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _primaryButton(label: 'ยืนยัน OTP', onPressed: _confirmOtpAndContinue),
      ],
    );
  }

  Widget _buildStepNewPassword() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _newCtrl,
          obscureText: _obscureNew,
          decoration: _decoration(
            'รหัสผ่านใหม่',
            suffix: IconButton(
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
              icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility, color: AppColors.gray400),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            'อย่างน้อย 8 ตัว มีพิมพ์ใหญ่ พิมพ์เล็ก ตัวเลข และอักขระพิเศษ',
            style: AppTextStyles.caption,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirmCtrl,
          obscureText: _obscureConfirm,
          onSubmitted: (_) => _loading ? null : _submitNewPassword(),
          decoration: _decoration(
            'ยืนยันรหัสผ่านใหม่',
            suffix: IconButton(
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: AppColors.gray400),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _primaryButton(label: 'ตั้งรหัสผ่านใหม่', onPressed: _submitNewPassword),
      ],
    );
  }

  Widget _primaryButton({required String label, required VoidCallback onPressed}) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _loading ? null : onPressed,
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
            : Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
      ),
    );
  }
}
