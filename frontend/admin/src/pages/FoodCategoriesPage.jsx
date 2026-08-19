import { useEffect, useState } from 'react';
import { Paper, TextInput, Title, Stack, Group, Center, ActionIcon, Text, Button, Menu } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconEdit, IconTrash, IconCheck, IconX, IconPlus, IconDotsVertical } from '@tabler/icons-react';
import { modals } from '@mantine/modals';
import {
  getFoodCategories,
  createFoodCategory, renameFoodCategory, deleteFoodCategory,
  getFoodTypes, createFoodType, reorderFoodTypes, renameFoodType, deleteFoodType,
} from '../api/foodMenus';

// อาหาร/เครื่องดื่ม/ของหวาน คือ type built-in — ป้ายกำกับภาษาไทยตายตัว หัวข้อ
// ที่แอดมินเพิ่มเองใช้ชื่อที่พิมพ์ไว้ตรงๆ เป็นป้ายกำกับ (ดู BUILTIN_LABEL[t.name]
// || t.name ตอน render) แก้ชื่อ/ลบหัวข้อ built-in ไม่ได้ (PROTECTED_FOOD_TYPES
// ฝั่ง backend กันไว้อยู่แล้ว แต่เช็คซ้ำฝั่งนี้เพื่อไม่ให้ขึ้นปุ่มลวงตา)
const BUILTIN_LABEL = { food: 'อาหาร', drink: 'เครื่องดื่ม', dessert: 'ของหวาน' };
const PROTECTED_TYPE_VALUES = Object.keys(BUILTIN_LABEL);

