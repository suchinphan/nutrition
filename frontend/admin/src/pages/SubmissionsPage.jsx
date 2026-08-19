import { useEffect, useState } from 'react';
import {
  Stack, Title, SegmentedControl, Accordion, Group, Text, Badge, Textarea, Button, Switch,
} from '@mantine/core';
import { IconCheck, IconX } from '@tabler/icons-react';
import { notifications } from '@mantine/notifications';
import { getSubmissions, approveSubmission, rejectSubmission } from '../api/submissions';

const ITEM_TYPE_LABEL = { food: 'อาหาร', drink: 'เครื่องดื่ม', dessert: 'ของหวาน' };
const STATUS_META = {
  pending: { label: 'รอตรวจ', color: 'orange' },
  approved: { label: 'อนุมัติแล้ว', color: 'brandGreen' },
  rejected: { label: 'ปฏิเสธแล้ว', color: 'red' },
};

function StatusBadge({ status }) {
  const meta = STATUS_META[status] || STATUS_META.pending;
  return <Badge color={meta.color} variant="light">{meta.label}</Badge>;
}

function SubmissionDetail({ sub, onChanged }) {
  const [createFoodItem, setCreateFoodItem] = useState(true);
  const [approving, setApproving] = useState(false);
  const [rejecting, setRejecting] = useState(false);
  const [showReject, setShowReject] = useState(false);
  const [reason, setReason] = useState('');

  const handleApprove = async () => {
    setApproving(true);
    try {
      const result = await approveSubmission(sub.id, createFoodItem);
      notifications.show({
        color: 'green',
        message: result.created_food_item_id
          ? `อนุมัติแล้ว — สร้างเมนูร่างใหม่ (id ${result.created_food_item_id}) แล้ว ไปเติมข้อมูลต่อได้ที่หน้าเมนูอาหาร`
          : 'อนุมัติแล้ว',
      });
      onChanged();
    } catch (err) {
      notifications.show({ color: 'red', title: 'อนุมัติไม่สำเร็จ', message: err.message });
    } finally {
      setApproving(false);
    }
  };

  const handleReject = async () => {
    if (!reason.trim()) return;
    setRejecting(true);
    try {
      await rejectSubmission(sub.id, reason.trim());
      notifications.show({ color: 'green', message: 'ปฏิเสธข้อเสนอแล้ว' });
      onChanged();
    } catch (err) {
      notifications.show({ color: 'red', title: 'ปฏิเสธไม่สำเร็จ', message: err.message });
    } finally {
      setRejecting(false);
    }
  };

  return (
    <Stack gap="sm">
      <Text size="sm"><b>ชื่อ (TH):</b> {sub.name_th || '-'}</Text>
      <Text size="sm"><b>ชื่อ (EN):</b> {sub.name_en || '-'}</Text>
      <Text size="sm"><b>ประเภท:</b> {ITEM_TYPE_LABEL[sub.item_type] || sub.item_type}</Text>
      <Text size="sm"><b>รายละเอียดที่ผู้ใช้ให้มา:</b> {sub.detail || '(ไม่มี)'}</Text>
      <Text size="xs" c="dimmed">
        ผู้เสนอ: {sub.user_id ? `#${sub.user_id}` : sub.anon_id ? `anon:${sub.anon_id}` : 'ไม่ทราบ'}
        {sub.created_at ? ` · ${new Date(sub.created_at).toLocaleString('th-TH')}` : ''}
      </Text>
      {sub.status === 'rejected' && sub.review_note && (
        <Text size="sm" c="red">เหตุผลที่ปฏิเสธ: {sub.review_note}</Text>
      )}

      {sub.status === 'pending' && (
        <Group justify="space-between" mt="xs" wrap="wrap">
          <Group>
            <Switch
              label="สร้างเมนูร่างอัตโนมัติ"
              checked={createFoodItem}
              onChange={(e) => setCreateFoodItem(e.currentTarget.checked)}
            />
            <Button color="brandGreen" leftSection={<IconCheck size={16} />} loading={approving} onClick={handleApprove}>
              อนุมัติ
            </Button>
          </Group>
          {!showReject ? (
            <Button variant="light" color="red" leftSection={<IconX size={16} />} onClick={() => setShowReject(true)}>
              ปฏิเสธ
            </Button>
          ) : null}
        </Group>
      )}

      {sub.status === 'pending' && showReject && (
        <Stack gap={4}>
          <Textarea
            placeholder="เหตุผลที่ปฏิเสธ (จำเป็น)"
            value={reason}
            onChange={(e) => setReason(e.currentTarget.value)}
            autosize
            minRows={2}
          />
          <Group justify="flex-end">
            <Button variant="default" size="xs" onClick={() => setShowReject(false)}>ยกเลิก</Button>
            <Button color="red" size="xs" loading={rejecting} disabled={!reason.trim()} onClick={handleReject}>
              ยืนยันปฏิเสธ
            </Button>
          </Group>
        </Stack>
      )}
    </Stack>
  );
}

export function SubmissionsPage() {
  const [filter, setFilter] = useState('pending');
  const [submissions, setSubmissions] = useState([]);
  const [pendingCount, setPendingCount] = useState(0);

  const load = () => {
    getSubmissions(filter).then(setSubmissions).catch(() => setSubmissions([]));
    getSubmissions('pending').then((rows) => setPendingCount(rows.length)).catch(() => {});
  };

  useEffect(() => {
    load();
    // เดิมโหลดครั้งเดียวตอนเปิดหน้า/เปลี่ยน filter เท่านั้น — ผู้ใช้ส่งข้อเสนอ
    // ใหม่มาระหว่างที่แอดมินเปิดหน้านี้ค้างไว้แล้วไม่เห็นเลยจนกว่าจะรีเฟรชเอง
    // ผูก poll เหมือน ReportsPage.jsx (รายการหลัก ไม่ใช่ chat) ทุก 15 วิ
    const interval = setInterval(load, 15000);
    return () => clearInterval(interval);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter]);

  return (
    <Stack gap="lg">
      <Group gap="xs">
        <Title order={3} c="brandGreen.6">ข้อเสนอเมนู</Title>
        {pendingCount > 0 && <Badge color="orange" variant="filled">{pendingCount} รอตรวจ</Badge>}
      </Group>

      <SegmentedControl
        value={filter}
        onChange={setFilter}
        data={[
          { label: 'รอตรวจ', value: 'pending' },
          { label: 'อนุมัติแล้ว', value: 'approved' },
          { label: 'ปฏิเสธแล้ว', value: 'rejected' },
          { label: 'ทั้งหมด', value: 'all' },
        ]}
      />

      {submissions.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">ไม่มีรายการ</Text>
      ) : (
        <Accordion variant="separated" radius="md">
          {submissions.map((s) => (
            <Accordion.Item key={s.id} value={String(s.id)}>
              <Accordion.Control>
                <Group justify="space-between" wrap="nowrap" pr="sm">
                  <Stack gap={0}>
                    <Text fw={600} size="sm">{s.name_th || s.name_en || '(ไม่มีชื่อ)'}</Text>
                    <Text size="xs" c="dimmed">{ITEM_TYPE_LABEL[s.item_type] || s.item_type}</Text>
                  </Stack>
                  <StatusBadge status={s.status} />
                </Group>
              </Accordion.Control>
              <Accordion.Panel>
                <SubmissionDetail sub={s} onChanged={load} />
              </Accordion.Panel>
            </Accordion.Item>
          ))}
        </Accordion>
      )}
    </Stack>
  );
}
