-- ============================================================
--  Migration 022 — RLS 보안 보완: 익명 읽기 차단 + 회차 리테일러 격리
-- ============================================================
--
--  2026-09-04 보안 점검 결과, 정적 사이트(GitHub Pages) 특성상 공격자는 로그인
--  화면을 거치지 않고 소스에 박힌 publishable 키로 PostgREST 에 직접 질의한다.
--  대부분 테이블(claims/invoices/vouchers/budgets/settled_records/profiles/...)은
--  RLS 로 익명 SELECT 시 0건이 나오지만, 아래 두 곳이 뚫려 있었다:
--
--   1) settlement_types : 정책이 USING (true) 라서 로그인 없이 GL코드·코스트센터·
--      바우처 템플릿 경로·source_config(파싱규칙)·브랜드 배분비율이 통째로 노출.
--   2) rounds : 정책이 (is_admin() OR status <> 'DRAFT') 라서
--      (a) 익명 사용자가 non-DRAFT 회차의 final_summary / source_summary 에 담긴
--          실제 정산 금액(총액·VAT·리테일러사별 금액)을 그대로 읽을 수 있었고,
--      (b) 로그인한 리테일러사 계정도 "남의 회차 요약"까지 전부 볼 수 있었다.
--
--  이 마이그레이션은 두 정책을 교체한다. 다른 테이블 정책은 점검 결과 정상이라
--  건드리지 않는다. Storage('settlements' 버킷) 정책도 전부 to authenticated +
--  리테일러 폴더/admin 스코프로 정상.
--
--  ⚠️ 적용 후 반드시 diagnostics/diag_rls_anon_exposure.sql 로 재검증할 것.
-- ============================================================


-- ------------------------------------------------------------
-- 1) settlement_types — 익명 읽기 차단 (로그인 사용자만 읽기)
-- ------------------------------------------------------------
--  리테일러 UI 는 claims → rounds → settlement_types 조인으로 유형명/방향/
--  청구단위/양식경로/source_config 를 읽으므로 authenticated 전체에는 열어둔다.
--  (리테일러에게 GL코드 등 회계 설정까지 보이는 잔여 이슈는 후속 과제 —
--   회계 컬럼을 admin 전용 별도 테이블로 분리하는 방식 권장. README 참고.)
drop policy if exists types_read on settlement_types;
create policy types_read on settlement_types
  for select
  to authenticated
  using (true);


-- ------------------------------------------------------------
-- 2) rounds — 익명 읽기 차단 + 리테일러는 "본인이 참여한 회차"만
-- ------------------------------------------------------------
--  회차 참여 여부 = 그 회차에 본인 리테일러사의 claims 행이 있는가.
--  (claims 행은 AP=회차 OPEN 시, AR=대상 생성 시 관리자가 미리 만든다.
--   즉 non-DRAFT 회차라면 대상 리테일러사에는 항상 claims 행이 존재한다.)
--  RLS 정책 내부 서브쿼리가 claims RLS 에 다시 걸리는 것을 피하려고
--  SECURITY DEFINER 헬퍼로 감싼다.
create or replace function public.has_claim_in_round(p_round uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.claims c
    where c.round_id = p_round
      and c.retailer_id = public.my_retailer()
  )
$$;

revoke all on function public.has_claim_in_round(uuid) from public;
grant execute on function public.has_claim_in_round(uuid) to authenticated;

drop policy if exists rounds_read on rounds;
create policy rounds_read on rounds
  for select
  to authenticated
  using (
    public.is_admin()
    or (status <> 'DRAFT' and public.has_claim_in_round(id))
  );

-- rounds_admin (관리자 전체 권한) 은 그대로 유지 — 재생성 불필요.


-- ------------------------------------------------------------
-- 3) 적용 직후 자체 점검
-- ------------------------------------------------------------
--  아래는 참고용. 실제 익명 재현 테스트는 diagnostics 쿼리 + curl 로 수행.
select
  polname,
  polcmd,
  pg_get_expr(polqual, polrelid)          as using_expr,
  (select array_agg(rolname) from pg_roles where oid = any(polroles)) as roles
from pg_policy
where polrelid in ('public.rounds'::regclass, 'public.settlement_types'::regclass)
order by polrelid::regclass::text, polname;
