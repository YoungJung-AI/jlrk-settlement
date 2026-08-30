-- ============================================================
--  Migration 006-fix — invoices 테스트 데이터 정리 후 재적용
--  (biz_no 단위로 쪼개져 있던 이전 테스트 행들이 남아있어
--   UNIQUE(round_id, retailer_id) 추가가 실패했을 가능성이 높음)
-- ============================================================

-- 1) 테스트 데이터 정리 (실제 운영 데이터가 쌓이기 전이므로 전체 삭제해도 안전)
delete from invoices;

-- 2) 컬럼/제약 재정비
alter table invoices alter column biz_no drop not null;
alter table invoices drop constraint if exists invoices_round_id_biz_no_key;
alter table invoices drop constraint if exists invoices_round_id_retailer_id_key;
alter table invoices add constraint invoices_round_id_retailer_id_key unique (round_id, retailer_id);

-- 3) 확인
select conname from pg_constraint where conrelid = 'invoices'::regclass;
