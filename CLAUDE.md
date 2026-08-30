# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# JLRK 리테일러 정산 포털

JLR Korea가 8개 리테일러(21개 지점)와 주고받는 정산·청구 업무를 대체하는 웹 포털.
기존에는 엑셀 청구서를 메일로 주고받고, 세금계산서 PDF를 수작업으로 캡쳐해 회사 결재 바우처에
붙여넣던 프로세스를 전부 시스템화했다. 담당자 1인(관리자) + 리테일러 8개사 계정 구조.

## 아키텍처 — 반드시 지킬 것

- **빌드 과정 없음.** `index.html` 단일 파일이 전부. React/Vue/번들러 도입 금지 — 지금 방식이 의도된 설계.
- 프론트: GitHub Pages 정적 호스팅 (`index.html`을 그대로 배포)
- 백엔드: Supabase (Postgres + Auth + Storage + Edge Functions), 리전 ap-northeast-2(Seoul)
- 인증/보안: RLS(Row Level Security)로 리테일러 간 데이터 격리. 프론트에 넣는 키는
  `anon`/`publishable` 키뿐 — `service_role` 키는 Edge Function 시크릿에만 존재.
- 라이브러리(CDN): `@supabase/supabase-js`, SheetJS(`xlsx`), `pdf.js`, `JSZip`.
  **ExcelJS·jsPDF·html2canvas는 의도적으로 제거함** (아래 "겪었던 사고" 참고). 다시 추가하지 말 것.

## 저장소 구조

```
/index.html                 ← 애플리케이션 전체 (HTML+CSS+JS 단일 파일)
/migrations/                ← 실행 순서대로 정리된 SQL. README.md에 각 파일 설명 있음
/migrations/diagnostics/    ← 스키마 상태 점검용 진단 쿼리
/supabase/functions/        ← Edge Functions (send-email, manage-user)
```

## 명령어 / 로컬 개발

빌드·테스트 러너·패키지 매니저 없음. `npm` 스크립트도 없다.

- **로컬 실행**: 정적 서버로 `index.html`을 열면 끝. `python3 -m http.server 8000` 후
  `http://localhost:8000`. `file://`로 직접 열면 Supabase 인증 리다이렉트가 깨질 수 있으니 서버로 띄울 것.
  별도 개발용 Supabase 프로젝트는 없고 `index.html:723` 상수(`SUPABASE_URL`/`SUPABASE_ANON_KEY`)가
  프로덕션을 가리킨다 — 로컬에서 로그인하면 실데이터에 붙는다는 점 유의.
- **배포**: `main`에 push하면 GitHub Pages가 `index.html`을 그대로 서빙. 파이프라인 없음.
- **Edge Function 배포**: `supabase functions deploy send-email` / `supabase functions deploy manage-user`
  (Supabase CLI 필요, `supabase link`로 프로젝트 연결 후). 시크릿은
  `supabase secrets set GMAIL_USER=... GMAIL_APP_PASSWORD=...` / `... SERVICE_ROLE_KEY=...`.
  로컬 테스트는 `supabase functions serve <name> --env-file .env`.
- **SQL 실행**: `migrations/`는 Supabase SQL Editor에 순서대로 붙여넣어 실행하는 방식(자동 러너 없음).
  스키마 상태 점검은 `migrations/diagnostics/check_migrations_status.sql`를 SQL Editor에서 재실행.
- **바우처 xlsx 검증**: 생성된 파일은 LibreOffice `recalc.py`로 열어 재계산이 깨지지 않는지 확인
  (아래 "겪었던 사고" 1번). 자동 테스트 없으므로 수동 검증이 유일한 안전장치.

## index.html 내부 구조 (단일 파일 SPA)

- **레이아웃**: `<head>`에 CDN 스크립트 4개(`index.html:718~721`) → 인라인 `<style>`(다크 테마 커스텀 프로퍼티)
  → `<body>`에 로그인 화면 + 비밀번호변경 화면 + `<main>` 안에 `<section id="view-*">` 8개
  (`dashboard`/`accounts`/`audit`/`types`/`retailers`/`rounds`/`roundDetail`/`retailer`) → 인라인 `<script>`.
- **라우팅**: 해시 라우터 없음. `switchView(name)`(`index.html:1263`)이 모든 `<section>`을 `display:none`으로
  깔고 `view-<name>` 하나만 켠 뒤, 이름에 맞는 `loadXxx()`를 호출한다. 네비 클릭 → `switchView`.
