import { apiGet, apiPatch } from './client';

export const getSubmissions = (status = 'pending') =>
  apiGet(`/admin/submissions?status=${encodeURIComponent(status)}`).then((r) => r.submissions || []);

export const approveSubmission = (id, createFoodItem) =>
  apiPatch(`/admin/submissions/${id}/approve`, { create_food_item: !!createFoodItem });

export const rejectSubmission = (id, reason) =>
  apiPatch(`/admin/submissions/${id}/reject`, { reason });
