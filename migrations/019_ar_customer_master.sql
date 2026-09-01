-- ============================================================
--  Migration 019 — AR 거래처 마스터 시드 + 사업자번호 보정
--  사용자 제공 (AR_.xlsx, 2026-09-01) + 크로스체크 답변 반영
--  상세: docs/data-crosscheck.md
-- ============================================================

-- 1) 사업자번호 보정 (AP 기준 = ws.biz_no)
update workshops set biz_no = '2548500545' where code = 'HS-BC';   -- 효성 센텀: 172-86-00556(오기) → 254-85-00545 (사용자 확인)
update workshops set biz_no = '5028540484' where code = 'EN-DG';   -- 인타이어 대구 AP 기준

-- 2) AR 전용 사업자번호 (AP와 다른 경우만)
update workshops set ar_biz_no = '5148147707' where code = 'EN-DG'; -- 인타이어 대구: AR 세금계산서는 707 시작 (사용자 확인)
-- 위본 전주(WB-JJ)는 509-85-03267 로 AP=AR 동일 → ar_biz_no 불필요

-- 3) AR 거래처 코드 (customer_code) — DB 지점 코드 기준
update workshops set customer_code = 'KR00470MIS' where code = 'AJ-HN';
update workshops set customer_code = 'KR01075MIS' where code = 'AJ-SS';
update workshops set customer_code = 'KR01020MIS' where code = 'AJ-ICND';
update workshops set customer_code = 'KR01070MIS' where code = 'CH-DC';
update workshops set customer_code = 'KR00480MIS' where code = 'CH-SS';
update workshops set customer_code = 'KR01077MIS' where code = 'CH-SW';
update workshops set customer_code = 'KR01034MIS' where code = 'EN-DG';
update workshops set customer_code = 'KR01170MIS' where code = 'HS-BC';   -- 효성 센텀 AR 코드 = 1170MIS (사용자 확인, DMS의 1030MIS 아님)
update workshops set customer_code = 'KR01190MIS' where code = 'HS-US';
update workshops set customer_code = 'KR00820MIS' where code = 'HY';
update workshops set customer_code = 'KR00560MIS' where code = 'JL';
update workshops set customer_code = 'KR01280MIS' where code = 'KCC-GD';
update workshops set customer_code = 'KR01074MIS' where code = 'KCC-BD';
update workshops set customer_code = 'KR01079MIS' where code = 'KCC-SC';
update workshops set customer_code = 'KR01095MIS' where code = 'KCC-SN';
update workshops set customer_code = 'KR01072MIS' where code = 'KCC-WJ';
update workshops set customer_code = 'KR01073MIS' where code = 'KCC-IS';
update workshops set customer_code = 'KR01150MIS' where code = 'KCC-JJ';
update workshops set customer_code = 'KR01290MIS' where code = 'WB-GJ';
update workshops set customer_code = 'KR01300MIS' where code = 'WB-JJ';

-- 서대구(EN-SDG), 천안(CH-CA·미등록), 브리티시(BA-PC·미등록)는 AR 마스터에 없음 → customer_code 공란 유지
--   ※ 천안 지점이 AR/AP 정산에 계속 등장하면 workshops 에 신규 등록 필요

-- 확인
select code, name, biz_no, ar_biz_no, customer_code
from workshops order by code;
