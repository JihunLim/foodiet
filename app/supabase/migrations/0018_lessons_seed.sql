-- 0018_lessons_seed.sql — 2분 마이크로 레슨 12편 시드 (spec F7)
--
-- ⚠️ 출시 전 소유자 검토 필요.
--   원고(제목·요약·본문·출처 라벨)는 개발 중 작성한 초안이다. published = true 로 시드하지만
--   운영 반영 전에 소유자가 문장·수치·출처를 직접 검토하고, 필요하면 이 파일을 고쳐 재실행한다
--   (on conflict (slug) do update — 재실행 안전, 사용자 lesson_reads·published 값은 유지된다).
--   검토 전 노출을 막고 싶으면: update public.lessons set published = false;
--
-- 원칙
--   * 출처는 2026-11-14 세션 리서치에서 실제로 열람한 URL 만 사용 (PubMed 항목 제목은 Europe PMC 로 확인).
--   * 근거 수준을 넘는 효과 주장 금지 — 관찰 연구는 "연관", 혈당 근거(먹는 순서)는 혈당 팁으로만.
--   * 금지 어휘 없음, 하루 최소선(남 1500 / 여 1200 kcal) 아래 권유 없음, 의학적 조언 아님(앱 화면 고지).
--   * body 블록: {t:'h'|'p'|'tip'|'list', text? , items?}
--
-- 의존: 0017_diet_content.sql (public.lessons 테이블).

-- 10. protein
insert into public.lessons (slug, title, summary, body, tags, read_minutes, sources, sort, published)
values (
  $t$protein$t$,
  $t$단백질, 끼니마다 한 칸씩$t$,
  $t$단백질은 포만감이 오래가고 근육을 지키는 데 도움이 될 수 있어. 하루 총량보다 끼니마다 나눠 챙기는 게 쉬워.$t$,
  $j$[
  {
    "t": "h",
    "text": "왜 단백질부터 볼까?"
  },
  {
    "t": "p",
    "text": "칼로리를 줄이는 동안엔 체지방과 함께 근육도 빠지기 쉬워. 연구들을 정리한 리뷰에서는 단백질을 넉넉히 먹은 식단이 체지방을 줄이고 근육(제지방)을 지키는 쪽에 유리했다고 봤어. 포만감이 오래가는 것도 장점이야. 다만 그 효과도 결국 식단을 얼마나 꾸준히 이어가느냐에 달려 있대."
  },
  {
    "t": "h",
    "text": "얼마나 먹으면 될까?"
  },
  {
    "t": "p",
    "text": "연구에서 자주 쓰는 범위는 체중 1kg당 하루 1.2~1.6g, 한 끼에 25~30g 정도야. 상황마다 달라서 숫자를 정확히 맞추기보다 \"끼니마다 단백질 반찬 하나\"로 시작하면 충분해. 고기만 떠올리기 쉬운데 두부·콩·달걀·유제품·생선까지 선택지가 넓어. 튀기거나 소스를 듬뿍 얹으면 칼로리도 같이 올라가니 굽거나 삶는 쪽이 편해."
  },
  {
    "t": "list",
    "items": [
      "달걀 2개, 또는 두부 반 모",
      "닭가슴살·생선·살코기 손바닥 한 장 크기",
      "그릭요거트나 우유·두유 한 잔",
      "편의점이라면 삶은 달걀, 두유, 단백질 음료"
    ]
  },
  {
    "t": "tip",
    "text": "아침이 빵이나 커피뿐이라면 달걀이나 우유 하나만 더해 봐. 그게 오늘의 단백질 한 칸이야."
  },
  {
    "t": "p",
    "text": "콩팥 질환이 있거나 식사 제한을 안내받았다면 단백질 양은 의료진과 먼저 이야기해줘."
  }
]$j$::jsonb,
  array[$t$단백질$t$]::text[],
  2,
  $j$[
  {
    "label": "Leidy HJ 외 (2015) The role of protein in weight loss and maintenance — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/25926512/"
  }
]$j$::jsonb,
  10,
  true
)
on conflict (slug) do update set
  title = excluded.title,
  summary = excluded.summary,
  body = excluded.body,
  tags = excluded.tags,
  read_minutes = excluded.read_minutes,
  sources = excluded.sources,
  sort = excluded.sort,
  updated_at = now();  -- published 는 재실행해도 건드리지 않는다

