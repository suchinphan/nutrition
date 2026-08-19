import { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { login as apiLogin, logout as apiLogout, checkAuth } from '../api/auth';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      // checkAuth() rethrows anything that isn't a 401/403 (เช่น network
      // error ตอน backend ล่ม) — เดิมไม่มี try/catch ตรงนี้ ทำให้
      // setLoading(false) ไม่ถูกเรียกเลยถ้า throw จริง แอดมินแพนเนลค้างที่
      // loading spinner ตลอดไป (บั๊กที่เจอจริง) ถือว่า auth เช็คไม่ได้ =
      // ยังไม่ authenticated แทน ให้ตกไปหน้า login ตามปกติ
      try {
        const authenticated = await checkAuth();
        setUser(authenticated ? { authenticated: true } : null);
      } catch {
        setUser(null);
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  const login = useCallback(async (username, password) => {
    const result = await apiLogin(username, password);
    setUser(result);
    return result;
  }, []);

  const logout = useCallback(async () => {
    try {
      await apiLogout();
    } finally {
      setUser(null);
    }
  }, []);

  return (
    <AuthContext.Provider value={{ user, loading, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
