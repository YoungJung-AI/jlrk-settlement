# Engine Oil Package — 3종 바우처 구조 분석

사용자 제공 zip(`정산/`) 3개 바우처 + master + rawdata 분석 결과. FY27 Q2(2607) 기준.
구현 착수 전 이 문서의 "확인 필요" 항목을 사용자와 맞춰야 함.

## 전체 데이터 흐름

```
[원본 2종 — 리테일러가 시스템에서 클레임 전송 → 관리자가 다운로드해 업로드]
  CouponClaim_현황.xlsx        → 쿠폰 사용 클레임 (부품/공임, 쿠폰(고객)/쿠폰(KR) 분리 컬럼 포함)
  쿠폰북정산내역_....xlsx       → 쿠폰북 판매/환불/반품 (Sales Incentive 산출용)
        ↓  master가 workshop code VLOOKUP + 차대번호로 브랜드 판정 + COUNTIFS/SUMIFS 피벗
[master: FY27 Q2 2607 Engine Oil Package master.xlsx]
  · 'Engine Oil Package Claim list'  ← CouponClaim 원본 (B=지점코드, C=Brand, D=정산시기,
                                        E=쿠폰(고객), F=쿠폰(KR), J=Customer, K=VME, L=Castrol)
  · 'FY27 Q2 Claim'                  ← 지점 × 브랜드(J/L) 피벗: Count / Customer / VME / Castrol
                                        → 이 표가 3개 바우처의 'Claim' 시트에 그대로 들어감
  · 'Engine Oil Package 판매'        ← 쿠폰북정산내역 원본 (Q=가격(VAT), I=유형 판매/환불/반품)
  · 'Sales Incentive'                ← 판매 기반 인센티브 산출 (120행)
        ↓
  ┌──────────────────┬────────────────────────┬──────────────────────┐
  ① 사용반환금         ② Retailer Support        ③ Sales Incentive
```

## 브랜드 판정
`=IF(MID(차대번호, 3, 1) = "L", "Landrover", "Jaguar")` — 차대번호(VIN) 3번째 글자.

## 공통 템플릿 구조
각 바우처 xlsx = `AP without PO`(표지, GL 라인 39~) + `AP_input reqeust`(지점 라인 7~27) + 데이터 시트.
- 표지 E21 = Invoice Date(세금계산서작성일), E25 = Net, E27 = VAT코드(`V0: 0%` 전부), E29 = VAT(0), E31 = Total.
- 표지 GL 라인: F열 = GL코드, G열 = 금액(=input 시트 M28=JG합 / N28=LR합 참조), N열 = Text, S열 = LR/JG 표식.
- input 시트: D=vendor code, E=biz no, F=지점명, I=`=M+N`, J=VAT(0), M=JG(0200), N=LR(0100), P7=Text.
  M/N은 `VLOOKUP(vendorcode, Claim!범위, 컬럼, FALSE)`로 Claim 시트에서 값을 당겨옴.
- 표지 M54 검증식: 일부 템플릿은 `=IF(G53=$E$27,...)` 로 **VAT코드 셀 참조 버그**(=$E$25 여야 맞음).

## ① 사용반환금  (`AP Voucher_..._사용반환금_202607.xlsx`)
- 시트: `AP without PO` / `AP_input reqeust` / `Claim`
- `Claim` 컬럼: C=Code, D=리테일러, E=지점, **F~I = Jaguar(Count/Customer/VME/Castrol)**, **J~M = LandRover(동일)**, N=최종입금.
- input M7(JG) = `VLOOKUP(D7, Claim!$C$4:$K$24, 5, FALSE)` → Claim **G열 = Jaguar Customer**
- input N7(LR) = `VLOOKUP(D7, Claim!$C$4:$K$24, 9, FALSE)` → Claim **K열 = LandRover Customer**
- → **사용반환금 = "Customer"(쿠폰 고객분)만.** GL **702030000**, 라인 2개(LR=N28, JG=M28).
- 표지 E25 = `=G53`. M54 = `=IF(G53=$E$25,...)` (정상).

