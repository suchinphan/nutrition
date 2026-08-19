import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  SimpleGrid,
  Card,
  Text,
  Title,
  Stack,
  Group,
  ThemeIcon,
  Grid,
  Skeleton,
  Button,
  Badge,
  ScrollArea,
  UnstyledButton,
  SegmentedControl,
} from '@mantine/core';
import { LineChart, DonutChart, BarChart } from '@mantine/charts';
import {
  IconUsers,
  IconUserPlus,
  IconToolsKitchen2,
  IconMessageCircle2,
  IconChevronRight,
} from '@tabler/icons-react';
import {
  getDashboardSummary,
  getMealTrend,
  getFoodTypeDist,
  getTopFoods,
  getGoalDist,
  getGenderDist,
  getAllergenStats,
  getMenuCompleteness,
} from '../api/dashboard';

// สีตาม spec ของหน้านี้โดยเฉพาะ (#1D9E75 / #EF9F27) — ไม่แตะ theme.js กลาง
// ของแอป เพราะหน้าอื่น (Login/FoodCategories/MenuFood/Reports/ProfileHistory)
// ยังใช้ brandGreen (#00C700) เดิมอยู่ งานนี้ scope แค่หน้า Dashboard เท่านั้น
const PRIMARY = '#1D9E75';
const SECONDARY = '#EF9F27';
const CARD_BORDER = '#e5e7eb';

const FOOD_TYPE_LABEL_TH = { food: 'อาหาร', drink: 'เครื่องดื่ม', dessert: 'ของหวาน' };
const DONUT_PALETTE = [PRIMARY, SECONDARY, '#5B8DEF'];

// ชาย=blue (ใช้เฉดฟ้าเดียวกับที่ DONUT_PALETTE ตัวที่ 3 ใช้อยู่แล้ว ให้ยัง
// เป็น palette เดียวกันทั้งหน้า) หญิง=pink ไม่ระบุ=gray
const GENDER_LABEL_TH = { male: 'ชาย', female: 'หญิง', unspecified: 'ไม่ระบุ' };
const GENDER_COLOR = { male: '#5B8DEF', female: '#EC4899', unspecified: '#9CA3AF' };

const COMPLETENESS_REASON_LABEL = {
  missing_image: 'ไม่มีรูป',
  missing_serving_sizes: 'ไม่มีขนาดเสิร์ฟ',
  not_yet_allergen_reviewed: 'ยังไม่ตรวจสารก่อภูมิแพ้',
};

// รวม 3 รายการจาก backend (แยกตามเหตุผล) เป็นรายการเดียวต่อเมนู — เมนูเดียว
// ขาดได้หลายอย่างพร้อมกัน (เช่น ทั้งไม่มีรูปและไม่มีขนาดเสิร์ฟ) จึงรวม badge
// เหตุผลไว้ในการ์ดเดียวแทนที่จะโชว์ซ้ำ 3 รอบ
function mergeMenuCompleteness(data) {
  const byId = new Map();
  for (const reasonKey of Object.keys(COMPLETENESS_REASON_LABEL)) {
    for (const item of data[reasonKey] || []) {
      if (!byId.has(item.id)) byId.set(item.id, { id: item.id, name: item.name, reasons: [] });
      byId.get(item.id).reasons.push(reasonKey);
    }
  }
  return [...byId.values()];
}

function formatShortDate(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`;
}

// รวมข้อมูลรายวันจาก /admin/dashboard/meal-trend เป็นรายเดือน/รายปีฝั่ง
// client แทนการเพิ่ม endpoint ใหม่ — backend คืนรายวันมาให้เสมออยู่แล้ว
// (สูงสุด 366 วัน) จุดข้อมูลไม่เยอะพอจะเป็นคอขวด รวมตรงนี้ง่ายกว่า
// "ทั้งหมด" ใช้บักเก็ตรายเดือนแบบเดียวกับ "เดือน" ต่างกันแค่ backend ไม่ cap
// ช่วงวันที่ (ดู ?days=all ใน admin_dashboard_meal_trend) — ข้อมูลแค่ไม่กี่เดือน
// บักเก็ตรายปีจะเหลือแท่งเดียวไม่มีประโยชน์ รายเดือนอ่านง่ายกว่า
function aggregateTrend(trend, granularity) {
  if (granularity === 'day') return trend;
  const buckets = new Map();
  for (const t of trend) {
    const d = new Date(t.date);
    const key = granularity === 'month' || granularity === 'all'
      ? `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
      : `${d.getFullYear()}`;
    const entry = buckets.get(key) || { date: key, planned: 0, eaten: 0 };
    entry.planned += t.planned;
    entry.eaten += t.eaten;
    buckets.set(key, entry);
  }
  // Map เก็บลำดับ insertion ไว้ตามเดิม — trend ที่ backend ส่งมาเรียงจากเก่า
  // ไปใหม่อยู่แล้ว บักเก็ตที่รวมได้เลยเรียงตามเวลาถูกต้องโดยไม่ต้อง sort ซ้ำ
  return [...buckets.values()];
}

