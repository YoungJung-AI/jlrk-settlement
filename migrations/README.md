# 마이그레이션 인덱스

이미 프로덕션 Supabase에 전부 반영 완료 상태 (2026-08-30 기준, `diagnostics/check_migrations_status.sql`로 검증함).
**새로 실행할 필요 없음** — 이 폴더는 스키마 변경 이력 기록용. 신규 환경을 처음부터 구축할 때만 순서대로 실행.

| 파일 | 내용 |
|---|---|
| `000_schema.sql` | Phase 0 기반 스키마 — 테이블 13개, RLS, 트리거, 헬퍼 함수(`is_admin()` 등) |
| `000_seed_retailers.sql` | 리테일러 8개사 + 지점 21개 시드 데이터 |
| `001_invoice_biz_no_rollup.sql` | (히스토리) 세금계산서 롤업을 biz_no 단위로 — 이후 006에서 리테일러 단위로 되돌림 |
| `002_claim_file_storage.sql` | 청구서 파일 업로드 지원 (`claims.file_path` + Storage RLS) |
| `003_reject_resubmit_rls.sql` | 반송된 건은 회차 마감 후에도 재제출 허용 |
| `004_admin_storage_write.sql` | 관리자가 리테일러 폴더에 첨부파일 업로드 가능하도록 |
| `005_invoice_insert_policy.sql` | (히스토리) biz_no 기준 invoice insert 정책 |
| `006_invoice_retailer_unit.sql` | **세금계산서를 리테일러×회차 단위 1건으로 최종 확정** (biz_no 기준 폐기) |
| `009_voucher_template_fields.sql` | 바우처 템플릿 업로드, `workshops.is_primary`, `vouchers.retailer_id` nullable |
| `010_invoice_issue_date.sql` | 관리자가 지정하는 세금계산서 발행일 |
| `011_admin_notify_email.sql` | 관리자 알림 수신 이메일 |
| `012_ar_workflow.sql` | AR(JLRK→리테일러 청구) 워크플로우 — dispute enum 정리, 확인/근거 필드 |
| `013_ar_settlement_structure.sql` | AR 정산 유형 설정 (VAT코드/브랜드배분/원천파싱/customer_code) |
| `014_audit_log_permissions.sql` | 감사로그 기록 권한, profiles 관리자 조회 |
| `015_round_archive.sql` | 회차 아카이브 (파일 삭제 권한, 최종 요약 보존) |
| `016_account_management.sql` | 계정 관리 (초기 비밀번호 변경 강제) |
| `017_budget_management.sql` | 예산 구분(P&A Selling/VME/FMI/Accrual), 주기 확장(연간/상시) |
| `018_dedup_settled_records.sql` | 범용 기정산 이력 (`settled_records`) — 시스템 산출 정산의 중복 방지 |

## ⚠️ 알아둘 것

- `001`과 `005`는 나중에 `006`으로 **설계가 뒤집힌 히스토리**임. 006이 최종 상태.
- `007`, `008`은 스키마 변경이 없는 순수 진단 쿼리라 `diagnostics/`로 분리했음.
- `diagnostics/check_migrations_status.sql`은 언제든 재실행해서 스키마 상태를 점검할 수 있는 상시 도구.