## ② Retailer Support  (`AP Voucher_..._Retailer Support_202607.xlsx`)
- 시트: `AP without PO` / `AP_input reqeust (VME)` / `AP_input reqeust (Castrol)` / `Claim`
- `Claim` 컬럼(사용반환금 대비 1칸 왼쪽): B=Code, C=리테일러, D=지점, **E~H = Jaguar**, **I~L = LandRover**, M=최종입금.
- VME 시트:   M7(JG) = `VLOOKUP(D7, Claim!$B$4:$M$24, 6, FALSE)` → Claim **G열 = Jaguar VME**
              N7(LR) = `... , 10, FALSE)` → Claim **K열 = LandRover VME**
- Castrol 시트: M7(JG) = `VLOOKUP(D7, Claim!$B$4:$L$24, 7, FALSE)` → Claim **H열 = Jaguar Castrol**
              N7(LR) = `... , 11, FALSE)` → Claim **L열 = LandRover Castrol**
- 표지 **GL 라인 4개**:
  | 행 | D열 라벨(원본) | F열 GL | G열 금액 | 표식 |
  |----|---------------|--------|---------|------|
  | 39 | `KR02JSU300 JG P&A` | 700050800 | `(VME)!N28` = VME LR | S39='LR', text `_LR` |
  | 40 | `KR02LSU300 LR P&A` | 700050800 | `(VME)!M28` = VME JG | S40='JG', text `_JG` |
  | 41 | `KR02JSU300 JG P&A` | 1105020600 | `(Castrol)!N28` = Castrol LR | S41='LR', text `_LR` |
  | 42 | `KR02LSU300 LR P&A` | 1105020600 | `(Castrol)!M28` = Castrol JG | S42='JG', text `_JG` |
  → **D열 코스트센터 라벨과 실제 금액/표식이 반대**(D39는 JG인데 LR 금액·`_LR` 텍스트). 원본 회계 오류.
- → Retailer Support = "VME + Castrol"(쿠폰 KR분). GL **700050800**(VME) + **1105020600**(Castrol).

## ③ Sales Incentive  (`AP without PO_FY27 Q1 Engine Oil Package incentive.xlsx`)
- 시트: `AP without PO` / `AP_input reqeust` / `Engine Oil Package 판매`(원본 판매라인) / `Sales Incentive`
- input 시트: **I열(Amount excl VAT)이 지점별 수동 입력값** (예: I7 한남=2,380,000). M7 = `=ROUND(I7*10%,0)` (JG 10%), N7 = `=I7-M7` (LR 90%). 라인 단위 고정 10:90.
- 대상 지점 목록이 다름 — 브리티시(KRJD01260) 포함, 행 7~31, Total 행 32.
- 표지 E25 = `='AP_input reqeust'!I32` (총합). **GL 라인 2개**, GL **700050800**:
  - 39행: G39 = `=ROUND($E$25*90%,0)` → LR, text `FY27 Q1 Engine Oil Package Sales Incentive`
  - 40행: G40 = `=$E$25-G39` → JG
  → 표지 단위 **고정 90:10**.
- 산출식(history): 지점별 금액 = **최종 판매수 × 10,000원** (판매 count − 환불 count). ※ master `Sales Incentive` 시트에서 정확한 식 재확인 필요.
- M54 = `=IF(G53=$E$27,...)` (VAT코드 참조 버그).

## 확정된 계산식 (master `Engine Oil Package Claim list` 행4~5 + 사용자 확인 2026-08-31)

원본 `CouponClaim 현황.xlsx` 컬럼: A번호 B딜러명 C지점 D쿠폰번호 E클레임상태 F쿠폰사용참조번호
G사용일자 H클레임전송일자 I고객명 J차량번호 **K차대번호** L부품금액 M공임금액 **N총금액**.

CouponClaim 라인별 (`클레임상태='전송'` AND dedup_hash ∉ settled_records):
```
brand   = (차대번호[3번째 글자] == 'L') ? 'LandRover' : 'Jaguar'
total   = N(총금액)                       # = 부품금액 + 공임금액
customer= total * 0.8                      # 쿠폰(고객) → 사용반환금
castrol = 21000                            # 상수, 쿠폰 1건당
vme     = total * 0.2 - 21000              # (= margin off + 10000). 쿠폰(KR) 20% 중 Castrol 제외분
```
지점 × 브랜드 집계:
```
count    = 라인 수
customer = Σ(total) * 0.8
castrol  = 21000 * count
vme      = Σ(total) * 0.2 - 21000 * count
```
→ 검증(master N열): `customer + (vme + castrol) == total` (즉 80% + 20%).