-- 20. fiber
insert into public.lessons (slug, title, summary, body, tags, read_minutes, sources, sort, published)
values (
  $t$fiber$t$,
  $t$채소 한 접시가 먼저 배를 채워줘$t$,
  $t$식이섬유는 천천히 소화돼서 포만감을 오래 끌어줘. 우리 대부분은 생각보다 덜 먹고 있어.$t$,
  $j$[
  {
    "t": "h",
    "text": "섬유질이 하는 일"
  },
  {
    "t": "p",
    "text": "식이섬유는 천천히 소화돼서 배부른 느낌을 오래 끌어줘. 칼로리를 줄인 식단을 6개월 따라간 연구(POUNDS Lost)에서는 칼로리·탄단지와 별개로 식이섬유를 많이 먹은 사람일수록 체중이 더 줄었고 식단도 더 잘 이어갔어. 관찰 결과라서 섬유질만으로 빠진다고 할 순 없지만, 챙길 이유는 충분해. 채소는 부피에 비해 칼로리가 낮아서 접시를 넉넉하게 채워주는 역할도 해."
  },
  {
    "t": "h",
    "text": "우리는 얼마나 먹고 있을까?"
  },
  {
    "t": "p",
    "text": "질병관리청 국민건강영양조사에서 과일·채소를 하루 500g 이상 먹는 20대는 남자 10.6%, 여자 7.5%뿐이었어. 20·30대는 잡곡·과일 점수도 낮은 편이야. 대부분 모자란 상태라서 조금만 더해도 차이가 커. 처음부터 확 늘리면 속이 더부룩할 수 있으니 하루 한 접시씩 천천히 늘리고 물도 같이 챙겨."
  },
  {
    "t": "list",
    "items": [
      "밥에 잡곡이나 현미 섞기",
      "김치 말고 나물·샐러드 한 접시 더하기",
      "간식은 과일 한 개나 방울토마토 한 줌",
      "국은 미역·버섯·두부 같은 건더기 위주로"
    ]
  },
  {
    "t": "tip",
    "text": "한 끼에 채소 반찬을 두 가지 놓아 보자. 사진에 초록색이 한 칸 보이면 오늘 몫은 챙긴 거야."
  }
]$j$::jsonb,
  array[$t$식이섬유$t$, $t$채소$t$]::text[],
  2,
  $j$[
  {
    "label": "Miketinas DC 외 (2019) Fiber Intake Predicts Weight Loss and Dietary Adherence (POUNDS Lost) — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/31174214/"
  },
  {
    "label": "질병관리청 — 2025 국민건강영양조사 결과 발표",
    "url": "https://www.kdca.go.kr/bbs/kdca/42/312791/artclView.do"
  },
  {
    "label": "뉴시스 (2026-08-04) 질병관리청 식생활평가지수 발표 보도",
    "url": "https://mobile.newsis.com/view/NISX20260804_0003735294"
  }
]$j$::jsonb,
  20,
  true
)
on conflict (slug) do update set
  title = excluded.title,
  summary = excluded.summary,
  body = excluded.body,
  tags = excluded.tags,
  read_minutes = excluded.read_minutes,
  sources = excluded.sources,
  sort = excluded.sort,
  updated_at = now();  -- published 는 재실행해도 건드리지 않는다

-- 30. energy-density
insert into public.lessons (slug, title, summary, body, tags, read_minutes, sources, sort, published)
values (
  $t$energy-density$t$,
  $t$같은 한 그릇, 다른 칼로리$t$,
  $t$음식 1g에 든 칼로리(에너지 밀도)를 알면 배부르게 먹으면서 양을 조절하기 쉬워.$t$,
  $j$[
  {
    "t": "h",
    "text": "에너지 밀도가 뭐야?"
  },
  {
    "t": "p",
    "text": "음식 1g에 든 칼로리야. 채소·과일·살코기·건더기 많은 국처럼 물과 섬유가 많은 음식은 낮고, 과자·튀김·버터·견과처럼 기름지고 마른 음식은 높아. 같은 그릇을 채워도 칼로리가 몇 배씩 차이 나. 기름에 볶은 요리보다 채소가 듬뿍 든 찜이나 샐러드가 같은 배부름을 더 적은 칼로리로 주는 식이야."
  },
  {
    "t": "p",
    "text": "31개 연구를 묶은 분석에서 에너지 밀도를 낮춘 음식을 줬더니 하루에 먹는 칼로리가 뚜렷하게 줄었어. 미국 식생활지침 근거 검토도 에너지 밀도가 낮은 식사가 감량과 유지에 도움이 된다고 봤고. 다만 체중 변화까지 직접 잰 연구는 적어서, \"배부르게 덜 먹게 돕는 도구\" 정도로 생각하면 좋아."
  },
  {
    "t": "h",
    "text": "간식에 써먹기"
  },
  {
    "t": "list",
    "items": [
      "과자 한 봉지 대신 → 방울토마토·오이·사과",
      "크림 파스타 대신 → 토마토 파스타 + 샐러드",
      "볶음밥은 양을 조금 덜고 → 채소를 더 넣어 부피 맞추기",
      "주스 대신 → 과일 그대로"
    ]
  },
  {
    "t": "p",
    "text": "견과나 올리브유처럼 에너지 밀도가 높아도 몸에 필요한 음식도 있어. 피하라는 게 아니라 한 줌, 한 숟가락처럼 양을 정해서 먹으면 돼."
  },
  {
    "t": "tip",
    "text": "\"빼기\"보다 \"더하기\"로 생각해 봐. 채소로 접시 반을 먼저 채우면 나머지는 자연스럽게 자리가 정해져."
  }
]$j$::jsonb,
  array[$t$포만감$t$, $t$간식$t$]::text[],
  2,
  $j$[
  {
    "label": "Robinson E 외 (2022) Calorie reformulation: energy density and daily energy intake (메타분석) — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/35459185/"
  },
  {
    "label": "Pérez-Escamilla R 외 (2012) Dietary energy density and body weight in adults and children — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/22480489/"
  }
]$j$::jsonb,
  30,
  true
)
on conflict (slug) do update set
  title = excluded.title,
  summary = excluded.summary,
  body = excluded.body,
  tags = excluded.tags,
  read_minutes = excluded.read_minutes,
  sources = excluded.sources,
  sort = excluded.sort,
  updated_at = now();  -- published 는 재실행해도 건드리지 않는다

