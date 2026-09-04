-- ============================================================
--  진단 — 익명(anon) / 리테일러 역할에서 테이블별 노출 여부 점검
--  2026-09-04 보안 점검 대응 (migration 022). SQL Editor 에서 실행.
-- ============================================================

-- 1) 민감 테이블의 SELECT 정책이 anon 역할에 열려 있는지
--    (roles 에 'anon' 또는 'public' 이 있고 using_expr 가 상시참(true 등)이면 위험)
select
  c.relname                                   as table_name,
  p.polname                                   as policy,
  p.polcmd                                    as cmd,
  coalesce(
    (select array_agg(r.rolname order by r.rolname)
       from pg_roles r where r.oid = any(p.polroles)),
    array['PUBLIC']
  )                                           as applies_to_roles,
  pg_get_expr(p.polqual, p.polrelid)          as using_expr
from pg_policy p
join pg_class c on c.oid = p.polrelid
where c.relnamespace = 'public'::regnamespace
  and c.relname in (
    'rounds','settlement_types','claims','invoices','vouchers',
    'disputes','budgets','settled_records','profiles','retailers',
    'workshops','audit_log'
  )
  and p.polcmd in ('r','*')            -- SELECT / ALL
order by c.relname, p.polname;

-- 기대값:
--  · rounds            : rounds_read → applies_to_roles = {authenticated},
--                        using_expr 에 is_admin() 와 has_claim_in_round(id) 포함
--  · settlement_types  : types_read → {authenticated}, using_expr = true
--  · 그 외             : {authenticated} 이고 is_admin()/my_retailer() 스코프
--  ⚠️ applies_to_roles 에 'anon' 또는 'PUBLIC' 이 뜨면 즉시 조치


-- 2) RLS 가 아예 꺼진 public 테이블이 있는지 (있으면 anon 전체 노출)
select n.nspname as schema, c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
  and c.relrowsecurity = false
order by c.relname;
-- 기대값: 0 행 (모든 업무 테이블 RLS on)


-- 3) anon / authenticated 역할에 직접 부여된 테이블 GRANT 점검
--    (RLS 위에 얹히는 컬럼/테이블 권한. anon 에 write 계열이 있으면 위험)
select
  table_schema, table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon','authenticated')
  and table_name in (
    'rounds','settlement_types','claims','invoices','vouchers',
    'disputes','budgets','settled_records','profiles'
  )
order by table_name, grantee, privilege_type;
-- 참고: Supabase 기본값으로 anon/authenticated 에 CRUD GRANT 가 있고 RLS 로 거른다.
--       실제 차단은 위 1)의 정책이 담당하므로 정책이 핵심.
