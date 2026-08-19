import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/widgets.dart';
import '../models/app_error.dart';
import '../models/report.dart';
import '../services/report_service.dart';

/// หน้าแชท ticket 1 เรื่อง — ใช้ทั้งฝั่งกำลังดำเนินการ (พิมพ์ตอบได้ +
/// polling ทุก 4 วินาทีให้เห็นข้อความแอดมินสด) และฝั่งปิดแล้ว (ดูอย่างเดียว
/// จากหน้าประวัติ — [report.status] เป็น closed ตั้งแต่แรกอยู่แล้วเสมอ)
class TicketChatPage extends StatefulWidget {
  final Report report;
  final ReportService reportService;

  const TicketChatPage({super.key, required this.report, required this.reportService});

  @override
  State<TicketChatPage> createState() => _TicketChatPageState();
}

class _TicketChatPageState extends State<TicketChatPage> {
  List<ReportMessage> _messages = [];
  ReportStatus _status = ReportStatus.pending;
  bool _canReply = true;
  bool _loading = true;
  String? _error;
  bool _sending = false;

  Timer? _pollTimer;
  final _inputCtrl = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _status = widget.report.status;
    _load();
    // ticket ที่ปิดแล้วไม่มีทางมีข้อความใหม่อีก ไม่ต้อง poll ให้เปลืองแบตเตอรี่/
    // network เปล่าๆ
    if (widget.report.status != ReportStatus.closed) {
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _load(silent: true));
    }
    // เปิดหน้า ticket นี้แล้ว = อ่านข้อความจากแอดมินล่าสุดแล้ว — badge/poller
    // ที่ RootShell จะไม่นับ ticket นี้เป็น unread อีกในรอบถัดไป
    widget.reportService.markReportRead(widget.report.id);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _inputCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final result = await widget.reportService.fetchMessages(widget.report.id);
    if (!mounted) return;
    result.when(
      ok: (thread) {
        final gotNewMessages = thread.messages.length != _messages.length;
        setState(() {
          _messages = thread.messages;
          _canReply = thread.canReply;
          _status = thread.status;
          _loading = false;
        });
        if (!thread.canReply) _pollTimer?.cancel(); // แอดมินเพิ่งปิดเรื่องระหว่างที่เปิดหน้านี้ค้างไว้
        if (gotNewMessages) _scrollToBottom();
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final result = await widget.reportService.sendMessage(widget.report.id, text);
    if (!mounted) return;
    result.when(
      ok: (msg) {
        setState(() {
          _messages = [..._messages, msg];
          _sending = false;
          _inputCtrl.clear();
        });
        _scrollToBottom();
      },
      err: (error) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toUserMessage())));
        // ปิดเรื่องไปพอดีระหว่างที่กำลังพิมพ์ (409 TICKET_CLOSED) — โหลดสถานะ
        // ใหม่ให้ UI สลับเป็นโหมดอ่านอย่างเดียวทันที
        if (error is ConflictError) _load();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(widget.report.title.isEmpty ? 'รายงานปัญหา' : widget.report.title)),
      body: Column(
        children: [
          if (_status == ReportStatus.closed)
            Container(
              width: double.infinity,
              color: AppColors.gray50,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'เรื่องนี้ปิดแล้ว — ดูประวัติแชทได้อย่างเดียว',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
              ),
            ),
          Expanded(child: _buildBody()),
          if (_canReply) _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (_, _) => const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: AppSkeletonLoader(variant: AppSkeletonVariant.listItem),
        ),
      );
    }
    if (_error != null) {
      return Column(
        children: [
          AppErrorBanner(message: _error!, onRetry: _load),
          const Spacer(),
        ],
      );
    }
    if (_messages.isEmpty) {
      return AppEmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'ยังไม่มีข้อความ',
        ctaLabel: 'รีเฟรช',
        onCta: _load,
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, i) => _buildBubble(_messages[i]),
    );
  }

  Widget _buildBubble(ReportMessage m) {
    final isUser = m.sender == ReportSender.user;
    final time = m.createdAt;
    final timeLabel = time == null
        ? ''
        : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? AppColors.teal500 : AppColors.gray50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              m.message.isEmpty ? '-' : m.message,
              style: AppTextStyles.bodyMedium.copyWith(color: isUser ? Colors.white : AppColors.gray900),
            ),
            const SizedBox(height: 4),
            Text(
              '${isUser ? 'คุณ' : 'แอดมิน'}${timeLabel.isEmpty ? '' : ' • $timeLabel'}',
              style: AppTextStyles.caption.copyWith(color: isUser ? Colors.white70 : AppColors.gray400),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'พิมพ์ข้อความ...',
                  filled: true,
                  fillColor: AppColors.gray50,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: AppColors.gray100),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: AppColors.gray100),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: AppColors.teal500, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                onPressed: _sending ? null : _send,
                style: IconButton.styleFrom(backgroundColor: AppColors.teal500, foregroundColor: Colors.white),
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