function formatTrendLabel(key, granularity) {
  if (granularity === 'day') return formatShortDate(key);
  if (granularity === 'month' || granularity === 'all') {
    const [y, m] = key.split('-');
    return `${m}/${y.slice(2)}`;
  }
  return key;
}

// ใช้กับฟิลเตอร์ วัน/เดือน/ปี ของ "สัดส่วนเมนูแต่ละประเภท" กับ "Top 10 เมนู"
// — undefined (all) แปลว่าไม่กรอง นับทุกมื้อที่เคยทานจริงตั้งแต่ต้น (ค่า
// default เดิมก่อนมีฟิลเตอร์ คงไว้เป็นตัวเลือกแรกกันข้อมูลดูโล่งเกินไปตอน
// สมาชิกยังน้อย/เพิ่งเริ่มระบบ)
const PERIOD_DAYS = { all: undefined, day: 1, month: 30, year: 366 };
const PERIOD_OPTIONS = [
  { label: 'ทั้งหมด', value: 'all' },
  { label: 'วัน', value: 'day' },
  { label: 'เดือน', value: 'month' },
  { label: 'ปี', value: 'year' },
];

const TREND_TITLE = {
  all: 'มื้ออาหารทั้งหมดตั้งแต่เริ่มระบบ (วางแผน vs ทานจริง)',
  day: 'มื้ออาหารรายวัน 30 วันย้อนหลัง (วางแผน vs ทานจริง)',
  month: 'มื้ออาหารรายเดือนย้อนหลัง (วางแผน vs ทานจริง)',
  year: 'มื้ออาหารรายปีย้อนหลัง (วางแผน vs ทานจริง)',
};

