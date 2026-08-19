import { apiGet, apiPost } from './client';

// ทุก filter ต่อกันด้วย AND ฝั่ง backend เสมอ (ดู list_all_users ใน
// backend/admin/admin_routes.py) — ส่งเฉพาะ param ที่มีค่าจริง กัน query
// string รกด้วย key ว่างเปล่า
export const getUsers = ({ search, healthGoal, gender, allergy } = {}) => {
  const params = new URLSearchParams();
  if (search) params.set('search', search);
  if (healthGoal) params.set('health_goal', healthGoal);
  if (gender) params.set('gender', gender);
  if (allergy) params.set('allergy', allergy);
  const qs = params.toString();
  return apiGet(`/admin/users${qs ? `?${qs}` : ''}`).then((r) => r.users || []);
};

// ตั้งผู้ใช้คนนี้เป็นแอดมิน — ใช้ endpoint /admin/user/action ตัวเดียวกับ
// approve/delete เดิม (ดู backend/admin/admin_routes.py user_action) แค่เพิ่ม
// action ใหม่ ไม่สร้าง endpoint แยก
export const promoteToAdmin = (userId) =>
  apiPost('/admin/user/action', { user_id: userId, action: 'make_admin' });
