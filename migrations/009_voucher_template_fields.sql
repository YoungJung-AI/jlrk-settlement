-- ============================================================
--  Migration 009 — Phase 4 바우처 생성 지원
-- ============================================================

-- 정산 유형별 바우처 라인 정의 (GL코드/코스트센터/설명)
alter table settlement_types add column if not exists voucher_lines jsonb default '[]'::jsonb;

-- 지점 중 "대표 지점"(eSmart vendor code 대표) 지정용 — 없으면 승인액 최대 지점을 자동 선택
alter table workshops add column if not exists is_primary boolean not null default false;

-- 바우처는 리테일러별이 아니라 회차 전체 1건으로 생성 (All Retailer 방식) → retailer_id nullable
alter table vouchers alter column retailer_id drop not null;
