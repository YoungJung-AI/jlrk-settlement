-- ============================================================
--  Migration 013 — AR Voucher 정산 구조
--  두 사례(One DMS License / Engine Oil Package) 분석 반영
-- ============================================================

-- 1) 정산 유형별 AR 설정
alter table settlement_types add column if not exists vat_code text default 'A1: 10%';
  -- 'A1: 10%' (부가세 10%) | 'A0: 0%' (Engine Oil처럼 부가세 없는 대금 정산)

alter table settlement_types add column if not exists brand_split_mode text default 'FIXED';
  -- 'ACTUAL' : 원천데이터의 브랜드 실적대로 (Engine Oil)
  -- 'FIXED'  : 고정비율 (One DMS = JG 10% / LR 90%)

alter table settlement_types add column if not exists brand_jg_ratio numeric(5,4) default 0.10;
  -- brand_split_mode='FIXED'일 때 JG 비율 (0.10 = 10%)

alter table settlement_types add column if not exists amount_mode text default 'UPLOAD';
  -- 'UPLOAD' : 원천 엑셀 업로드 → 지점별 자동 집계 (Engine Oil)
  -- 'UNIT'   : 수량 × 단가 계산 (One DMS License)
  -- 'MANUAL' : 관리자가 직접 입력

alter table settlement_types add column if not exists unit_price numeric(18,4);
  -- amount_mode='UNIT'일 때 1단위당 금액 (예: DMS 월 라이센스 단가 109,329.6667)

alter table settlement_types add column if not exists source_config jsonb default '{}'::jsonb;
  -- 원천 엑셀 파싱 규칙. 예:
  -- {"sheet":"FY27 Q1 Jun","workshop_col":"Workshop","amount_col":"Total",
  --  "jg_col":"Jaguar","lr_col":"Landrover","header_keyword":"Workshop"}

alter table settlement_types add column if not exists charge_unit text default 'WORKSHOP';
  -- AR 금액 계상 단위: 'WORKSHOP'(지점별 개별 계상, Engine Oil)
  --                  'PRIMARY'(법인 대표지점 1곳에 몰아서, One DMS)

-- 2) AR 거래처 코드 체계는 AP(vendor code)와 완전히 별개 — 지점 마스터에 분리 보관
alter table workshops add column if not exists customer_code text;   -- 예: KR01074MIS
alter table workshops add column if not exists ar_biz_no text;        -- AR용 사업자번호(AP와 다른 경우 있음)

-- 3) 브랜드별 금액을 청구 단위로 저장 (바우처 GL 라인 산출용)
alter table claims add column if not exists jg_amount numeric(18,2);
alter table claims add column if not exists lr_amount numeric(18,2);

-- 4) 수량 기반 계산(One DMS)용
alter table claims add column if not exists quantity numeric(18,4);

-- 확인
select column_name, data_type
from information_schema.columns
where table_name = 'settlement_types'
  and column_name in ('vat_code','brand_split_mode','brand_jg_ratio','amount_mode','unit_price','source_config','charge_unit')
order by column_name;