-- 40. slow-eating
insert into public.lessons (slug, title, summary, body, tags, read_minutes, sources, sort, published)
values (
  $t$slow-eating$t$,
  $t$한 입 먹고, 수저 내려놓기$t$,
  $t$천천히 먹으면 한 끼에 먹는 양이 줄었다는 실험들이 있어. 채소 먼저 먹기는 혈당 팁 정도로 보자.$t$,
  $j$[
  {
    "t": "h",
    "text": "속도와 양"
  },
  {
    "t": "p",
    "text": "22개 실험을 묶은 분석에서 천천히 먹을 때 한 끼에 먹는 칼로리가 줄었어. 그런데 식후 몇 시간 동안 느끼는 배고픔은 빨리 먹을 때와 비슷했대. 빨리 먹는 사람에게 비만이 더 많다는 관찰 연구도 있지만, 그건 원인까지 말해주진 않아. 속도를 늦추는 습관이 실제로 체중을 줄이는지는 아직 확인되지 않았어. 그래도 천천히 먹으면 음식 맛을 더 느끼고, 배가 찼는지 중간에 확인할 틈이 생겨."
  },
  {
    "t": "list",
    "items": [
      "한 입 먹고 수저 내려놓기",
      "영상 보면서 먹지 않기, 먹는 데만 집중하기",
      "한 끼에 시간을 조금 더 쓰기 — 처음엔 타이머로 재 봐도 좋아",
      "중간에 물 한 모금으로 쉬어가기"
    ]
  },
  {
    "t": "h",
    "text": "채소 먼저 먹기는?"
  },
  {
    "t": "p",
    "text": "채소·단백질을 밥보다 먼저 먹으면 건강한 성인의 식후 혈당이 덜 오른다는 연구 정리가 있어. 하지만 체중 효과는 보고되지 않았고, 당뇨가 있는 사람들을 본 분석에서도 뚜렷한 효과는 확인되지 않았어. 식후 혈당을 위한 팁 정도로 생각하자."
  },
  {
    "t": "tip",
    "text": "오늘 한 끼만 \"한 입 먹고 수저 내려놓기\"로 먹어 봐. 어땠는지 기록에 한 줄 남겨두면 좋아."
  }
]$j$::jsonb,
  array[$t$속도$t$]::text[],
  2,
  $j$[
  {
    "label": "Robinson E 외 (2014) Effect of eating rate on energy intake and hunger (메타분석) — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/24847856/"
  },
  {
    "label": "Ohkuma T 외 (2015) Association between eating rate and obesity (메타분석) — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/26100137/"
  },
  {
    "label": "Kim J 외 (2026) Meal sequence and blood glucose response in healthy adults (체계적 고찰) — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/41837403/"
  },
  {
    "label": "Okami Y 외 (2022) Efficacy of a meal sequence in patients with type 2 diabetes (메타분석) — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/35210284/"
  }
]$j$::jsonb,
  40,
  true
)
on conflict (slug) do update set
  title = excluded.title,
  summary = excluded.summary,
  body = excluded.body,
  tags = excluded.tags,
  read_minutes = excluded.read_minutes,
  sources = excluded.sources,
  sort = excluded.sort,
  updated_at = now();  -- published 는 재실행해도 건드리지 않는다