// ดึงข้อมูล 1 การ์ด/กราฟ แบบอิสระจากการ์ดอื่น — พังหรือโหลดช้าการ์ดเดียวไม่ทำให้
// การ์ดที่เหลือค้างตาม (แต่ละการ์ดมี loading/error/retry ของตัวเอง)
// deps: เพิ่มเข้ามาให้การ์ดที่ fetchFn เปลี่ยนได้ตามตัวกรอง (เช่น กราฟ
// แนวโน้มมื้ออาหารที่สลับวัน/เดือน/ปีได้) โหลดใหม่เองอัตโนมัติ — การ์ดอื่นๆ
// ที่ fetchFn คงที่ตลอดยังส่ง deps ว่าง (ค่า default) เหมือนเดิมทุกประการ
function useDashboardResource(fetchFn, deps = []) {
  const [state, setState] = useState({ status: 'loading', data: null, error: null });

  const load = useCallback(() => {
    setState((s) => ({ ...s, status: 'loading', error: null }));
    fetchFn()
      .then((data) => setState({ status: 'ok', data, error: null }))
      .catch((err) => setState({ status: 'error', data: null, error: err.message || 'โหลดข้อมูลไม่สำเร็จ' }));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  useEffect(() => { load(); }, [load]);

  return { ...state, reload: load };
}

function DashCard({ children, style, ...props }) {
  return (
    <Card
      withBorder
      radius={12}
      p="lg"
      shadow="none"
      style={{ borderColor: CARD_BORDER, background: '#ffffff', ...style }}
      {...props}
    >
      {children}
    </Card>
  );
}

function MetricCard({ icon: Icon, label, value, resource }) {
  const { status, data, error, reload } = resource;
  return (
    <DashCard>
      <Group justify="space-between" mb="xs">
        <Text size="sm" c="dimmed">{label}</Text>
        <ThemeIcon size={36} radius={12} variant="light" color="teal" style={{ color: PRIMARY }}>
          <Icon size={20} />
        </ThemeIcon>
      </Group>
      {status === 'loading' ? (
        <Skeleton height={32} width={80} />
      ) : status === 'error' ? (
        <Group gap={6}>
          <Text size="sm" c="red">โหลดไม่สำเร็จ</Text>
          <Button size="compact-xs" variant="subtle" onClick={reload}>ลองใหม่</Button>
        </Group>
      ) : (
        <Text size="28px" fw={700}>{value(data)}</Text>
      )}
      {status === 'error' && <Text size="xs" c="dimmed" mt={4}>{error}</Text>}
    </DashCard>
  );
}

function ChartCard({ title, height = 280, resource, isEmpty, extra, children }) {
  const { status, data, error, reload } = resource;
  return (
    <DashCard h="100%">
      <Group justify="space-between" mb="md" wrap="wrap" gap="xs">
        <Text fw={600}>{title}</Text>
        {extra}
      </Group>
      {status === 'loading' ? (
        <Skeleton height={height} radius={8} />
      ) : status === 'error' ? (
        <Stack align="center" justify="center" h={height} gap="xs">
          <Text c="red" size="sm">โหลดข้อมูลไม่สำเร็จ</Text>
          <Text c="dimmed" size="xs">{error}</Text>
          <Button size="xs" variant="light" onClick={reload}>ลองใหม่</Button>
        </Stack>
      ) : isEmpty(data) ? (
        <Group justify="center" h={height}>
          <Text c="dimmed" size="sm">ยังไม่มีข้อมูล</Text>
        </Group>
      ) : (
        children(data)
      )}
    </DashCard>
  );
}

export function DashboardPage() {
  const navigate = useNavigate();
  const [trendGranularity, setTrendGranularity] = useState('day');
  const summary = useDashboardResource(getDashboardSummary);
  const trend = useDashboardResource(
    () => getMealTrend(trendGranularity === 'day' ? 30 : trendGranularity === 'all' ? 'all' : 366),
    [trendGranularity],
  );
  const [foodTypePeriod, setFoodTypePeriod] = useState('all');
  const foodType = useDashboardResource(
    () => getFoodTypeDist(PERIOD_DAYS[foodTypePeriod]),
    [foodTypePeriod],
  );
  const [topFoodsPeriod, setTopFoodsPeriod] = useState('all');
  const topFoods = useDashboardResource(
    () => getTopFoods(10, PERIOD_DAYS[topFoodsPeriod]),
    [topFoodsPeriod],
  );
  const goalDist = useDashboardResource(getGoalDist);
  const genderDist = useDashboardResource(getGenderDist);
  const allergenStats = useDashboardResource(getAllergenStats);
  const menuCompleteness = useDashboardResource(getMenuCompleteness);

  const goToEditItem = (itemId) => navigate('/menu-food', { state: { editItemId: itemId } });

  return (
    <Stack gap="lg">
      <Title order={3} style={{ color: PRIMARY }}>แดชบอร์ด</Title>

      {/* Row 1 — metric cards */}
      <SimpleGrid cols={{ base: 1, sm: 2, lg: 4 }}>
        <MetricCard
          icon={IconUsers}
          label="จำนวนสมาชิกทั้งหมด"
          resource={summary}
          value={(d) => d.total_members}
        />
        <MetricCard
          icon={IconUserPlus}
          label="สมาชิกใหม่ 7 วันล่าสุด"
          resource={summary}
          value={(d) => d.new_members_7d}
        />
        <MetricCard
          icon={IconToolsKitchen2}
          label="มื้ออาหารที่บันทึกวันนี้"
          resource={summary}
          value={(d) => d.meals_logged_today}
        />
        <MetricCard
          icon={IconMessageCircle2}
          label="Ticket รอตอบ"
          resource={summary}
          value={(d) => d.pending_tickets}
        />
      </SimpleGrid>

      {/* Row 2 — main charts */}
      <Grid>
        <Grid.Col span={{ base: 12, md: 6 }}>
          <ChartCard
            title={TREND_TITLE[trendGranularity]}
            resource={trend}
            isEmpty={(d) => !d?.trend?.length || d.trend.every((t) => t.planned === 0 && t.eaten === 0)}
            extra={
              <SegmentedControl
                size="xs"
                value={trendGranularity}
                onChange={setTrendGranularity}
                data={[
                  { label: 'ทั้งหมด', value: 'all' },
                  { label: 'วัน', value: 'day' },
                  { label: 'เดือน', value: 'month' },
                  { label: 'ปี', value: 'year' },
                ]}
              />
            }
          >
            {(d) => (
              <LineChart
                h={280}
                data={aggregateTrend(d.trend, trendGranularity).map((t) => ({
                  date: formatTrendLabel(t.date, trendGranularity),
                  วางแผน: t.planned,
                  ทานจริง: t.eaten,
                }))}
                dataKey="date"
                series={[
                  { name: 'วางแผน', color: PRIMARY },
                  { name: 'ทานจริง', color: SECONDARY },
                ]}
                curveType="monotone"
                withDots={false}
                gridAxis="y"
              />
            )}
          </ChartCard>
        </Grid.Col>
        <Grid.Col span={{ base: 12, md: 6 }}>
          <ChartCard
            title="สัดส่วนเมนูแต่ละประเภท (ทานจริง)"
            resource={foodType}
            isEmpty={(d) => !d?.distribution?.length}
            extra={
              <SegmentedControl
                size="xs"
                value={foodTypePeriod}
                onChange={setFoodTypePeriod}
                data={PERIOD_OPTIONS}
              />
            }
          >
            {(d) => (
              <Group justify="center">
                <DonutChart
                  h={280}
                  data={d.distribution.map((row, i) => ({
                    name: FOOD_TYPE_LABEL_TH[row.type] || row.type,
                    value: row.count,
                    color: DONUT_PALETTE[i % DONUT_PALETTE.length],
                  }))}
                  withLabelsLine
                  withLabels
                  chartLabel="เมนู"
                />
              </Group>
            )}
          </ChartCard>
        </Grid.Col>
      </Grid>

      {/* Row 3 — secondary charts */}
      <Grid>
        <Grid.Col span={{ base: 12, md: 4 }}>
          <ChartCard
            title="Top 10 เมนูที่ถูกเลือกมากที่สุด"
            resource={topFoods}
            isEmpty={(d) => !d?.top_foods?.length}
            extra={
              <SegmentedControl
                size="xs"
                value={topFoodsPeriod}
                onChange={setTopFoodsPeriod}
                data={PERIOD_OPTIONS}
              />
            }
          >
            {(d) => (
              <BarChart
                h={280}
                data={d.top_foods.map((f) => ({ name: f.name, 'จำนวนครั้ง': f.count }))}
                dataKey="name"
                series={[{ name: 'จำนวนครั้ง', color: PRIMARY }]}
                gridAxis="y"
              />
            )}
          </ChartCard>
        </Grid.Col>
        <Grid.Col span={{ base: 12, md: 4 }}>
          <ChartCard
            title="สมาชิกแยกตามเป้าหมายสุขภาพ"
            resource={goalDist}
            isEmpty={(d) => !d?.distribution?.length}
          >
            {(d) => (
              <BarChart
                h={280}
                data={d.distribution.map((g) => ({ name: g.health_goal, 'จำนวนสมาชิก': g.count }))}
                dataKey="name"
                series={[{ name: 'จำนวนสมาชิก', color: SECONDARY }]}
                gridAxis="y"
              />
            )}
          </ChartCard>
        </Grid.Col>
        <Grid.Col span={{ base: 12, md: 4 }}>
          <ChartCard
            title="สัดส่วนเพศของสมาชิก"
            resource={genderDist}
            isEmpty={(d) => !d || d.male + d.female === 0}
          >
            {(d) => (
              <Group justify="center">
                <DonutChart
                  h={280}
                  data={['male', 'female']
                    .filter((key) => d[key] > 0)
                    .map((key) => ({
                      name: GENDER_LABEL_TH[key],
                      value: d[key],
                      color: GENDER_COLOR[key],
                    }))}
                  withLabelsLine
                  withLabels
                  chartLabel="สมาชิก"
                />
              </Group>
            )}
          </ChartCard>
        </Grid.Col>
      </Grid>

      {/* Row 4 — งานที่ 4: widget เสริม (สารก่อภูมิแพ้ที่พบบ่อย / เมนูที่ยังไม่สมบูรณ์) */}
      <Grid>
        <Grid.Col span={{ base: 12, md: 6 }}>
          <ChartCard
            title="สารก่อภูมิแพ้ที่พบบ่อย"
            resource={allergenStats}
            isEmpty={(d) => !d?.distribution?.length}
          >
            {(d) => (
              <BarChart
                h={280}
                data={d.distribution.slice(0, 10).map((row) => ({ name: row.allergen, 'จำนวนคน': row.count }))}
                dataKey="name"
                series={[{ name: 'จำนวนคน', color: SECONDARY }]}
                orientation="vertical"
                gridAxis="x"
              />
            )}
          </ChartCard>
        </Grid.Col>
        <Grid.Col span={{ base: 12, md: 6 }}>
          <ChartCard
            title="เมนูที่ยังไม่สมบูรณ์"
            resource={menuCompleteness}
            isEmpty={(d) => mergeMenuCompleteness(d).length === 0}
          >
            {(d) => {
              const rows = mergeMenuCompleteness(d);
              return (
                <ScrollArea h={280}>
                  <Stack gap={4}>
                    {rows.map((item) => (
                      <UnstyledButton
                        key={item.id}
                        onClick={() => goToEditItem(item.id)}
                        p="xs"
                        style={{ borderRadius: 8, border: `1px solid ${CARD_BORDER}` }}
                      >
                        <Group justify="space-between" wrap="nowrap">
                          <Stack gap={4}>
                            <Text size="sm" fw={600}>{item.name}</Text>
                            <Group gap={4}>
                              {item.reasons.map((r) => (
                                <Badge key={r} size="xs" color="orange" variant="light">
                                  {COMPLETENESS_REASON_LABEL[r]}
                                </Badge>
                              ))}
                            </Group>
                          </Stack>
                          <IconChevronRight size={16} color="#9CA3AF" />
                        </Group>
                      </UnstyledButton>
                    ))}
                  </Stack>
                </ScrollArea>
              );
            }}
          </ChartCard>
        </Grid.Col>
      </Grid>
    </Stack>
  );
}
