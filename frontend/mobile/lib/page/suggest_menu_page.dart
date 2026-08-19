import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../services/menu_suggestion_service.dart';
import 'my_submissions_page.dart';

const _itemTypeOptions = [
  ('food', 'อาหาร'),
  ('drink', 'เครื่องดื่ม'),
  ('dessert', 'ของหวาน'),
];

/// หน้าส่งข้อเสนอเมนูใหม่ให้แอดมินตรวจ — backend มี endpoint (POST /submit)
/// และหน้าแอดมิน ("ข้อเสนอเมนู") รอตรวจอยู่แล้ว แต่ฝั่งผู้ใช้ไม่เคยมีทางส่งเข้า
/// มาได้เลย (ผู้ใช้รายงานจริง) เข้าถึงจากปุ่มในหน้าหลัก/แดชบอร์ด
class SuggestMenuPage extends StatefulWidget {
  const SuggestMenuPage({super.key});

  @override
  State<SuggestMenuPage> createState() => _SuggestMenuPageState();
}

class _SuggestMenuPageState extends State<SuggestMenuPage> {
  final _nameThCtrl = TextEditingController();
  final _nameEnCtrl = TextEditingController();
  final _detailCtrl = TextEditingController();
  final _service = createMenuSuggestionService();
  String _itemType = _itemTypeOptions.first.$1;
  bool _sending = false;

  @override
  void dispose() {
    _nameThCtrl.dispose();
    _nameEnCtrl.dispose();
    _detailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final nameTh = _nameThCtrl.text.trim();
    if (nameTh.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกชื่อเมนูภาษาไทย')),
      );
      return;
    }
    setState(() => _sending = true);
    final result = await _service.submit(
      nameTh: nameTh,
      nameEn: _nameEnCtrl.text.trim(),
      itemType: _itemType,
      detail: _detailCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    result.when(
      ok: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ส่งข้อเสนอเมนูแล้ว รอแอดมินตรวจสอบ')),
        );
        Navigator.of(context).pop();
      },
      err: (error) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toUserMessage())),
      ),
    );
  }

  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('เสนอเมนูใหม่'),
        actions: [
          IconButton(
            tooltip: 'ข้อเสนอของฉัน',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MySubmissionsPage(service: _service)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'อยากให้แอดมินเพิ่มเมนูอะไรในแอป? กรอกรายละเอียดแล้วส่งได้เลย',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameThCtrl,
            decoration: _decoration('ชื่อเมนู (ภาษาไทย) *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameEnCtrl,
            decoration: _decoration('ชื่อเมนู (ภาษาอังกฤษ)', hint: 'ไม่บังคับ'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _itemType,
            decoration: _decoration('ประเภท'),
            items: _itemTypeOptions
                .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
                .toList(),
            onChanged: (v) => setState(() => _itemType = v ?? _itemType),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _detailCtrl,
            minLines: 3,
            maxLines: 6,
            decoration: _decoration('รายละเอียดเพิ่มเติม', hint: 'ส่วนผสม/เหตุผลที่อยากให้เพิ่ม (ไม่บังคับ)'),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _sending ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal500,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('ส่งข้อเสนอ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
