-- ============================================================
--  Migration 003 — 반송(REJECTED) 건은 회차 마감 여부와 무관하게
--  리테일러가 재제출할 수 있도록 정책 완화
-- ============================================================

drop policy if exists "claims_retailer_write" on claims;
create policy "claims_retailer_write" on claims for update
  using (
    retailer_id = public.my_retailer()
    and (
      exists (
        select 1 from rounds r
        where r.id = claims.round_id
          and r.status = 'OPEN'
          and (r.claim_due_at is null or now() < r.claim_due_at)
      )
      or claims.status = 'REJECTED'
    )
  )
  with check (retailer_id = public.my_retailer());
