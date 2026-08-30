-- ============================================================
--  Migration 002 — 청구서/증빙 파일 업로드 지원
-- ============================================================

-- 1. claims: 업로드 파일 경로 저장
alter table claims add column if not exists file_path text;

-- 2. Storage RLS — 'settlements' 버킷
--    경로 규칙: settlements/{retailer_id}/{round_id}/{claim_id}-{filename}
--    (버킷 자체 이름은 bucket_id로 필터링, 실제 파일 경로는 name 컬럼)

drop policy if exists "settlements_insert_own" on storage.objects;
create policy "settlements_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'settlements'
    and (storage.foldername(name))[1] = coalesce(public.my_retailer()::text, '')
  );

drop policy if exists "settlements_update_own" on storage.objects;
create policy "settlements_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'settlements'
    and (storage.foldername(name))[1] = coalesce(public.my_retailer()::text, '')
  );

drop policy if exists "settlements_read" on storage.objects;
create policy "settlements_read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'settlements'
    and (
      public.is_admin()
      or (storage.foldername(name))[1] = coalesce(public.my_retailer()::text, '')
    )
  );
