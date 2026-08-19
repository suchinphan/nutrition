import '../models/food_item.dart';
import '../models/result.dart';
import 'auth_service.dart';
import 'typed_api_client.dart';

/// สัญญา (interface) ของ service ที่ดึงรายการเมนู — แทน endpoint แยก
/// food-menus/dessert-menus/drink-menus เดิม ด้วย /api/food-items เดียว
abstract class FoodItemService {
  Future<Result<List<FoodItem>>> fetchFoodItems({String? type, int? categoryId, String? search});
  Future<Result<FoodItem>> fetchFoodItemById(int id);

  /// เมนูยอดนิยม — นับสะสมตลอดกาลจากผู้ใช้ทุกคน (ไม่ใช่แค่ตัวเอง) ต่างจาก
  /// [MealLogService.fetchRecentItems] ที่นับเฉพาะประวัติของ user นี้คนเดียว
  Future<Result<List<FoodItem>>> fetchPopularItems({String? type, int limit = 10});

  /// หัวข้อเมนูทั้งหมด (food/drink/dessert built-in + หัวข้อที่แอดมินเพิ่มเอง)
  /// เรียงตามลำดับที่ตั้งไว้ในหน้าแอดมิน — ใช้สร้างแท็บ/ตัวกรองแบบไดนามิก
  /// (ดู backend/api.py api_food_types)
  Future<Result<List<String>>> fetchFoodTypes();
}

class HttpFoodItemService implements FoodItemService {
  final TypedApiClient _client;
  const HttpFoodItemService(this._client);

  @override
  Future<Result<List<FoodItem>>> fetchFoodItems({
    String? type,
    int? categoryId,
    String? search,
  }) {
    final params = <String, String>{
      if (type != null) 'type': type,
      if (categoryId != null) 'category_id': categoryId.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final query = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
    return _client.getJson<List<FoodItem>>(
      '/api/food-items$query',
      decode: (json) => ((json as Map<String, dynamic>)['items'] as List)
          .map((i) => FoodItem.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<Result<FoodItem>> fetchFoodItemById(int id) {
    return _client.getJson<FoodItem>(
      '/api/food-items/$id',
      decode: (json) => FoodItem.fromJson(json as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<List<FoodItem>>> fetchPopularItems({String? type, int limit = 10}) {
    final params = <String, String>{
      if (type != null) 'type': type,
      'limit': limit.toString(),
    };
    final query = '?${Uri(queryParameters: params).query}';
    return _client.getJson<List<FoodItem>>(
      '/api/food-items/popular$query',
      decode: (json) => ((json as Map<String, dynamic>)['items'] as List)
          .map((i) => FoodItem.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<Result<List<String>>> fetchFoodTypes() {
    return _client.getJson<List<String>>(
      '/api/food-types',
      decode: (json) => ((json as Map<String, dynamic>)['types'] as List)
          .map((t) => (t as Map<String, dynamic>)['name'] as String)
          .toList(),
    );
  }
}

FoodItemService createFoodItemService() {
  final client = TypedApiClient(tokenProvider: () => AuthService().token);
  return HttpFoodItemService(client);
}
