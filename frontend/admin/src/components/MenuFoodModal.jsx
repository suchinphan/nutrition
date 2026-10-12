import { useEffect, useState } from 'react';
import {
  Modal, Stack, TextInput, NumberInput, Select, Button, Group, Textarea, Switch,
  Divider, Text, Table, ActionIcon, Checkbox, SimpleGrid, Loader,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { IconTrash, IconPlus, IconCheck, IconX } from '@tabler/icons-react';
import { notifications } from '@mantine/notifications';
import { modals } from '@mantine/modals';
import {
  getFoodCategories, getFoodItems, createFoodItem, updateFoodItem,
  addServingSize, updateServingSize, deleteServingSize,
  getAllergens, createAllergen, updateAllergen, deleteAllergen, setFoodItemAllergens,
} from '../api/foodMenus';

// fiber_g/sugar_g/iron_mg/vitamin_c_mg ตัดออกจากฟอร์มนี้แล้ว (ผู้ใช้ขอ) —
// ไม่มีหน้าไหนในแอปมือถือแสดงค่าพวกนี้จริง (fiber_g/sugar_g ถูก parse เข้า
// FoodItem model แต่ไม่เคยถูกเอาไป render เลย, iron_mg/vitamin_c_mg ไม่ถูก
// parse เข้า model ด้วยซ้ำ) คอลัมน์ backend/DB ยังอยู่เหมือนเดิม แค่ไม่มีช่อง
// กรอกในแอดมินอีกต่อไป (แถวเก่าที่เคยมีค่าไว้ก่อนหน้านี้ไม่หาย แค่แก้ไม่ได้
// จากฟอร์มนี้)
const EMPTY_VALUES = {
  name: '', name_th: '', category_id: null,
  calories: 0, protein_g: 0, carbs_g: 0, fat_g: 0,
  image_url: '', swap_food_id: null, upgrade_tips: '',
  is_active: true,
};

const TYPE_LABELS = { food: 'อาหาร', drink: 'เครื่องดื่ม', dessert: 'ของหวาน' };

function ServingSizeManager({ itemId, sizes, onChanged, baseCalories = 0 }) {
  const [newSize, setNewSize] = useState({ unit_name: '', unit_name_th: '', calories_multiplier: 1, grams_approx: '' });
  const [adding, setAdding] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [editingValues, setEditingValues] = useState({});

  const toMultiplier = (value) => {
    const numericValue = Number(value);
    const base = Number(baseCalories || 0);
    if (!Number.isFinite(numericValue) || numericValue <= 0 || !base) return 1;
    return numericValue / base;
  };

  const fromMultiplier = (multiplier) => {
    const numericValue = Number(multiplier);
    const base = Number(baseCalories || 0);
    if (!Number.isFinite(numericValue) || numericValue <= 0 || !base) return 0;
    return Math.round(numericValue * base);
  };

  const handleAdd = async () => {
    if (!newSize.unit_name.trim()) return;
    setAdding(true);
    try {
      await addServingSize(itemId, {
        ...newSize,
        calories_multiplier: toMultiplier(newSize.calories_multiplier),
      });
      setNewSize({ unit_name: '', unit_name_th: '', calories_multiplier: 1, grams_approx: '' });
      onChanged();
    } catch (err) {
      notifications.show({ color: 'red', title: 'เพิ่มขนาดไม่สำเร็จ', message: err.message });
    } finally {
      setAdding(false);
    }
  };

  const startEdit = (s) => {
    setEditingId(s.id);
    setEditingValues({
      unit_name_th: s.unit_name_th || '',
      calories_multiplier: fromMultiplier(s.calories_multiplier),
      grams_approx: s.grams_approx ?? '',
    });
  };

  const saveEdit = async (s) => {
    try {
      await updateServingSize(itemId, s.id, {
        ...editingValues,
        calories_multiplier: toMultiplier(editingValues.calories_multiplier),
      });
      setEditingId(null);
      onChanged();
    } catch (err) {
      notifications.show({ color: 'red', title: 'แก้ไขไม่สำเร็จ', message: err.message });
    }
  };

  const handleDelete = async (s) => {
    try {
      await deleteServingSize(itemId, s.id);
      onChanged();
    } catch (err) {
      notifications.show({ color: 'red', title: 'ลบไม่สำเร็จ', message: err.message });
    }
  };

  return (
    <Stack gap="xs">
      <Text fw={600} size="sm">ขนาดเสิร์ฟ</Text>
      <Table striped withTableBorder>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>หน่วย (EN)</Table.Th>
            <Table.Th>หน่วย (TH)</Table.Th>
            <Table.Th>แคลอรีต่อขนาด</Table.Th>
            <Table.Th>กรัมโดยประมาณ</Table.Th>
            <Table.Th w={80}></Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {sizes.map((s) => (
            <Table.Tr key={s.id}>
              <Table.Td>{s.unit_name}</Table.Td>
              {editingId === s.id ? (
                <>
                  <Table.Td>
                    <TextInput size="xs" value={editingValues.unit_name_th}
                      onChange={(e) => { const val = e.currentTarget.value; setEditingValues((v) => ({ ...v, unit_name_th: val })); }} />
                  </Table.Td>
                  <Table.Td>
                    <NumberInput size="xs" min={0} step={10} value={editingValues.calories_multiplier}
                      onChange={(v) => setEditingValues((s) => ({ ...s, calories_multiplier: v }))} />
                  </Table.Td>
                  <Table.Td>
                    <NumberInput size="xs" min={0} value={editingValues.grams_approx}
                      onChange={(v) => setEditingValues((s) => ({ ...s, grams_approx: v }))} />
                  </Table.Td>
                  <Table.Td>
                    <Group gap={4} wrap="nowrap">
                      <ActionIcon variant="subtle" color="brandGreen" onClick={() => saveEdit(s)}><IconCheck size={14} /></ActionIcon>
                      <ActionIcon variant="subtle" color="gray" onClick={() => setEditingId(null)}><IconX size={14} /></ActionIcon>
                    </Group>
                  </Table.Td>
                </>
              ) : (
                <>
                  <Table.Td>{s.unit_name_th || '-'}</Table.Td>
                  <Table.Td>{fromMultiplier(s.calories_multiplier)}</Table.Td>
                  <Table.Td>{s.grams_approx ?? '-'}</Table.Td>
                  <Table.Td>
                    <Group gap={4} wrap="nowrap">
                      <ActionIcon variant="subtle" color="brandGreen" onClick={() => startEdit(s)}>✎</ActionIcon>
                      <ActionIcon variant="subtle" color="red" onClick={() => handleDelete(s)}><IconTrash size={14} /></ActionIcon>
                    </Group>
                  </Table.Td>
                </>
              )}
            </Table.Tr>
          ))}
          {sizes.length === 0 && (
            <Table.Tr><Table.Td colSpan={5}><Text size="sm" c="dimmed" ta="center">ยังไม่มีขนาดเสิร์ฟ</Text></Table.Td></Table.Tr>
          )}
        </Table.Tbody>
      </Table>
      <Group wrap="nowrap" align="flex-end">
        <TextInput size="xs" label="หน่วย (EN)" placeholder="small/medium/large" flex={1}
          value={newSize.unit_name} onChange={(e) => { const val = e.currentTarget.value; setNewSize((s) => ({ ...s, unit_name: val })); }} />
        <TextInput size="xs" label="หน่วย (TH)" placeholder="เล็ก/กลาง/ใหญ่" flex={1}
          value={newSize.unit_name_th} onChange={(e) => { const val = e.currentTarget.value; setNewSize((s) => ({ ...s, unit_name_th: val })); }} />
        <NumberInput size="xs" label="แคลอรี/ขนาด" min={0} step={10} w={120}
          value={newSize.calories_multiplier} onChange={(v) => setNewSize((s) => ({ ...s, calories_multiplier: v }))} />
        <NumberInput size="xs" label="กรัม" min={0} w={90}
          value={newSize.grams_approx} onChange={(v) => setNewSize((s) => ({ ...s, grams_approx: v }))} />
        <Button size="xs" leftSection={<IconPlus size={14} />} loading={adding} onClick={handleAdd}>เพิ่ม</Button>
      </Group>
    </Stack>
  );
}

export function MenuFoodModal({ opened, onClose, typeFilter, initialValues, onSaved }) {
  const [categories, setCategories] = useState([]);
  const [swapCandidates, setSwapCandidates] = useState([]);
  const [allergensMaster, setAllergensMaster] = useState([]);
  const [allergenIds, setAllergenIds] = useState([]);
  const [currentItem, setCurrentItem] = useState(null);
  const [loadingRefs, setLoadingRefs] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [newAllergenName, setNewAllergenName] = useState('');
  const [addingAllergen, setAddingAllergen] = useState(false);
  const [editingAllergenId, setEditingAllergenId] = useState(null);
  const [editingAllergenName, setEditingAllergenName] = useState('');

  const form = useForm({ initialValues: EMPTY_VALUES });

  useEffect(() => {
    if (!opened) return;
    form.setValues({ ...EMPTY_VALUES, ...(initialValues || {}) });
    setCurrentItem(initialValues || null);
    setAllergenIds(initialValues?.allergen_ids || []);
    setNewAllergenName('');
    setEditingAllergenId(null);
    setLoadingRefs(true);
    Promise.all([
      getFoodCategories(typeFilter),
      getFoodItems(typeFilter),
      getAllergens(),
    ])
      .then(([cats, items, allergens]) => {
        setCategories(cats);
        setSwapCandidates(items.filter((i) => i.id !== initialValues?.id));
        setAllergensMaster(allergens);
      })
      .catch(() => {})
      .finally(() => setLoadingRefs(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened, typeFilter, initialValues]);

  const refreshCurrentItem = async () => {
    const items = await getFoodItems(typeFilter);
    const fresh = items.find((i) => i.id === currentItem?.id);
    if (fresh) setCurrentItem(fresh);
    onSaved();
  };

  const handleSubmit = async (values) => {
    setSubmitting(true);
    try {
      // Mantine Select ส่ง category_id/swap_food_id มาเป็น string เสมอ —
      // เดิม path create แปลงเป็น Number() แต่ path update ส่ง string ตรงๆ
      // (บั๊กที่เจอจริง — ใช้งานได้เพราะ MySQL implicit cast ให้ ไม่ใช่เพราะ
      // ถูกต้องจริง) แปลงให้เหมือนกันทั้ง 2 path ก่อนส่งออก
      const normalized = {
        ...values,
        category_id: values.category_id ? Number(values.category_id) : null,
        swap_food_id: values.swap_food_id ? Number(values.swap_food_id) : null,
      };
      const saved = currentItem
        ? await updateFoodItem(currentItem.id, normalized)
        : await createFoodItem(normalized);
      setCurrentItem(saved);
      try {
        await setFoodItemAllergens(saved.id, allergenIds);
      } catch (err) {
        notifications.show({ color: 'red', title: 'บันทึกเมนูแล้ว แต่สารก่อภูมิแพ้ไม่สำเร็จ', message: err.message });
      }
      notifications.show({ color: 'green', message: currentItem ? 'แก้ไขข้อมูลเมนูแล้ว' : 'เพิ่มเมนูแล้ว — ใส่ขนาดเสิร์ฟต่อได้เลย' });
      onSaved();
    } catch (err) {
      notifications.show({ color: 'red', title: 'บันทึกไม่สำเร็จ', message: err.message });
    } finally {
      setSubmitting(false);
    }
  };

  const hasValue = (value) => value !== null && value !== undefined && value !== '';

  const computedKcal = Math.round(
    (form.values.carbs_g || 0) * 4 + (form.values.protein_g || 0) * 4 + (form.values.fat_g || 0) * 9,
  );

  // มีแคลอรีแต่ยังไม่มีสารอาหารเลย -> คำนวณสารอาหารจากแคลอรี (50/20/30)
  // มีสารอาหารแต่ยังไม่มีแคลอรี -> คำนวณแคลอรีจากสารอาหาร (4/4/9)
  // โดยมีการคำนวณอัตโนมัติทันทีเมื่อค่าฟิลด์เปลี่ยน เพื่อให้ไม่ต้องกดปุ่ม
  const hasMacros = hasValue(form.values.protein_g) || hasValue(form.values.carbs_g) || hasValue(form.values.fat_g);
  const hasCalories = hasValue(form.values.calories);

  const calculateMissing = () => {
    const missingFields = [];

    if (!form.values.name?.trim()) missingFields.push('ชื่อเมนู (EN)');
    if (!form.values.name_th?.trim()) missingFields.push('ชื่อเมนู (TH)');
    if (!form.values.category_id) missingFields.push('หมวดหมู่');
    if (!hasCalories) missingFields.push('แคลอรี');
    if (!hasValue(form.values.protein_g)) missingFields.push('โปรตีน');
    if (!hasValue(form.values.carbs_g)) missingFields.push('คาร์บ');
    if (!hasValue(form.values.fat_g)) missingFields.push('ไขมัน');

    if (missingFields.length > 0) {
      notifications.show({
        color: 'yellow',
        title: 'กรอกข้อมูลให้ครบถ้วนก่อน',
        message: `คุณยังขาดข้อมูลต่อไปนี้ก่อนคำนวณสารอาหาร: ${missingFields.join(', ')}`,
        autoClose: 10000,
      });
      return;
    }

    notifications.show({
      color: 'green',
      title: 'กรอกข้อมูลครบถ้วนเรียบร้อยแล้ว',
      message: 'กรอกข้อมูลครบถ้วนเรียบร้อยแล้ว',
      autoClose: 10000,
    });

    if (hasMacros && !hasCalories) {
      form.setFieldValue('calories', computedKcal);
    }
  };

  // รีเซ็ตฟอร์มกลับไปค่าล่าสุดที่ถูกต้อง (ไม่ใช่ค่าว่างเปล่าเสมอ) — ถ้าเป็น
  // การแก้ไขเมนูเดิม ต้องกลับไปค่าของเมนูนั้นจริง (ใช้ initialValues เดียวกับ
  // ตอนเปิดฟอร์มครั้งแรก) ถ้าเป็นการสร้างใหม่ค่อยกลับไปว่างเปล่าทั้งหมด —
  // เผื่อกรอกผิดแล้วอยากเริ่มใหม่โดยไม่ต้องปิดฟอร์มแล้วเปิดใหม่
  const handleReset = () => {
    form.setValues({ ...EMPTY_VALUES, ...(initialValues || {}) });
    setAllergenIds(initialValues?.allergen_ids || []);
  };

  // checkbox ที่มีอยู่เป็น master list ตายตัว บางเมนู (เช่นของหวานไทยที่มี
  // กะทิ/ถั่วเขียว) ไม่มีสารก่อภูมิแพ้ให้เลือกตรงกับที่ใช้จริง (ผู้ใช้รายงาน
  // จริง) — เพิ่มชื่อใหม่เข้า master list ตรงนี้เลย แล้วติ๊กเลือกให้ทันที
  // ไม่ต้องออกไปแก้ที่อื่น
  const handleAddAllergen = async () => {
    const name = newAllergenName.trim();
    if (!name) return;
    setAddingAllergen(true);
    try {
      const created = await createAllergen(name);
      setAllergensMaster((prev) => (
        prev.some((a) => a.id === created.id) ? prev : [...prev, created]
      ));
      setAllergenIds((prev) => (prev.includes(created.id) ? prev : [...prev, created.id]));
      setNewAllergenName('');
    } catch (err) {
      notifications.show({ color: 'red', title: 'เพิ่มสารก่อภูมิแพ้ไม่สำเร็จ', message: err.message });
    } finally {
      setAddingAllergen(false);
    }
  };

  const startEditAllergen = (a) => {
    setEditingAllergenId(a.id);
    setEditingAllergenName(a.name);
  };

  const saveEditAllergen = async () => {
    const name = editingAllergenName.trim();
    if (!name) return;
    try {
      const updated = await updateAllergen(editingAllergenId, name);
      setAllergensMaster((prev) => prev.map((a) => (a.id === updated.id ? updated : a)));
      setEditingAllergenId(null);
    } catch (err) {
      notifications.show({ color: 'red', title: 'แก้ไขชื่อไม่สำเร็จ', message: err.message });
    }
  };

  // ลบตัวนี้กระทบทุกเมนูในระบบที่เคยติ๊กไว้ ไม่ใช่แค่เมนูที่กำลังแก้อยู่ —
  // ต้องยืนยันก่อนเสมอ
  const handleDeleteAllergen = (a) => {
    modals.openConfirmModal({
      title: 'ยืนยันการลบ',
      children: <Text size="sm">ลบสารก่อภูมิแพ้ "{a.name}" ใช่หรือไม่? เมนูที่เคยติ๊กตัวนี้ไว้จะถูกเอาออกจากรายการนี้ไปด้วย</Text>,
      labels: { confirm: 'ลบ', cancel: 'ยกเลิก' },
      confirmProps: { color: 'red' },
      onConfirm: async () => {
        try {
          await deleteAllergen(a.id);
          setAllergensMaster((prev) => prev.filter((x) => x.id !== a.id));
          setAllergenIds((prev) => prev.filter((id) => id !== a.id));
        } catch (err) {
          notifications.show({ color: 'red', title: 'ลบไม่สำเร็จ', message: err.message });
        }
      },
    });
  };

  const title = `${currentItem ? 'แก้ไข' : 'เพิ่ม'}เมนู${TYPE_LABELS[typeFilter] || typeFilter || ''}`;

  return (
    <Modal opened={opened} onClose={onClose} title={title} centered size="lg">
      <Stack gap="md">
        <form onSubmit={form.onSubmit(handleSubmit)}>
          <Stack gap="sm">
            <Group grow>
              <TextInput label="ชื่อเมนู (EN)" required {...form.getInputProps('name')} />
              <TextInput label="ชื่อเมนู (TH)" {...form.getInputProps('name_th')} />
            </Group>
            <Select
              label="หมวดหมู่"
              placeholder="เลือกหมวดหมู่"
              required
              data={categories.map((c) => ({ value: String(c.id), label: c.name }))}
              value={form.values.category_id ? String(form.values.category_id) : ''}
              onChange={(v) => form.setFieldValue('category_id', v)}
            />
            <SimpleGrid cols={4}>
              <NumberInput label="แคลอรี" min={0} {...form.getInputProps('calories')} />
              <NumberInput label="โปรตีน (g)" min={0} {...form.getInputProps('protein_g')} />
              <NumberInput label="คาร์บ (g)" min={0} {...form.getInputProps('carbs_g')} />
              <NumberInput label="ไขมัน (g)" min={0} {...form.getInputProps('fat_g')} />
            </SimpleGrid>
            <Group justify="flex-end" mt={-8}>
              <Button
                type="button"
                size="xs"
                variant="light"
                color="brandGreen"
                onClick={calculateMissing}
              >
                คำนวณสารอาหาร
              </Button>
            </Group>
            <Stack gap="xs">
              <Text fw={600} size="sm">สารก่อภูมิแพ้</Text>
              <SimpleGrid cols={2}>
                {allergensMaster.map((a) => (
                  editingAllergenId === a.id ? (
                    <Group key={a.id} gap={4} wrap="nowrap">
                      <TextInput size="xs" flex={1} value={editingAllergenName}
                        onChange={(e) => setEditingAllergenName(e.currentTarget.value)}
                        onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); saveEditAllergen(); } }}
                        autoFocus />
                      <ActionIcon size="sm" variant="subtle" color="brandGreen" onClick={saveEditAllergen}><IconCheck size={14} /></ActionIcon>
                      <ActionIcon size="sm" variant="subtle" color="gray" onClick={() => setEditingAllergenId(null)}><IconX size={14} /></ActionIcon>
                    </Group>
                  ) : (
                    <Group key={a.id} gap={4} wrap="nowrap" justify="space-between">
                      <Checkbox label={a.name} checked={allergenIds.includes(a.id)}
                        onChange={() => setAllergenIds((prev) => (
                          prev.includes(a.id) ? prev.filter((x) => x !== a.id) : [...prev, a.id]
                        ))} />
                      <Group gap={2} wrap="nowrap">
                        <ActionIcon size="sm" variant="subtle" onClick={() => startEditAllergen(a)}>✎</ActionIcon>
                        <ActionIcon size="sm" variant="subtle" color="red" onClick={() => handleDeleteAllergen(a)}><IconTrash size={14} /></ActionIcon>
                      </Group>
                    </Group>
                  )
                ))}
              </SimpleGrid>
              {allergensMaster.length === 0 && <Text size="sm" c="dimmed">ยังไม่มี allergen ในระบบ</Text>}
              <Group wrap="nowrap" align="flex-end">
                <TextInput
                  size="xs"
                  placeholder="ไม่มีในรายการ? พิมพ์ชื่อใหม่ เช่น กะทิ"
                  flex={1}
                  value={newAllergenName}
                  onChange={(e) => setNewAllergenName(e.currentTarget.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); handleAddAllergen(); } }}
                />
                <Button size="xs" variant="light" color="brandGreen" loading={addingAllergen} onClick={handleAddAllergen}>
                  เพิ่ม
                </Button>
              </Group>
            </Stack>
            <TextInput label="URL รูปภาพ" placeholder="https://..." {...form.getInputProps('image_url')} />
            <Select
              label="เมนูทดแทน (แนะนำเวลามีภูมิแพ้/ข้อจำกัด)"
              placeholder="ไม่มี"
              clearable
              data={swapCandidates.map((i) => ({ value: String(i.id), label: i.name_th || i.name }))}
              value={form.values.swap_food_id ? String(form.values.swap_food_id) : ''}
              onChange={(v) => form.setFieldValue('swap_food_id', v)}
            />
            <Textarea label="คำแนะนำ (upgrade tips)" autosize minRows={2} {...form.getInputProps('upgrade_tips')} />
            <Switch label="เปิดใช้งาน (แสดงในแอป)" checked={form.values.is_active} onChange={(e) => form.setFieldValue('is_active', e.currentTarget.checked)} />
            <Group justify="flex-end" mt="sm">
              <Button variant="subtle" color="gray" onClick={handleReset}>รีเซ็ต</Button>
              <Button variant="default" onClick={onClose}>ปิด</Button>
              <Button type="submit" color="brandGreen" loading={submitting}>
                {currentItem ? 'บันทึกการแก้ไข' : 'สร้างเมนู'}
              </Button>
            </Group>
          </Stack>
        </form>

        {loadingRefs && <Loader size="sm" />}

        {currentItem && !loadingRefs && (
          <>
            <Divider label="ขนาดเสิร์ฟ (ไม่บังคับ)" labelPosition="center" />
            <ServingSizeManager itemId={currentItem.id} sizes={currentItem.serving_sizes || []} onChanged={refreshCurrentItem} baseCalories={Number(form.values.calories || 0)} />
          </>
        )}
      </Stack>
    </Modal>
  );
}
