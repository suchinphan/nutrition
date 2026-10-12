import { apiGet, apiPost, apiPut, apiDelete } from './client';

// food_items รวม food/drink/dessert เป็นตารางเดียวแล้ว (แทน food-menus/
// dessert-menus/drink-menus เดิม) — ดู backend/admin/admin_routes.py
export const getFoodCategories = (type) =>
  apiGet(`/api/food-categories${type ? `?type=${type}` : ''}`);

export const createFoodCategory = (type, name) =>
  apiPost('/admin/food-categories', { type, name });
export const renameFoodCategory = (id, name) =>
  apiPut(`/admin/food-categories/${id}`, { name });
export const deleteFoodCategory = (id) => apiDelete(`/admin/food-categories/${id}`);

// "หัวข้อ" ที่แอดมินเพิ่มเอง (นอกเหนือจาก food/drink/dessert built-in ที่แก้/ลบ
// ผ่านนี้ไม่ได้ — ดู backend/admin/admin_routes.py PROTECTED_FOOD_TYPES เพราะ
// แอปมือถือ/endpoint แนะนำเมนู hardcode รับแค่ 3 ค่านั้น)
export const getFoodTypes = () => apiGet('/admin/food-types').then((r) => r.types || []);
export const createFoodType = (name) => apiPost('/admin/food-types', { name });
export const reorderFoodTypes = (order) => apiPut('/admin/food-types/reorder', { order });
export const renameFoodType = (oldType, name) =>
  apiPut(`/admin/food-types/${encodeURIComponent(oldType)}`, { name });
export const deleteFoodType = (type) =>
  apiDelete(`/admin/food-types/${encodeURIComponent(type)}`);

export const getFoodItems = (type) =>
  apiGet(`/admin/food-items${type ? `?type=${type}` : ''}`).then((r) => r.items || []);

export const createFoodItem = (payload) => apiPost('/admin/food-items', payload);
export const updateFoodItem = (id, payload) => apiPut(`/admin/food-items/${id}`, payload);
export const deleteFoodItem = (id) => apiDelete(`/admin/food-items/${id}`);

// dry_run=true (ค่า default ฝั่ง backend) แค่ preview ไม่แตะ DB — ต้องส่ง
// dry_run=false ชัดเจนถึงจะเขียนจริง (ดู admin_import_food_items)
export const importFoodItemsCsv = (file, dryRun, type) => {
  const formData = new FormData();
  formData.append('file', file);
  return apiPost(
    `/admin/food-items/import?type=${encodeURIComponent(type)}&dry_run=${dryRun ? 'true' : 'false'}`,
    formData
  );
};

export const addServingSize = (itemId, payload) =>
  apiPost(`/admin/food-items/${itemId}/serving-sizes`, payload);
export const updateServingSize = (itemId, servingId, payload) =>
  apiPut(`/admin/food-items/${itemId}/serving-sizes/${servingId}`, payload);
export const deleteServingSize = (itemId, servingId) =>
  apiDelete(`/admin/food-items/${itemId}/serving-sizes/${servingId}`);

// master list สำหรับติ๊กเลือก — endpoint แคบๆ ที่ขออนุญาตเพิ่มไว้ (ดู
// backend/admin/admin_routes.py admin_list_allergens)
export const getAllergens = () => apiGet('/admin/allergens').then((r) => r.allergens || []);
export const createAllergen = (name) => apiPost('/admin/allergens', { name });
export const updateAllergen = (id, name) => apiPut(`/admin/allergens/${id}`, { name });
export const deleteAllergen = (id) => apiDelete(`/admin/allergens/${id}`);
export const setFoodItemAllergens = (itemId, allergenIds) =>
  apiPost(`/admin/food-items/${itemId}/allergens`, { allergen_ids: allergenIds });
