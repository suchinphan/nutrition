import { useEffect, useRef, useState } from 'react';
import {
  Stack, Title, SegmentedControl, Accordion, Group, Text, Badge, Textarea, Button, Paper,
  ScrollArea, Skeleton,
} from '@mantine/core';
import { IconSend, IconCircleX } from '@tabler/icons-react';
import { notifications } from '@mantine/notifications';
import { modals } from '@mantine/modals';
import { getReports, replyReport, closeReport, getReportMessages } from '../api/reports';

const STATUS_META = {
  pending: { label: 'รอตรวจ', color: 'orange' },
  replied: { label: 'ตอบแล้ว', color: 'green' },
  closed: { label: 'เสร็จสิ้น', color: 'gray' },
};

function StatusBadge({ status }) {
  const meta = STATUS_META[status] || STATUS_META.pending;
  return <Badge color={meta.color} variant="light">{meta.label}</Badge>;
}

function MessageBubble({ msg }) {
  const isAdmin = msg.sender_type === 'admin';
  return (
    <Group justify={isAdmin ? 'flex-end' : 'flex-start'} wrap="nowrap" mb={8}>
      <Paper
        withBorder={!isAdmin}
        p="xs"
        radius="md"
        maw="75%"
        bg={isAdmin ? 'brandGreen.6' : 'gray.0'}
      >
        <Text size="sm" c={isAdmin ? 'white' : 'dark'} style={{ whiteSpace: 'pre-wrap' }}>
          {msg.message}
        </Text>
        <Text size="10px" c={isAdmin ? 'brandGreen.1' : 'dimmed'} mt={2}>
          {isAdmin ? 'แอดมิน' : 'ผู้ใช้'}
          {msg.created_at ? ` · ${new Date(msg.created_at).toLocaleString('th-TH')}` : ''}
        </Text>
      </Paper>
    </Group>
  );
}

