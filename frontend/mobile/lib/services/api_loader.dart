import 'dart:convert';
import '../models/menu_item_detail.dart';
import 'app_config.dart';
import 'api_client.dart';

class ApiLoader {
  static final ApiClient _client = ApiClient(getApiBase());

  /// รายละเอียดเต็มของเมนู 1 ชิ้น (แคลอรี/โปรตีน/คาร์บ/ไขมัน/น้ำตาล/ใยอาหาร)
  /// ค้นด้วยชื่อ exact match ผ่าน POST /menu-info จริง (ครอบคลุมทั้งอาหารคาว/
  /// ของหวาน/เครื่องดื่ม) คืน null ถ้าเรียกไม่สำเร็จหรือไม่พบเมนูนี้ในระบบ
  static Future<MenuItemDetail?> loadMenuDetail(String name) async {
    try {
      final resp = await _client.post(
        '/menu-info',
        body: {
          'names': [name],
        },
      );
      if (resp.statusCode != 200) return null;
      final decoded = json.decode(resp.body) as Map<String, dynamic>;
      final items = decoded['items'] as List<dynamic>?;
      if (items == null || items.isEmpty) return null;
      final detail = MenuItemDetail.fromJson(items.first as Map<String, dynamic>);
      return detail.isKnown ? detail : null;
    } catch (_) {
      return null;
    }
  }

  static List<String> _namesFromItemsResponse(String body) {
    final m = json.decode(body) as Map<String, dynamic>;
    final items = (m['items'] as List<dynamic>?) ?? const [];
    return items
        .map((i) {
          final map = i as Map<String, dynamic>;
          final nameTh = map['name_th'] as String?;
          return (nameTh != null && nameTh.isNotEmpty) ? nameTh : (map['name'] as String? ?? '');
        })
        .where((n) => n.isNotEmpty)
        .toList();
  }

  static Future<List<String>> _loadByType(String type) async {
    try {
      final resp = await _client.get('/api/food-items?type=$type');
      if (resp.statusCode != 200) return [];
      return _namesFromItemsResponse(resp.body);
    } catch (_) {
      return [];
    }
  }

  /// หา category_id จากชื่อหมวด (food_categories ไม่มี query-by-name ตรงๆ
  /// ฝั่ง backend จึงดึงรายการหมวดของ type นั้นมาหาเองที่นี่)
  static Future<List<String>> _loadByCategoryName(String type, String categoryName) async {
    try {
      final catResp = await _client.get('/api/food-categories?type=$type');
      if (catResp.statusCode != 200) return [];
      final cats = json.decode(catResp.body) as List<dynamic>;
      final match = cats.cast<Map<String, dynamic>>().where((c) => c['name'] == categoryName);
      if (match.isEmpty) return [];
      final categoryId = match.first['id'];
      final itemsResp = await _client.get('/api/food-items?category_id=$categoryId');
      if (itemsResp.statusCode != 200) return [];
      return _namesFromItemsResponse(itemsResp.body);
    } catch (_) {
      return [];
    }
  }

  // Desserts come from food_items (type=dessert)
  static Future<List<String>> loadDessertMenus() => _loadByType('dessert');

  // เครื่องดื่ม: ไม่มีหมวดย่อยแบบ "เพื่อสุขภาพ/ลดน้ำหนัก/เพิ่มพลังงาน" ใน schema
  // ใหม่แล้ว (food_categories มีแค่ type=drink เดียว) ทั้ง 3 เมธอดนี้จึงคืน
  // เครื่องดื่มทั้งหมดเหมือนกัน — หน้าที่เรียกใช้ (menu_food_page/class_food_page)
  // รวมทั้ง 3 ผลลัพธ์เป็น Set เดียวอยู่แล้วจึงไม่กระทบผลลัพธ์สุดท้าย
  static Future<List<String>> loadHealthyDrinks() => _loadByType('drink');
  static Future<List<String>> loadWeightLossDrinks() => _loadByType('drink');
  static Future<List<String>> loadEnergyDrinks() => _loadByType('drink');

  // อาหาร: หมวดหมู่ใหม่ไม่มี "ครบ5หมู่/ลดน้ำหนัก/สร้างกล้ามเนื้อ" แบบ query
  // keyword เดิมอีกต่อไป จับคู่กับ food_categories จริงที่ใกล้เคียงที่สุดแทน —
  // key ของ map คืนแค่ 1 อันเพราะหน้าที่เรียกใช้ flatten ทุก key รวมกันอยู่แล้ว
  static Future<Map<String, Set<String>>> loadProteinMenus() async {
    final items = await _loadByCategoryName('food', 'โปรตีนสูง');
    return {'โปรตีนสูง': items.toSet()};
  }

  static Future<Map<String, Set<String>>> loadVegetableMenus() async {
    final items = await _loadByCategoryName('food', 'ผัก/ธัญพืช');
    return {'ผัก/ธัญพืช': items.toSet()};
  }

  static Future<Map<String, Set<String>>> loadCarbMenus() async {
    final items = await _loadByCategoryName('food', 'อาหารจานเดียว');
    return {'อาหารจานเดียว': items.toSet()};
  }
}