-- 50. soup-sodium
insert into public.lessons (slug, title, summary, body, tags, read_minutes, sources, sort, published)
values (
  $t$soup-sodium$t$,
  $t$국물 한 그릇과 다음 날 체중계$t$,
  $t$짜게 먹은 다음 날 체중이 오르는 건 대부분 수분이야. 국물 습관 하나가 나트륨을 크게 좌우해.$t$,
  $j$[
  {
    "t": "h",
    "text": "짠 저녁 다음 날, 숫자가 오른 이유"
  },
  {
    "t": "p",
    "text": "나트륨을 많이 먹으면 몸이 수분을 더 붙잡아 둬서 다음 날 체중계 숫자가 훌쩍 오르기도 해. 이건 대부분 물이야. 나트륨이 체지방을 늘린다는 뜻은 아니니까 하루 숫자에 놀라지 않아도 돼. 대신 혈압 건강을 생각하면 줄여볼 만한 이유는 충분해. 반대로 싱겁게 먹은 며칠 뒤 숫자가 쑥 내려가는 것도 같은 이유야. 그것도 지방보다는 물이 빠진 거라서, 숫자 하나로 기뻐하거나 실망할 필요가 없어."
  },
  {
    "t": "h",
    "text": "우리 식탁의 나트륨"
  },
  {
    "t": "p",
    "text": "2025년 국민건강영양조사에서 하루 나트륨 섭취는 평균 3,043mg이었어. WHO 권고(2,000mg)의 1.5배쯤이야. 식약처 분석에서 큰 몫을 차지한 음식은 김치, 그리고 국·탕·찌개였어. 배달·포장 음식으로 먹는 나트륨도 늘고 있대."
  },
  {
    "t": "list",
    "items": [
      "국물보다 건더기 먼저 먹기",
      "작은 국그릇(200ml 정도)에 덜어 먹기",
      "간장·쌈장은 찍어 먹을 만큼만",
      "배달 찌개는 처음부터 국물을 조금 덜어두기"
    ]
  },
  {
    "t": "tip",
    "text": "짠 음식을 먹은 다음 날 체중이 올랐다면 며칠 흐름으로 봐줘. 물 충분히 마시고 평소대로 먹으면 돼."
  }
]$j$::jsonb,
  array[$t$나트륨$t$, $t$국물$t$, $t$체중변동$t$]::text[],
  2,
  $j$[
  {
    "label": "질병관리청 — 2025 국민건강영양조사 결과 발표",
    "url": "https://www.kdca.go.kr/bbs/kdca/42/312791/artclView.do"
  },
  {
    "label": "쿠키뉴스 (2024-05) 식약처 나트륨 섭취 분석 보도",
    "url": "https://www.kukinews.com/article/view/kuk202405300165"
  }
]$j$::jsonb,
  50,
  true
)
on conflict (slug) do update set
  title = excluded.title,
  summary = excluded.summary,
  body = excluded.body,
  tags = excluded.tags,
  read_minutes = excluded.read_minutes,
  sources = excluded.sources,
  sort = excluded.sort,
  updated_at = now();  -- published 는 재실행해도 건드리지 않는다

-- 60. weight-trend
insert into public.lessons (slug, title, summary, body, tags, read_minutes, sources, sort, published)
values (
  $t$weight-trend$t$,
  $t$체중은 오르내리는 게 정상이야$t$,
  $t$하루 숫자보다 1~2주 흐름을 보면 마음도 편하고 판단도 정확해져.$t$,
  $j$[
  {
    "t": "h",
    "text": "하루 숫자보다 흐름"
  },
  {
    "t": "p",
    "text": "체중은 물, 소금, 먹은 양, 화장실, 몸 상태에 따라 하루에도 오르내려. 체중 기록을 분석한 연구에서는 주말에 오르고 평일에 내려가는 주간 리듬이 흔하게 나타났어. 월요일 아침 숫자가 높은 건 이상한 일이 아니야. 생리 주기나 운동 다음 날처럼 몸 상태에 따라 며칠씩 높게 나오기도 해."
  },
  {
    "t": "h",
    "text": "추세로 읽는 법"
  },
  {
    "t": "list",
    "items": [
      "같은 조건에서 재기: 아침, 화장실 다녀온 뒤, 비슷한 옷",
      "하루 숫자 대신 1~2주 평균 흐름 보기",
      "하루 새 1kg 넘게 올랐다면 전날 짠 음식이나 늦은 식사부터 떠올려 보기",
      "숫자가 마음을 너무 흔들면 재는 횟수를 줄여도 괜찮아"
    ]
  },
  {
    "t": "p",
    "text": "연구들을 묶은 분석에서 체중 재기는 식사·활동 계획과 함께할 때 감량과 연결됐고, 매일 재는 것과 덜 자주 재는 것의 차이는 뚜렷하지 않았어. 체중 재기가 대부분 사람에게 심리적으로 큰 영향이 없었다는 분석도 있지만 사람마다 달라. 나한테 맞는 빈도를 찾으면 돼."
  },
  {
    "t": "tip",
    "text": "점 하나보다 선을 봐줘. 오늘 숫자는 흐름 속 한 점일 뿐이야."
  }
]$j$::jsonb,
  array[$t$체중변동$t$, $t$기록$t$]::text[],
  2,
  $j$[
  {
    "label": "Orsama AL 외 (2014) Weight rhythms: weight increases during weekends and decreases during weekdays — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/24504358/"
  },
  {
    "label": "Madigan CD 외 (2015) 자가 체중 측정 메타분석 — PMC",
    "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC4546162/"
  },
  {
    "label": "Benn Y 외 (2016) What is the psychological impact of self-weighing? (메타분석) — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/26742706/"
  }
]$j$::jsonb,
  60,
  true
)
on conflict (slug) do update set
  title = excluded.title,
  summary = excluded.summary,
  body = excluded.body,
  tags = excluded.tags,
  read_minutes = excluded.read_minutes,
  sources = excluded.sources,
  sort = excluded.sort,
  updated_at = now();  -- published 는 재실행해도 건드리지 않는다

