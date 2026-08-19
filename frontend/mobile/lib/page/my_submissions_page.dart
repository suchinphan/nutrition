import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/widgets.dart';
import '../models/menu_suggestion.dart';
import '../services/menu_suggestion_service.dart';

/// สถานะข้อเสนอเมนูที่ผู้ใช้เคยส่งไป — ผู้ใช้รายงานจริง: ส่งข้อเสนอแล้วไม่มี
/// ทางรู้เลยว่าแอดมินอนุมัติหรือปฏิเสธ (ดู TicketHistoryPage ที่ใช้ layout
/// เดียวกันสำหรับ ticket แจ้งปัญหา)
class MySubmissionsPage extends StatefulWidget {
  final MenuSuggestionService service;

  const MySubmissionsPage({super.key, required this.service});

  @override
  State<MySubmissionsPage> createState() => _MySubmissionsPageState();
}

class _MySubmissionsPageState extends State<MySubmissionsPage> {
  bool _loading = true;
  String? _error;
  List<MenuSuggestion> _submissions = [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // โผล่หน้านี้ค้างไว้รอผลแอดมิน — poll เหมือน ticket_chat_page.dart
    // (ทุก 5 วิ, silent ไม่กระพริบ skeleton) ยกเลิกเองใน _load() ตอนไม่มีรายการ
    // "รอตรวจสอบ" เหลือแล้ว กันเปลืองแบตเตอรี่/network เปล่าๆ
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final result = await widget.service.fetchMine();
    if (!mounted) return;
    result.when(
      ok: (submissions) {
        setState(() {
          _submissions = submissions;
          _loading = false;
        });
        if (submissions.every((s) => s.status != SubmissionStatus.pending)) {
          _pollTimer?.cancel();
        }
      },
      err: (error) {
        if (!silent) {
          setState(() {
            _loading = false;
            _error = error.toUserMessage();
          });
        }
      },
    );
  }

  // created_at มาจาก get_thailand_time() ฝั่ง backend อยู่แล้ว (ดู models.py)
  // เป็นเวลาไทยตรงๆ ไม่ต้องแปลง timezone เพิ่ม — รูปแบบเดียวกับ
  // report_problem_page.dart._formatDate
  String _formatDateTime(DateTime? d) {
    if (d == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)} น.';
  }

  (Color, Color) _statusColors(SubmissionStatus status) => switch (status) {
    SubmissionStatus.approved => (AppColors.teal50, AppColors.teal700),
    SubmissionStatus.rejected => (AppColors.coral50, AppColors.coral600),
    SubmissionStatus.pending => (AppColors.gray100, AppColors.gray600),
  };

  static const _itemTypeLabels = {'food': 'อาหาร', 'drink': 'เครื่องดื่ม', 'dessert': 'ของหวาน'};

  void _openDetail(MenuSuggestion s) {
    final (bg, fg) = _statusColors(s.status);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.nameTh.isEmpty ? '-' : s.nameTh,
                    style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                  child: Text(s.status.labelTh, style: AppTextStyles.caption.copyWith(color: fg)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if ((s.nameEn ?? '').isNotEmpty) ...[
              Text('ชื่อภาษาอังกฤษ', style: AppTextStyles.caption.copyWith(color: AppColors.gray600)),
              Text(s.nameEn!, style: AppTextStyles.bodyMedium),
              const SizedBox(height: 12),
            ],
            Text('ประเภท', style: AppTextStyles.caption.copyWith(color: AppColors.gray600)),
            Text(_itemTypeLabels[s.itemType] ?? s.itemType, style: AppTextStyles.bodyMedium),
            if ((s.detail ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('รายละเอียดที่ส่ง', style: AppTextStyles.caption.copyWith(color: AppColors.gray600)),
              Text(s.detail!, style: AppTextStyles.bodyMedium),
            ],
            const SizedBox(height: 12),
            Text('ส่งเมื่อ', style: AppTextStyles.caption.copyWith(color: AppColors.gray600)),
            Text(_formatDateTime(s.createdAt), style: AppTextStyles.bodyMedium),
            if (s.status == SubmissionStatus.rejected && (s.reviewNote ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('เหตุผลที่ปฏิเสธ', style: AppTextStyles.caption.copyWith(color: AppColors.gray600)),
              Text(s.reviewNote!, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.coral600)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(title: const Text('ข้อเสนอเมนูของฉัน')),
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
    if (_submissions.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: 400,
            child: AppEmptyState(
              icon: Icons.restaurant_menu_outlined,
              title: 'ยังไม่เคยเสนอเมนู',
              ctaLabel: 'รีเฟรช',
              onCta: _load,
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _submissions.length,
      itemBuilder: (context, i) {
        final s = _submissions[i];
        final (bg, fg) = _statusColors(s.status);
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openDetail(s),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.nameTh.isEmpty ? '-' : s.nameTh,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                        child: Text(s.status.labelTh, style: AppTextStyles.caption.copyWith(color: fg)),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, color: AppColors.gray400, size: 20),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_formatDateTime(s.createdAt), style: AppTextStyles.caption.copyWith(color: AppColors.gray600)),
                  if (s.status == SubmissionStatus.rejected && (s.reviewNote ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'เหตุผล: ${s.reviewNote}',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.coral600),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
