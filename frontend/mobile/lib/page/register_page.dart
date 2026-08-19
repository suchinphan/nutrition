import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/widgets.dart';
import '../services/auth_service.dart';
import '../services/app_config.dart';
import '../utils/password_validator.dart';

enum _PasswordStrength { weak, medium, strong }

_PasswordStrength _passwordStrength(String pass) {
  final hasUpper = RegExp(r'[A-Z]').hasMatch(pass);
  final hasLower = RegExp(r'[a-z]').hasMatch(pass);
  final hasDigit = RegExp(r'\d').hasMatch(pass);
  final hasSpecial = RegExp(r'[^A-Za-z0-9]').hasMatch(pass);
  final classes = [hasUpper, hasLower, hasDigit, hasSpecial].where((b) => b).length;
  if (pass.length < 8 || classes < 4) return _PasswordStrength.weak;
  if (pass.length >= 12) return _PasswordStrength.strong;
  return _PasswordStrength.medium;
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  final _nameFocus = FocusNode();
  final _surnameFocus = FocusNode();
  final _userFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();
  final _confirmFocus = FocusNode();

  String? _nameError;
  String? _surnameError;
  String? _usernameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _submitError;

  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  static final _usernameReg = RegExp(r'^[A-Za-z0-9_.]{4,}$');
  static final _emailReg = RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() => _onUnfocus(_nameFocus, () => setState(() => _nameError = _validateName())));
    _surnameFocus.addListener(() => _onUnfocus(_surnameFocus, () => setState(() => _surnameError = _validateSurname())));
    _userFocus.addListener(() => _onUnfocus(_userFocus, () => setState(() => _usernameError = _validateUsername())));
    _emailFocus.addListener(() => _onUnfocus(_emailFocus, () => setState(() => _emailError = _validateEmail())));
    _passFocus.addListener(() {
      _onUnfocus(_passFocus, () => setState(() => _passwordError = validatePassword(_passController.text)));
      setState(() {}); // refresh strength bar as user types/leaves the field
    });
    _confirmFocus.addListener(() => _onUnfocus(_confirmFocus, () => setState(() => _confirmError = _validateConfirm())));
    _passController.addListener(() => setState(() {})); // live strength bar
  }

  void _onUnfocus(FocusNode node, VoidCallback run) {
    if (!node.hasFocus) run();
  }

  String? _validateName() => _nameController.text.trim().isEmpty ? 'กรุณากรอกชื่อ' : null;
  String? _validateSurname() => _surnameController.text.trim().isEmpty ? 'กรุณากรอกนามสกุล' : null;
  String? _validateUsername() => _usernameReg.hasMatch(_userController.text.trim())
      ? null
      : 'ชื่อผู้ใช้ต้องเป็น A-Z, a-z, ตัวเลข, _ หรือ . และยาวอย่างน้อย 4 ตัวอักษร';
  String? _validateEmail() =>
      _emailReg.hasMatch(_emailController.text.trim()) ? null : 'กรุณากรอกอีเมลภาษาอังกฤษให้ถูกต้อง';
  String? _validateConfirm() =>
      _confirmController.text == _passController.text ? null : 'รหัสผ่านไม่ตรงกัน';

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _userController.dispose();
    _emailController.dispose();
    _passController.dispose();
    _confirmController.dispose();
    _nameFocus.dispose();
    _surnameFocus.dispose();
    _userFocus.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {Widget? suffix, String? errorText}) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecoration(
      labelText: label,
      suffixIcon: suffix,
      errorText: errorText,
      filled: true,
      fillColor: AppColors.gray50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(AppColors.gray100, 1),
      enabledBorder: border(AppColors.gray100, 1),
      focusedBorder: border(AppColors.teal500, 2),
      errorBorder: border(AppColors.coral400, 1),
      focusedErrorBorder: border(AppColors.coral400, 2),
    );
  }

  Widget _strengthBar() {
    final pass = _passController.text;
    if (pass.isEmpty) return const SizedBox.shrink();
    final strength = _passwordStrength(pass);
    final segments = switch (strength) {
      _PasswordStrength.weak => 1,
      _PasswordStrength.medium => 2,
      _PasswordStrength.strong => 3,
    };
    final color = switch (strength) {
      _PasswordStrength.weak => AppColors.coral400,
      _PasswordStrength.medium => AppColors.amber500,
      _PasswordStrength.strong => AppColors.teal500,
    };
    final label = switch (strength) {
      _PasswordStrength.weak => 'รหัสผ่านอ่อน',
      _PasswordStrength.medium => 'รหัสผ่านปานกลาง',
      _PasswordStrength.strong => 'รหัสผ่านแข็งแรง',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(
              3,
              (i) => Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: i < segments ? color : AppColors.gray100,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: AppTextStyles.caption.copyWith(color: color)),
        ],
      ),
    );
  }

  void _onRegister() async {
    if (_loading) return;

    final name = _nameController.text.trim();
    final surname = _surnameController.text.trim();
    final user = _userController.text.trim();
    final email = _emailController.text.trim();
    final pass = _passController.text;

    setState(() {
      _nameError = _validateName();
      _surnameError = _validateSurname();
      _usernameError = _validateUsername();
      _emailError = _validateEmail();
      _passwordError = validatePassword(pass);
      _confirmError = _validateConfirm();
      _submitError = null;
    });

    if (_nameError != null ||
        _surnameError != null ||
        _usernameError != null ||
        _emailError != null ||
        _passwordError != null ||
        _confirmError != null) {
      return;
    }

    setState(() => _loading = true);

    final url = Uri.parse('${getApiBase()}/register/');

    try {
      final resp = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': user,
              'email': email,
              'password': pass,
              'confirm_password': _confirmController.text,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          resp.body.isNotEmpty) {
        final j = jsonDecode(resp.body);

        final token =
            j['token'] ??
            j['authToken'] ??
            j['password_token'] ??
            (j['data'] != null ? j['data']['authToken'] : null);

        final id =
            j['user_id'] ??
            j['id'] ??
            (j['data'] != null ? j['data']['userid'] : null);

        if (token != null && id != null) {
          await AuthService().handleAuthSuccess(token, {
            'id': id,
            'username': j['username'] ?? user,
            'email': j['email'] ?? email,
          });
          // ชื่อ-นามสกุลไม่ได้อยู่ใน payload ของ /register (backend เดิม) —
          // ใช้ endpoint PATCH /user/<id> ที่มีอยู่แล้ว (ผ่าน saveUser) แทน
          // การแก้ backend เพิ่ม
          await AuthService().saveUser({'name': name, 'surname': surname});
        }

        if (!mounted) return;

        // ปิด flow สมัครสมาชิกกลับไปที่ RootShell เดิม แทนการ push
        // MainScreen() ใหม่ทับซึ่งจะทำให้แถบนำทางล่าง/FAB ของ RootShell หายไป
        Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
      } else {
        String msg = 'สมัครสมาชิกไม่สำเร็จ';
        try {
          if (resp.body.isNotEmpty) {
            final j = jsonDecode(resp.body);
            if (j is Map && j['error'] != null) {
              msg = j['error'].toString();
            }
          }
        } catch (_) {}

        if (!mounted) return;
        setState(() => _submitError = msg);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitError = 'ไม่สามารถติดต่อเซิร์ฟเวอร์ได้');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
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
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Icon(Icons.arrow_back, color: AppColors.gray900, size: 26),
                  ),
                  const Expanded(child: SizedBox()),
                  Text('สมัครสมาชิก', style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900)),
                  const Expanded(child: SizedBox()),
                  const SizedBox(width: 26),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_submitError != null) ...[
                      AppErrorBanner(message: _submitError!, onRetry: _onRegister),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nameController,
                            focusNode: _nameFocus,
                            textInputAction: TextInputAction.next,
                            decoration: _decoration('ชื่อ', errorText: _nameError),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _surnameController,
                            focusNode: _surnameFocus,
                            textInputAction: TextInputAction.next,
                            decoration: _decoration('นามสกุล', errorText: _surnameError),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _userController,
                      focusNode: _userFocus,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_.]')),
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                      decoration: _decoration('ชื่อผู้ใช้งาน', errorText: _usernameError),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _emailController,
                      focusNode: _emailFocus,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9@._\-\+]')),
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                      decoration: _decoration('อีเมล', errorText: _emailError),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passController,
                      focusNode: _passFocus,
                      obscureText: _obscurePass,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9!@#\$%\^&\*\(\)_\-\+\=\{\}\[\]\|;:\x27\x22,<>\.\?\/\\`~]')),
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                      decoration: _decoration(
                        'รหัสผ่าน',
                        errorText: _passwordError,
                        suffix: IconButton(
                          onPressed: () => setState(() => _obscurePass = !_obscurePass),
                          icon: Icon(
                            _obscurePass ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.gray400,
                          ),
                        ),
                      ),
                    ),
                    _strengthBar(),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirmController,
                      focusNode: _confirmFocus,
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _onRegister(),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9!@#\$%\^&\*\(\)_\-\+\=\{\}\[\]\|;:\x27\x22,<>\.\?\/\\`~]')),
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                      decoration: _decoration(
                        'ยืนยันรหัสผ่าน',
                        errorText: _confirmError,
                        suffix: IconButton(
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.gray400,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _onRegister,
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
                                'สมัครสมาชิก',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
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