-- 70. late-night
insert into public.lessons (slug, title, summary, body, tags, read_minutes, sources, sort, published)
values (
  $t$late-night$t$,
  $t$야식이 당길 때 쓰는 "만약-그러면"$t$,
  $t$밤에 먹는 시간보다 하루 전체 양이 더 중요해. 미리 정해둔 한 문장이 선택을 쉽게 해줘.$t$,
  $j$[
  {
    "t": "h",
    "text": "시간보다 하루 총량"
  },
  {
    "t": "p",
    "text": "국민건강영양조사 자료를 본 국내 연구에서 성인 절반 가까이(46.3%)가 밤에 간식을 먹었어. 야식을 먹은 사람은 하루 총 칼로리와 당류가 더 많았지만, 다른 조건을 맞춰 보면 체질량지수나 비만 위험은 차이가 없었어. 밤에 먹었다는 사실보다 하루 전체 양이 더 중요하다는 쪽에 가까워. 그러니 늦게 먹었다고 자책하기보다 하루 전체를 보는 게 좋아."
  },
  {
    "t": "h",
    "text": "계획은 한 문장으로"
  },
  {
    "t": "p",
    "text": "70개 연구를 묶은 분석에서 \"만약 ~하면, ~할 거야\"처럼 구체적인 한 문장 계획이 식습관에 작지만 꾸준한 도움을 줬어. \"안 먹기\"보다 \"대신 하기\"로 쓴 계획이 더 잘 통했대. 계획은 거창할 필요 없어. 자주 겪는 상황 하나만 골라서 문장으로 만들어 두면 돼."
  },
  {
    "t": "list",
    "items": [
      "만약 밤 10시에 배달앱을 열면 → 물 한 잔 마시고 10분 뒤에 다시 볼 거야",
      "만약 퇴근길에 너무 배고프면 → 저녁을 거르지 않고 단백질 있는 한 끼를 먹을 거야",
      "만약 그래도 출출하면 → 우유·요거트·과일처럼 가벼운 걸 접시에 덜어 먹을 거야"
    ]
  },
  {
    "t": "tip",
    "text": "오늘 밤에 쓸 문장 하나만 골라 봐. 먹었더라도 괜찮아, 기록해두면 다음 계획이 더 정확해져."
  }
]$j$::jsonb,
  array[$t$야식$t$]::text[],
  2,
  $j$[
  {
    "label": "Carrero I 외 (2019) Implementation intention interventions for healthy eating (메타회귀) — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/31125588/"
  },
  {
    "label": "Samdal GB 외 (2017) Effective behaviour change techniques in overweight and obese adults — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/28351367/"
  },
  {
    "label": "국민건강영양조사 자료 기반 성인 야간 간식 섭취 분석 — KoreaScholar",
    "url": "https://db.koreascholar.com/Article/Detail/449884"
  }
]$j$::jsonb,
  70,
  true
)
on conflict (slug) do update set
  title = excluded.title,
  summary = excluded.summary,
  body = excluded.body,
  tags = excluded.tags,
  read_minutes = excluded.read_minutes,
  sources = excluded.sources,
  sort = excluded.sort,
  updated_at = now();  -- published 는 재실행해도 건드리지 않는다

