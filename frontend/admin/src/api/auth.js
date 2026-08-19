import { apiGet, apiPost } from './client';

export function login(username, password) {
  return apiPost('/admin/login', { username, password });
}

export function logout() {
  return apiPost('/admin/logout');
}

// No dedicated /admin/me endpoint exists; reuse an authenticated GET and
// treat 200 as logged-in, 401/403 as not.
export async function checkAuth() {
  try {
    await apiGet('/admin/users');
    return true;
  } catch (err) {
    if (err.status === 401 || err.status === 403) return false;
    throw err;
  }
}
