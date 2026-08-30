-- ============================================================
--  Migration 018 — 기정산 중복 방지 + 시스템 산출 정산
-- ============================================================

-- 1) 정산 유형별 중복키 정의
alter table settlement_types add column if not exists dedup_keys jsonb default '[]'::jsonb;
--  예: ["차대번호","쿠폰사용 참조번호","쿠폰번호"]

-- 2) 상태 필터 (정산 대상으로 인정할 조건)
alter table settlement_types add column if not exists status_filter jsonb default '{}'::jsonb;
--  예: {"column":"클레임상태","allowed":["전송"]}

-- 3) 산출 방식에 SYSTEM 추가 (리테일러 입력 없이 관리자가 원본만 올리면 시스템이 계산)
--    amount_mode 는 text 컬럼이라 값만 추가로 쓰면 됨: 'UPLOAD' | 'UNIT' | 'MANUAL' | 'SYSTEM'

-- 4) 범용 기정산 이력
create table if not exists settled_records (
  id uuid primary key default gen_random_uuid(),
  type_id uuid not null references settlement_types(id) on delete cascade,
  dedup_hash text not null,              -- 조합키를 정규화(공백제거+대문자)해 만든 지문
  raw_keys jsonb,                        -- 원본 키 값 (조회·검증용)
  round_id uuid references rounds(id) on delete set null,
  retailer_id uuid references retailers(id) on delete set null,
  workshop_id uuid references workshops(id) on delete set null,
  amount numeric(18,2),
  source text default 'ROUND',           -- 'ROUND'(정상 정산) | 'INITIAL'(과거분 초기적재)
  settled_at timestamptz not null default now(),
  unique (type_id, dedup_hash)           -- 같은 유형 안에서 같은 건은 한 번만
);

create index if not exists settled_type_hash_idx on settled_records (type_id, dedup_hash);
create index if not exists settled_round_idx on settled_records (round_id);

alter table settled_records enable row level security;
drop policy if exists "settled_admin" on settled_records;
create policy "settled_admin" on settled_records for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- 5) 회차에 원본 업로드 결과 요약 보관
alter table rounds add column if not exists source_summary jsonb;
--  예: {"total":1970,"target":412,"already":1522,"excluded":36,"amount":145230000}