-- 80. convenience
insert into public.lessons (slug, title, summary, body, tags, read_minutes, sources, sort, published)
values (
  $t$convenience$t$,
  $t$편의점 한 끼는 조합으로 고르자$t$,
  $t$주식 하나, 단백질 하나, 채소·과일 하나. 국물은 하나만.$t$,
  $j$[
  {
    "t": "h",
    "text": "편의점 도시락의 숫자"
  },
  {
    "t": "p",
    "text": "한국소비자원이 인기 편의점 도시락 10개를 조사했더니 나트륨이 하루 기준치의 55~86%, 단백질은 36~71%였어. 일부 제품은 표시된 영양성분과 실제 값이 달랐고, 도시락을 컵라면과 같이 먹는다는 사람도 44%였지. 편의점 김밥 12종 조사에서는 한 줄 나트륨이 하루 기준치의 38~70%였어."
  },
  {
    "t": "h",
    "text": "조합 공식"
  },
  {
    "t": "list",
    "items": [
      "주식 하나: 김밥 한 줄, 주먹밥, 샌드위치, 도시락 중 하나",
      "단백질 하나: 삶은 달걀, 우유·두유, 닭가슴살, 단백질 음료",
      "채소·과일 하나: 샐러드 컵, 과일 컵, 방울토마토",
      "국물은 하나만, 아니면 생략"
    ]
  },
  {
    "t": "p",
    "text": "소비자원도 김밥은 컵라면 대신 우유나 달걀과 같이 먹으라고 권했어. 김밥에 컵라면을 더하면 나트륨이 하루 기준치를 넘기기 쉬워. 영양성분표의 나트륨 칸만 봐도 고르기가 훨씬 쉬워져. 같은 도시락이라도 제품마다 차이가 크니까, 자주 먹는 제품은 한 번 확인해두면 다음부터 편해."
  },
  {
    "t": "tip",
    "text": "계산대 가기 전에 바구니를 한 번 봐. 단백질 칸이 비어 있으면 달걀이나 우유 하나 추가!"
  }
]$j$::jsonb,
  array[$t$편의점$t$]::text[],
  2,
  $j$[
  {
    "label": "뉴시스 (2023-06-28) 한국소비자원 편의점 도시락 조사 보도",
    "url": "https://mobile.newsis.com/view/NISX20230628_0002355924"
  },
  {
    "label": "한국소비자원 편의점 김밥 조사 보도 — supple",
    "url": "https://supple.kr/news/cmv98fm9y00flxwob4l53f9h9"
  }
]$j$::jsonb,
  80,
  true
)
on conflict (slug) do update set
  title = excluded.title,
  summary = excluded.summary,
  body = excluded.body,
  tags = excluded.tags,
  read_minutes = excluded.read_minutes,
  sources = excluded.sources,
  sort = excluded.sort,
  updated_at = now();  -- published 는 재실행해도 건드리지 않는다

-- 90. delivery
insert into public.lessons (slug, title, summary, body, tags, read_minutes, sources, sort, published)
values (
  $t$delivery$t$,
  $t$배달 주문 전 30초 점검$t$,
  $t$배달이 잦을수록 양·기름·소금이 같이 늘기 쉬워. 주문 화면에서 바꿀 수 있는 게 꽤 많아.$t$,
  $j$[
  {
    "t": "h",
    "text": "배달이 잦을 때"
  },
  {
    "t": "p",
    "text": "제주 지역 19~39세 312명을 조사한 연구에서 배달음식을 주 3회 이상 먹는 사람은 주 1회 미만인 사람보다 비만 비율이 높게 나타났어. 짜게 먹는 습관, 아침 거르기와도 함께 나타났고. 한 시점의 설문이라 배달이 원인이라고 할 순 없어. 그래도 국민건강영양조사에서 20·30대는 지방에서 얻는 에너지 비율이 권장 상한(30%)을 넘었으니 메뉴 고를 때 한 번 더 볼 만해."
  },
  {
    "t": "h",
    "text": "주문 전 체크"
  },
  {
    "t": "list",
    "items": [
      "1인분이 진짜 1인분인지 보기 — 2인 세트면 반은 덜어서 다음 끼니로",
      "사이드 하나는 채소로: 샐러드, 쌈, 무침",
      "튀김·크림 대신 구이·찜 메뉴가 있는지 보기",
      "소스·드레싱은 따로 받아서 찍어 먹기"
    ]
  },
  {
    "t": "p",
    "text": "배달이 잦은 주라면 일주일에 한두 번은 직접 차리거나 포장 샐러드·도시락으로 바꿔 보는 것도 방법이야. 매번 완벽할 필요는 없어. 한 번에 하나만 바꿔도 충분해."
  },
  {
    "t": "tip",
    "text": "배달이 오면 용기째 말고 접시에 덜어 먹어 봐. 사진도 잘 나오고, 내가 먹은 양이 눈에 보여."
  }
]$j$::jsonb,
  array[$t$배달$t$]::text[],
  2,
  $j$[
  {
    "label": "배달음식 섭취 빈도와 비만 — Journal of Nutrition and Health (2024)",
    "url": "https://koreascience.kr/article/JAKO202421472553028.page"
  },
  {
    "label": "질병관리청 — 2025 국민건강영양조사 결과 발표",
    "url": "https://www.kdca.go.kr/bbs/kdca/42/312791/artclView.do"
  }
]$j$::jsonb,
  90,
  true
)
on conflict (slug) do update set
  title = excluded.title,
  summary = excluded.summary,
  body = excluded.body,
  tags = excluded.tags,
  read_minutes = excluded.read_minutes,
  sources = excluded.sources,
  sort = excluded.sort,
  updated_at = now();  -- published 는 재실행해도 건드리지 않는다

