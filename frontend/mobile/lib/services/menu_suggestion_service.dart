import 'auth_service.dart';
import 'typed_api_client.dart';
import '../models/result.dart';
import '../models/menu_suggestion.dart';

/// ส่งข้อเสนอเมนูใหม่ให้แอดมินตรวจ — เรียก POST /submit ที่ backend มีอยู่แล้ว
/// (ดู backend/api.py submit()) แต่ฝั่งมือถือไม่เคยมี UI เรียกใช้เลย ผู้ใช้
/// รายงานจริง: หน้าแอดมินมีหน้า "ข้อเสนอเมนู" ไว้ตรวจอยู่แล้ว แต่ฝั่งผู้ใช้
/// ไม่มีทางส่งข้อเสนอเข้ามาได้เลยสักทาง
abstract class MenuSuggestionService {
  Future<Result<void>> submit({
    required String nameTh,
    String? nameEn,
    required String itemType,
    String? detail,
  });

  /// เช็คสถานะข้อเสนอของตัวเอง (pending/approved/rejected) — ผู้ใช้รายงานจริง:
  /// ส่งข้อเสนอไปแล้วไม่มีทางรู้เลยว่าแอดมินอนุมัติหรือปฏิเสธ (ดู
  /// backend/api.py my_submissions())
  Future<Result<List<MenuSuggestion>>> fetchMine();
}

class HttpMenuSuggestionService implements MenuSuggestionService {
  final TypedApiClient _client;
  final int? Function() _userId;

  HttpMenuSuggestionService(this._client, this._userId);

  @override
  Future<Result<void>> submit({
    required String nameTh,
    String? nameEn,
    required String itemType,
    String? detail,
  }) {
    final userId = _userId();
    return _client.postJson<void>(
      '/submit',
      body: {
        'user_id': userId,
        'name_th': nameTh,
        if (nameEn != null && nameEn.isNotEmpty) 'name_en': nameEn,
        'item_type': itemType,
        if (detail != null && detail.isNotEmpty) 'detail': detail,
      },
      decode: (_) {},
    );
  }

  @override
  Future<Result<List<MenuSuggestion>>> fetchMine() {
    return _client.getJson<List<MenuSuggestion>>(
      '/api/my_submissions',
      decode: (json) => ((json as Map<String, dynamic>)['submissions'] as List)
          .map((s) => MenuSuggestion.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

MenuSuggestionService createMenuSuggestionService() {
  final auth = AuthService();
  final client = TypedApiClient(tokenProvider: () => auth.token);
  return HttpMenuSuggestionService(client, () {
    final id = auth.user?['id'] ?? auth.user?['user_id'];
    return id == null ? null : int.tryParse(id.toString());
  });
}
