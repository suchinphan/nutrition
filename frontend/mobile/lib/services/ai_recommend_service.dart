import 'auth_service.dart';
import 'typed_api_client.dart';
import '../models/result.dart';

/// เมนูที่ระบบแนะนำหนึ่งรายการ — มาจาก POST /api/ai/recommend (ดู
/// backend/api.py ai_recommend_menu / health_calc.score_food_candidate)
class AiRecommendation {
  final int foodItemId;
  final String menuName;
  final String portionSize;
  final double calories;
  final String imageUrl;

  const AiRecommendation({
    required this.foodItemId,
    required this.menuName,
    required this.portionSize,
    required this.calories,
    required this.imageUrl,
  });

  factory AiRecommendation.fromJson(Map<String, dynamic> json) => AiRecommendation(
    foodItemId: json['food_item_id'] as int,
    menuName: json['menu_name'] as String? ?? '',
    portionSize: json['portion_size'] as String? ?? '',
    calories: (json['calories'] as num?)?.toDouble() ?? 0,
    imageUrl: json['image_url'] as String? ?? '',
  );
}

class AiRecommendResult {
  final double targetCalories;
  final List<AiRecommendation> items;
  // true เมื่อหมวดนี้ไม่ควรแนะนำเลยสำหรับโรคประจำตัวที่ผู้ใช้มี (เช่นเบาหวาน
  // กับของหวาน — ดู backend/health_calc.py blocked_category_reason) ต่างจาก
  // items ว่างเปล่าธรรมดา ต้องโชว์เหตุผลเจาะจงแทนข้อความ "ยังไม่มีเมนูแนะนำ"
  final bool blocked;
  final String? blockedReason;
  const AiRecommendResult({
    required this.targetCalories,
    required this.items,
    this.blocked = false,
    this.blockedReason,
  });
}

/// เรียก AI แนะนำเมนู (rule-based ranking ตามแคลอรีคงเหลือ+เป้าหมาย
/// สุขภาพ+โรคประจำตัว — ดู health_calc.score_food_candidate) ยังไม่เคยมี UI
/// ฝั่งมือถือเรียกใช้เลยตั้งแต่ backend เพิ่ม endpoint นี้มา (ผู้ใช้รายงานจริง)
String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

abstract class AiRecommendService {
  Future<Result<AiRecommendResult>> fetchRecommendations({
    required String category,
    int limit = 5,
    DateTime? date,
    bool randomize = false,
  });
}

class HttpAiRecommendService implements AiRecommendService {
  final TypedApiClient _client;
  HttpAiRecommendService(this._client);

  @override
  Future<Result<AiRecommendResult>> fetchRecommendations({
    required String category,
    int limit = 5,
    DateTime? date,
    bool randomize = false,
  }) {
    return _client.postJson<AiRecommendResult>(
      '/api/ai/recommend',
      body: {
        'category': category,
        'limit': limit,
        'randomize': randomize,
        if (date != null) 'date': _ymd(date),
      },
      decode: (json) {
        final map = json as Map<String, dynamic>;
        return AiRecommendResult(
          targetCalories: (map['target_calories'] as num?)?.toDouble() ?? 0,
          items: ((map['recommendations'] as List?) ?? const [])
              .map((r) => AiRecommendation.fromJson(r as Map<String, dynamic>))
              .toList(),
          blocked: map['blocked'] as bool? ?? false,
          blockedReason: map['reason'] as String?,
        );
      },
    );
  }
}

AiRecommendService createAiRecommendService() {
  final auth = AuthService();
  return HttpAiRecommendService(TypedApiClient(tokenProvider: () => auth.token));
}
