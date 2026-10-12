import { useEffect, useMemo, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { Tabs, TextInput, Table, ActionIcon, Button, Group, Title, Stack, Text, Badge } from '@mantine/core';
import { IconSearch, IconEdit, IconTrash, IconPlus, IconFileImport } from '@tabler/icons-react';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { getFoodItems, getFoodCategories, getFoodTypes, deleteFoodItem } from '../api/foodMenus';
import { MenuFoodModal } from '../components/MenuFoodModal';
import { ImportCsvModal } from '../components/ImportCsvModal';

// built-in 3 ประเภทมีป้ายกำกับภาษาไทยตายตัว หัวข้อที่แอดมินเพิ่มเองในหน้า
// "หมวดหมู่อาหาร" ใช้ชื่อที่พิมพ์ไว้ตรงๆ เป็นแท็บที่นี่ด้วย (ดึงจาก
// GET /admin/food-types เหมือนกัน ไม่ต้องมาแก้ไฟล์นี้ทุกครั้งที่เพิ่มหัวข้อใหม่)
const TYPE_LABELS = { food: 'อาหาร', drink: 'เครื่องดื่ม', dessert: 'ของหวาน' };

function MenuTable({ items, categoryNameById, search, onSearch, onEdit, onDelete }) {
  const filtered = items.filter((item) =>
    (item.name || '').toLowerCase().includes(search.toLowerCase()) ||
    (item.name_th || '').includes(search)
  );

  return (
    <Stack gap="sm">
      <TextInput
        placeholder="ค้นหาเมนู..."
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => onSearch(e.currentTarget.value)}
        maw={300}
      />
      <Table striped highlightOnHover withTableBorder>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>ชื่อ</Table.Th>
            <Table.Th>หมวดหมู่</Table.Th>
            <Table.Th>แคลอรี่</Table.Th>
            <Table.Th>สถานะ</Table.Th>
            <Table.Th w={100}></Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {filtered.map((item) => (
            <Table.Tr key={item.id}>
              <Table.Td>{item.name_th || item.name}</Table.Td>
              <Table.Td>{categoryNameById[item.category_id] || '-'}</Table.Td>
              <Table.Td>{item.calories ?? '-'}</Table.Td>
              <Table.Td>
                <Badge color={item.is_active ? 'brandGreen' : 'gray'} variant="light">
                  {item.is_active ? 'ใช้งาน' : 'ปิดใช้งาน'}
                </Badge>
              </Table.Td>
              <Table.Td>
                <Group gap={4}>
                  <ActionIcon variant="subtle" color="brandGreen" onClick={() => onEdit(item)}>
                    <IconEdit size={16} />
                  </ActionIcon>
                  <ActionIcon variant="subtle" color="red" onClick={() => onDelete(item)}>
                    <IconTrash size={16} />
                  </ActionIcon>
                </Group>
              </Table.Td>
            </Table.Tr>
          ))}
          {filtered.length === 0 && (
            <Table.Tr>
              <Table.Td colSpan={5}><Text c="dimmed" ta="center" py="md">ไม่พบข้อมูล</Text></Table.Td>
            </Table.Tr>
          )}
        </Table.Tbody>
      </Table>
    </Stack>
  );
}

export function MenuFoodPage() {
  const [type, setType] = useState('food');
  const [types, setTypes] = useState([]);
  const [items, setItems] = useState([]);
  const [categories, setCategories] = useState([]);
  const [search, setSearch] = useState({});
  const [modalState, setModalState] = useState({ opened: false, editing: null });
  const [importOpened, setImportOpened] = useState(false);
  const location = useLocation();
  const navigate = useNavigate();

  const load = (t) => {
    getFoodItems(t).then(setItems).catch(() => setItems([]));
    getFoodCategories(t).then(setCategories).catch(() => setCategories([]));
  };

  useEffect(() => { getFoodTypes().then(setTypes).catch(() => setTypes([])); }, []);

  useEffect(() => { load(type); }, [type]);

  // มาจาก "เมนูที่ยังไม่สมบูรณ์" บนแดชบอร์ด (DashboardPage งานที่ 4) — เปิด
  // ฟอร์มแก้ไขเมนูนั้นตรงๆ โดยไม่ต้องรู้ล่วงหน้าว่าเป็น food/drink/dessert
  // (backend /admin/food-items ไม่ใส่ type ตอน filter แต่ไม่ใส่ type เลยจะได้
  // ทุกประเภทมาพร้อม category_type ต่อรายการ) ล้าง location.state ทิ้งหลังใช้
  // กันเปิดซ้ำถ้า refresh/กด back มาที่หน้านี้อีกที
  useEffect(() => {
    const editItemId = location.state?.editItemId;
    if (!editItemId) return;
    getFoodItems().then((all) => {
      const item = all.find((i) => i.id === editItemId);
      if (item) {
        setType(item.category_type);
        setModalState({ opened: true, editing: item });
      }
    }).catch(() => {});
    navigate(location.pathname, { replace: true, state: {} });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [location.state]);

  const categoryNameById = useMemo(
    () => Object.fromEntries(categories.map((c) => [c.id, c.name])),
    [categories]
  );

  const openCreate = () => setModalState({ opened: true, editing: null });
  const openEdit = (item) => setModalState({ opened: true, editing: item });
  const closeModal = () => setModalState((s) => ({ ...s, opened: false }));

  const handleDelete = (item) => {
    modals.openConfirmModal({
      title: 'ยืนยันการลบ',
      children: <Text size="sm">ต้องการลบ "{item.name_th || item.name}" ใช่หรือไม่?</Text>,
      labels: { confirm: 'ลบ', cancel: 'ยกเลิก' },
      confirmProps: { color: 'red' },
      onConfirm: async () => {
        try {
          await deleteFoodItem(item.id);
          notifications.show({ color: 'green', message: 'ลบเรียบร้อย' });
          load(type);
        } catch (err) {
          notifications.show({ color: 'red', title: 'ลบไม่สำเร็จ', message: err.message });
        }
      },
    });
  };

  return (
    <Stack gap="lg">
      <Title order={3} c="brandGreen.6">เมนูอาหาร</Title>
      <Tabs value={type} onChange={setType}>
        <Tabs.List>
          {types.map((t) => (
            <Tabs.Tab key={t.id} value={t.name}>{TYPE_LABELS[t.name] || t.name}</Tabs.Tab>
          ))}
        </Tabs.List>
        <Tabs.Panel value={type} pt="md">
          <Stack gap="sm">
            <Group justify="flex-end">
              <Button variant="light" leftSection={<IconFileImport size={16} />} color="brandGreen" onClick={() => setImportOpened(true)}>
                นำเข้าจาก CSV
              </Button>
              <Button leftSection={<IconPlus size={16} />} color="brandGreen" onClick={openCreate}>
                เพิ่ม{TYPE_LABELS[type] || type}
              </Button>
            </Group>
            <MenuTable
              items={items}
              categoryNameById={categoryNameById}
              search={search[type] || ''}
              onSearch={(v) => setSearch((s) => ({ ...s, [type]: v }))}
              onEdit={openEdit}
              onDelete={handleDelete}
            />
          </Stack>
        </Tabs.Panel>
      </Tabs>
      <MenuFoodModal
        opened={modalState.opened}
        typeFilter={type}
        initialValues={modalState.editing}
        onClose={closeModal}
        onSaved={() => load(type)}
      />
      <ImportCsvModal
        opened={importOpened}
        type={type}
        categories={categories}
        onClose={() => setImportOpened(false)}
        onImported={() => load(type)}
      />
    </Stack>
  );
}
