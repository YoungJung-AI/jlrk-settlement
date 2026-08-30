-- ============================================================
--  JLR Korea 리테일러 정산 포털 — Phase 0 스키마
--  Supabase (Postgres) / SQL Editor 에 그대로 실행
--  작성: 기획 확정본 v1
-- ============================================================

-- ---------- 0. 확장 ----------
create extension if not exists "pgcrypto";

-- ---------- 1. ENUM ----------
create type settlement_direction as enum ('AP', 'AR');
-- AP = JLRK -> 리테일러 지원금 지급 (리테일러가 청구)
-- AR = JLRK -> 리테일러 청구 (관리자가 공지)

create type settlement_period  as enum ('MONTHLY', 'QUARTERLY');
create type claim_unit         as enum ('RETAILER', 'WORKSHOP');
create type notify_mode        as enum ('INSTANT', 'DAILY_DIGEST');
create type user_role          as enum ('ADMIN', 'RETAILER');

create type round_status as enum (
  'DRAFT',        -- 공통: 작성 중, 리테일러 미노출
  -- AP 흐름
  'OPEN',         -- 청구 접수중
  'CLOSED',       -- 마감 / JLRK 검토중
  'CONFIRMED',    -- 확정금액 공지 / 세금계산서 접수중
  'INVOICED',     -- 계산서 전원 접수 / 바우처 생성 가능
  'VOUCHERED',    -- 바우처 생성 완료
  -- AR 흐름
  'PUBLISHED',    -- 청구 공지 / 확인·이의제기 접수중
  'FINALIZED',    -- 이의 종결, 최종 청구금액 확정
  -- 공통 종료
  'ARCHIVED'
);

create type claim_status as enum (
  'NOT_SUBMITTED',
  'SUBMITTED',
  'REJECTED',     -- 반송 (개별 재오픈)
  'APPROVED',
  'CANCELLED'
);

create type invoice_status as enum (
  'PENDING',      -- 계산서 미제출
  'SUBMITTED',
  'MISMATCH',     -- OCR 금액 != 확정금액
  'ACCEPTED'
);

create type dispute_status as enum ('RAISED', 'APPROVED', 'the_REJECTED');
-- NOTE: 'the_REJECTED' 는 claim_status.REJECTED 와 이름 충돌 회피용.
--       별도 enum 이므로 실제로는 'REJECTED' 로 바꿔도 무방.

