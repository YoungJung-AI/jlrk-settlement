-- ============================================================
--  Migration 012 — AR Voucher (JLRK → 리테일러 청구) 워크플로우
-- ============================================================

-- 1) 초기 스키마에서 이름 충돌 회피용으로 넣었던 'the_REJECTED' 를 정상 명칭으로 변경
do $$
begin
  if exists (
    select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'dispute_status' and e.enumlabel = 'the_REJECTED'
  ) then
    alter type dispute_status rename value 'the_REJECTED' to 'REJECTED';
  end if;
end $$;

-- 2) 리테일러의 "청구 확인" 시각 (AR 전용)
alter table claims add column if not exists confirmed_at timestamptz;

-- 3) AR 근거자료 경로 (관리자가 리테일러에게 제시하는 청구 근거)
alter table claims add column if not exists evidence_path text;

-- 4) 이의제기 재수정을 위해 update 도 허용 (기존엔 insert 정책만 있었음)
drop policy if exists "disputes_retailer_update" on disputes;
create policy "disputes_retailer_update" on disputes for update to authenticated
  using (
    retailer_id = public.my_retailer()
    and status = 'RAISED'
    and exists (
      select 1 from rounds r
      where r.id = disputes.round_id
        and r.status = 'PUBLISHED'
        and (r.dispute_due_at is null or now() < r.dispute_due_at)
    )
  )
  with check (retailer_id = public.my_retailer());

-- 5) 리테일러가 AR 청구를 "확인" 처리할 수 있도록 claims update 정책 확장
--    (기존 정책은 회차가 OPEN 이거나 반송건일 때만 허용했음)
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
      or exists (   -- AR: 공지 상태에서 확인 처리
        select 1 from rounds r
        where r.id = claims.round_id
          and r.status = 'PUBLISHED'
      )
    )
  )
  with check (retailer_id = public.my_retailer());
