-- ============================================================
--  Migration 023 — settlement_types 회계 컬럼을 리테일러에게서 완전 차단
-- ============================================================
--
--  022 는 익명(anon) 읽기만 막았다. 로그인한 리테일러사 계정은 여전히
--  settlement_types 를 통째로 SELECT 해서 아래 내부 회계 설정을 볼 수 있었다:
--    voucher_lines(GL코드·코스트센터·라인설명), voucher_template_path,
--    brand_split_mode / brand_jg_ratio(JG:LR 배분비율), unit_price(단가),
--    dedup_keys / status_filter, amount_cap, rounding, budget_category 등.
--
--  조치:
--   1) settlement_types 직접 SELECT = 관리자 전용 (types_read → is_admin())
--   2) 리테일러 UI 가 실제로 쓰는 안전 컬럼만 노출하는 뷰
--      settlement_types_public 생성. 뷰는 security_invoker=off(기본) 라서
--      뷰 소유자 권한으로 실행 → 기반 테이블 RLS 를 우회하고, 뷰에 select 권한을
--      가진 authenticated 는 안전 컬럼만 본다.
--      노출 컬럼: id, code, name, direction, claim_unit, form_template_path,
--                source_config 는 {preset} 만 남긴 축약본.
--   3) index.html 의 리테일러 경로 3곳(제출이력 / 청구목록 / 제출알림)이
--      settlement_types 임베드 대신 이 뷰를 조회하도록 변경 (같은 커밋).
--
--  ⚠️ 적용 후: diagnostics/diag_rls_anon_exposure.sql + 리테일러 계정 로그인으로
--     settlement_types 직접 조회가 0건인지, settlement_types_public 은 안전 컬럼만
--     나오는지 재검증.
-- ============================================================


-- ------------------------------------------------------------
-- 1) settlement_types 직접 SELECT = 관리자 전용
-- ------------------------------------------------------------
drop policy if exists types_read on settlement_types;
create policy types_read on settlement_types
  for select
  to authenticated
  using (public.is_admin());
-- types_admin (for all / is_admin) 은 그대로 유지 — 재생성 불필요.


-- ------------------------------------------------------------
-- 2) 리테일러용 안전 뷰
-- ------------------------------------------------------------
create or replace view public.settlement_types_public as
  select
    id,
    code,
    name,
    direction,
    claim_unit,
    form_template_path,
    jsonb_strip_nulls(
      jsonb_build_object('preset', source_config->>'preset')
    ) as source_config
  from public.settlement_types;

-- 뷰가 뷰 소유자 권한으로 실행되도록 (기본값이지만 명시)
alter view public.settlement_types_public set (security_invoker = false);

revoke all on public.settlement_types_public from anon;
grant select on public.settlement_types_public to authenticated;


-- ------------------------------------------------------------
-- 3) 검증
-- ------------------------------------------------------------
select
  polname,
  pg_get_expr(polqual, polrelid) as using_expr,
  (select array_agg(rolname) from pg_roles where oid = any(polroles)) as roles
from pg_policy
where polrelid = 'public.settlement_types'::regclass
order by polname;
-- 기대: types_read → using_expr = is_admin(), roles = {authenticated}

select column_name
from information_schema.columns
where table_schema = 'public' and table_name = 'settlement_types_public'
order by ordinal_position;
-- 기대: id, code, name, direction, claim_unit, form_template_path, source_config
