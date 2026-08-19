import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/widgets.dart';
import '../models/report.dart';
import '../services/report_service.dart';
import 'ticket_chat_page.dart';

/// หน้าแจ้งเตือนเต็มจอ — เดิมกดไอคอนกระดิ่งแล้วขึ้นแค่ SnackBar ลอยๆ หายไปเอง
/// โชว์ empty state ตายตัวไม่มีข้อมูลจริงเลย ทั้งที่แอปมีการแจ้งเตือนจริง
/// อยู่แล้วจุดเดียว — แอดมินตอบ ticket ที่ผู้ใช้แจ้งปัญหาไว้ (ดู
/// main.dart _pollUnreadCount ที่ยิง SnackBar/system notification ตอนมีของ
/// ใหม่ แต่ไม่เคยเก็บไว้ที่ไหนให้ย้อนดูได้ — ผู้ใช้รายงานจริง: เห็น SnackBar
/// เด้งแล้วแต่หน้านี้ไม่โชว์ย้อนหลังให้เลย) ดึง ticket ที่แอดมินตอบแล้ว
/// (replied/closed) มาแสดงเป็นประวัติแทน กดแต่ละอันเปิดหน้าแชทของเรื่องนั้น
/// ได้เลย (ตัวหน้าแชทเองมาร์กอ่านให้อัตโนมัติอยู่แล้ว)
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final ReportService _reportService = createReportService();
  bool _loading = true;
  String? _error;
  List<Report> _notifications = [];

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
    final results = await Future.wait([
      _reportService.fetchMyReports(scope: 'open'),
      _reportService.fetchMyReports(scope: 'closed'),
    ]);
    if (!mounted) return;
    final all = <Report>[];
    String? err;
    for (final r in results) {
      r.when(ok: all.addAll, err: (e) => err ??= e.toUserMessage());
    }
    // การแจ้งเตือน = ticket ที่แอดมินตอบแล้วเท่านั้น (replied/closed) — เรื่อง
    // ที่ยัง pending (แอดมินยังไม่ตอบ) ไม่มีอะไรให้แจ้งจริงๆ
    final notified = all.where((r) => r.status != ReportStatus.pending).toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    setState(() {
      _notifications = notified;
      _loading = false;
      _error = all.isEmpty ? err : null;
    });
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '-';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('การแจ้งเตือน')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(
          4,
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
    if (_notifications.isEmpty) {
      return AppEmptyState(
        icon: Icons.notifications_none,
        title: 'ยังไม่มีการแจ้งเตือน',
        subtitle: 'เมื่อแอดมินตอบเรื่องที่คุณแจ้งไว้ จะแสดงย้อนหลังไว้ที่นี่',
        ctaLabel: 'กลับ',
        onCta: () => Navigator.of(context).pop(),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _notifications.length,
      itemBuilder: (context, i) {
        final r = _notifications[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            // เดิมใช้ไอคอนแชทลอยเปล่าๆ ไม่มีพื้นหลัง ดูโล่ง/ไม่เข้าธีม —
            // ใส่วงกลมพื้นอ่อนสีเดียวกับที่การ์ดอื่นในแอปใช้ (teal50/teal600)
            // ให้เข้าชุดกับ AppAvatarInitials/การ์ดเป้าหมายสุขภาพ
            leading: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.teal50, shape: BoxShape.circle),
              child: const Icon(Icons.forum_rounded, color: AppColors.teal700, size: 22),
            ),
            title: Text(r.title.isEmpty ? '-' : r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              (r.adminReply != null && r.adminReply!.isNotEmpty)
                  ? r.adminReply!
                  : 'แอดมินตอบเรื่องที่คุณแจ้งไว้แล้ว',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(_formatDate(r.createdAt), style: AppTextStyles.caption),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TicketChatPage(report: r, reportService: _reportService),
              ),
            ),
          ),
        );
      },
    );
  }
}
