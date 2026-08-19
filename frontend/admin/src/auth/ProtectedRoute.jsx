import { Navigate, Outlet } from 'react-router-dom';
import { LoadingOverlay } from '@mantine/core';
import { useAuth } from './AuthContext';

export function ProtectedRoute() {
  const { user, loading } = useAuth();

  if (loading) {
    return <LoadingOverlay visible zIndex={1000} overlayProps={{ radius: 'sm', blur: 2 }} />;
  }

  if (!user) {
    return <Navigate to="/login" replace />;
  }

  return <Outlet />;
}
