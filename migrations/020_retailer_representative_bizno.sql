-- ============================================================
--  Migration 020 — 리테일러 대표 사업자번호
--  세금계산서는 리테일러당 1장 (사용자 확정 2026-09-01).
--  그룹 내 사업자번호가 갈리는 AJ·HS·WB 는 아래 대표 지점 기준으로 발행.
--    아주   → 한남   (214-88-00795)
--    효성   → 부산센텀 (254-85-00545)
--    위본   → 광주   (185-85-02077)
--  세금계산서 롤업/유니크 제약은 기존 그대로 unique(round_id, retailer_id).
-- ============================================================

update retailers set biz_no = '2148800795' where code = 'AJ';   -- 한남 기준
update retailers set biz_no = '2548500545' where code = 'HS';   -- 부산센텀 기준
update retailers set biz_no = '1858502077' where code = 'WB';   -- 광주 기준
update retailers set biz_no = '2148835620' where code = 'CH';   -- 그룹 내 단일
update retailers set biz_no = '1178159958' where code = 'KCC';
update retailers set biz_no = '5028540484' where code = 'EN';   -- 대구 (AP 기준)
update retailers set biz_no = '6178149208' where code = 'HY';
update retailers set biz_no = '3148626446' where code = 'JL';

-- 확인
select code, name, biz_no from retailers order by code;
