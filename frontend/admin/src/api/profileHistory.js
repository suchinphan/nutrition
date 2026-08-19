import { apiGet } from './client';

// Read-only — there is intentionally no update/delete function here.
// See backend/admin/admin_routes.py: GET /admin/profile-history is the
// only route for this data.
export async function getProfileHistory({ startDate, endDate, page = 1, perPage = 50 } = {}) {
  const params = new URLSearchParams();
  if (startDate) params.set('start_date', startDate);
  if (endDate) params.set('end_date', endDate);
  params.set('page', String(page));
  params.set('per_page', String(perPage));
  const res = await apiGet(`/admin/profile-history?${params.toString()}`);
  return res || { events: [], total: 0, page: 1, per_page: perPage };
}
