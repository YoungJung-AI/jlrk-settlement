-- ============================================================
--  Migration 015 — 회차 아카이브
--  완료된 회차의 파일을 로컬로 내려받은 뒤 서버에서 정리하기 위한 준비
-- ============================================================

-- 1) 관리자가 Storage 파일을 삭제할 수 있어야 함 (기존엔 insert/update/select 만 있었음)
drop policy if exists "settlements_admin_delete" on storage.objects;
create policy "settlements_admin_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'settlements' and public.is_admin());

-- 2) 아카이브 이력
alter table rounds add column if not exists archived_at timestamptz;
alter table rounds add column if not exists archive_note text;

-- 3) 아카이브 후에도 남길 최종 요약 (파일이 지워져도 금액 근거는 유지)
alter table rounds add column if not exists final_summary jsonb;
--  예: {"total":138739347,"vat":13873935,"jg":13873935,"lr":124865412,
--       "retailers":[{"code":"AJ","amount":22303252}], "archived_files":12}

-- 4) 아카이브된 회차는 리테일러 화면에서 숨기기 위해 상태값 사용 (ARCHIVED)
--    기존 round_status enum 에 이미 'ARCHIVED' 존재하므로 추가 작업 없음
