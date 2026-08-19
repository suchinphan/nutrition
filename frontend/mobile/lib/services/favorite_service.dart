import '../models/food_item.dart';
import '../models/result.dart';
import 'auth_service.dart';
import 'typed_api_client.dart';

/// สัญญา (interface) ของ service รายการโปรด — คุย /api/favorites จริง
abstract class FavoriteService {
  Future<Result<List<FoodItem>>> fetchFavorites();

  /// idempotent — เมนูนี้เป็นโปรดอยู่แล้วก็เรียกซ้ำได้ ไม่ error
  Future<Result<void>> addFavorite(int foodItemId);

  /// idempotent — ไม่ใช่โปรดอยู่แล้วก็เรียกซ้ำได้ ไม่ error
  Future<Result<void>> removeFavorite(int foodItemId);
}

class HttpFavoriteService implements FavoriteService {
  final TypedApiClient _client;
  const HttpFavoriteService(this._client);

  @override
  Future<Result<List<FoodItem>>> fetchFavorites() {
    return _client.getJson<List<FoodItem>>(
      '/api/favorites',
      decode: (json) => ((json as Map<String, dynamic>)['items'] as List)
          .map((i) => FoodItem.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<Result<void>> addFavorite(int foodItemId) {
    return _client.postJson<void>('/api/favorites/$foodItemId', decode: (_) {});
  }

  @override
  Future<Result<void>> removeFavorite(int foodItemId) {
    return _client.deleteJson<void>('/api/favorites/$foodItemId', decode: (_) {});
  }
}

FavoriteService createFavoriteService() {
  final client = TypedApiClient(tokenProvider: () => AuthService().token);
  return HttpFavoriteService(client);
}
