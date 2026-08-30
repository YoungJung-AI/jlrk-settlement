-- ============================================================
--  Migration 016 — 계정 관리
--  관리자가 계정을 만들고 초기 비밀번호를 지정하면,
--  사용자는 첫 로그인 시 반드시 비밀번호를 변경해야 한다.
-- ============================================================

-- 1) 비밀번호 변경 강제 플래그
alter table profiles add column if not exists must_change_password boolean not null default false;
alter table profiles add column if not exists password_changed_at timestamptz;
alter table profiles add column if not exists is_active boolean not null default true;
alter table profiles add column if not exists email text;   -- 목록 표시용 (auth.users 조회 없이)

-- 2) 본인 프로필의 비밀번호 변경 플래그를 스스로 해제할 수 있어야 함
drop policy if exists "profiles_self_update" on profiles;
create policy "profiles_self_update" on profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- 3) 기존 계정은 이미 사용 중이므로 변경 강제 대상에서 제외
update profiles set must_change_password = false where must_change_password is null;
