import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/widgets.dart';
import '../models/report.dart';
import '../services/report_service.dart';
import 'ticket_chat_page.dart';

/// ประวัติ ticket ที่ปิดแล้วทั้งหมด — แยกออกมาจากหน้าโปรไฟล์ที่โชว์แค่เรื่อง
/// ที่กำลังดำเนินการ กันรายการยาวสะสมเรื่อยๆ ไม่รู้จบ แตะแต่ละใบเพื่อดู
/// ประวัติแชทได้ (อ่านอย่างเดียว)
class TicketHistoryPage extends StatefulWidget {
  final ReportService reportService;

  const TicketHistoryPage({super.key, required this.reportService});

  @override
  State<TicketHistoryPage> createState() => _TicketHistoryPageState();
}

class _TicketHistoryPageState extends State<TicketHistoryPage> {
  bool _loading = true;
  String? _error;
  List<Report> _reports = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.reportService.fetchMyReports(scope: 'closed');
    if (!mounted) return;
    result.when(
      ok: (reports) => setState(() {
        _reports = reports;
        _loading = false;
      }),
      err: (error) => setState(() {
        _loading = false;
        _error = error.toUserMessage();
      }),
    );
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '-';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(title: const Text('ประวัติการรายงานปัญหา')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(
          5,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: AppSkeletonLoader(variant: AppSkeletonVariant.listItem),
          ),
        ),
      );
    }
    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: AppErrorBanner(message: _error!, onRetry: _load),
          ),
        ],
      );
    }
    if (_reports.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: 400,
            child: AppEmptyState(
              icon: Icons.history,
              title: 'ยังไม่มีประวัติ ticket ที่ปิดแล้ว',
              ctaLabel: 'รีเฟรช',
              onCta: _load,
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _reports.length,
      itemBuilder: (context, i) {
        final r = _reports[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(r.title.isEmpty ? '-' : r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_formatDate(r.createdAt), style: AppTextStyles.caption),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.gray100, borderRadius: BorderRadius.circular(8)),
              child: Text('เสร็จสิ้น', style: AppTextStyles.caption.copyWith(color: AppColors.gray600)),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TicketChatPage(report: r, reportService: widget.reportService),
              ),
            ),
          ),
        );
      },
    );
  }
}
