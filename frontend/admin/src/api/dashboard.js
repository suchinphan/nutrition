import { apiGet } from './client';

// เดิมมี /admin/dashboard-stats ตัวเดียว (ยังคงไว้เผื่อโค้ดอื่นอ้างอิงอยู่)
// ตอนนี้แยกเป็น 5 endpoint ย่อยตาม Part 2 ของ prompt เพื่อให้แต่ละการ์ด/กราฟ
// โหลด+error อิสระจากกัน แทนที่จะรอข้อมูลก้อนเดียวทั้งหมด
export function getDashboardStats() {
  return apiGet('/admin/dashboard-stats');
}

export function getDashboardSummary() {
  return apiGet('/admin/dashboard/summary');
}

export function getMealTrend(days = 30) {
  return apiGet(`/admin/dashboard/meal-trend?days=${days}`);
}

// days: ไม่ส่ง (undefined) = all-time เหมือนเดิม, ส่งมาก็กรองเฉพาะ N วัน
// ย้อนหลัง (ใช้คู่กับฟิลเตอร์ วัน/เดือน/ปี ในหน้าแดชบอร์ด)
export function getFoodTypeDist(days) {
  return apiGet(`/admin/dashboard/food-type-dist${days ? `?days=${days}` : ''}`);
}

export function getTopFoods(limit = 10, days) {
  const params = new URLSearchParams({ limit });
  if (days) params.set('days', days);
  return apiGet(`/admin/dashboard/top-foods?${params.toString()}`);
}

export function getGoalDist() {
  return apiGet('/admin/dashboard/goal-dist');
}

export function getGenderDist() {
  return apiGet('/admin/dashboard/gender-dist');
}

export function getAllergenStats() {
  return apiGet('/admin/dashboard/allergen-stats');
}

export function getMenuCompleteness() {
  return apiGet('/admin/dashboard/menu-completeness');
}
