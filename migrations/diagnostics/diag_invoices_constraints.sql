-- 진단 1: invoices 테이블에 걸린 모든 정책
select policyname, cmd, roles, qual, with_check
from pg_policies
where tablename = 'invoices';

-- 진단 2: invoices 테이블의 제약(유니크 포함)
select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'invoices'::regclass;

-- 진단 3: RLS가 활성화돼 있는지
select relname, relrowsecurity, relforcerowsecurity
from pg_class
where relname = 'invoices';
