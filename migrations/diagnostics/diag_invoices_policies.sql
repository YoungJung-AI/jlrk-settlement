-- ============================================================
--  Migration 007 — invoices INSERT 정책 재작성 (명시적 컬럼 한정)
--  + 진단용 쿼리
-- ============================================================

drop policy if exists "invoices_retailer_insert" on invoices;
create policy "invoices_retailer_insert" on invoices
  for insert to authenticated
  with check (
    retailer_id = public.my_retailer()
    and exists (
      select 1 from rounds r
      where r.id = invoices.round_id
        and r.status = 'CONFIRMED'
        and (r.invoice_due_at is null or now() < r.invoice_due_at)
    )
  );

-- ---------- 진단 1: 현재 invoices 관련 정책 목록 ----------
select policyname, cmd, qual, with_check
from pg_policies
where tablename = 'invoices';

-- ---------- 진단 2: 문제의 회차 상태/마감일 확인 ----------
select id, period_label, status, claim_due_at, invoice_due_at
from rounds
where period_label = 'FY27 Q1'
order by created_at desc
limit 5;