-- 100. hoesik
insert into public.lessons (slug, title, summary, body, tags, read_minutes, sources, sort, published)
values (
  $t$hoesik$t$,
  $t$회식 자리, 미리 정해두는 세 가지$t$,
  $t$술자리는 길어질수록 먹는 양도 같이 늘기 쉬워. 시작 전에 정해두면 훨씬 편해.$t$,
  $j$[
  {
    "t": "h",
    "text": "회식은 계획이 반"
  },
  {
    "t": "p",
    "text": "2025년 국민건강영양조사에서 성인의 월간 폭음률은 35.1%였어. 세 명 중 한 명꼴이야. 술자리는 안주와 술이 길게 이어지고 분위기상 양을 가늠하기 어려워서, 그 자리에서 판단하기보다 미리 정해두는 게 쉬워. 회식이 잦은 시기라면 매번 다 지키려 하기보다 세 가지 중 하나만 지켜도 괜찮아."
  },
  {
    "t": "h",
    "text": "미리 정해두는 세 가지"
  },
  {
    "t": "list",
    "items": [
      "출발 전: 빈속으로 가지 않기 — 우유나 달걀 같은 가벼운 단백질 먼저",
      "안주: 튀김·전보다 두부·생선·회·구이를 먼저 집기",
      "술: 오늘 마실 잔 수를 정하고, 잔 사이에 물 한 잔"
    ]
  },
  {
    "t": "p",
    "text": "술에도 칼로리가 있고, 자리가 길어질수록 안주에 손이 더 가기 쉬워. 2차에 가더라도 음료나 물로 함께하는 선택지도 있어. 술을 줄이는 건 체중뿐 아니라 컨디션에도 좋아. 다음 날 아침엔 물부터 한 잔, 해장은 국물보다 건더기 위주로 먹으면 나트륨도 덜 수 있어."
  },
  {
    "t": "tip",
    "text": "다음 날 굶어서 맞추지 않아도 돼. 평소처럼 세 끼, 물 넉넉히, 단백질 챙기면 충분해."
  }
]$j$::jsonb,
  array[$t$회식$t$, $t$술$t$]::text[],
  2,
  $j$[
  {
    "label": "질병관리청 — 2025 국민건강영양조사 결과 발표",
    "url": "https://www.kdca.go.kr/bbs/kdca/42/312791/artclView.do"
  },
  {
    "label": "정책브리핑 — 2025 지역사회건강조사 심층분석 보도",
    "url": "https://www.korea.kr/news/policyNewsView.do?newsId=148975331"
  }
]$j$::jsonb,
  100,
  true
)
on conflict (slug) do update set
  title = excluded.title,
  summary = excluded.summary,
  body = excluded.body,
  tags = excluded.tags,
  read_minutes = excluded.read_minutes,
  sources = excluded.sources,
  sort = excluded.sort,
  updated_at = now();  -- published 는 재실행해도 건드리지 않는다

-- 110. after-overeating
insert into public.lessons (slug, title, summary, body, tags, read_minutes, sources, sort, published)
values (
  $t$after-overeating$t$,
  $t$많이 먹은 다음 날, 굶지 말고 평소대로$t$,
  $t$다음 날 오른 체중은 대부분 수분이야. 몰아서 줄이기보다 평소 리듬으로 돌아가는 게 제일 편해.$t$,
  $j$[
  {
    "t": "h",
    "text": "숫자가 확 올랐다면"
  },
  {
    "t": "p",
    "text": "많이 먹은 다음 날 체중이 훌쩍 오르는 건 대부분 탄수화물과 함께 저장되는 수분 때문이야. 글리코겐 1g이 물 약 3g과 같이 저장된다는 설명이 일반적이야. 하룻밤 새 그만큼 지방이 붙은 게 아니야. 주말에 오르고 평일에 내려가는 체중 리듬도 흔하게 관찰돼."
  },
  {
    "t": "h",
    "text": "다음 날은 이렇게"
  },
  {
    "t": "list",
    "items": [
      "굶지 않기: 평소처럼 세 끼, 하루 최소선(남 1500·여 1200kcal) 아래로 내리지 않기",
      "끼니마다 단백질과 채소 한 칸씩",
      "물 넉넉히, 짠 음식은 조금 덜",
      "체중은 며칠 흐름으로 보기",
      "어제 한 끼는 일주일 전체로 보면 작은 부분이라는 것 기억하기"
    ]
  },
  {
    "t": "p",
    "text": "나를 다그치지 않고 친구 대하듯 대하는 \"자기자비\"를 다룬 연구들을 모은 고찰에서, 많은 연구가 먹는 습관이 나아졌다고 보고했어(연구 방법의 한계는 있어). 연속 기록이 끊겼을 때 그걸 자기 탓으로 돌릴수록 다시 시작하기 어려웠다는 연구도 있고."
  },
  {
    "t": "tip",
    "text": "어제 많이 먹었어도 오늘 기록을 여는 너는 이미 다시 시작한 거야. 오늘 첫 끼를 평소처럼 남겨 보자."
  }
]$j$::jsonb,
  array[$t$과식$t$, $t$주말$t$]::text[],
  2,
  $j$[
  {
    "label": "Brenton-Peters J 외 (2021) Self-compassion in weight management: A systematic review — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/34560404/"
  },
  {
    "label": "Orsama AL 외 (2014) Weight rhythms: weight increases during weekends and decreases during weekdays — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/24504358/"
  },
  {
    "label": "Silverman & Barasch (2023) 끊긴 연속 기록과 참여에 관한 연구 — UDSpace",
    "url": "https://udspace.udel.edu/items/42ce576b-8e1f-429a-8541-e29e48dbcfbb"
  },
  {
    "label": "인사이트 — 명절 뒤 급격한 체중 증가와 수분 설명 기사",
    "url": "https://www.insight.co.kr/news/523421"
  }
]$j$::jsonb,
  110,
  true
)
on conflict (slug) do update set
  title = excluded.title,
  summary = excluded.summary,
  body = excluded.body,
  tags = excluded.tags,
  read_minutes = excluded.read_minutes,
  sources = excluded.sources,
  sort = excluded.sort,
  updated_at = now();  -- published 는 재실행해도 건드리지 않는다

