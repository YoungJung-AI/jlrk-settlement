-- ============================================================
--  Migration 017 — 예산 관리 + 주기 확장
-- ============================================================

-- 1) 주기에 '연간(YEARLY)' / '상시(ONGOING)' 추가
do $$
begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid=e.enumtypid
                 where t.typname='settlement_period' and e.enumlabel='YEARLY') then
    alter type settlement_period add value 'YEARLY';
  end if;
  if not exists (select 1 from pg_enum e join pg_type t on t.oid=e.enumtypid
                 where t.typname='settlement_period' and e.enumlabel='ONGOING') then
    alter type settlement_period add value 'ONGOING';
  end if;
end $$;

-- 2) 예산 구분
do $$
begin
  if not exists (select 1 from pg_type where typname='budget_category') then
    create type budget_category as enum ('PA_SELLING','VME','FMI','ACCRUAL');
  end if;
end $$;

alter table settlement_types add column if not exists budget_category budget_category;
  -- P&A Selling / VME / FMI / Accrual

-- 3) 회차별 예산 귀속 정보 (회계연도·분기)
alter table rounds add column if not exists fiscal_year text;    -- 예: 'FY27'
alter table rounds add column if not exists fiscal_quarter text; -- 예: 'Q1'

-- 4) 예산 한도 관리 (선택 — 집행률 계산용)
create table if not exists budgets (
  id uuid primary key default gen_random_uuid(),
  category budget_category not null,
  fiscal_year text not null,
  fiscal_quarter text,              -- null = 연간 예산
  amount numeric(18,2) not null default 0,
  memo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (category, fiscal_year, fiscal_quarter)
);

alter table budgets enable row level security;
drop policy if exists "budgets_admin" on budgets;
create policy "budgets_admin" on budgets for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "budgets_read" on budgets;
create policy "budgets_read" on budgets for select to authenticated
  using (public.is_admin());

create index if not exists budgets_fy_idx on budgets (fiscal_year, fiscal_quarter);
create index if not exists rounds_fy_idx on rounds (fiscal_year, fiscal_quarter);
