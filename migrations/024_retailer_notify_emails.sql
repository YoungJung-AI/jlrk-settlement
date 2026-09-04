-- ============================================================
--  Migration 024 — 리테일러 알림 수신 이메일(대표주소) 등록
-- ============================================================
--  각 리테일러 정산담당자 계정(migration 없음 — manage-user Edge Function 으로 생성)
--  이메일을 retailers.email 에 반영. 담당자가 2명인 곳(AJ·KCC)은 쉼표로 구분해
--  둘 다 수신하도록 저장한다.
--
--  index.html 은 splitEmails() 로 쉼표/세미콜론을 분리해 여러 명에게 발송한다
--  (getRetailerEmails / notifyEngineOilPublished / remindUnsubmitted).
--
--  ※ 이 값은 이미 관리자 계정으로 PostgREST PATCH 를 통해 프로덕션에 반영됨.
--     이 파일은 이력 기록용.
-- ============================================================

update retailers set email = 'shh@aju.co.kr, daechan88@aju.co.kr'      where code = 'AJ';
update retailers set email = 'kimjh6@kcc.co.kr, edcheon@kcc.co.kr'     where code = 'KCC';
update retailers set email = 'dg.koo@hshyosung.com'                    where code = 'HS';
update retailers set email = 'hiy@webonautomotive.com'                 where code = 'WB';
update retailers set email = 'jyyr1213@hanyoungmotors.com'             where code = 'HY';
update retailers set email = 'shyun@chunilauto.co.kr'                  where code = 'CH';
update retailers set email = 'nsh@jlrmotors.co.kr'                     where code = 'JL';
update retailers set email = 'bjkim@entire.co.kr'                      where code = 'EN';

-- 확인
select code, name, email from retailers order by code;