- **세션/진입**: `checkSession()` → `enterApp(session)`(`index.html:1171`)에서 `profiles` 행을 읽어
  전역 `myProfile`에 저장하고 `role`로 분기 — `ADMIN`이면 `#adminNav` 표시 + `switchView('dashboard')`,
  `RETAILER`면 `retailer-mode` 클래스 + `loadMyRetailerContext()` + `switchView('retailer')`.
  `must_change_password`면 비밀번호 변경 화면으로 강제, `is_active===false`면 로그아웃.
- **전역 상태**(`index.html:726~735`): `sb`(Supabase 클라이언트), `myProfile`, `myRetailer`,
  `myWorkshops`, `selectedRetailerIds`, `currentRoundId`. 프레임워크 없이 이 전역들 + DOM이 상태의 전부.
- **권한**: 프론트 분기는 UX일 뿐 실제 격리는 전부 Postgres RLS. 관리자 전용 서버 작업(계정 생성 등)은
  `sb.functions.invoke('manage-user', ...)`가 Edge Function에서 `role='ADMIN'`을 재검증한다.
- **AP vs AR 회차 상세**: `renderRoundDetail()`(AP) / `renderARRoundDetail()`(AR)로 갈리고,
  `amount_mode`에 따라 다시 `renderSystemSourceSection`(SYSTEM), 업로드/수동 입력 UI 등으로 분기.

## 도메인 핵심 개념

- **정산 방향 2종**: `AP`(JLRK가 리테일러에 지급, 리테일러가 청구서 제출) / `AR`(JLRK가 리테일러에 청구, 리테일러는 확인·이의제기만)
- **청구 단위 vs 계산서 단위가 다름**: `claim_unit`은 정산 유형마다 법인 단위/지점 단위로 갈리지만,
  세금계산서는 **항상 리테일러(법인)×회차 단위로 1건**. vendor code별 배분은 바우처 생성 단계에서 처리.
- **정산 유형(`settlement_types`)이 모든 걸 설정으로 관리**: GL코드, 코스트센터, VAT 코드,
  JG/LR 배분 방식(고정비율 vs 실적기준), 금액 산출 방식(`UPLOAD`/`SYSTEM`/`UNIT`/`MANUAL`),
  원천 파싱 규칙(`source_config` JSON), 중복 판정 키(`dedup_keys`) 등. 새 정산 종류를 추가할 때
  코드를 건드리지 않고 이 설정만으로 커버하는 게 목표.
- **바우처 생성**: 관리자가 실제 결재 원본 엑셀을 템플릿으로 업로드해두면, 생성 시 그 파일의
  특정 셀 값만 바꿔서 내려받는다. 새로 만들지 않는다.
- **기정산 이력(`settled_records`)**: 리테일러 입력 없이 시스템이 원본 데이터를 읽어 자동 정산하는
  유형(`amount_mode='SYSTEM'`)에서, 이미 정산한 건을 정규화된 조합키로 걸러내는 범용 테이블.
  유형마다 `dedup_keys`가 다르므로 조합키 설계 시 "여러 건이 묶이는 컬럼을 단독 키로 쓰지 말 것"
  (예: 참조번호 하나에 쿠폰 여러 장이 물리는 사례로 실제 검증함).

## ⚠️ 겪었던 사고 — 재발 방지

1. **ExcelJS로 기존 xlsx 템플릿을 열었다 재저장하면 파일이 손상된다.**
   externalLinks, printerSettings(인쇄영역 포함), customXml, calcChain 등 원본 부품이
   무더기로 유실됨. 그래서 바우처 생성은 ExcelJS를 아예 쓰지 않고 **JSZip으로 xlsx 내부 XML을
   직접 문자열 치환**하는 방식으로 전환했다 (`buildVoucherFromTemplate` 계열 함수 참고).
   새 값을 넣어야 하는 셀만 정규식으로 찾아 `<c r="I7">...</c>` 형태를 갈아끼우고, 나머지 파츠는
   원본 zip 그대로 둔다. LibreOffice `recalc.py`로 검증하는 습관을 들일 것.
2. **표지 PDF 자동 생성은 포기한 기능이다.** 브라우저에서 엑셀 렌더링을 재현할 방법이 없어
   html2canvas 기반 시도가 4번 실패했다. 인쇄영역만 원본 그대로 보존해두고, 사용자가 엑셀에서
   직접 "다른 이름으로 저장 > PDF"를 누르는 수동 단계로 확정. 다시 자동화 시도하지 말 것.
3. **정의된 이름(defined names)의 외부 참조**(`[숫자]시트` 또는 `[파일명.xls]시트` 형태)가
   원본 템플릿에 남아있으면 재저장 시 손상 원인이 된다. 걸러낼 때 숫자 인덱스뿐 아니라
   대괄호 안에 뭐가 오든 전부 제거해야 한다 (`stripExternalDefinedNames` 참고 — 현재는
   XML 직접 조작 방식으로 넘어가면서 이 이슈 자체가 사라졌지만, 유사 로직 필요 시 기억할 것).