-- ---------- 2. 마스터 ----------
create table retailers (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,          -- 예: 'CHN', 'DHM'
  name        text not null,
  biz_no      text not null,                 -- 사업자등록번호
  ceo_name    text,
  email       text not null,                 -- 대표 수신 메일
  is_active   boolean not null default true, -- ★ 물리 삭제 금지, 비활성화만
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table workshops (
  id          uuid primary key default gen_random_uuid(),
  retailer_id uuid not null references retailers(id) on delete restrict,
  code        text not null unique,
  name        text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Supabase auth.users 와 1:1
create table profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  role        user_role not null default 'RETAILER',
  retailer_id uuid references retailers(id) on delete restrict,
  display_name text,
  created_at  timestamptz not null default now(),
  constraint retailer_must_have_retailer_id
    check (role = 'ADMIN' or retailer_id is not null)
);

-- ---------- 3. 정산 유형 (Phase 1 화면이 CRUD 하는 대상) ----------
create table settlement_types (
  id                   uuid primary key default gen_random_uuid(),
  code                 text not null unique,
  name                 text not null,
  direction            settlement_direction not null,
  period               settlement_period not null,
  claim_unit           claim_unit not null default 'RETAILER',
  -- invoice_unit 은 항상 법인(RETAILER) 이므로 컬럼 없음

  due_rule             jsonb,      -- 예: {"anchor":"next_month","day":10,"time":"18:00"}
  form_template_path   text,       -- 청구서 양식 (Storage)
  voucher_template_path text,      -- 바우처 템플릿 (Storage)
  required_files       jsonb default '[]'::jsonb,

  vat_included         boolean not null default false,
  amount_cap           numeric(18,2),
  rounding             text default 'FLOOR',

  notify               notify_mode not null default 'INSTANT',
  reminder_days        int[] default '{3,1}',
  early_close          boolean not null default false, -- 전원 제출 시 조기마감
  allow_reopen         boolean not null default true,  -- 마감 후 개별 재오픈

  target_retailers     uuid[],     -- null = 활성 전체
  is_active            boolean not null default true,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

-- ---------- 4. 회차 ----------
create table rounds (
  id             uuid primary key default gen_random_uuid(),
  type_id        uuid not null references settlement_types(id) on delete restrict,
  period_label   text not null,               -- 'FY27 Q1', '2026-07'
  status         round_status not null default 'DRAFT',
  claim_due_at   timestamptz,
  invoice_due_at timestamptz,
  dispute_due_at timestamptz,                 -- AR 전용
  form_path      text,                        -- 회차별 양식(유형 템플릿 override)
  memo           text,
  created_by     uuid references profiles(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (type_id, period_label)
);

-- ---------- 5. 청구 (청구 단위 = 유형에 따라 법인 or 지점) ----------
create table claims (
  id              uuid primary key default gen_random_uuid(),
  round_id        uuid not null references rounds(id) on delete cascade,
  retailer_id     uuid not null references retailers(id) on delete restrict,
  workshop_id     uuid references workshops(id) on delete restrict, -- null = 법인 단위
  status          claim_status not null default 'NOT_SUBMITTED',
  claimed_amount  numeric(18,2),
  approved_amount numeric(18,2),
  reject_reason   text,
  detail          jsonb,          -- 청구서 파싱 결과(라인아이템)
  submitted_at    timestamptz,
  reviewed_at     timestamptz,
  reviewed_by     uuid references profiles(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- 청구 단위별 중복 방지
create unique index claims_uniq_retailer
  on claims (round_id, retailer_id) where workshop_id is null;
create unique index claims_uniq_workshop
  on claims (round_id, workshop_id) where workshop_id is not null;

create index claims_round_idx    on claims (round_id);
create index claims_retailer_idx on claims (retailer_id);

-- ---------- 6. 세금계산서 (항상 법인 단위, claims 를 롤업) ----------
create table invoices (
  id             uuid primary key default gen_random_uuid(),
  round_id       uuid not null references rounds(id) on delete cascade,
  retailer_id    uuid not null references retailers(id) on delete restrict,
  status         invoice_status not null default 'PENDING',
  supply_amount  numeric(18,2),   -- 공급가액 (= 소속 claims approved 합계)
  vat            numeric(18,2),
  total_amount   numeric(18,2),
  file_path      text,            -- 업로드된 계산서 PDF
  ocr_amount     numeric(18,2),   -- PDF 에서 추출한 공급가액
  match_flag     boolean,         -- ocr_amount = supply_amount 여부
  submitted_at   timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (round_id, retailer_id)
);

-- ---------- 7. 이의제기 (AR 전용) ----------
create table disputes (
  id           uuid primary key default gen_random_uuid(),
  round_id     uuid not null references rounds(id) on delete cascade,
  retailer_id  uuid not null references retailers(id) on delete restrict,
  status       dispute_status not null default 'RAISED',
  reason       text not null,
  evidence_path text,
  requested_amount numeric(18,2),
  decision_note text,
  decided_by   uuid references profiles(id),
  decided_at   timestamptz,
  created_at   timestamptz not null default now(),
  unique (round_id, retailer_id)
);

-- ---------- 8. 바우처 ----------
create table vouchers (
  id           uuid primary key default gen_random_uuid(),
  round_id     uuid not null references rounds(id) on delete cascade,
  retailer_id  uuid not null references retailers(id) on delete restrict,
  file_path    text,
  generated_at timestamptz not null default now(),
  generated_by uuid references profiles(id),
  unique (round_id, retailer_id)
);

-- ---------- 9. 감사 로그 ----------
create table audit_log (
  id          bigserial primary key,
  actor_id    uuid references profiles(id),
  action      text not null,          -- 'CLAIM_SUBMIT', 'ROUND_CLOSE', ...
  target_type text,
  target_id   uuid,
  payload     jsonb,
  at          timestamptz not null default now()
);
create index audit_at_idx on audit_log (at desc);

-- ============================================================
--  10. 권한 헬퍼 (SECURITY DEFINER — RLS 재귀 방지)
-- ============================================================
create or replace function public.my_role() returns user_role
language sql stable security definer set search_path = public as $$
  select role from profiles where id = auth.uid()
$$;

create or replace function public.my_retailer() returns uuid
language sql stable security definer set search_path = public as $$
  select retailer_id from profiles where id = auth.uid()
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() = 'ADMIN', false)
$$;

-- ============================================================
--  11. RLS — 격리는 여기서 강제된다
-- ============================================================
alter table retailers        enable row level security;
alter table workshops        enable row level security;
alter table profiles         enable row level security;
alter table settlement_types enable row level security;
alter table rounds           enable row level security;
alter table claims           enable row level security;
alter table invoices         enable row level security;
alter table disputes         enable row level security;
alter table vouchers         enable row level security;
alter table audit_log        enable row level security;

-- 마스터: 본인 소속 또는 관리자
create policy retailers_read on retailers for select
  using (is_admin() or id = my_retailer());
create policy retailers_admin on retailers for all
  using (is_admin()) with check (is_admin());

create policy workshops_read on workshops for select
  using (is_admin() or retailer_id = my_retailer());
create policy workshops_admin on workshops for all
  using (is_admin()) with check (is_admin());

create policy profiles_self on profiles for select
  using (is_admin() or id = auth.uid());
create policy profiles_admin on profiles for all
  using (is_admin()) with check (is_admin());

-- 정산 유형: 리테일러는 읽기만
create policy types_read on settlement_types for select using (true);
create policy types_admin on settlement_types for all
  using (is_admin()) with check (is_admin());

-- 회차: DRAFT 는 리테일러에게 안 보임
create policy rounds_read on rounds for select
  using (is_admin() or status <> 'DRAFT');
create policy rounds_admin on rounds for all
  using (is_admin()) with check (is_admin());

-- 청구: 자기 법인 것만
create policy claims_read on claims for select
  using (is_admin() or retailer_id = my_retailer());

create policy claims_admin on claims for all
  using (is_admin()) with check (is_admin());

-- ★ 리테일러 쓰기: OPEN 상태 + 서버시각 기준 마감 전에만
create policy claims_retailer_write on claims for update
  using (
    retailer_id = my_retailer()
    and exists (
      select 1 from rounds r
      where r.id = claims.round_id
        and r.status = 'OPEN'
        and (r.claim_due_at is null or now() < r.claim_due_at)
    )
  )
  with check (retailer_id = my_retailer());

-- 세금계산서: CONFIRMED 상태 + 마감 전에만
create policy invoices_read on invoices for select
  using (is_admin() or retailer_id = my_retailer());
create policy invoices_admin on invoices for all
  using (is_admin()) with check (is_admin());
create policy invoices_retailer_write on invoices for update
  using (
    retailer_id = my_retailer()
    and exists (
      select 1 from rounds r
      where r.id = invoices.round_id
        and r.status = 'CONFIRMED'
        and (r.invoice_due_at is null or now() < r.invoice_due_at)
    )
  )
  with check (retailer_id = my_retailer());

-- 이의제기: PUBLISHED 상태 + 이의 마감 전에만
create policy disputes_read on disputes for select
  using (is_admin() or retailer_id = my_retailer());
create policy disputes_admin on disputes for all
  using (is_admin()) with check (is_admin());
create policy disputes_retailer_write on disputes for insert
  with check (
    retailer_id = my_retailer()
    and exists (
      select 1 from rounds r
      where r.id = round_id
        and r.status = 'PUBLISHED'
        and (r.dispute_due_at is null or now() < r.dispute_due_at)
    )
  );

-- 바우처 / 감사로그: 관리자 전용
create policy vouchers_admin on vouchers for all
  using (is_admin()) with check (is_admin());
create policy audit_admin on audit_log for select using (is_admin());

-- ============================================================
--  12. updated_at 트리거
-- ============================================================
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

do $$
declare t text;
begin
  foreach t in array array['retailers','settlement_types','rounds','claims','invoices']
  loop
    execute format(
      'create trigger trg_%1$s_touch before update on %1$s
       for each row execute function public.touch_updated_at()', t);
  end loop;
end $$;

-- ============================================================
--  13. 마감 자동 전환 (pg_cron 에서 5분마다 호출)
-- ============================================================
create or replace function public.auto_close_rounds() returns void
language plpgsql security definer set search_path = public as $$
begin
  update rounds set status = 'CLOSED'
   where status = 'OPEN' and claim_due_at is not null and now() >= claim_due_at;

  update rounds set status = 'INVOICED'
   where status = 'CONFIRMED' and invoice_due_at is not null and now() >= invoice_due_at;

  update rounds set status = 'FINALIZED'
   where status = 'PUBLISHED' and dispute_due_at is not null and now() >= dispute_due_at;
end $$;

-- select cron.schedule('auto-close', '*/5 * * * *', 'select public.auto_close_rounds()');
