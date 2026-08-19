import { apiGet } from './client';

export const getActionLog = ({ entityType, limit = 100 } = {}) => {
  const params = new URLSearchParams();
  if (entityType) params.set('entity_type', entityType);
  if (limit) params.set('limit', limit);
  return apiGet(`/admin/action-log?${params.toString()}`).then((r) => r.action_log || []);
};
