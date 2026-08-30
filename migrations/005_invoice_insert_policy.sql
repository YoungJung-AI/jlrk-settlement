-- ============================================================
--  Migration 005 — invoices upsert 지원 (신규 생성은 없었음)
--  세금계산서를 사전 생성하지 않고, 승인 완료 시점에 리테일러가
--  제출하면서 그때 처음 생성(upsert)되는 방식으로 변경
-- ============================================================

drop policy if exists "invoices_retailer_insert" on invoices;
create policy "invoices_retailer_insert" on invoices
  for insert to authenticated
  with check (
    retailer_id = public.my_retailer()
    and exists (
      select 1 from rounds r
      where r.id = round_id
        and r.status = 'CONFIRMED'
        and (r.invoice_due_at is null or now() < r.invoice_due_at)
    )
  );