### 바우처별 값
- **① 사용반환금**: 지점별 JG = Jaguar.customer, LR = LandRover.customer. 표지 라인 2개(GL 702030000).
- **② Retailer Support**: VME 시트 지점별 JG=Jaguar.vme / LR=LandRover.vme;
  Castrol 시트 지점별 JG=Jaguar.castrol / LR=LandRover.castrol.
  표지 라인 4개 — **라벨·금액·표식을 올바르게 맞춰 생성**(원본 반전 버그 시스템에서 교정, 사용자 확인함):
  GL 700050800 JG(KR02JSU300)=ΣJG.vme / GL 700050800 LR(KR02LSU300)=ΣLR.vme /
  GL 1105020600 JG=ΣJG.castrol / GL 1105020600 LR=ΣLR.castrol.
- **③ Sales Incentive**: 원본 `쿠폰북정산내역` 컬럼 A기준월 B리테일러 C지점명 **D지점코드** **E유형**(판매/환불/반품)
  F차대번호 ... M가격(VAT) P요청여부 Q요청일.
  지점별 `최종판매수 = 판매건수 − 환불건수 (+ 반품건수)` × **10,000원**.
  표지 라인 2개(GL 700050800): LR = ROUND(총액×90%), JG = 총액 − LR (고정 90:10).
  ※ 브리티시(BA) 등 8개사 밖 딜러는 앞으로 없음(사용자 확인) → 21개 지점만 대상.

## 확인 필요 (구현 착수 전)
1. **쿠폰(고객)/쿠폰(KR) 분리**: master를 보면 `Claim list` E열(쿠폰 고객)·F열(쿠폰 KR)이 원본에 이미 분리돼 들어옴.
   history의 "총금액 × 80% / × 20%"는 근사 설명이고, 실제로는 원본 컬럼을 그대로 합산하는 것으로 보임 → 맞나?
   (그렇다면 시스템은 80/20 계산이 아니라 원본 E/F 컬럼 SUMIFS만 하면 됨.)
2. **Customer / VME / Castrol** 3분해가 `Claim list`의 어느 컬럼인지 — CouponClaim 원본 실제 헤더명 확정 필요.
3. **Sales Incentive 지점별 금액** = 판매수 × 10,000이 맞나? master `Sales Incentive` 시트 식 확인.
   또한 이 바우처만 대상 지점(브리티시 등)이 8개사 밖까지 포함 — 포털에서 어떻게 다룰지.
4. **JG/LR 라인 반전**: 바우처를 생성할 때 원본 템플릿의 반전된 라벨을 그대로 둘지(결재 통과용, 총액은 맞음),
   아니면 시스템이 라벨·금액을 올바르게 맞춰 생성할지. (사용자 회계 확인 사항)
5. **Text(Description)**: 바우처마다 `FY27 Q2 Engine Oil Package_사용반환금_202607` / `..._JLRK Support_VME_202606` /
   `FY27 Q1 Engine Oil Package Sales Incentive` 등 패턴이 제각각 — 유형 설정 `voucher_lines[].description` +
   회차 기간으로 조립할 규칙 확정 필요.
6. **VME/Castrol 단가**: history에 "VME 10,000 / Castrol 21,000" 언급 — 원본에 이미 계산돼 들어오면 시스템은 합산만.

## 구현 계획 (확인 후)
1. 정산 유형 설정: `voucher_lines`를 3개까지 편집 가능하게 + 각 라인에 산출 대상(Customer/VME/Castrol/판매수×단가) 지정
2. SYSTEM 유형 회차: DRAFT에서 원본 2종 업로드 → master 피벗 로직을 JS로 재현 → 지점별·브랜드별 표 + 검증 배지
3. 리테일러 [정산 확정] 화면 (입력 없음, 확인 버튼만)
4. 바우처 3종 생성: 저장된 템플릿 3개에 JSZip XML 치환 (사용반환금=input 1시트, Retailer Support=input 2시트, Incentive=input 1시트 + 지점 목록 상이)