-- 120. plateau
insert into public.lessons (slug, title, summary, body, tags, read_minutes, sources, sort, published)
values (
  $t$plateau$t$,
  $t$정체기는 점검표로 풀어보자$t$,
  $t$체중이 멈춘 건 흔한 흐름이야. 더 줄이기 전에 빠진 곳부터 찾아보자.$t$,
  $j$[
  {
    "t": "h",
    "text": "정체기는 흔해"
  },
  {
    "t": "p",
    "text": "스마트폰 앱 연구들을 묶은 분석에서도 평균 감량 폭은 3개월보다 12개월에 더 작았어. 처음처럼 계속 빠지지 않는 건 많은 사람이 겪는 흐름이야. 너만 그런 게 아니야."
  },
  {
    "t": "h",
    "text": "원인은 생각보다 소박해"
  },
  {
    "t": "p",
    "text": "6개월 무렵의 정체를 수학 모형으로 살펴본 연구에서는 대사가 느려진 것보다 계획한 식사량에서 조금씩 벗어난 날들이 쌓인 영향이 더 컸어. 그래서 정체기엔 \"더 줄이기\"보다 \"빠진 곳 찾기\"가 먼저야."
  },
  {
    "t": "list",
    "items": [
      "기록에서 빠진 끼니가 있었나? 간식·음료·소스까지",
      "주말에 평일보다 꽤 많이 먹었나?",
      "라떼·주스·술 같은 음료 칼로리는?",
      "체중이 줄었는데 목표 칼로리는 예전 그대로인가?"
    ]
  },
  {
    "t": "p",
    "text": "감량 뒤 유지를 다룬 연구들에서는 식사와 활동을 함께 다룬 꾸준한 습관이 다시 찌는 걸 줄이는 데 작지만 의미 있는 도움을 줬어. 기록을 꾸준히 한 사람일수록 결과가 좋은 경향도 있었고(관찰 결과라 원인까진 몰라)."
  },
  {
    "t": "tip",
    "text": "목표를 하루 최소선(남 1500·여 1200kcal) 아래로 내리지는 마. 점검표에서 하나만 골라 이번 주에 바꿔 보자."
  }
]$j$::jsonb,
  array[$t$정체기$t$, $t$기록$t$]::text[],
  2,
  $j$[
  {
    "label": "Thomas DM 외 (2014) Effect of dietary adherence on the body weight plateau — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/25080458/"
  },
  {
    "label": "Chew HSJ 외 (2022) Sustainability of Weight Loss Through Smartphone Apps (메타분석) — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/36129739/"
  },
  {
    "label": "Dombrowski SU 외 (2014) Long term maintenance of weight loss (메타분석) — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/25134100/"
  },
  {
    "label": "Patel ML 외 (2021) Self-Monitoring via Digital Health in Weight Loss Interventions — PubMed",
    "url": "https://pubmed.ncbi.nlm.nih.gov/33624440/"
  }
]$j$::jsonb,
  120,
  true
)
on conflict (slug) do update set
  title = excluded.title,
  summary = excluded.summary,
  body = excluded.body,
  tags = excluded.tags,
  read_minutes = excluded.read_minutes,
  sources = excluded.sources,
  sort = excluded.sort,
  updated_at = now();  -- published 는 재실행해도 건드리지 않는다
