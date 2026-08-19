import { useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { Paper, TextInput, PasswordInput, Button, Title, Stack, Center, Text } from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useAuth } from '../auth/AuthContext';

export function LoginPage() {
  const { user, loading, login } = useAuth();
  const navigate = useNavigate();
  const [submitting, setSubmitting] = useState(false);

  const form = useForm({
    initialValues: { username: '', password: '' },
    validate: {
      username: (v) => (v.trim() ? null : 'กรุณากรอกชื่อผู้ใช้'),
      password: (v) => (v ? null : 'กรุณากรอกรหัสผ่าน'),
    },
  });

  if (!loading && user) {
    return <Navigate to="/" replace />;
  }

  const handleSubmit = async (values) => {
    setSubmitting(true);
    try {
      await login(values.username, values.password);
      navigate('/');
    } catch (err) {
      // เดิม catch {} ทิ้ง error object เลย ทำให้ network error/backend ล่ม
      // (err.status เป็น undefined) โชว์ข้อความ "รหัสผ่านผิด" เหมือนกันหมด
      // กับกรอกรหัสผ่านผิดจริง (บั๊กที่เจอจริง) — แยกตาม err.status แทน
      const isBadCredentials = err?.status === 401 || err?.status === 403;
      notifications.show({
        color: 'red',
        title: 'เข้าสู่ระบบไม่สำเร็จ',
        message: isBadCredentials
          ? 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง'
          : `เชื่อมต่อเซิร์ฟเวอร์ไม่ได้: ${err?.message || 'กรุณาลองใหม่อีกครั้ง'}`,
      });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Center mih="100vh" bg="#f8f9fa">
      <Paper shadow="md" p="xl" radius="md" w={380}>
        <Stack gap="md">
          <div>
            <Title order={2} c="#0E5916" ta="center">Admin Dashboard</Title>
            <Text ta="center" c="dimmed" size="sm">เข้าสู่ระบบสำหรับผู้ดูแล</Text>
          </div>
          <form onSubmit={form.onSubmit(handleSubmit)}>
            <Stack gap="sm">
              <TextInput
                label="ชื่อผู้ใช้"
                placeholder="username"
                {...form.getInputProps('username')}
              />
              <PasswordInput
                label="รหัสผ่าน"
                placeholder="password"
                {...form.getInputProps('password')}
              />
              <Button type="submit" color="brandGreen" loading={submitting} mt="sm">
                เข้าสู่ระบบ
              </Button>
            </Stack>
          </form>
        </Stack>
      </Paper>
    </Center>
  );
}
