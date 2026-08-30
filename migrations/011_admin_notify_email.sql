-- ============================================================
--  Migration 011 — 관리자 알림 수신 이메일
-- ============================================================
alter table profiles add column if not exists notify_email text;

-- 본인 관리자 계정에 알림 받을 이메일을 등록하세요 (본인 이메일로 교체):
-- update profiles set notify_email = '본인이메일@example.com' where role = 'ADMIN';
