import { useEffect, useState } from 'react';
import { Stack, Title, Group, Select, Button, Table, Text, Badge } from '@mantine/core';
import { IconRefresh } from '@tabler/icons-react';
import { getActionLog } from '../api/actionLog';

// ตรงกับ entity_type จริงที่ _log_admin_action ใน backend/admin/admin_routes.py
// เรียกใช้ (grep แล้วเจอทั้งหมด 5 ค่า) — ไม่มี endpoint แยกให้ดึงรายการนี้
// แบบ dynamic จึง hardcode ตรงนี้เหมือนที่ TYPE_LABELS ในหน้าอื่นทำอยู่แล้ว
const ENTITY_TYPE_LABEL = {
  food_category: 'หมวดหมู่อาหาร',
  food_item: 'เมนูอาหาร',
  report: 'รายงานปัญหา',
  user: 'สมาชิก',
  submission: 'ข้อเสนอเมนู',
};
const ACTION_COLOR = {
  create: 'brandGreen',
  update: 'blue',
  delete: 'red',
  approve: 'brandGreen',
  reject: 'red',
  restore: 'brandGreen',
  reply: 'blue',
  close: 'gray',
};

export function ActionLogPage() {
  // '' ไม่ใช่ null — Select ของ Mantine forward ลง <input> จริงข้างใน ส่ง
  // null ตรงๆ โดน React เตือน "value prop should not be null"
  const [entityType, setEntityType] = useState('');
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);

  const load = () => {
    setLoading(true);
    getActionLog({ entityType }).then(setRows).catch(() => setRows([])).finally(() => setLoading(false));
  };

  useEffect(load, [entityType]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <Stack gap="lg">
      <Title order={3} c="brandGreen.6">ประวัติการทำงานของแอดมิน</Title>

      <Group align="flex-end">
        <Select
          label="ประเภท"
          placeholder="ทั้งหมด"
          clearable
          data={Object.entries(ENTITY_TYPE_LABEL).map(([value, label]) => ({ value, label }))}
          value={entityType}
          onChange={(v) => setEntityType(v ?? '')}
          w={200}
        />
        <Button variant="light" color="brandGreen" leftSection={<IconRefresh size={16} />} onClick={load} loading={loading}>
          รีเฟรช
        </Button>
      </Group>

      <Table striped highlightOnHover withTableBorder>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>เวลา</Table.Th>
            <Table.Th>แอดมิน</Table.Th>
            <Table.Th>การกระทำ</Table.Th>
            <Table.Th>ประเภท</Table.Th>
            <Table.Th>รหัส</Table.Th>
            <Table.Th>รายละเอียด</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {rows.map((r) => (
            <Table.Tr key={r.id}>
              <Table.Td>{r.created_at ? new Date(r.created_at).toLocaleString('th-TH') : '-'}</Table.Td>
              <Table.Td>{r.admin_username || (r.admin_user_id ? `#${r.admin_user_id}` : '-')}</Table.Td>
              <Table.Td><Badge color={ACTION_COLOR[r.action] || 'gray'} variant="light">{r.action}</Badge></Table.Td>
              <Table.Td>{ENTITY_TYPE_LABEL[r.entity_type] || r.entity_type}</Table.Td>
              <Table.Td>{r.entity_id ?? '-'}</Table.Td>
              <Table.Td>{r.detail || '-'}</Table.Td>
            </Table.Tr>
          ))}
          {!loading && rows.length === 0 && (
            <Table.Tr>
              <Table.Td colSpan={6}><Text c="dimmed" ta="center" py="md">ไม่มีรายการ</Text></Table.Td>
            </Table.Tr>
          )}
        </Table.Tbody>
      </Table>
    </Stack>
  );
}
