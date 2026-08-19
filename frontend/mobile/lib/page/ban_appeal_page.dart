import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/report_service.dart';

/// หน้าขอปลดแบน — ticket schema ใหม่ไม่มี image_url แล้ว ปุ่ม/ฟอร์มแนบรูป
/// จึงถูกตัดออกตามคำตอบที่ยืนยันไว้
class BanAppealPage extends StatefulWidget {
  final String? initialUsername;
  const BanAppealPage({super.key, this.initialUsername});

  @override
  State<BanAppealPage> createState() => _BanAppealPageState();
}

class _BanAppealPageState extends State<BanAppealPage> {
  final Color primaryGreen = AppColors.leaf;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ReportService _reportService = createReportService();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialUsername != null && widget.initialUsername!.isNotEmpty) {
      _usernameController.text = widget.initialUsername!;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendAppeal() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final text = _msgController.text.trim();

    if (username.isEmpty && email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกชื่อผู้ใช้หรืออีเมลเพื่อยืนยันบัญชี')),
      );
      return;
    }
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาระบุเหตุผลขอปลดแบน')),
      );
      return;
    }

    setState(() => _isSending = true);
    final result = await _reportService.submitUnbanRequest(
      message: text,
      username: username.isEmpty ? null : username,
      email: email.isEmpty ? null : email,
      password: password.isEmpty ? null : password,
    );
    if (!mounted) return;
    await result.when(
      ok: (_) async {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('ส่งคำขอแล้ว'),
            content: const Text('คำขอปลดแบนของคุณถูกส่งไปยังทีมผู้ดูแลระบบแล้ว เราจะติดต่อกลับโดยเร็วที่สุด'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ตกลง')),
            ],
          ),
        );
        if (!mounted) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) nav.pop();
      },
      err: (error) async {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toUserMessage())));
        if (kDebugMode) debugPrint('Send ban appeal failed: ${error.toUserMessage()}');
      },
    );
    if (mounted) setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F8F6),
        elevation: 0,
        iconTheme: IconThemeData(color: primaryGreen),
        title: Text(
          'ขอปลดแบน',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20.0),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'หากบัญชีของคุณถูกระงับ คุณสามารถส่งคำขอปลดแบนพร้อมเหตุผลได้ที่นี่',
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'ชื่อผู้ใช้',
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'อีเมล',
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'รหัสผ่าน (กรณีไม่ได้ล็อกอิน)',
                    hintText: 'กรอกเฉพาะถ้าคุณยังไม่ได้เข้าสู่ระบบ',
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _msgController,
                  minLines: 4,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: 'เหตุผลขอปลดแบน',
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSending ? null : _sendAppeal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('ส่งคำขอปลดแบน'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
