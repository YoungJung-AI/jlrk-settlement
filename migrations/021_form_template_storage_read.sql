-- ============================================================
--  Migration 021 — 리테일러가 청구서 양식을 다운로드할 수 있도록 Storage 읽기 허용
-- ============================================================
--
-- 증상: 리테일러 계정에서 [청구서 양식 다운로드] 클릭 시
--       "다운로드 실패: Object not found" 발생.
--
-- 원인: 002_claim_file_storage.sql 의 settlements_read 정책은
--       (storage.foldername(name))[1] = my_retailer()  또는  is_admin()
--       조건만 허용한다. 청구서 양식은 `form-templates/{typeId}.xlsx` 경로에
--       저장되므로 첫 폴더가 리테일러 UUID 가 아니고, 리테일러는 admin 도 아니라서
--       createSignedUrl 이 객체를 못 찾는다(권한 없음 → Object not found).
--
-- 해결: `form-templates/` 폴더는 로그인한 모든 사용자가 읽을 수 있도록 별도 정책 추가.
--       양식 파일은 빈 입력 서식(리테일러 데이터 없음)이라 노출 위험이 없다.
--       RLS 정책은 OR(permissive)로 합쳐지므로 기존 정책은 그대로 두고 추가만 한다.
--       업로드/수정/삭제는 여전히 관리자만(004, 015).

drop policy if exists "settlements_read_form_templates" on storage.objects;
create policy "settlements_read_form_templates" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'settlements'
    and (storage.foldername(name))[1] = 'form-templates'
  );
