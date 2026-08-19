import 'dart:typed_data';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// หน้าตัดรูปโปรไฟล์ให้เป็นวงกลม — รับรูปต้นฉบับ ([imageBytes]) แล้วให้ผู้ใช้
/// ซูม/เลื่อนเลือกจุดที่ต้องการก่อนอัปโหลดจริง คืนผลลัพธ์เป็น Uint8List ของ
/// รูปที่ตัดแล้ว (jpg) ผ่าน Navigator.pop หรือ null ถ้ายกเลิก
class AvatarCropPage extends StatefulWidget {
  final Uint8List imageBytes;

  const AvatarCropPage({super.key, required this.imageBytes});

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  final _controller = CropController();
  bool _cropping = false;

  void _onCropped(CropResult result) {
    if (!mounted) return;
    switch (result) {
      case CropSuccess(:final croppedImage):
        Navigator.of(context).pop(croppedImage);
      case CropFailure():
        setState(() => _cropping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ตัดรูปไม่สำเร็จ กรุณาลองใหม่อีกครั้ง')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('ปรับตำแหน่งรูป'),
        actions: [
          TextButton(
            onPressed: _cropping
                ? null
                : () {
                    setState(() => _cropping = true);
                    _controller.cropCircle();
                  },
            child: Text(
              'เสร็จสิ้น',
              style: TextStyle(
                color: _cropping ? Colors.white54 : AppColors.teal500,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Crop(
            controller: _controller,
            image: widget.imageBytes,
            onCropped: _onCropped,
            withCircleUi: true,
            baseColor: Colors.black,
            maskColor: Colors.black.withValues(alpha: 0.65),
          ),
          if (_cropping)
            const ColoredBox(
              color: Colors.black38,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
