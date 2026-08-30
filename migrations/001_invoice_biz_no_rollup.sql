-- ============================================================
--  Migration 001 — invoice 롤업 기준을 biz_no로 변경 (A안)
--  Phase 0 스키마가 이미 반영된 상태에서 실행
-- ============================================================

-- 1. workshops: 세금계산서 발행 단위 식별용 컬럼 추가
alter table workshops add column if not exists vendor_code text;
alter table workshops add column if not exists biz_no text;

-- 2. retailers.biz_no: 이제 "그룹 대표값"일 뿐, 실제 발행 단위 아님 → nullable로 변경
alter table retailers alter column biz_no drop not null;

-- 3. invoices: retailer_id 대신 biz_no 기준으로 유니크 (그룹 내 biz_no가 여러 개일 수 있음)
alter table invoices add column if not exists biz_no text;
alter table invoices drop constraint if exists invoices_round_id_retailer_id_key;
alter table invoices alter column biz_no set not null;
alter table invoices add constraint invoices_round_id_biz_no_key unique (round_id, biz_no);

-- RLS의 invoices_retailer_write 정책은 retailer_id = my_retailer() 로 이미 그룹 단위 필터링 중이라
-- (한 리테일러 로그인이 자기 그룹 내 여러 biz_no 인보이스를 다루는 구조) 정책 자체는 안 바꿔도 됨.
