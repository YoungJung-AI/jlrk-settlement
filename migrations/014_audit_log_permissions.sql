-- ============================================================
--  Migration 014 — 감사로그(audit_log) 기록 지원
--  기존엔 관리자 조회(select) 정책만 있어 기록이 불가했음
-- ============================================================

-- 로그인한 사용자는 자기 행위를 기록할 수 있어야 함 (본인 명의로만)
drop policy if exists "audit_insert_self" on audit_log;
create policy "audit_insert_self" on audit_log
  for insert to authenticated
  with check (actor_id = auth.uid());

-- 리테일러도 본인 행위 로그는 조회 가능하게 (관리자는 전체)
drop policy if exists "audit_admin" on audit_log;
drop policy if exists "audit_select" on audit_log;
create policy "audit_select" on audit_log
  for select to authenticated
  using (public.is_admin() or actor_id = auth.uid());

-- 조회 성능
create index if not exists audit_target_idx on audit_log (target_type, target_id);
create index if not exists audit_actor_idx on audit_log (actor_id);

-- 활동 이력에 행위자 이름을 표시하려면 관리자가 모든 profiles를 읽을 수 있어야 함
-- (기존 profiles_self 정책은 본인 것만 허용) — 관리자 전체 조회를 명시적으로 보장
drop policy if exists "profiles_admin_read" on profiles;
create policy "profiles_admin_read" on profiles
  for select to authenticated
  using (public.is_admin() or id = auth.uid());

