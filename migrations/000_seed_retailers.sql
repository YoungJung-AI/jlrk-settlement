-- ============================================================
--  Seed 001 — 리테일러 8개사 + 지점 21개
--  Recall(FY27 Q1) + Pickup&Delivery(FY26 Q1) 바우처 교차검증으로 확정
--  CEO명 / 이메일은 데이터 없음 — null로 두고 추후 UPDATE 필요
-- ============================================================

insert into retailers (code, name, email) values
  ('AJ',  '아주네트웍스', 'placeholder@example.com'),
  ('CH',  '천일오토모빌', 'placeholder@example.com'),
  ('KCC', '케이씨씨오토모빌', 'placeholder@example.com'),
  ('WB',  '위본오토모티브', 'placeholder@example.com'),
  ('HS',  '효성프리미어모터스', 'placeholder@example.com'),
  ('EN',  '인타이어모터스', 'placeholder@example.com'),
  ('HY',  '한영모터스', 'placeholder@example.com'),
  ('JL',  '제이엘모터스', 'placeholder@example.com');
  -- ★ email은 placeholder — 실제 수신 메일 확인되면 UPDATE 필요

insert into workshops (retailer_id, code, name, vendor_code, biz_no)
select r.id, w.code, w.name, w.vendor_code, w.biz_no
from (values
  ('AJ','AJ-HN',  '한남',      'KRJD01047','2148800795'),
  ('AJ','AJ-ICND','인천남동',  'KRJD01020','2148800795'),
  ('AJ','AJ-SS',  '성산',      'KRJD01075','1058539317'),

  ('CH','CH-SS',  '성수',      'KRJD01048','2148835620'),
  ('CH','CH-DC',  '대치',      'KRJD01070','2148835620'),
  ('CH','CH-SW',  '수원',      'KRJD01077','2148835620'),

  ('KCC','KCC-SC','서초양재',  'KRJD01079','1178159958'),
  ('KCC','KCC-BD','분당',      'KRJD01074','1178159958'),
  ('KCC','KCC-IS','일산',      'KRJD01073','1178159958'),
  ('KCC','KCC-WJ','원주',      'KRJD01072','1178159958'),
  ('KCC','KCC-JJ','제주',      'KRJD01150','1178159958'),
  ('KCC','KCC-SN','성남',      'KRJD01095','1178159958'),
  ('KCC','KCC-GD','강동',      'KRJD01280','1178159958'),

  ('WB','WB-GJ',  '광주',      'KRJD01290','1858502077'),
  ('WB','WB-JJ',  '전주',      'KRJD01300','5098503267'),

  ('HS','HS-BC',  '센텀(부산)','KRJD01030','1728600556'),
  ('HS','HS-US',  '울산',      'KRJD01190','7728500820'),

  ('EN','EN-DG',  '대구',      'KRJD01034','5028540484'),
  ('EN','EN-SDG', '서대구',    'KRJD01065','8828501316'),

  ('HY','HY',     '부산',      'KRJD01120','6178149208'),

  ('JL','JL',     '대전',      'KRJD01056','3148626446')
) as w(retailer_code, code, name, vendor_code, biz_no)
join retailers r on r.code = w.retailer_code;

-- 확인용
select r.code as retailer, count(*) as workshop_count
from workshops w join retailers r on r.id = w.retailer_id
group by r.code order by r.code;
