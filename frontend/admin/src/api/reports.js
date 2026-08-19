import { apiGet, apiPost } from './client';

export const getReports = (status) =>
  apiGet(`/admin/reports${status && status !== 'all' ? `?status=${status}` : ''}`).then((r) => r.reports || []);

export const replyReport = (reportId, message) =>
  apiPost('/admin/reply', { report_id: reportId, message });

export const closeReport = (reportId) => apiPost('/admin/close_report', { report_id: reportId });

// บทสนทนาแบบ chat ของ ticket 1 เรื่อง — แทนที่รูปแบบเดิม (message + admin_reply
// อย่างละ 1 ข้อความ) ด้วยประวัติข้อความไปมาได้หลายรอบ
export const getReportMessages = (reportId) => apiGet(`/admin/reports/${reportId}/messages`);
