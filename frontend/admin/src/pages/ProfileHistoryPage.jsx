import { useEffect, useState } from 'react';
import { Stack, Title, TextInput, Text, Group, Pagination, Card, Badge } from '@mantine/core';
import { IconSearch } from '@tabler/icons-react';
import { getProfileHistory } from '../api/profileHistory';

function EventCard({ event }) {
  return (
    <Card shadow="sm" padding="md" radius="md" withBorder>
      <Group justify="space-between" mb={4}>
        <Text fw={700}>{event.username || `user_${event.user_id}`}</Text>
        <Badge color={event.type === 'profile_edit' ? 'brandGreen' : 'gray'} variant="light">
          {event.type === 'profile_edit' ? 'แก้ไขข้อมูลส่วนตัว' : 'เสนอเมนู'}
        </Badge>
      </Group>
      {event.type === 'profile_edit' ? (
        <Text size="sm">
          {event.field_label}: {event.old_value ?? '(ว่าง)'} → {event.new_value ?? '(ว่าง)'}
        </Text>
      ) : (
        <Text size="sm">
          เสนอเมนู: {event.name_th || event.name_en || '-'}
          {' '}({event.item_type === 'drink' ? 'เครื่องดื่ม' : event.item_type === 'dessert' ? 'ของหวาน' : 'อาหาร'}) —{' '}
          สถานะ: {event.status === 'approved' ? 'อนุมัติแล้ว' : event.status === 'rejected' ? 'ปฏิเสธ' : 'รอตรวจ'}
        </Text>
      )}
      <Text size="xs" c="dimmed" mt={4}>
        {event.at ? new Date(event.at).toLocaleString('th-TH') : ''}
      </Text>
    </Card>
  );
}

export function ProfileHistoryPage() {
  const [events, setEvents] = useState([]);
  const [total, setTotal] = useState(0);
  const [search, setSearch] = useState('');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [page, setPage] = useState(1);
  const perPage = 20;

  useEffect(() => {
    // backend clamp per_page ไว้ที่ 200 สูงสุดเสมอ (ดู admin_routes.py) —
    // เดิมขอ 1000 ทั้งที่ไม่มีทางได้เกิน 200 แถวจริง แต่ตัวเลข "total" ที่
    // backend คืนกลับคำนวณจากก่อน clamp ทำให้ "N รายการทั้งหมด" ที่โชว์
    // มากกว่าที่เลื่อนดูได้จริงเสมอเมื่อมีมากกว่า 200 แถว (บั๊กที่เจอจริง)
    // ขอเท่าที่ backend ให้ได้จริงแทน กันความคาดหวังผิดว่าจะได้ครบ 1000
    getProfileHistory({ startDate, endDate, page: 1, perPage: 200 })
      .then((res) => {
        setEvents(res.events || []);
        setTotal(res.total || 0);
      })
      .catch(() => {
        setEvents([]);
        setTotal(0);
      });
  }, [startDate, endDate]);

  useEffect(() => { setPage(1); }, [search]);

  const filtered = events.filter((e) => {
    const q = search.trim().toLowerCase();
    if (!q) return true;
    return (e.username || '').toLowerCase().includes(q);
  });

  const totalPages = Math.max(1, Math.ceil(filtered.length / perPage));
  const pageSafe = Math.min(page, totalPages);
  const paginated = filtered.slice((pageSafe - 1) * perPage, pageSafe * perPage);

  return (
    <Stack gap="lg">
      <Title order={3} c="brandGreen.6">ประวัติการกรอกข้อมูล</Title>
      <Text size="sm" c="dimmed">
        ดูอย่างเดียว — แก้ไขหรือลบข้อมูลของสมาชิกจากหน้านี้ไม่ได้
        {' '}
        {total > events.length
          ? `(แสดง ${events.length} รายการล่าสุด จากทั้งหมด ${total} รายการ — จำกัดจำนวนที่โหลดต่อครั้ง ลองแคบช่วงวันที่เพื่อดูรายการเก่ากว่านี้)`
          : `(${total} รายการทั้งหมด)`}
      </Text>
      <Group align="flex-end">
        <TextInput
          label="ค้นหาชื่อผู้ใช้"
          placeholder="ค้นหาชื่อผู้ใช้..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          maw={280}
        />
        <TextInput
          type="date"
          label="ตั้งแต่วันที่"
          value={startDate}
          onChange={(e) => setStartDate(e.currentTarget.value)}
          maw={180}
        />
        <TextInput
          type="date"
          label="ถึงวันที่"
          value={endDate}
          onChange={(e) => setEndDate(e.currentTarget.value)}
          maw={180}
        />
      </Group>
      <Stack gap="sm">
        {paginated.map((e, i) => (
          <EventCard key={`${e.type}-${e.user_id}-${e.at}-${i}`} event={e} />
        ))}
        {filtered.length === 0 && <Text c="dimmed" ta="center" py="xl">ไม่พบข้อมูล</Text>}
      </Stack>
      {totalPages > 1 && (
        <Group justify="center">
          <Pagination total={totalPages} value={pageSafe} onChange={setPage} color="brandGreen" />
        </Group>
      )}
    </Stack>
  );
}