## 코딩 컨벤션

- 주석·UI 텍스트는 전부 한국어.
- 함수명 패턴: `renderXxx`(화면 그리기), `loadXxx`(데이터 조회+렌더), `notifyXxx`(메일 발송),
  `logAudit(action, targetType, targetId, payload)`(감사로그 — 전부 실패해도 조용히 무시).
- 알림(`sendEmail`)과 감사로그는 **실패해도 업무 흐름을 막지 않는다** — try/catch로 감싸고
  console.warn만 남긴다. 이 패턴을 깨지 말 것.
- CSS는 커스텀 프로퍼티 기반 다크 테마(`--bg`, `--surface`, `--accent` 등). 860px 이하 모바일 대응 있음.
- 금액 입력은 전부 천단위 콤마 포맷(`formatAmountInput`/`readAmountInput`), 서버엔 숫자로 저장.

## 진행 상태 (Phase 0~7 전부 1차 완료)

Phase 0 백엔드 → 1 정산유형관리 → 2 회차개설/제출 → 3 검토/확정/계산서 →
4 바우처생성 → 5 이메일알림 → 6 AR청구 → 7 대시보드/감사로그/계정관리/예산관리
전부 기능은 구현됐고 스키마도 프로덕션에 반영 완료 (`migrations/diagnostics/check_migrations_status.sql`로 검증됨).

## 미완료 / 다음에 할 일

- [ ] **Edge Function 미배포 2건** — 코드는 `/supabase/functions/`에 있음, 아직 Supabase에 deploy 안 함
  - `send-email`: Gmail SMTP 발송 (`GMAIL_USER`, `GMAIL_APP_PASSWORD` 시크릿 필요)
  - `manage-user`: 관리자의 계정 생성/비밀번호 재설정 (`SERVICE_ROLE_KEY` 시크릿 필요)
- [ ] 리테일러 실제 이메일 주소 미입력 (전원 `placeholder@example.com` — 메일 발송 자동 스킵됨)
- [ ] **Engine Oil Package 클레임 기반 정산 — 설계는 끝났고 코드 구현 진행 중.**
  마지막 작업 지점: `classifySourceRows` / `settled_records` 관련 로직을 막 붙이던 중이었음.
  요구사항: 리테일러가 시스템 안에서 "클레임 전송" 버튼을 누른 원본(누적 전체)을 관리자가 업로드하면,
  `클레임상태='전송' AND dedup_hash가 settled_records에 없음` 조건으로 이번 회차 대상만 자동 추출.
  월 단위로 끊지 않고 "미정산 잔량" 기준으로 지연 건까지 자동 포함되게 설계함.
  이 유형은 바우처가 **한 원본에서 3개**(사용반환금/Retailer Support/Sales Incentive) 나오는데,
  각각 배분 비율과 GL 라인 구성이 다름 — 상세는 이전 대화 기록 참고 필요.
- [ ] One DMS License 같은 `amount_mode='UNIT'`(수량×단가) 유형의 입력 UI가 아직 없음.
  DB 필드(`claims.quantity`, `settlement_types.unit_price`)만 있고 화면 미구현 — 지금은 관리자가
  수동 계산 후 금액만 입력하는 임시 방편.
- [ ] AR 검증 규칙 엔진(사용자가 발견한 오류 패턴을 자연어/UI로 등록해 자동 검증) — 설계 논의만 하고
  구현 전. Anthropic API 키 필요 여부 포함해 사용자와 재확인 필요.
- [ ] GitHub Pages URL이 개인 계정(`youngjung-ai.github.io`)으로 보이는 문제 — Organization 이전 검토 중,
  사내 승인 필요해 보류 상태.

## 확인해야 할 것 (아직 리스크로 남아있음)

- AJ/EN/HS/WB 리테일러 그룹은 **지점별로 사업자번호가 다르다** (프랜차이즈 개별사업자 구조).
  세금계산서는 리테일러 단위 1건으로 확정했지만, 실제 회계 처리와 맞는지 사용자 확인 필요.
- 여러 정산 원본에서 **JG/LR 코스트센터 라인이 뒤바뀐 실제 회계 오류**를 발견해 사용자에게 보고함
  (Recall 10:90 고정배분 버그, Engine Oil Retailer Support JG/LR 라인 반전 등). 시스템 버그가 아니라
  사용자의 기존 수작업 엑셀에 있던 문제이므로, 코드 수정 대상이 아니라 사용자가 실제 회계와
  크로스체크할 사안. 새로 정산 유형을 만들 때 원본 파일의 계산식을 그대로 믿지 말고 검증할 것.