// แชท 1 ticket — poll ทุก 4 วินาทีเฉพาะตอนเรื่องยังไม่ปิดและ panel เปิดอยู่
// (ticket ปิดแล้วไม่มีทางมีข้อความใหม่ ไม่ต้อง poll ให้เปลืองเปล่าๆ)
function TicketChatPanel({ report, onChanged }) {
  const [messages, setMessages] = useState([]);
  const [loading, setLoading] = useState(true);
  const [canReply, setCanReply] = useState(report.status !== 'closed');
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const pollRef = useRef(null);
  const viewportRef = useRef(null);

  const load = async (silent) => {
    if (!silent) setLoading(true);
    try {
      const data = await getReportMessages(report.id);
      setMessages(data.messages || []);
      setCanReply(!!data.can_reply);
      if (!data.can_reply && pollRef.current) {
        clearInterval(pollRef.current);
        pollRef.current = null;
      }
    } catch {
      // เงียบไว้ตอน silent refresh — ไม่ต้องกวน error ทุก 4 วินาทีถ้าหลุดชั่วคราว
    } finally {
      if (!silent) setLoading(false);
    }
  };

  useEffect(() => {
    load(false);
    if (report.status !== 'closed') {
      pollRef.current = setInterval(() => load(true), 4000);
    }
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [report.id]);

  useEffect(() => {
    if (viewportRef.current) {
      viewportRef.current.scrollTo({ top: viewportRef.current.scrollHeight, behavior: 'smooth' });
    }
  }, [messages]);

  const handleReply = async () => {
    const message = text.trim();
    if (!message) return;
    setBusy(true);
    try {
      await replyReport(report.id, message);
      setText('');
      await load(true);
      onChanged();
      notifications.show({ color: 'green', message: 'ตอบกลับแล้ว' });
    } catch (err) {
      notifications.show({ color: 'red', title: 'ตอบกลับไม่สำเร็จ', message: err.message });
    } finally {
      setBusy(false);
    }
  };

  const handleClose = () => {
    modals.openConfirmModal({
      title: 'ยืนยันการปิดเรื่อง',
      children: <Text size="sm">ต้องการปิดเรื่องนี้ใช่หรือไม่? หลังปิดแล้วผู้ใช้จะดูประวัติแชทได้อย่างเดียว</Text>,
      labels: { confirm: 'ปิดเรื่อง', cancel: 'ยกเลิก' },
      confirmProps: { color: 'gray' },
      onConfirm: async () => {
        try {
          await closeReport(report.id);
          notifications.show({ color: 'green', message: 'ปิดเรื่องแล้ว' });
          setCanReply(false);
          onChanged();
        } catch (err) {
          notifications.show({ color: 'red', title: 'ปิดเรื่องไม่สำเร็จ', message: err.message });
        }
      },
    });
  };

  if (loading) {
    return (
      <Stack gap="xs">
        <Skeleton height={40} radius="md" />
        <Skeleton height={40} radius="md" ml="30%" />
        <Skeleton height={40} radius="md" width="60%" />
      </Stack>
    );
  }

  return (
    <Stack gap="sm">
      <ScrollArea.Autosize mah={320} viewportRef={viewportRef}>
        {messages.length === 0 ? (
          <Text size="sm" c="dimmed" ta="center" py="md">ยังไม่มีข้อความ</Text>
        ) : (
          messages.map((m) => <MessageBubble key={m.id} msg={m} />)
        )}
      </ScrollArea.Autosize>

      {canReply ? (
        <>
          <Textarea
            placeholder="พิมพ์คำตอบกลับ..."
            value={text}
            onChange={(e) => setText(e.currentTarget.value)}
            autosize
            minRows={2}
            maxRows={6}
          />
          <Group justify="space-between">
            <Button
              variant="light"
              color="gray"
              leftSection={<IconCircleX size={16} />}
              onClick={handleClose}
            >
              ปิดเรื่อง
            </Button>
            <Button
              color="brandGreen"
              leftSection={<IconSend size={16} />}
              loading={busy}
              onClick={handleReply}
            >
              ตอบกลับ
            </Button>
          </Group>
        </>
      ) : (
        <Text size="xs" c="dimmed" ta="center">เรื่องนี้ปิดแล้ว — ดูประวัติแชทได้อย่างเดียว</Text>
      )}
    </Stack>
  );
}

export function ReportsPage() {
  const [reports, setReports] = useState([]);
  const [openCount, setOpenCount] = useState(0);
  const [filter, setFilter] = useState('open');

  const load = () => {
    getReports(filter).then(setReports).catch(() => setReports([]));
    getReports('open').then((r) => setOpenCount(r.length)).catch(() => {});
  };

  useEffect(() => {
    load();
    // รายการหลัก (ไม่ใช่ chat ที่เปิดอยู่) รีเฟรชห่างกว่า เพราะแค่ต้องการ
    // สถานะ/จำนวนรวมที่ไม่จำเป็นต้องสดเท่าตัวแชทเอง
    const interval = setInterval(load, 15000);
    return () => clearInterval(interval);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter]);

  return (
    <Stack gap="lg">
      <Group gap="xs">
        <Title order={3} c="brandGreen.6">รายงานปัญหา</Title>
        {openCount > 0 && <Badge color="orange" variant="filled">{openCount} กำลังดำเนินการ</Badge>}
      </Group>

      <SegmentedControl
        value={filter}
        onChange={setFilter}
        data={[
          { label: 'กำลังดำเนินการ', value: 'open' },
          { label: 'เสร็จสิ้น', value: 'closed' },
        ]}
      />

      {reports.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">ไม่มีรายการ</Text>
      ) : (
        <Accordion variant="separated" radius="md">
          {reports.map((r) => (
            <Accordion.Item key={r.id} value={String(r.id)}>
              <Accordion.Control>
                <Group justify="space-between" wrap="nowrap" pr="sm">
                  <Stack gap={0}>
                    <Text fw={600} size="sm">{r.title || '(ไม่มีหัวข้อ)'}</Text>
                    <Text size="xs" c="dimmed">
                      {r.username || `#${r.user_id}`}
                      {r.created_at ? ` · ${new Date(r.created_at).toLocaleString('th-TH')}` : ''}
                    </Text>
                  </Stack>
                  <StatusBadge status={r.status} />
                </Group>
              </Accordion.Control>
              <Accordion.Panel>
                <TicketChatPanel report={r} onChanged={load} />
              </Accordion.Panel>
            </Accordion.Item>
          ))}
        </Accordion>
      )}
    </Stack>
  );
}