function CategoryManager({ type, label, isProtected, categories, onChanged, onTypeRenamed, onTypeDeleted }) {
  const [newName, setNewName] = useState('');
  const [adding, setAdding] = useState(false);
  const [editingType, setEditingType] = useState(false);
  const [typeName, setTypeName] = useState(label);
  const [editingId, setEditingId] = useState(null);
  const [editingName, setEditingName] = useState('');

  useEffect(() => { setNewName(''); setEditingType(false); setTypeName(label); }, [type, label]);

  const handleAdd = async () => {
    const name = newName.trim();
    if (!name) return;
    setAdding(true);
    try {
      await createFoodCategory(type, name);
      notifications.show({ color: 'green', message: 'เพิ่มหมวดหมู่แล้ว' });
      setNewName('');
      onChanged();
    } catch (err) {
      notifications.show({ color: 'red', title: 'เพิ่มไม่สำเร็จ', message: err.message });
    } finally {
      setAdding(false);
    }
  };

  const startEdit = (c) => {
    setEditingId(c.id);
    setEditingName(c.name);
  };

  const saveEdit = async (c) => {
    const name = editingName.trim();
    if (!name || name === c.name) {
      setEditingId(null);
      return;
    }
    try {
      await renameFoodCategory(c.id, name);
      notifications.show({ color: 'green', message: 'แก้ไขชื่อหมวดหมู่แล้ว' });
      setEditingId(null);
      onChanged();
    } catch (err) {
      notifications.show({ color: 'red', title: 'แก้ไขไม่สำเร็จ', message: err.message });
    }
  };

  const handleDelete = (c) => {
    modals.openConfirmModal({
      title: 'ยืนยันการลบหมวดหมู่',
      children: <Text size="sm">ต้องการลบหมวดหมู่ "{c.name}" ใช่หรือไม่? (ลบไม่ได้ถ้ายังมีเมนูผูกอยู่)</Text>,
      labels: { confirm: 'ลบ', cancel: 'ยกเลิก' },
      confirmProps: { color: 'red' },
      onConfirm: async () => {
        try {
          await deleteFoodCategory(c.id);
          notifications.show({ color: 'green', message: 'ลบหมวดหมู่แล้ว' });
          onChanged();
        } catch (err) {
          notifications.show({ color: 'red', title: 'ลบไม่สำเร็จ', message: err.message });
        }
      },
    });
  };

  const saveTypeEdit = async () => {
    const name = typeName.trim();
    if (!name || name === label) {
      setEditingType(false);
      setTypeName(label);
      return;
    }
    try {
      await renameFoodType(type, name);
      notifications.show({ color: 'green', message: 'แก้ไขชื่อหัวข้อแล้ว' });
      setEditingType(false);
      onTypeRenamed(name);
    } catch (err) {
      notifications.show({ color: 'red', title: 'แก้ไขไม่สำเร็จ', message: err.message });
    }
  };

  const handleDeleteType = () => {
    modals.openConfirmModal({
      title: 'ยืนยันการลบหัวข้อ',
      children: <Text size="sm">ต้องการลบหัวข้อ "{label}" พร้อมหมวดหมู่ทั้งหมดในนี้ใช่หรือไม่? (ลบไม่ได้ถ้ายังมีเมนูผูกอยู่)</Text>,
      labels: { confirm: 'ลบ', cancel: 'ยกเลิก' },
      confirmProps: { color: 'red' },
      onConfirm: async () => {
        try {
          await deleteFoodType(type);
          notifications.show({ color: 'green', message: 'ลบหัวข้อแล้ว' });
          onTypeDeleted();
        } catch (err) {
          notifications.show({ color: 'red', title: 'ลบไม่สำเร็จ', message: err.message });
        }
      },
    });
  };

  return (
    <Stack gap="xs">
      <Group justify="space-between" wrap="nowrap">
        {editingType ? (
          <Group flex={1} wrap="nowrap">
            <TextInput
              size="xs"
              flex={1}
              autoFocus
              value={typeName}
              onChange={(e) => setTypeName(e.currentTarget.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') saveTypeEdit();
                if (e.key === 'Escape') { setEditingType(false); setTypeName(label); }
              }}
            />
            <ActionIcon variant="subtle" color="brandGreen" onClick={saveTypeEdit}>
              <IconCheck size={14} />
            </ActionIcon>
            <ActionIcon variant="subtle" color="gray" onClick={() => { setEditingType(false); setTypeName(label); }}>
              <IconX size={14} />
            </ActionIcon>
          </Group>
        ) : (
          <>
            <Title order={5} c="brandGreen.6">หมวดหมู่ — {label}</Title>
            {!isProtected && (
              <Menu shadow="md" width={140} position="bottom-end" withinPortal>
                <Menu.Target>
                  <ActionIcon variant="subtle" color="gray" aria-label="ตัวเลือกหัวข้อ">
                    <IconDotsVertical size={16} />
                  </ActionIcon>
                </Menu.Target>
                <Menu.Dropdown>
                  <Menu.Item leftSection={<IconEdit size={14} />} onClick={() => setEditingType(true)}>
                    แก้ไข
                  </Menu.Item>
                  <Menu.Item leftSection={<IconTrash size={14} />} color="red" onClick={handleDeleteType}>
                    ลบ
                  </Menu.Item>
                </Menu.Dropdown>
              </Menu>
            )}
          </>
        )}
      </Group>
      {categories.map((c) => (
        <Group key={c.id} justify="space-between" wrap="nowrap">
          {editingId === c.id ? (
            <Group flex={1} wrap="nowrap">
              <TextInput
                size="xs"
                flex={1}
                value={editingName}
                onChange={(e) => setEditingName(e.currentTarget.value)}
              />
              <ActionIcon variant="subtle" color="brandGreen" onClick={() => saveEdit(c)}>
                <IconCheck size={14} />
              </ActionIcon>
              <ActionIcon variant="subtle" color="gray" onClick={() => setEditingId(null)}>
                <IconX size={14} />
              </ActionIcon>
            </Group>
          ) : (
            <>
              <Text size="sm">{c.name}</Text>
              <Group gap={4}>
                <ActionIcon variant="subtle" color="brandGreen" onClick={() => startEdit(c)}>
                  <IconEdit size={14} />
                </ActionIcon>
                <ActionIcon variant="subtle" color="red" onClick={() => handleDelete(c)}>
                  <IconTrash size={14} />
                </ActionIcon>
              </Group>
            </>
          )}
        </Group>
      ))}
      {categories.length === 0 && <Text size="sm" c="dimmed">ยังไม่มีหมวดหมู่ในประเภทนี้</Text>}

      <Group wrap="nowrap" mt="xs">
        <TextInput
          size="xs"
          flex={1}
          placeholder="ชื่อหมวดหมู่ใหม่"
          value={newName}
          onChange={(e) => setNewName(e.currentTarget.value)}
          onKeyDown={(e) => e.key === 'Enter' && handleAdd()}
        />
        <ActionIcon
          variant="filled"
          color="brandGreen"
          radius="xl"
          size="lg"
          loading={adding}
          aria-label="เพิ่มหมวดหมู่ใหม่"
          onClick={handleAdd}
        >
          <IconPlus size={18} />
        </ActionIcon>
      </Group>
    </Stack>
  );
}

