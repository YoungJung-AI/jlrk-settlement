-- ============================================================
--  마이그레이션 001~018 적용 여부 진단
--  각 항목이 ✅면 반영됨, ❌면 아직 반영 안 된 것.
--  ❌가 있으면 해당 번호의 migration 파일을 다시 실행하면 됨
--  (전부 IF NOT EXISTS / IF EXISTS 로 짜여있어 재실행해도 안전함)
--
--  ※ 007, 008번은 스키마 변경 없는 진단용 SELECT라서 이 목록에 없음
-- ============================================================

select * from (

  -- 001: 핵심 테이블
  select '001' as migration, 'table' as kind, t as item,
    case when exists(select 1 from information_schema.tables where table_name=t) then '✅' else '❌' end as status
  from unnest(array['retailers','workshops','profiles','settlement_types','rounds','claims','invoices','disputes','vouchers','audit_log']) as t

  union all
  -- 002: 청구서 파일 + storage 정책
  select '002','column','claims.file_path',
    case when exists(select 1 from information_schema.columns where table_name='claims' and column_name='file_path') then '✅' else '❌' end
  union all
  select '002','storage_policy','settlements_insert_own',
    case when exists(select 1 from pg_policies where tablename='objects' and policyname='settlements_insert_own') then '✅' else '❌' end
  union all
  select '002','storage_policy','settlements_read',
    case when exists(select 1 from pg_policies where tablename='objects' and policyname='settlements_read') then '✅' else '❌' end

  union all
  -- 003: 반송건 재제출 (정책 존재 여부만 확인)
  select '003','policy','claims_retailer_write',
    case when exists(select 1 from pg_policies where tablename='claims' and policyname='claims_retailer_write') then '✅' else '❌' end

  union all
  -- 004: 관리자 storage 쓰기
  select '004','storage_policy','settlements_admin_write',
    case when exists(select 1 from pg_policies where tablename='objects' and policyname='settlements_admin_write') then '✅' else '❌' end
  union all
  select '004','storage_policy','settlements_admin_update',
    case when exists(select 1 from pg_policies where tablename='objects' and policyname='settlements_admin_update') then '✅' else '❌' end

  union all
  -- 005/006/006_fix: invoices 구조 (최종 상태 = 리테일러 단위, biz_no nullable)
  select '006','column','invoices.biz_no (nullable)',
    case when exists(select 1 from information_schema.columns where table_name='invoices' and column_name='biz_no' and is_nullable='YES') then '✅' else '❌' end
  union all
  select '006','constraint','invoices unique(round_id,retailer_id)',
    case when exists(select 1 from pg_constraint where conname='invoices_round_id_retailer_id_key') then '✅' else '❌' end
  union all
  select '006','storage_policy','invoices_retailer_insert',
    case when exists(select 1 from pg_policies where tablename='invoices' and policyname='invoices_retailer_insert') then '✅' else '❌' end

  union all
  -- 009: 바우처 템플릿 설정
  select '009','column','settlement_types.voucher_lines',
    case when exists(select 1 from information_schema.columns where table_name='settlement_types' and column_name='voucher_lines') then '✅' else '❌' end
  union all
  select '009','column','workshops.is_primary',
    case when exists(select 1 from information_schema.columns where table_name='workshops' and column_name='is_primary') then '✅' else '❌' end
  union all
  select '009','column','vouchers.retailer_id (nullable)',
    case when exists(select 1 from information_schema.columns where table_name='vouchers' and column_name='retailer_id' and is_nullable='YES') then '✅' else '❌' end

  union all
  -- 010: 세금계산서 발행일
  select '010','column','rounds.invoice_issue_date',
    case when exists(select 1 from information_schema.columns where table_name='rounds' and column_name='invoice_issue_date') then '✅' else '❌' end

  union all
  -- 011: 관리자 알림 이메일
  select '011','column','profiles.notify_email',
    case when exists(select 1 from information_schema.columns where table_name='profiles' and column_name='notify_email') then '✅' else '❌' end

  union all
  -- 012: AR 워크플로우
  select '012','enum_value','dispute_status.REJECTED (정상명)',
    case when exists(select 1 from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='dispute_status' and e.enumlabel='REJECTED') then '✅' else '❌' end
  union all
  select '012','column','claims.confirmed_at',
    case when exists(select 1 from information_schema.columns where table_name='claims' and column_name='confirmed_at') then '✅' else '❌' end
  union all
  select '012','column','claims.evidence_path',
    case when exists(select 1 from information_schema.columns where table_name='claims' and column_name='evidence_path') then '✅' else '❌' end
  union all
  select '012','policy','disputes_retailer_update',
    case when exists(select 1 from pg_policies where tablename='disputes' and policyname='disputes_retailer_update') then '✅' else '❌' end

  union all
  -- 013: AR 정산 구조
  select '013','column','settlement_types.vat_code',
    case when exists(select 1 from information_schema.columns where table_name='settlement_types' and column_name='vat_code') then '✅' else '❌' end
  union all
  select '013','column','settlement_types.amount_mode',
    case when exists(select 1 from information_schema.columns where table_name='settlement_types' and column_name='amount_mode') then '✅' else '❌' end
  union all
  select '013','column','workshops.customer_code',
    case when exists(select 1 from information_schema.columns where table_name='workshops' and column_name='customer_code') then '✅' else '❌' end
  union all
  select '013','column','claims.jg_amount',
    case when exists(select 1 from information_schema.columns where table_name='claims' and column_name='jg_amount') then '✅' else '❌' end

  union all
  -- 014: 감사로그 권한
  select '014','policy','audit_insert_self',
    case when exists(select 1 from pg_policies where tablename='audit_log' and policyname='audit_insert_self') then '✅' else '❌' end
  union all
  select '014','policy','profiles_admin_read',
    case when exists(select 1 from pg_policies where tablename='profiles' and policyname='profiles_admin_read') then '✅' else '❌' end

  union all
  -- 015: 아카이브
  select '015','storage_policy','settlements_admin_delete',
    case when exists(select 1 from pg_policies where tablename='objects' and policyname='settlements_admin_delete') then '✅' else '❌' end
  union all
  select '015','column','rounds.archived_at',
    case when exists(select 1 from information_schema.columns where table_name='rounds' and column_name='archived_at') then '✅' else '❌' end
  union all
  select '015','column','rounds.final_summary',
    case when exists(select 1 from information_schema.columns where table_name='rounds' and column_name='final_summary') then '✅' else '❌' end

  union all
  -- 016: 계정 관리
  select '016','column','profiles.must_change_password',
    case when exists(select 1 from information_schema.columns where table_name='profiles' and column_name='must_change_password') then '✅' else '❌' end
  union all
  select '016','column','profiles.is_active',
    case when exists(select 1 from information_schema.columns where table_name='profiles' and column_name='is_active') then '✅' else '❌' end
  union all
  select '016','column','profiles.email',
    case when exists(select 1 from information_schema.columns where table_name='profiles' and column_name='email') then '✅' else '❌' end

  union all
  -- 017: 예산 관리
  select '017','enum_value','settlement_period.YEARLY',
    case when exists(select 1 from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='settlement_period' and e.enumlabel='YEARLY') then '✅' else '❌' end
  union all
  select '017','enum_value','settlement_period.ONGOING',
    case when exists(select 1 from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='settlement_period' and e.enumlabel='ONGOING') then '✅' else '❌' end
  union all
  select '017','type','budget_category (enum)',
    case when exists(select 1 from pg_type where typname='budget_category') then '✅' else '❌' end
  union all
  select '017','table','budgets',
    case when exists(select 1 from information_schema.tables where table_name='budgets') then '✅' else '❌' end
  union all
  select '017','column','rounds.fiscal_year',
    case when exists(select 1 from information_schema.columns where table_name='rounds' and column_name='fiscal_year') then '✅' else '❌' end

  union all
  -- 018: 기정산 중복 방지
  select '018','column','settlement_types.dedup_keys',
    case when exists(select 1 from information_schema.columns where table_name='settlement_types' and column_name='dedup_keys') then '✅' else '❌' end
  union all
  select '018','table','settled_records',
    case when exists(select 1 from information_schema.tables where table_name='settled_records') then '✅' else '❌' end
  union all
  select '018','column','rounds.source_summary',
    case when exists(select 1 from information_schema.columns where table_name='rounds' and column_name='source_summary') then '✅' else '❌' end

) checks
order by migration, kind, item;
