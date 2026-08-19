import { useEffect, useState } from 'react';
import { Stack, Title, Group, TextInput, Select, Table, Text, Badge, Button } from '@mantine/core';
import { IconSearch, IconShieldCheck } from '@tabler/icons-react';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useDebouncedValue } from '@mantine/hooks';
import { getUsers, promoteToAdmin } from '../api/members';
import { getAllergens } from '../api/foodMenus';

// ตรงกับตัวเลือกจริงที่แอปมือถือให้ผู้ใช้กรอก (ดู
// frontend/mobile/lib/page/profile_page.dart _goalOptions/_genderOptions)
// backend เก็บค่าดิบเป็นข้อความไทยตรงๆ ไม่แปลงเป็น enum อังกฤษ จึงต้องใช้
// ค่าเดียวกันเป๊ะตรงนี้ถึงจะ filter ตรง
const HEALTH_GOAL_OPTIONS = ['ลดน้ำหนัก', 'รักษาน้ำหนัก', 'เพิ่มน้ำหนัก'];
const GENDER_OPTIONS = ['ชาย', 'หญิง', 'ไม่ระบุ'];

export function MembersPage() {
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  // '' ไม่ใช่ null — Select ของ Mantine forward value ลง <input> จริงข้างใน
  // ตรงๆ ส่ง null เข้าไปโดนตรง React เตือน "value prop should not be null"
  // (controlled/uncontrolled ambiguity) ใช้ '' แทนตั้งแต่ initial state เลย
  const [healthGoal, setHealthGoal] = useState('');
  const [gender, setGender] = useState('');
  const [allergy, setAllergy] = useState('');
  const [allergensMaster, setAllergensMaster] = useState([]);
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => { getAllergens().then(setAllergensMaster).catch(() => {}); }, []);

  const loadUsers = () => {
    setLoading(true);
    return getUsers({ search: debouncedSearch, healthGoal, gender, allergy })
      .then(setUsers)
      .catch(() => setUsers([]))
      .finally(() => setLoading(false));
  };

  // loadUsers คืนค่า Promise (ให้ handlePromote เรียกซ้ำหลังตั้งแอดมินเสร็จ
  // ได้) — ห้ามส่ง loadUsers ตรงๆ เป็น callback ของ useEffect เพราะ React จะ
  // เอา Promise ที่มันคืนมาไปตีความเป็น cleanup function แทน แล้วพังตอน
  // unmount/effect รันซ้ำ ("destroy is not a function" — บั๊กที่เจอจริง) ห่อ
  // ด้วย arrow function เปล่าๆ กันไม่ให้ effect callback คืนอะไรกลับไปเลย
  useEffect(() => { loadUsers(); }, [debouncedSearch, healthGoal, gender, allergy]);

  // ตั้งผู้ใช้เป็นแอดมิน — ให้สิทธิ์เข้าหลังบ้านได้เต็มที่ ต้องยืนยันก่อนกัน
  // กดพลาด (ย้อนกลับเองไม่ได้จากหน้านี้ ต้องไปแก้ที่ฐานข้อมูลตรงถ้าตั้งผิดคน)
  const handlePromote = (u) => {
    modals.openConfirmModal({
      title: 'ยืนยันการตั้งเป็นแอดมิน',
      children: (
        <Text size="sm">
          ต้องการให้ "{u.username}" ({u.email || '-'}) เป็นแอดมินใช่หรือไม่?
          แอดมินจะเข้าถึงระบบหลังบ้านได้ทั้งหมด
        </Text>
      ),
      labels: { confirm: 'ตั้งเป็นแอดมิน', cancel: 'ยกเลิก' },
      confirmProps: { color: 'brandGreen' },
      onConfirm: async () => {
        try {
          await promoteToAdmin(u.id);
          notifications.show({ color: 'green', message: `ตั้ง ${u.username} เป็นแอดมินแล้ว` });
          loadUsers();
        } catch (err) {
          notifications.show({ color: 'red', title: 'ตั้งเป็นแอดมินไม่สำเร็จ', message: err.message });
        }
      },
    });
  };

  return (
    <Stack gap="lg">
      <Title order={3} c="brandGreen.6">ตรวจสอบข้อมูลสมาชิก</Title>

      <Group align="flex-end" wrap="wrap">
        <TextInput
          label="ค้นหา"
          placeholder="ชื่อผู้ใช้ / อีเมล / ชื่อ-นามสกุล"
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          w={260}
        />
        <Select
          label="เป้าหมายสุขภาพ"
          placeholder="ทั้งหมด"
          clearable
          data={HEALTH_GOAL_OPTIONS}
          value={healthGoal}
          onChange={(v) => setHealthGoal(v ?? '')}
          w={180}
        />
        <Select
          label="เพศ"
          placeholder="ทั้งหมด"
          clearable
          data={GENDER_OPTIONS}
          value={gender}
          onChange={(v) => setGender(v ?? '')}
          w={140}
        />
        <Select
          label="สารก่อภูมิแพ้"
          placeholder="ทั้งหมด"
          clearable
          searchable
          data={allergensMaster.map((a) => a.name)}
          value={allergy}
          onChange={(v) => setAllergy(v ?? '')}
          w={180}
        />
      </Group>

      <Text size="sm" c="dimmed">พบ {users.length} คน</Text>

      <Table striped highlightOnHover withTableBorder>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>ชื่อผู้ใช้</Table.Th>
            <Table.Th>อีเมล</Table.Th>
            <Table.Th>เพศ</Table.Th>
            <Table.Th>เป้าหมาย</Table.Th>
            <Table.Th>สารก่อภูมิแพ้</Table.Th>
            <Table.Th>สมัครเมื่อ</Table.Th>
            <Table.Th>สิทธิ์</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {users.map((u) => (
            <Table.Tr key={u.id}>
              <Table.Td>{u.username}</Table.Td>
              <Table.Td>{u.email || '-'}</Table.Td>
              <Table.Td>{u.gender || '-'}</Table.Td>
              <Table.Td>{u.health_goal || '-'}</Table.Td>
              <Table.Td>
                {u.food_allergies?.length
                  ? <Group gap={4}>{u.food_allergies.map((a) => <Badge key={a} size="xs" variant="light" color="orange">{a}</Badge>)}</Group>
                  : '-'}
              </Table.Td>
              <Table.Td>{u.created_at ? new Date(u.created_at).toLocaleDateString('th-TH') : '-'}</Table.Td>
              <Table.Td>
                {u.is_admin
                  ? <Badge color="brandGreen" leftSection={<IconShieldCheck size={12} />}>แอดมิน</Badge>
                  : <Button size="xs" variant="light" color="brandGreen" onClick={() => handlePromote(u)}>ตั้งเป็นแอดมิน</Button>}
              </Table.Td>
            </Table.Tr>
          ))}
          {!loading && users.length === 0 && (
            <Table.Tr>
              <Table.Td colSpan={7}><Text c="dimmed" ta="center" py="md">ไม่พบข้อมูล</Text></Table.Td>
            </Table.Tr>
          )}
        </Table.Tbody>
      </Table>
    </Stack>
  );
}
