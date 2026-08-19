import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/widgets.dart';
import '../services/auth_service.dart';
import '../services/consent_service.dart';

/// หน้ายินยอม PDPA — บังคับผ่านก่อนใช้ฟีเจอร์อื่นเมื่อ GET
/// /api/consents/status คืน consented=false (ดูจุดเรียกหน้านี้ใน
/// main.dart RootShell._maybeShowConsentGate) ปิดด้วยปุ่ม back ไม่ได้
/// (PopScope canPop:false) แต่ "ไม่ยินยอม" ยังเลือกออกจากระบบได้จริง —
/// ไม่ใช่กับดักที่ไม่มีทางออกเลย
///
/// หมายเหตุ: ข้อความอธิบายด้านล่างเป็น placeholder ตามใจความที่ขอ ควรให้
/// ฝ่ายกฎหมาย/PDPA officer จริงตรวจทานถ้อยคำก่อนใช้งานจริง
class PdpaConsentPage extends StatefulWidget {
  const PdpaConsentPage({super.key});

  @override
  State<PdpaConsentPage> createState() => _PdpaConsentPageState();
}

class _PdpaConsentPageState extends State<PdpaConsentPage> {
  final ConsentService _consentService = createConsentService();
  bool _agreed = false;
  bool _submitting = false;
  bool _loadingVersion = true;
  String _currentVersion = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final result = await _consentService.fetchStatus();
    if (!mounted) return;
    result.when(
      ok: (status) => setState(() {
        _currentVersion = status.currentVersion;
        _loadingVersion = false;
      }),
      err: (e) => setState(() {
        _loadingVersion = false;
        _error = e.toUserMessage();
      }),
    );
  }

  Future<void> _confirm() async {
    if (!_agreed || _submitting || _currentVersion.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await _consentService.giveConsent(_currentVersion);
    if (!mounted) return;
    result.when(
      ok: (_) => Navigator.of(context).pop(),
      err: (e) => setState(() {
        _submitting = false;
        _error = e.toUserMessage();
      }),
    );
  }

  Future<void> _decline() async {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('ยังไม่ยินยอมใช่ไหม?'),
        content: const Text(
          'ถ้ายังไม่ยินยอม ฟีเจอร์หลักของแอป (บันทึกการกิน ติดตามน้ำหนัก '
          'ดูประวัติ ฯลฯ) จะยังใช้งานไม่ได้ เพราะต้องใช้ข้อมูลสุขภาพของคุณ '
          'คุณสามารถอ่านรายละเอียดอีกครั้ง หรือออกจากระบบไปก่อนก็ได้',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop('reread'), child: const Text('อ่านอีกครั้ง')),
          TextButton(onPressed: () => Navigator.of(ctx).pop('logout'), child: const Text('ออกจากระบบ')),
        ],
      ),
    );
    if (choice == 'logout') {
      await AuthService().clearToken(force: true);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Widget _bullet(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('•  ', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray600)),
        Expanded(child: Text(text, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray600))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.gray50,
        appBar: AppBar(title: const Text('ความยินยอมใช้ข้อมูลสุขภาพ'), automaticallyImplyLeading: false),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'เพื่อใช้ฟีเจอร์หลักของแอปนี้ เราจำเป็นต้องขอความยินยอมในการเก็บ '
                'และใช้ข้อมูลสุขภาพของคุณ ตามพระราชบัญญัติคุ้มครองข้อมูลส่วนบุคคล (PDPA)',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray900),
              ),
              const SizedBox(height: 20),
              Text('ข้อมูลที่เราเก็บ', style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900)),
              const SizedBox(height: 8),
              _bullet('น้ำหนักและส่วนสูง'),
              _bullet('โรคประจำตัว'),
              _bullet('อาการแพ้อาหาร'),
              _bullet('ประวัติการกินอาหารของคุณ'),
              const SizedBox(height: 16),
              Text('นำไปใช้เพื่อ', style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900)),
              const SizedBox(height: 8),
              _bullet('คำนวณแคลอรีและคำแนะนำโภชนาการที่เหมาะกับคุณ'),
              _bullet('เตือนเมนูที่มีสารก่อภูมิแพ้ตรงกับที่คุณระบุไว้'),
              _bullet('ติดตามความก้าวหน้าของเป้าหมายสุขภาพที่คุณตั้งไว้'),
              const SizedBox(height: 16),
              Text('ใครเข้าถึงข้อมูลได้บ้าง', style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900)),
              const SizedBox(height: 8),
              _bullet('ทีมงานผู้ดูแลระบบของแอป เพื่อการสนับสนุน/ซ่อมบำรุงเท่านั้น'),
              _bullet('เราไม่ขายหรือเปิดเผยข้อมูลสุขภาพของคุณให้บุคคลภายนอกเพื่อการตลาด'),
              const SizedBox(height: 20),
              if (_error != null) ...[
                AppErrorBanner(message: _error!, onRetry: _loadingVersion ? _loadVersion : _confirm),
                const SizedBox(height: 16),
              ],
              CheckboxListTile(
                value: _agreed,
                onChanged: _loadingVersion ? null : (v) => setState(() => _agreed = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'ฉันอ่านและยินยอมให้เก็บ/ใช้ข้อมูลสุขภาพของฉันตามที่อธิบายข้างต้น',
                  style: AppTextStyles.bodyMedium,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: (_agreed && !_submitting && !_loadingVersion) ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teal500,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('ยินยอม', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _submitting ? null : _decline,
                  child: Text('ไม่ยินยอม', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.coral600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