function NewTypeForm({ onCreated, onCancel }) {
  const [typeName, setTypeName] = useState('');
  const [saving, setSaving] = useState(false);

  const handleCreate = async () => {
    const name = typeName.trim();
    if (!name) return;
    setSaving(true);
    try {
      await createFoodType(name);
      notifications.show({ color: 'green', message: `เพิ่มหัวข้อ "${name}" แล้ว` });
      onCreated(name);
    } catch (err) {
      notifications.show({ color: 'red', title: 'เพิ่มหัวข้อไม่สำเร็จ', message: err.message });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Group wrap="nowrap">
      <TextInput
        size="xs"
        flex={1}
        autoFocus
        placeholder="ชื่อหัวข้อใหม่ เช่น ผลไม้"
        value={typeName}
        onChange={(e) => setTypeName(e.currentTarget.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') handleCreate();
          if (e.key === 'Escape') onCancel();
        }}
      />
      <ActionIcon variant="filled" color="brandGreen" loading={saving} onClick={handleCreate}>
        <IconCheck size={14} />
      </ActionIcon>
      <ActionIcon variant="subtle" color="gray" onClick={onCancel}>
        <IconX size={14} />
      </ActionIcon>
    </Group>
  );
}

// ponytail: หน้านี้เคยมีฟอร์มสร้าง/แก้/ลบ FoodMenu ซ้ำกับ MenuFoodPage เต็มรูปแบบ
// ตัดออก เหลือเฉพาะงานจัดการหมวดหมู่ที่ไม่มีที่อื่นทำ — จัดการเมนูอาหารทั้งหมด
// ไปที่หน้า "เมนูอาหาร"
export function FoodCategoriesPage() {
  const [type, setType] = useState('food');
  const [allCategories, setAllCategories] = useState([]);
  const [types, setTypes] = useState([]);
  const [addingNewType, setAddingNewType] = useState(false);
  const [dragIndex, setDragIndex] = useState(null);

  const loadCategories = () => {
    getFoodCategories().then(setAllCategories).catch(() => setAllCategories([]));
  };
  // backend seed แถว food/drink/dessert ใน FoodType ให้เองถ้ายังไม่มี (ดู
  // _ensure_builtin_food_types) ฝั่งนี้เลยแค่ render ตามลำดับที่ได้กลับมาตรงๆ
  // ได้ทั้งหัวข้อ built-in และหัวข้อที่แอดมินเพิ่มเองในลิสต์เดียว เรียงปนกันได้
  const loadTypes = () => {
    getFoodTypes().then(setTypes).catch(() => setTypes([]));
  };

  useEffect(() => { loadCategories(); loadTypes(); }, []);

  const activeLabel = BUILTIN_LABEL[type] || type;
  const categories = allCategories.filter((c) => c.type === type);

  // ลากสลับตำแหน่งได้ทุกหัวข้อปนกัน (รวม built-in) — แก้ชื่อ/ลบยังคงถูกกันแยก
  // ต่างหากอยู่ ไม่เกี่ยวกับตำแหน่ง ลำดับใหม่อัปเดตบนจอทันที (optimistic) แล้ว
  // ค่อยยิงไปบันทึกที่ backend
  const handleDrop = (dropIndex) => {
    if (dragIndex === null || dragIndex === dropIndex) { setDragIndex(null); return; }
    const next = [...types];
    const [moved] = next.splice(dragIndex, 1);
    next.splice(dropIndex, 0, moved);
    setTypes(next);
    setDragIndex(null);
    reorderFoodTypes(next.map((t) => t.name)).catch(() => loadTypes());
  };

  return (
    <Stack gap="xl">
      <Title order={3} c="brandGreen.6" ta="center">จัดการหมวดหมู่อาหาร</Title>

      <Center>
        <Paper shadow="sm" p="lg" radius="md" withBorder w="100%" maw={480}>
          <Stack gap="md">
            <Group gap="xs" wrap="wrap">
              {types.map((t, i) => (
                <Button
                  key={t.id}
                  size="xs"
                  radius="xl"
                  variant={type === t.name ? 'filled' : 'light'}
                  color="brandGreen"
                  draggable
                  onDragStart={() => setDragIndex(i)}
                  onDragOver={(e) => e.preventDefault()}
                  onDrop={() => handleDrop(i)}
                  onClick={() => setType(t.name)}
                  style={{ cursor: 'grab' }}
                  title="ลากเพื่อเรียงลำดับ"
                >
                  {BUILTIN_LABEL[t.name] || t.name}
                </Button>
              ))}
              <ActionIcon
                variant="light"
                color="brandGreen"
                radius="xl"
                size={30}
                aria-label="เพิ่มหัวข้อใหม่"
                onClick={() => setAddingNewType((v) => !v)}
              >
                <IconPlus size={16} />
              </ActionIcon>
            </Group>
            {addingNewType && (
              <NewTypeForm
                onCancel={() => setAddingNewType(false)}
                onCreated={(newType) => {
                  setAddingNewType(false);
                  setType(newType);
                  loadTypes();
                }}
              />
            )}
            <CategoryManager
              type={type}
              label={activeLabel}
              isProtected={PROTECTED_TYPE_VALUES.includes(type)}
              categories={categories}
              onChanged={loadCategories}
              onTypeRenamed={(newType) => { setType(newType); loadTypes(); }}
              onTypeDeleted={() => { setType('food'); loadTypes(); loadCategories(); }}
            />
          </Stack>
        </Paper>
      </Center>
    </Stack>
  );
}
