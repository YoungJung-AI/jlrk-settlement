-- ============================================================
--  Migration 004 — 관리자가 반송 시 첨부파일을 올릴 수 있도록
--  Storage insert/update 권한을 is_admin()에도 허용
-- ============================================================

drop policy if exists "settlements_admin_write" on storage.objects;
create policy "settlements_admin_write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'settlements' and public.is_admin());

drop policy if exists "settlements_admin_update" on storage.objects;
create policy "settlements_admin_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'settlements' and public.is_admin());
