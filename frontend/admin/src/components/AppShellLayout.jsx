import { useEffect, useState } from 'react';
import { Outlet, Link, useLocation } from 'react-router-dom';
import { AppShell, Group, Text, Button, NavLink, Badge } from '@mantine/core';
import { IconLogout } from '@tabler/icons-react';
import { useAuth } from '../auth/AuthContext';
import { getSubmissions } from '../api/submissions';

const NAV_ITEMS = [
  { to: '/', label: 'แดชบอร์ด' },
  { to: '/food-categories', label: 'หมวดหมู่อาหาร' },
  { to: '/menu-food', label: 'เมนูอาหาร' },
  { to: '/submissions', label: 'ข้อเสนอเมนู', badgeKey: 'pendingSubmissions' },
  { to: '/members', label: 'ตรวจสอบข้อมูลสมาชิก' },
  { to: '/profile-history', label: 'ประวัติการกรอกข้อมูล' },
  { to: '/reports', label: 'รายงานปัญหา' },
  { to: '/action-log', label: 'ประวัติการทำงานแอดมิน' },
];

export function AppShellLayout() {
  const { logout } = useAuth();
  const location = useLocation();
  const [pendingSubmissions, setPendingSubmissions] = useState(0);

  useEffect(() => {
    const load = () => getSubmissions('pending').then((rows) => setPendingSubmissions(rows.length)).catch(() => {});
    load();
    // เบากว่ารายการหน้าอื่น (poll แค่จำนวน ไม่ใช่ทั้งลิสต์) — พอสำหรับ badge
    // ที่ไม่ต้องเรียลไทม์เป๊ะ
    const interval = setInterval(load, 30000);
    return () => clearInterval(interval);
  }, []);

  const badgeCounts = { pendingSubmissions };

  return (
    <AppShell header={{ height: 60 }} navbar={{ width: 220, breakpoint: 'sm' }} padding="md">
      <AppShell.Header>
        <Group h="100%" px="md" justify="space-between">
          <Text fw={700} c="brandGreen.6" size="lg">Admin</Text>
          <Button
            variant="subtle"
            color="red"
            leftSection={<IconLogout size={16} />}
            onClick={logout}
          >
            ออกจากระบบ
          </Button>
        </Group>
      </AppShell.Header>
      <AppShell.Navbar p="md">
        {NAV_ITEMS.map((item) => {
          const count = item.badgeKey ? badgeCounts[item.badgeKey] : 0;
          return (
            <NavLink
              key={item.to}
              component={Link}
              to={item.to}
              label={item.label}
              active={location.pathname === item.to}
              color="brandGreen"
              mb={4}
              rightSection={count > 0 ? <Badge color="orange" size="sm" circle>{count}</Badge> : null}
            />
          );
        })}
      </AppShell.Navbar>
      <AppShell.Main>
        <Outlet />
      </AppShell.Main>
    </AppShell>
  );
}
