ALTER TABLE health_goal_cycles ADD COLUMN acknowledged_at DATETIME NULL;
-- null = ผู้ใช้ยังไม่เคยเห็น dialog สรุปผลรอบนี้ (ดู
-- api.get_dashboard_summary / POST /api/user/health-goal-cycles/<id>/ack)
