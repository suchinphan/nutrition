import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/report.dart';
import '../services/report_service.dart';

/// หน้าแจ้งปัญหา — ticket schema ใหม่มีแค่ title+message (ไม่มี image_url/
/// ai_reply แล้ว) ปุ่ม/ฟอร์มแนบรูปจึงถูกตัดออกตามคำตอบที่ยืนยันไว้
class ReportProblemPage extends StatefulWidget {
  const ReportProblemPage({super.key});

  @override
  State<ReportProblemPage> createState() => _ReportProblemPageState();
}

class _ReportProblemPageState extends State<ReportProblemPage> {
  final Color primaryGreen = AppColors.leaf;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final ReportService _reportService = createReportService();
  bool _isSending = false;
  bool _isLoadingReports = false;
  List<Report> _reports = [];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    if (!mounted) return;
    setState(() => _isLoadingReports = true);
    final result = await _reportService.fetchMyReports();
    if (!mounted) return;
    result.when(
      ok: (reports) => setState(() => _reports = reports),
      err: (error) {
        if (kDebugMode) debugPrint('Load reports failed: ${error.toUserMessage()}');
      },
    );
    if (mounted) setState(() => _isLoadingReports = false);
  }

  Future<void> _submitReport() async {
    final title = _titleController.text.trim();
    final message = _messageController.text.trim();
    if (title.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกหัวข้อและรายละเอียดปัญหา')),
      );
      return;
    }

    setState(() => _isSending = true);
    final result = await _reportService.submitReportProblem(title: title, message: message);
    if (!mounted) return;
    result.when(
      ok: (_) async {
        _titleController.clear();
        _messageController.clear();
        await _loadReports();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ส่งรายงานปัญหาเรียบร้อยแล้ว')));
      },
      err: (error) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toUserMessage()))),
    );
    if (mounted) setState(() => _isSending = false);
  }

  String _formatDate(DateTime? createdAt) {
    if (createdAt == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(createdAt.day)}/${two(createdAt.month)}/${createdAt.year} ${two(createdAt.hour)}:${two(createdAt.minute)}';
  }

  (String, Color, Color) _statusMeta(ReportStatus status) => switch (status) {
    ReportStatus.replied => ('ตอบแล้ว', AppColors.leafLight, AppColors.leaf),
    ReportStatus.closed => ('ปิดเรื่อง', AppColors.line, AppColors.inkSoft),
    ReportStatus.pending => ('รอตรวจ', AppColors.turmericLight, AppColors.turmeric),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: primaryGreen),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'แจ้งปัญหา',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadReports,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.md),
          children: [
            _buildForm(),
            const SizedBox(height: AppSpace.xl),
            Text('รายการที่แจ้งไว้', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpace.sm),
            if (_isLoadingReports && _reports.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_reports.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('ยังไม่มีรายการที่แจ้ง', style: TextStyle(color: AppColors.inkSoft)),
                ),
              )
            else
              ..._reports.map(_buildReportCard),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: AppRadius.rMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('หัวข้อ', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(hintText: 'สรุปปัญหาสั้น ๆ'),
          ),
          const SizedBox(height: AppSpace.md),
          Text('รายละเอียด', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          TextField(
            controller: _messageController,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(hintText: 'อธิบายปัญหาที่พบ...'),
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton(
            onPressed: _isSending ? null : _submitReport,
            child: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('ส่ง'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(Report r) {
    final createdAt = _formatDate(r.createdAt);
    final (statusLabel, badgeBg, badgeFg) = _statusMeta(r.status);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: AppRadius.rMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  r.title.isEmpty ? '(ไม่มีหัวข้อ)' : r.title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: badgeBg, borderRadius: AppRadius.pill),
                child: Text(statusLabel,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: badgeFg)),
              ),
            ],
          ),
          if (r.message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(r.message, style: const TextStyle(fontSize: 13, color: AppColors.ink)),
          ],
          if (r.adminReply != null && r.adminReply!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: AppColors.leafLight,
                borderRadius: AppRadius.rSm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('คำตอบจากแอดมิน',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: primaryGreen)),
                  const SizedBox(height: 2),
                  Text(r.adminReply!, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
          if (createdAt.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(createdAt, style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
          ],
        ],
      ),
    );
  }
}
