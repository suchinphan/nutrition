import { Routes, Route } from 'react-router-dom';
import { ProtectedRoute } from './auth/ProtectedRoute';
import { AppShellLayout } from './components/AppShellLayout';
import { LoginPage } from './pages/LoginPage';
import { DashboardPage } from './pages/DashboardPage';
import { FoodCategoriesPage } from './pages/FoodCategoriesPage';
import { MenuFoodPage } from './pages/MenuFoodPage';
import { ProfileHistoryPage } from './pages/ProfileHistoryPage';
import { ReportsPage } from './pages/ReportsPage';
import { SubmissionsPage } from './pages/SubmissionsPage';
import { MembersPage } from './pages/MembersPage';
import { ActionLogPage } from './pages/ActionLogPage';

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route element={<ProtectedRoute />}>
        <Route element={<AppShellLayout />}>
          <Route path="/" element={<DashboardPage />} />
          <Route path="/food-categories" element={<FoodCategoriesPage />} />
          <Route path="/menu-food" element={<MenuFoodPage />} />
          <Route path="/submissions" element={<SubmissionsPage />} />
          <Route path="/members" element={<MembersPage />} />
          <Route path="/profile-history" element={<ProfileHistoryPage />} />
          <Route path="/reports" element={<ReportsPage />} />
          <Route path="/action-log" element={<ActionLogPage />} />
        </Route>
      </Route>
    </Routes>
  );
}
