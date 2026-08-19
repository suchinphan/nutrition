import { useState } from 'react';
import {
  Modal, Stack, Group, Button, Text, FileInput, Table, Badge, Alert, Divider, Anchor,
} from '@mantine/core';
import { IconUpload, IconDownload, IconAlertTriangle } from '@tabler/icons-react';
import { notifications } from '@mantine/notifications';
import { importFoodItemsCsv } from '../api/foodMenus';

// คอลัมน์ต้องตรงกับที่ backend อ่านจริง (ดู admin_import_food_items /
// _parse_import_row ใน backend/admin/admin_routes.py) — name/category_name
// จำเป็น ที่เหลือเว้นว่างได้
const TEMPLATE_HEADERS = [
  'name', 'name_th', 'category_name', 'calories', 'protein_g', 'carbs_g', 'fat_g', 'fiber_g', 'sugar_g', 'image_url',
];
const TEMPLATE_SAMPLE_ROW = [
  'Grilled Chicken Breast', 'อกไก่ย่าง', 'อาหารจานหลัก', '165', '31', '0', '3.6', '0', '0', '',
];

function downloadCsvTemplate() {
  const csv = [TEMPLATE_HEADERS.join(','), TEMPLATE_SAMPLE_ROW.join(',')].join('\r\n');
  const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'food_items_import_template.csv';
  a.click();
  URL.revokeObjectURL(url);
}

const STATUS_LABEL = {
  would_create: 'จะสร้างใหม่',
  created: 'สร้างแล้ว',
  error: 'ผิดพลาด',
};
const STATUS_COLOR = {
  would_create: 'brandGreen',
  created: 'brandGreen',
  error: 'red',
};

function ResultTable({ results }) {
  return (
    <Table striped withTableBorder>
      <Table.Thead>
        <Table.Tr>
          <Table.Th w={60}>แถว</Table.Th>
          <Table.Th>ชื่อเมนู</Table.Th>
          <Table.Th>หมวดหมู่</Table.Th>
          <Table.Th w={120}>สถานะ</Table.Th>
          <Table.Th>หมายเหตุ</Table.Th>
        </Table.Tr>
      </Table.Thead>
      <Table.Tbody>
        {results.map((r) => (
          <Table.Tr
            key={r.row}
            style={r.status === 'error' ? { background: '#fef2f2' } : r.warning ? { background: '#fffbeb' } : undefined}
          >
            <Table.Td>{r.row}</Table.Td>
            <Table.Td>{r.name || '-'}</Table.Td>
            <Table.Td>{r.category_name || '-'}</Table.Td>
            <Table.Td><Badge color={STATUS_COLOR[r.status] || 'gray'} variant="light">{STATUS_LABEL[r.status] || r.status}</Badge></Table.Td>
            <Table.Td>
              {r.error && <Text size="sm" c="red">{r.error}</Text>}
              {r.warning && <Text size="sm" c="orange">{r.warning}</Text>}
            </Table.Td>
          </Table.Tr>
        ))}
      </Table.Tbody>
    </Table>
  );
}

export function ImportCsvModal({ opened, onClose, onImported }) {
  const [file, setFile] = useState(null);
  const [previewing, setPreviewing] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [preview, setPreview] = useState(null);
  const [finalResult, setFinalResult] = useState(null);

  const reset = () => {
    setFile(null);
    setPreview(null);
    setFinalResult(null);
  };

  const handleClose = () => {
    reset();
    onClose();
  };

  const handlePreview = async () => {
    if (!file) return;
    setPreviewing(true);
    setFinalResult(null);
    try {
      const result = await importFoodItemsCsv(file, true);
      setPreview(result);
    } catch (err) {
      notifications.show({ color: 'red', title: 'อ่านไฟล์ไม่สำเร็จ', message: err.message });
    } finally {
      setPreviewing(false);
    }
  };

  const handleConfirm = async () => {
    if (!file) return;
    setConfirming(true);
    try {
      const result = await importFoodItemsCsv(file, false);
      setFinalResult(result);
      notifications.show({
        color: result.error_count > 0 ? 'orange' : 'green',
        message: `นำเข้าสำเร็จ ${result.created_count} รายการ (ผิดพลาด ${result.error_count} รายการ)`,
      });
      onImported();
    } catch (err) {
      notifications.show({ color: 'red', title: 'นำเข้าไม่สำเร็จ', message: err.message });
    } finally {
      setConfirming(false);
    }
  };

  const displayed = finalResult || preview;

  return (
    <Modal opened={opened} onClose={handleClose} title="นำเข้าเมนูจาก CSV" centered size="xl">
      <Stack gap="md">
        <Group justify="space-between" align="flex-end">
          <FileInput
            label="เลือกไฟล์ CSV"
            placeholder="เลือกไฟล์..."
            accept=".csv,text/csv"
            leftSection={<IconUpload size={16} />}
            value={file}
            onChange={(f) => { setFile(f); setPreview(null); setFinalResult(null); }}
            flex={1}
          />
          <Anchor size="sm" onClick={downloadCsvTemplate} style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <IconDownload size={14} /> ดาวน์โหลด CSV ตัวอย่าง
          </Anchor>
        </Group>

        <Group justify="flex-end">
          <Button variant="light" color="brandGreen" onClick={handlePreview} loading={previewing} disabled={!file}>
            ดูตัวอย่างก่อนนำเข้า
          </Button>
        </Group>

        {displayed && (
          <>
            <Divider />
            <Group gap="lg">
              <Text size="sm">ทั้งหมด <b>{displayed.total_rows}</b> แถว</Text>
              <Text size="sm" c="brandGreen.7">
                {finalResult ? 'สร้างแล้ว' : 'จะสร้าง'} <b>{finalResult ? finalResult.created_count : displayed.would_create_count}</b> รายการ
              </Text>
              <Text size="sm" c="red">ผิดพลาด <b>{displayed.error_count}</b> แถว</Text>
            </Group>
            {displayed.new_categories?.length > 0 && (
              <Alert icon={<IconAlertTriangle size={16} />} color="yellow" variant="light">
                จะสร้างหมวดหมู่ใหม่อัตโนมัติ: {displayed.new_categories.join(', ')}
              </Alert>
            )}
            <ResultTable results={displayed.results} />
          </>
        )}

        <Group justify="flex-end" mt="sm">
          <Button variant="default" onClick={handleClose}>ปิด</Button>
          {preview && !finalResult && (
            <Button
              color="brandGreen"
              loading={confirming}
              disabled={preview.would_create_count === 0}
              onClick={handleConfirm}
            >
              ยืนยันนำเข้า ({preview.would_create_count} รายการ)
            </Button>
          )}
        </Group>
      </Stack>
    </Modal>
  );
}
