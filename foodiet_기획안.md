# foodiet 서비스 기획안

> **한 줄 소개** — 사진 한 장만 찍으면, AI가 시간대·식사 종류·칼로리·영양소를 자동 분석하고, 목표 체중까지의 식단을 코칭해 주는 모바일 다이어트 파트너.

- 작성일: 2026-04-18
- 버전: **v1.2** (MVP 기획 + 디자인 시스템 + 기술 스택 확정)
- 대상 플랫폼: iOS + Android (**Flutter 단일 코드베이스**), PT 공유용 웹뷰 부가
- 백엔드: **Supabase** (Postgres + Auth + Storage + Edge Functions + RLS)
- 산출물 범위: 서비스 비전 → MVP 기능 명세 → AI 파이프라인 → 데이터 모델(Supabase 스키마·RLS) → 디자인 방향 → 로드맵(해외 확장 포함) → KPI → 리스크
- 동반 자산:
  - 프로젝트 홈: `index.html`
  - 디자인 시스템: `design-system/README.md`, `design-system/colors_and_type.css`
  - **Flutter 앱 스캐폴드(클라이언트 정식 구현)**: `app/` — pubspec, Dart 테마 토큰, Supabase 초기화, 푸디 버블/MealChip 샘플, i18n ARB(ko/en)
  - Supabase 마이그레이션 + Edge Functions: `app/supabase/` — `0001_init.sql`(§13), `analyze-entry`, `generate-coach`, `render-share`
  - UI 무드 참고(레거시 HTML 프로토타입): `design-system/ui_kits/ios_app/index.html` — 초기 무드 보드용. 체중/냉장고 화면이 포함돼 있으나 **MVP 범위 아님**. 정식 구현은 `app/`.
  - 마스코트: **푸디(Foodie)** — 잎사귀 달린 동글동글 딸기 캐릭터. AI 조언은 모두 푸디 입으로 전달.

### 이번 버전에서 확정된 핵심 의사결정 (v1.1 → v1.2)
| 항목 | 확정 내용 |
|---|---|
| 클라이언트 스택 | **Flutter** (iOS+Android 단일 코드베이스) |
| 백엔드 | **Supabase** (Postgres / Auth / Storage / Edge Functions) |
| 공유 링크 공개 범위 | **음식 사진 + 해당 사진의 예상 섭취 칼로리(kcal)만**. 매크로·영양소·체중·코치 메시지는 비공개 |
| 체중 공유 | **완전 제외** (PT 뷰에 체중 영역 없음) |
| 해외 확장 | **포함** — MVP에 i18n 구조 + 단위(kcal/kJ, kg/lb) 추상화 |
| PT 코멘트 기능 | v1.1 이후(MVP 제외) — 공유 범위 축소와 충돌 최소화 |

---

## 1. 배경과 문제 정의

### 1.1 문제
다이어트를 시도하는 사용자의 가장 큰 이탈 요인은 **"기록이 귀찮다"** 는 것이다. 기존 앱들은 다음 중 하나 이상을 요구한다.

- 음식 이름을 직접 검색/선택
- 양(그램/조각/컵) 수동 입력
- 아침/점심/저녁 **끼니 수동 지정**
- 한 끼에 여러 품목을 각각 등록

그 결과, 초기 3~7일 내에 기록이 중단되고 다이어트 루틴 자체가 깨진다. 또한 PT(퍼스널 트레이닝)를 받는 사용자는 선생님에게 식단을 공유해야 하지만, 매번 카톡으로 사진을 정리해 보내는 것이 번거로워 공유가 끊긴다.

### 1.2 기회
- 모바일 기기의 카메라 품질 상승 + 멀티모달 LLM의 음식 인식 정확도 상승
- 시간 메타데이터(촬영 시각) + 사진 내 시각 단서(플레이팅/조명/음료/포장)로 **아침/점심/저녁/간식 자동 분류 가능**
- 사용자 프로필(목표 체중, 활동량, 연령)과 기록을 결합한 **개인화 코칭**이 기술적으로 가능

### 1.3 비전 & 미션
- **비전**: 기록하지 않아도 기록되는 다이어트.
- **미션**: 사진 한 장 외의 노력을 모두 AI가 대신하도록 만들어, 다이어트 지속률을 기존 대비 2배로 끌어올린다.

---

## 2. 타겟 사용자 & 페르소나

### 2.1 1차 타겟
- 20대 후반 ~ 40대 초반
- 3개월 이상 다이어트를 시도했으나 기록 앱에서 이탈해 본 경험자
- 감량 목표 보유 (예: "-5kg/3개월")
- 스마트폰으로 일상 사진을 자주 찍는 사용자

### 2.2 2차 타겟
- PT/헬스장 회원으로 트레이너에게 식단 피드백을 받고 있는 사용자
- PT 트레이너 본인 (수신자 측)

### 2.3 페르소나

**페르소나 A — 직장인 "수민" (29세, 여)**
- 야근이 잦아 식사 시간이 불규칙. 점심이 오후 2시, 저녁이 밤 10시일 때가 많음
- "끼니 선택"을 매번 수정하기 귀찮아 기존 앱에서 이탈
- 니즈: 내가 신경 쓰지 않아도 아침/점심/저녁이 자동으로 잡혀야 함

**페르소나 B — PT 2개월차 "재호" (35세, 남)**
- 감량 중. PT 쌤이 식단 관리 중요하다고 해서 일주일에 2~3번 카톡으로 사진 보냄
- 니즈: 한 번에 일주일치 식단을 깔끔히 공유하고 싶음

**페르소나 C — PT 트레이너 "지은" (32세, 여)**
- 회원 20명의 식단을 봐 주어야 하는데, 카톡이 흩어져 관리가 안 됨
- 니즈: 회원별로 시간대별 식사 이력을 한 화면에서 보고 싶음

---

## 3. 핵심 가치 제안 & 차별화

| 가치 | 기존 앱 | foodiet |
|------|---------|---------|
| 기록 난이도 | 검색 + 양 입력 + 끼니 지정 | **사진 1장** |
| 끼니 분류 | 사용자가 지정 | AI가 시간·맥락으로 자동 분류 |
| 식사/간식 구분 | 별도 입력 | AI가 음식 구성·양으로 자동 판단 |
| 조언 | 일반 가이드 | 내 목표·기록 기반 개인화 조언 |
| 공유 | 사진 일일 전송 | PT 공유 링크 1개로 일괄 |

**차별화 포인트 TL;DR**: "사진만 찍으면 끝" + "AI가 나에게 맞춰 조언" + "PT 쌤 공유 1클릭"

---

## 4. MVP 기능 명세

### 4.1 [F1] 원탭 사진 기록
- 홈 화면 하단 중앙 플로팅 카메라 버튼 (최대 도달 거리)
- 촬영 즉시 업로드 큐 진입 → 백그라운드 분석 시작
- 여러 장 연속 촬영 지원 (한 상차림을 여러 각도에서)
- 갤러리에서 선택도 허용 (과거 사진 소급 기록)
- **수동 입력은 기본 숨김** (폴드로 접근)

**허용 오차/보정**: 분석 결과 카드에서 "다시 분석", "끼니 변경", "음식 추가"가 한 탭으로 가능 — 단 기본값은 AI 판단

### 4.2 [F2] AI 자동 분류
다음 3축으로 자동 분류한다.

1. **끼니 (meal_slot)**: `아침(breakfast)` / `점심(lunch)` / `저녁(dinner)` / `야식(late_night)`
2. **식사 종류 (eating_type)**: `식사(meal)` / `간식(snack)` / `음료(beverage)`
3. **음식 구성 (items)**: 여러 품목 분리 인식 (예: 공깃밥 + 김치찌개 + 달걀말이)

**끼니 자동 분류 규칙** (1차 휴리스틱 + 2차 LLM 판단):
| 촬영 시각(로컬) | 기본 추정 | 예외 힌트 |
|---|---|---|
| 05:00 ~ 10:30 | 아침 | 주류/야식 플레이팅 감지 시 재분류 |
| 10:30 ~ 14:30 | 점심 | 디저트 단독이면 간식 |
| 14:30 ~ 17:30 | 간식(기본) | 정찬 구성이면 늦은 점심 |
| 17:30 ~ 22:00 | 저녁 | 디저트/음료 단독이면 간식 |
| 22:00 ~ 05:00 | 야식 | 차/물 단독이면 음료 |

**식사/간식 자동 분류 규칙**:
- 단백질/탄수화물/채소 중 **2가지 이상** 포함되면 → 식사
- 디저트·스낵·과자·빵 단독, 또는 음료만 → 간식/음료
- 촬영 시각이 식사 시간대 바깥이면 간식 쪽 가중치 ↑

**사용자 오버라이드**: 모든 자동 분류는 1탭으로 변경 가능. 변경 이벤트는 개인화 모델의 피드백 시그널로 기록.

### 4.3 [F3] AI 칼로리 & 영양소 분석
각 사진에 대해 다음을 추정:

- 품목별 (이름, 추정 중량 g, kcal, 탄·단·지 g, 나트륨 mg, 당류 g)
- 사진 합계 (kcal, 탄·단·지)
- **신뢰도 (0~1)**: 0.6 미만이면 카드에 "확인 필요" 배지 + "보정하기" CTA

### 4.4 [F4] 개인화 AI 코칭 (푸디의 한마디)
모든 조언은 마스코트 **푸디** 입으로 전달. 말풍선은 `comp-ai-bubble` 컴포넌트, 카드 상단에는 "푸디의 한마디" 라벨.

다음 시점에 조언 생성:

1. **식사 직후 (in-meal nudge)**: 방금 먹은 식사가 오늘 목표에 어떻게 영향을 주는지 (예: "탄수 80g 남았어! 저녁은 단백질 위주로 가볼까?")
2. **데일리 리뷰 (저녁 9시 또는 첫 사진이 야식일 때)**: 오늘 총평 + 내일 제안
3. **주간 리포트 (일요일 저녁)**: 체중 변화, 섭취 패턴, 주중 vs 주말 편차, 다음 주 전략

**조언 톤앤매너 (푸디 보이스 · README 규칙과 동일)**:
- 친근한 반말 · 이름으로 부르기 ("지은아 👋")
- 비난·핀잔 금지. "실패"·"어겼다"·"망쳤다" 단어 금지. 제안·칭찬만.
- 구체 수치 포함 (예: "어제보다 나트륨 18% 줄었어!")
- 다음 1개 액션만 제시 (인지 과부하 방지)
- 이모지는 포인트로만 🌸🥗🍓 — 한 화면 1~2개 제한

### 4.5 [F5] 목표 설정 & 진행 추적
- 온보딩 시: 키, 현재 체중, 목표 체중, 목표 기한, 활동량, 식이 제한(선택: 비건/락토·오보/알레르기/종교)
- 일일 권장 섭취량(kcal, 탄·단·지) 자동 계산 (Mifflin-St Jeor + 활동계수 + 감량 적자)
- 메인 화면 상단에 "오늘의 남은 칼로리" 링 차트

### 4.6 [F6] PT 공유 — **사진 + 예상 섭취 칼로리만**
- 회원이 "PT 공유" 토글 ON → 공유 링크 생성 (토큰 기반, 만료일 설정 가능: 7일/30일/무제한)
- 링크 수신자(PT)는 로그인 없이 **읽기 전용 웹뷰** 접근
- **공개 범위(고정, 사용자 옵션 없음)**:
  - ✅ 음식 사진 (썸네일·원본)
  - ✅ 촬영 시각 · 끼니 배지(meal_slot)
  - ✅ 해당 사진의 **예상 섭취 칼로리 (kcal) 합계**
  - ✅ 일자별 예상 섭취 칼로리 합계
  - ❌ 매크로(탄·단·지)·나트륨·당류 — **비공개**
  - ❌ 체중 및 체중 추이 — **비공개** (v2도 체중 공유 계획 없음)
  - ❌ 코치 메시지·목표 설정·개인정보(본명·연락처·생년월일) — **비공개**
  - 공개 노출 이름: 회원이 지정한 **닉네임**만
- PT 뷰 구조: 날짜 선택 → 시간대별 사진 타임라인(사진 + 시간 + meal_slot + kcal) → 일자별 합계 → 주간 평균 칼로리
- 회원은 언제든 링크 끄기/재발급 가능, 열람 로그(시각·국가 단위 IP)는 회원만 확인 가능

### 4.7 [F7] 기록 조회
- **홈(오늘)**: 오늘 타임라인 + 남은 칼로리 링 + 가장 최근 코치 메시지
- **달력**: 월 단위 히트맵 (총 섭취 대비 목표 달성 정도를 셀 색으로)
- **상세일**: 아침·점심·저녁·간식·야식 섹션 + 품목 카드
- **인사이트**: 주간/월간 리포트

---

## 5. 사용자 플로우

### 5.1 첫 경험 (Onboarding → 첫 기록)
1. 앱 실행 → 가치 제안 3슬라이드 (사진 1장 / AI 분류 / PT 공유)
2. 간편 가입 (Apple / Google / 카카오)
3. 온보딩 설문 (키·현재/목표 체중·기한·활동량·식이 제한)
4. 권한 요청 (카메라, 알림)
5. 목표 대시보드로 진입, 첫 사진 유도 오버레이
6. 첫 사진 촬영 → 분석 결과 카드 → 원탭 확인
7. 즉시 in-meal nudge 1회 노출 (가치 체감 모먼트)

### 5.2 일상 플로우 (기록)
사진 촬영 → 업로드/분석 (백그라운드) → 홈 복귀 → 카드 푸시(완료 알림) → 필요 시 보정

### 5.3 PT 공유 플로우
설정 → PT 공유 → 링크 생성/복사 → 카톡/문자로 전달 → PT는 브라우저에서 열람

### 5.4 리텐션 플로우
- D1: "어제 수고했어요" 아침 푸시 + 오늘 목표 리마인드
- D3/D7: 첫 주간 리포트 알림
- 사진 기록 끊김 감지 시: 12시간 무기록 + 평소 기록 시간대 → 부드러운 리마인더 1회만

---

## 6. 정보 구조(IA) & 화면 목록

```
[Tab Bar]
 ├─ 🏠 홈(오늘)          — 남은 칼로리 링 + 오늘 타임라인 + 코치 메시지
 ├─ 📅 기록(달력/리스트) — 월 히트맵, 날짜 드릴다운
 ├─ ➕ 촬영(플로팅 FAB) — 어디에서든 접근
 ├─ 📊 인사이트         — 주간/월간 리포트, 추세 그래프
 └─ 👤 마이             — 목표, PT 공유, 계정, 알림, 프라이버시

[서브 화면]
 ├─ 분석 결과 카드(음식 품목 리스트 / 끼니 / 영양소)
 ├─ 보정 시트(품목 수정, 양 조정, 끼니 변경)
 ├─ 코치 메시지 상세
 ├─ PT 공유 설정(링크/만료/토글)
 └─ 웹뷰(PT 전용): 타임라인 + 요약 (읽기 전용)
```

---

## 7. 디자인 방향 (Foodiet 디자인 시스템 적용)

> 본 섹션은 첨부된 **Foodiet Design System (handoff bundle)** 에 맞춰 작성되었습니다. 토큰·일러스트·컴포넌트는 `design-system/` 폴더를 그대로 사용합니다 (`colors_and_type.css`, `assets/*.svg`, `ui_kits/ios_app/*`, `preview/*.html`).

### 7.1 디자인 컨셉 — "봄, 친구처럼 묻는 다이어트"
- 컬러 테마: **따뜻한 코랄 × 연두 × 크림 웜톤** (딸기·나물·쑥 무드)
- 라인·셰이프: 둥근 14~20px 코너, 얇은 손그림 외곽선(`#3E3A31`, 1.2~1.6px), 웜톤 섀도
- 보이스: 친근한 반말, 마스코트 **푸디(Foodie)** 가 AI 조언을 전달

### 7.2 디자인 원칙
1. **한 화면 한 결정** — 분석 결과 카드에서 "확인" 한 번이면 끝.
2. **사진 우선** — 크림 배경(`--cream-00 #FFFDFA`) + 둥근 14~18px 컨테이너로 사진이 주인공.
3. **숫자는 주인공, 그리고 친절하게** — 칼로리·체중은 `number-large` Gmarket Bold + `tnum`. 항상 목표 대비 해석(`"220kcal 남았어!"`)을 함께.
4. **판단하지 않는 톤** — 에러 레드는 분석 실패/네트워크 오류에만. 섭취 과다엔 `warning(#F2A93B)` 또는 푸디의 부드러운 제안만.

### 7.3 컬러 시스템 (토큰은 `colors_and_type.css` 그대로 사용)

**브랜드**
- Primary 코랄: `--coral-500 #FF8A5B` — CTA, 포인트, 칼로리 숫자
- Primary hover: `--coral-600 #EE7042` / soft: `--coral-100 #FFE4D1`
- Secondary 연두: `--leaf-500 #7FB77E` — 성공, 목표 달성, 야채/그린 요소

**뉴트럴 (웜톤)**
- `--cream-00 #FFFDFA` (바닥) / `--cream-50 #FBF6EF` (카드) / `--cream-100 #F4EDE2` (헤어라인)
- `--warm-900 #221F1A` (ink) / `--warm-700 #3E3A31` (heading) / `--warm-500 #6B6454` (body)

**식사 전용 (meal_slot 색상 — 앱/PT 뷰/달력 히트맵 모두 동일 토큰)**
| meal_slot | 토큰 | HEX | 용도 |
|---|---|---|---|
| 아침(breakfast) | `--meal-breakfast` | `#F7D36A` | 아침 카드 액센트, 히트맵 셀 |
| 점심(lunch) | `--meal-lunch` | `#FF8A5B` | Primary와 동일 — 점심은 자연스럽게 강조 |
| 저녁(dinner) | `--meal-dinner` | `#8B6FB3` | 라벤더 — 저녁의 차분한 톤 |
| 야식(late_night) | `--meal-dinner` + 어두운 오버레이 `rgba(26,17,8,0.12)` | — | 저녁 톤 재사용, 배경 살짝 어둡게 |
| 간식(snack, eating_type) | `--meal-snack` | `#7FB77E` | 식사 종류 축의 간식 배지 |

> **중요 — 두 축 혼동 방지**: `meal_slot`(아침/점심/저녁/야식)과 `eating_type`(식사/간식/음료)은 서로 다른 축입니다. UI에서는 상단 배지=`meal_slot 색`, 우측 작은 칩=`eating_type`으로 시각적으로 구분합니다.

**시맨틱**
- 성공 `--success = --leaf-500`, 주의 `--warning #F2A93B`, 위험 `--danger #E5574E`, 정보 `--info --sky-500 #9BC6E3`

**그라데이션 (히어로·온보딩·주간 리포트)**
- `--grad-spring` 피치→옐로→연두: 기본 온보딩·히어로
- `--grad-sunrise` 코랄 글로우: CTA 카드
- `--grad-sprout` 그린: 목표 달성 축하
- `--grad-bloom` 복숭아→라일락→연두: 주간 리포트

### 7.4 타이포그래피
- 패밀리: **Gmarket Sans** 300/500/700 (로컬 woff), 폴백 `Pretendard → Apple SD Gothic Neo → Noto Sans KR`
- 자간: 기본 `-0.01em`, 헤드라인 `-0.02em`
- 스케일: Display 42 / H1 34 / H2 28 / H3 24 / Title 18 / Body 16 / Body-sm 13 / Caption 12
- 숫자: 항상 Bold + `font-feature-settings: 'tnum' 1`. "오늘 남은 칼로리" 등 핵심 수치는 `number-large` 클래스.

### 7.5 컴포넌트 (`design-system/ui_kits/ios_app/Components.jsx`)
- **Button** (primary/secondary/ghost) — radius 14, press `scale(0.97)`, focus ring `rgba(255,138,91,0.12)`
- **Chip** — `radius-pill`, 선택형 카드용 `--warm-200` 보더
- **MealChip** — meal_slot별 색 도트 + 시간 라벨 (예: `점심 · 12:40`)
- **Card / Card elevated** — `--surface`, 보더 `--hairline`, shadow-sm/md, radius 14~20
- **Ring** (칼로리 원형 진행) — `.6s ease` stroke-dashoffset
- **ProgressBar** — 목표 대비 바, 남은 퍼센트 내부 라벨
- **TabBar** — 반투명 크림 + `backdrop-filter: blur(14px)`, 가운데 FAB(카메라) 돌출
- **FoodieBubble** — 푸디 얼굴 + 코랄 soft 배경(`--coral-50` + `--coral-100` 보더) 말풍선

### 7.6 스페이싱·라디우스·섀도
- Spacing: 4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 48 / 64 (`--sp-*`)
- Radius: xs 6 / sm 10 / **md 14 (기본 카드)** / lg 20 / xl 28 / pill 999
- Shadow: xs / sm(카드) / md(elevated) / lg(모달) / **coral(CTA glow)** / leaf — 전부 웜톤 `rgba(58,38,20,...)`

### 7.7 일러스트 & 아이콘
- UI 기능 아이콘: **Lucide 스타일 2px stroke**, `currentColor` 사용 (홈/카메라/차트/사람/시계)
- 무드 일러스트: 손그림 SVG (`assets/illust-strawberry.svg`, `illust-salad.svg`, `illust-rice-bowl.svg`, `illust-namul.svg`, `illust-camera.svg`, `illust-blossom.svg`, `illust-empty-state.svg`)
- 일러스트는 **맥락**에 맞게 사용 (예: 점심 카드=비빔밥, 빈 상태=카메라). 장식용 남용 금지.
- 이모지: 🌸 🥗 🍓 🌱 — 텍스트 내 1~2개/화면.

### 7.8 모션·상태
- 기본 전이: `all 0.15s ease`
- 버튼 press: `scale(0.97)` (색 불변)
- 링 프로그레스: `.6s ease` stroke
- 업로드 → 분석 → 결과 카드 전환: fade + 스켈레톤 (사진·칼로리 자리 유지)
- Hover: 코랄 → `--coral-600`
- Focus: 4px soft ring `rgba(255,138,91,0.12)`
- Disabled: opacity 0.4 + `not-allowed`
- 마스코트 한정 bounce 허용

### 7.9 UX 라이팅 (브랜드 보이스 · README 동일 규칙)
- 홈 인사: "안녕, 지은아 👋"
- 첫 기록 유도: "아직 기록이 없네! 첫 사진 찍어보자"
- 완료 피드백: "기록 완료 ✨ 오늘도 잘하고 있어"
- 과다 안내(부드럽게): "오늘 칼로리가 살짝 많아. 내일은 가볍게 가자"
- 금지: "실패" · "어겼다" · "망쳤다" · "~해주세요" (명령형)

### 7.10 적용 체크리스트 (구현 시 반드시 확인)
- [ ] `design-system/colors_and_type.css`를 전역 토큰으로 로드 (변수 하드코딩 금지)
- [ ] 색 토큰 사용(하드코딩 금지): `meal_slot`(breakfast/lunch/dinner/late_night)은 `--meal-breakfast/lunch/dinner` + 야식=dinner+overlay, `eating_type=snack`은 `--meal-snack`. 앱 · PT 뷰 · 달력 히트맵 모두 **동일 토큰**.
- [ ] AI 메시지는 모두 `FoodieBubble` + "푸디의 한마디" 라벨
- [ ] 에러 레드는 분석/네트워크 실패에만 — 섭취 과다는 `warning` 또는 푸디 제안
- [ ] 숫자는 Gmarket Bold + `tnum`
- [ ] 섀도는 웜톤만 (`rgba(58,38,20,...)`, 블루 그레이 금지)
- [ ] 버튼·카드 radius ≥ 14px

---

## 8. 기술 & AI 아키텍처

### 8.1 스택 결정 요약
| 레이어 | 기술 | 이유 |
|---|---|---|
| 클라이언트 | **Flutter** (Dart) | iOS+Android 단일 코드베이스, 빠른 반복. 카메라는 `image_picker`/`camera` 플러그인으로 충분 |
| 인증 | **Supabase Auth** | 이메일·소셜(Apple/Google) OAuth 원스톱, JWT가 Postgres RLS와 자연 연결 |
| DB | **Supabase Postgres** + RLS | 스키마·정책을 한 곳에서, 무서버 운영 부담 |
| 스토리지 | **Supabase Storage** (S3 호환) | 음식 사진 원본/썸네일, 공유 링크용 공개 경로 지원 |
| 백엔드 로직 | **Supabase Edge Functions** (Deno) | 분석 트리거, LLM 호출, 공유 토큰 생성 등 |
| 실시간/푸시 | Supabase Realtime(DB 변경 구독) + FCM/APNs | 분석 완료 시 홈 화면 즉시 갱신 |
| AI | 외부 멀티모달 LLM API(비전+텍스트) | 품목 분리·끼니/식사종류 추론·코칭 생성 |
| i18n | `intl` + ARB 파일 | MVP는 ko/en 2개 로케일 구성, 추가 로케일 확장 가능 |

**Supabase 프로젝트 키(publishable — 클라이언트 공개 가능)**: `sb_publishable_Lcz1dUKdgrFRPvfp3A-Ttw_U3EFm3bb`
- 클라이언트에 embed 가능하나 **`.env`에만 저장**하고 리포지토리에는 `.env.example`만 커밋.
- 서비스 롤(secret) 키는 **클라이언트에 절대 포함 금지** — Edge Function 환경변수로만 주입.

### 8.2 업로드·분석 파이프라인 (Flutter ↔ Supabase)
1. **Flutter**: 사진 캡처 → **HEIC 우선 / JPEG q80 fallback** 인코딩 → 클라이언트 리사이즈(최대 1600px 긴변) → Supabase Storage `food-photos/{user_id}/{entry_id}.{heic|jpg}` 에 업로드
2. **Flutter**: `entries` 행 `status=pending`으로 INSERT
3. **Postgres 트리거 또는 Edge Function `analyze-entry`**: 새 pending 행 감지 → 서명 URL 생성 → LLM 비전 호출
4. **Edge Function**: 품목 분리 + 끼니/식사종류 + 품목별 kcal·매크로 + 신뢰도 산출
5. **Edge Function**: `entries` 업데이트(`status=done`) + `entry_items` 다중 INSERT
6. **Flutter**: Supabase Realtime 구독으로 홈 카드 자동 갱신 (푸시는 백그라운드 보조)
7. 신뢰도 < 0.65 또는 끼니 경계 시간이면 **푸디 질문 카드** 한 번 노출

### 8.3 코칭 생성 파이프라인
- Edge Function `generate-coach`: trigger는 `entries.status=done` 또는 스케줄(데일리 21:00/주간 일요일 21:00)
- 입력: 프로필 + 오늘/주간 합계 + 최근 correction 이력 + 로케일
- 출력: `coach_messages` INSERT (Structured JSON, §10.2 스키마)
- Flutter는 `coach_messages`를 Realtime 구독 → FoodieBubble로 렌더

### 8.4 오프라인 & 실패 처리
- 네트워크 끊김 시: 사진·entry 로컬 큐(SharedPreferences + 파일) → 복구 시 자동 재업로드
- 업로드 실패/분석 실패: `entries.status = failed` + "다시 분석" CTA. 기록 자체는 사라지지 않음.
- 쿼터/과금 초과: 분석 재시도를 지수 백오프로 제한, 사용자에게는 상태 문구만 노출

### 8.5 Flutter 프로젝트 구조 (`app/`)
```
app/
├─ pubspec.yaml
├─ .env.example / .env (gitignore)
├─ lib/
│  ├─ main.dart                      # 앱 부트, Supabase.initialize
│  ├─ config/
│  │  └─ env.dart                    # flutter_dotenv 로드, 상수
│  ├─ supabase/
│  │  └─ client.dart                 # 싱글턴 SupabaseClient 래퍼
│  ├─ theme/
│  │  └─ foodiet_tokens.dart         # CSS 변수 → Dart ColorTokens/TextStyles
│  ├─ widgets/
│  │  ├─ foodie_bubble.dart          # 푸디 말풍선 컴포넌트
│  │  ├─ meal_chip.dart              # meal_slot 색 토큰 사용
│  │  └─ primary_button.dart
│  ├─ features/
│  │  ├─ onboarding/, home/, camera/, calendar/, insight/, share/
│  │  └─ ...  (체중 추적은 개인용 private 기능으로 v1.1, 냉장고 AI는 v1.2+ 탐색)
│  └─ l10n/                          # ARB 파일 (ko, en — 추가 로케일 확장)
└─ assets/                           # 로고·마스코트·일러스트 (design-system에서 symlink/copy)
```

---

## 9. AI 분류·분석 로직 상세

### 9.1 끼니 분류 결정 트리
```
input: (photo_features, local_time, user_history)
1) local_time → 시간대 후보 P0 = {breakfast|lunch|afternoon_snack|dinner|late_night}
2) photo_features → 플레이팅 스타일, 음식군, 용기(접시/그릇/포장) → P1 가중치
3) user_history → 이 사용자의 최근 7일 이 시간대 평균 끼니 → P2 가중치
4) meal_slot = argmax(P0·w0 + P1·w1 + P2·w2)  (w0=0.5, w1=0.3, w2=0.2 기본)
5) 경계 confidence < 0.65 → 사용자에게 1탭 확인
```

### 9.2 식사/간식 분류
- 품목 벡터 → "main_dish, side, dessert, snack, beverage" 중 주 성분 카테고리 선택
- 주 성분이 `dessert/snack/beverage`이면 → **간식/음료**
- 주 성분이 `main_dish`이고 side가 1개 이상이면 → **식사**
- 사용자 개인 패턴(간식이 평소 200kcal 이하인지 등)으로 임계 조정

### 9.3 영양소 추정
- 품목명 → 내부 식품 DB(한식 중심 커버리지 우선, 편의점·배달 프랜차이즈 포함) 조회
- 사진 내 참조 객체(식기 크기)로 중량 추정, 없으면 품목별 기본 분량 적용
- 신뢰도 = min(품목 분리 정확도, 중량 추정 정확도, DB 매치 정확도)

### 9.4 피드백 루프
- 사용자가 분류/품목/양을 수정할 때마다 이벤트 저장
- 주간 배치로 개인 보정 파라미터 업데이트 (예: 이 사용자는 공기밥을 반만 먹는다)
- 익명화된 집계로 전역 모델 재학습에도 활용(옵트인 필요, 프라이버시 정책 참고)

---

## 10. AI 코칭 전략

### 10.1 입력 컨텍스트 (코치 프롬프트가 받는 정보)
- 사용자 프로필(목표·기한·식이 제한)
- 오늘/이번 주 섭취 합계 및 목표 대비
- 최근 수정 이력(사용자가 자주 바꾸는 분류)
- 시간·컨텍스트(평일/주말, 운동 기록이 있다면)

### 10.2 출력 구조(Structured JSON)
```json
{
  "headline": "탄수 80g 남았어! 저녁은 단백질 위주로 가볼까?",
  "why": "점심에 탄수가 60% 비중이었고, 칼로리는 520 여유 있어.",
  "suggested_next_action": {
    "type": "meal_suggestion",
    "examples": ["닭가슴살 샐러드", "두부조림 + 채소"]
  },
  "warnings": [],
  "tone": "encouraging",
  "persona": "foodie"
}
```

- `persona: "foodie"` 고정 — 프런트는 이 값이 있을 때만 `FoodieBubble` 컴포넌트로 렌더.
- `headline`은 반말·20자 내외 권장. 금지어 필터(실패/어겼다/망쳤다/해주세요) 통과 후에만 노출.

### 10.3 안전·윤리 가드레일
- 섭식장애 징후 감지 키워드(극단 절식, 과도한 감량 속도 요청 등) → 코칭 대신 안내 메시지 + 전문가 상담 안내
- 미성년자는 초기 MVP 대상에서 제외 (약관 명시)
- 의학적 판단 금지 문구 항상 동봉

---

## 11. PT 공유 기능 상세

### 11.1 공유 링크 모델 (범위 축소 · 고정)
- 토큰 기반 서명 URL: `https://foodiet.app/s/{token}` — 토큰은 32바이트 URL-safe, 서버에는 해시만 저장
- 만료: 7일 / 30일 / 무기한 (회원 선택, 기본 30일)
- **공유 범위는 사용자 옵션이 아니라 서비스 고정값** — 데이터 모델 단에서 강제(§13 `share_links.scope_json`).
- 포함: 음식 사진 URL, 촬영 시각, `meal_slot` 배지, 해당 사진의 예상 섭취 kcal, 일자별 kcal 합계, 주간 평균 kcal
- 제외: 품목별 매크로·나트륨·당류, 체중 및 체중 추이, 코치 메시지, 목표/프로필, 본명·연락처·생년월일, 보정 이력(corrections)

### 11.2 PT 뷰 구성(웹뷰)
```
┌─────────────────────────────────────┐
│ 회원 닉네임  · 주간 평균 kcal      │  ← 체중·목표는 노출하지 않음
│ (공유 기간: 2026-04-01 ~ 04-18)     │
├─────────────────────────────────────┤
│ [날짜 탭] 오늘 / 지난 7일 / 지난 30일│
├─────────────────────────────────────┤
│ 04-17(수)  합계: 1,840 kcal         │
│  08:20 🍳 아침  사진 · 420 kcal     │
│  12:45 🍜 점심  사진 · 780 kcal     │
│  19:10 🥗 저녁  사진 · 640 kcal     │
├─────────────────────────────────────┤
│ 04-16(화)  합계: 1,720 kcal … (생략) │
└─────────────────────────────────────┘
```
- 타임라인 카드: 썸네일 + 시각 + `meal_slot` 배지 + `kcal`. **매크로/체중/코치 메시지 영역 자체가 DOM에 렌더되지 않는다.**
- 하단 고정: 인쇄/PDF 저장 버튼(MVP), "메모 남기기"는 v1.1(§15.2)로 분리

### 11.3 프라이버시
- 로그인 없이 열람 가능하되 `noindex, nofollow`, 토큰 추측 불가 길이, 토큰당 분당 60회 레이트리밋
- 회원은 언제든 링크 철회 → `share_links.revoked_at` 기록, 링크 즉시 403
- 공유 이벤트 로그(`share_access_logs` — 열람 시각·IP 국가 단위·UA family)는 회원에게 노출
- PT 뷰 서버(Edge Function `render-share`)는 **RLS 우회 서비스 롤**로 동작하되, 반드시 `share_links.scope_json`에 허용된 컬럼만 SELECT. 매크로·체중·코치 메시지는 SQL 단에서 선택 불가(§13).

### 11.4 공유 취소 시나리오
- 사용자가 "모든 공유 끄기" → 모든 `share_links.revoked_at = now()` 일괄 업데이트, 열람 중인 탭도 다음 요청부터 403
- 계정 삭제 → `share_links`, `share_access_logs`는 30일 보관 후 삭제(감사 목적), 그 외 개인 데이터는 즉시 파기

---

## 12. 알림 & 리텐션

- 기본 푸시: 아침 목표 리마인더(07:30 근방, 사용자 기상시간 학습 후 조정), 데일리 리뷰(저녁), 주간 리포트(일요일 저녁)
- 기록 공백 감지: 평소 사용자 식사 시간대 + 2시간 무기록 → **1회만** 리마인드
- 과용 방지: 하루 3개 이하 푸시 상한, 사용자 설정에서 개별 토글
- 이메일: 주간 리포트만(옵트인)

---

## 13. 데이터 모델 (Supabase Postgres + RLS)

### 13.1 Enum 선언
```sql
create type meal_slot   as enum ('breakfast','lunch','dinner','late_night');
create type eating_type as enum ('meal','snack','beverage');
create type entry_status as enum ('pending','done','failed');
create type coach_scope  as enum ('in_meal','daily','weekly');
```

### 13.2 핵심 테이블 DDL
```sql
-- 사용자는 Supabase Auth의 auth.users를 참조. 앱 전용 프로필 필드만 분리.
create table public.profiles (
  user_id          uuid primary key references auth.users(id) on delete cascade,
  nickname         text not null,
  locale           text not null default 'ko',        -- i18n (ko|en|ja|…)
  unit_energy      text not null default 'kcal',      -- 'kcal' | 'kJ'
  unit_mass        text not null default 'kg',        -- 'kg' | 'lb'
  height_cm        numeric(5,1),
  weight_kg        numeric(5,1),
  goal_weight_kg   numeric(5,1),
  goal_deadline    date,
  activity_level   smallint,                          -- 1(낮음)~5(매우 높음)
  diet_restrictions text[] default '{}',
  daily_kcal_target int,
  macros_target    jsonb,                             -- {carb_g, protein_g, fat_g}
  created_at       timestamptz default now(),
  deleted_at       timestamptz
);

create table public.entries (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  captured_at  timestamptz not null,
  image_path   text not null,                         -- Storage 'food-photos' 버킷 경로
  meal_slot    meal_slot,
  eating_type  eating_type,
  kcal_total   int,
  macros       jsonb,                                 -- {carb_g, protein_g, fat_g, sodium_mg, sugar_g}
  confidence   numeric(3,2),
  source       text check (source in ('camera','gallery')),
  status       entry_status not null default 'pending',
  locale       text,                                  -- 기록 시점 로케일 스냅샷
  created_at   timestamptz default now()
);
create index on public.entries (user_id, captured_at desc);

create table public.entry_items (
  id          uuid primary key default gen_random_uuid(),
  entry_id    uuid not null references public.entries(id) on delete cascade,
  name        text not null,
  qty_g       numeric(7,1),
  kcal        int,
  carb_g      numeric(6,1),
  protein_g   numeric(6,1),
  fat_g       numeric(6,1),
  sodium_mg   int,
  sugar_g     numeric(6,1),
  confidence  numeric(3,2)
);

create table public.corrections (
  id         uuid primary key default gen_random_uuid(),
  entry_id   uuid not null references public.entries(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  field      text not null,                           -- 'meal_slot' | 'eating_type' | 'item.qty' ...
  before_val jsonb,
  after_val  jsonb,
  created_at timestamptz default now()
);

create table public.coach_messages (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  scope      coach_scope not null,
  entry_id   uuid references public.entries(id) on delete set null,
  body_json  jsonb not null,                          -- §10.2 Structured JSON
  created_at timestamptz default now(),
  read_at    timestamptz,
  acted_at   timestamptz
);

create table public.weight_logs (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  logged_at  timestamptz not null,
  weight_kg  numeric(5,1) not null,
  source     text check (source in ('manual','scale_sync'))
);

-- PT 공유 링크: scope_json은 서비스 정책으로 고정(§11.1) — 사용자 수정 불가
create table public.share_links (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  token_hash  text not null unique,                   -- SHA-256(token)
  scope_json  jsonb not null default jsonb_build_object(
                 'photos', true,
                 'kcal_per_entry', true,
                 'kcal_daily_total', true,
                 'kcal_weekly_avg', true,
                 'macros', false,
                 'weight', false,
                 'coach_messages', false
               ),
  expires_at  timestamptz,
  revoked_at  timestamptz,
  created_at  timestamptz default now()
);

-- 서비스 정책 가드: scope_json이 고정값과 다르면 INSERT/UPDATE 거부
create or replace function public.enforce_share_scope() returns trigger language plpgsql as $$
begin
  if new.scope_json <> jsonb_build_object(
       'photos', true,
       'kcal_per_entry', true,
       'kcal_daily_total', true,
       'kcal_weekly_avg', true,
       'macros', false,
       'weight', false,
       'coach_messages', false
     ) then
    raise exception 'share_links.scope_json is fixed by policy';
  end if;
  return new;
end $$;
create trigger trg_share_scope_ins before insert or update on public.share_links
  for each row execute function public.enforce_share_scope();

create table public.share_access_logs (
  id            uuid primary key default gen_random_uuid(),
  share_link_id uuid not null references public.share_links(id) on delete cascade,
  accessed_at   timestamptz default now(),
  country       text,
  ua_family     text
);

create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  kind         text not null,
  scheduled_at timestamptz not null,
  sent_at      timestamptz,
  opened_at    timestamptz
);
```

### 13.3 Storage 버킷
- `food-photos` (private) — 객체 경로 규칙 `{user_id}/{entry_id}.jpg`; 클라이언트는 서명 URL로만 접근
- `share-thumbs` (public, optional) — PT 뷰에서만 쓰는 리사이즈 썸네일. 원본은 여전히 private, 썸네일도 서명 URL 권장
- 업로드 크기 제한: 10MB. 이미지 형식: `image/jpeg`, `image/heic`(iOS)→서버에서 JPEG 변환

### 13.4 RLS 정책 (전 테이블 `enable row level security`)
```sql
alter table public.profiles        enable row level security;
alter table public.entries         enable row level security;
alter table public.entry_items     enable row level security;
alter table public.corrections     enable row level security;
alter table public.coach_messages  enable row level security;
alter table public.weight_logs     enable row level security;
alter table public.share_links     enable row level security;
alter table public.share_access_logs enable row level security;
alter table public.notifications   enable row level security;

-- 본인 행만 SELECT/INSERT/UPDATE/DELETE
create policy "own_profile" on public.profiles
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_entries" on public.entries
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_entry_items" on public.entry_items
  using (exists (select 1 from public.entries e where e.id = entry_id and e.user_id = auth.uid()))
  with check (exists (select 1 from public.entries e where e.id = entry_id and e.user_id = auth.uid()));
create policy "own_corrections" on public.corrections
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_coach_messages" on public.coach_messages
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_weight_logs" on public.weight_logs
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_share_links" on public.share_links
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_share_access_logs_read" on public.share_access_logs
  for select using (exists (
    select 1 from public.share_links s where s.id = share_link_id and s.user_id = auth.uid()
  ));
create policy "own_notifications" on public.notifications
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- PT 뷰는 anon 키로 접근하지 않는다. Edge Function `render-share`가
-- service_role 키로 토큰 검증 → 허용 컬럼만 SELECT → JSON 응답.
```

### 13.5 데이터 일관성 규칙 (중요)
- `entries.meal_slot` enum은 **4값 고정** `breakfast | lunch | dinner | late_night`. 앱·서버·PT 뷰가 동일 enum을 공유.
- `entries.eating_type` enum은 **3값 고정** `meal | snack | beverage`.
  - **두 축을 혼동하지 않는다.** `meal_slot`은 시간대(아침/점심/저녁/야식), `eating_type`은 식사/간식/음료. 예: "저녁 10시에 먹은 라떼" → `meal_slot=late_night`, `eating_type=beverage`.
- UI 컬러 매핑(§7.3)은 이 enum 값을 기준으로 동일한 CSS/Dart 토큰(`--meal-breakfast/lunch/dinner` + `eating_type=snack → --meal-snack`)을 일관되게 참조한다.
- 사용자 수정은 `entries`를 직접 덮어쓰되 `corrections`에 이전값을 스냅샷으로 기록 (감사 추적 + 개인화 모델 시그널).
- 영양소 합계는 `entries.kcal_total / macros`에 원자적 반영. PT 뷰는 `entries.status='done'`의 확정값만 조회 (피드백 지연으로 인한 불일치 방지).
- **PT 공유 컬럼 정책(서버 강제)**: `render-share` Edge Function은 `macros`, `weight_logs.*`, `coach_messages.*`, `profiles.{weight_kg, goal_weight_kg, …}` 컬럼을 **결코 SELECT하지 않는다**. 테스트에서 해당 컬럼이 응답 JSON에 포함되는지 회귀 검증.
- 단위·로케일: `profiles.unit_energy/unit_mass/locale`을 기준으로 렌더 시점에 포맷. 저장은 항상 `kcal` / `kg` / ISO 타임스탬프로 정규화.

---

## 14. KPI / 성공 지표

### 14.1 North Star
**주간 활성 기록자 비율 (W1R)** = (주 3일 이상 사진 기록한 사용자 수) / (MAU)
- 목표: v1.0 론칭 3개월 내 W1R ≥ 40%

### 14.2 보조 지표
- 온보딩 완료율 ≥ 80%
- 첫날 첫 사진 기록률 ≥ 70%
- AI 분류 채택률(분류 미수정 비율) ≥ 85%
- 칼로리 추정 평균 오차 ≤ ±15%
- D7 리텐션 ≥ 35%, D30 ≥ 18%
- PT 공유 링크 활성 보유자 비율 ≥ 25%(PT 받는 사용자 세그먼트 중)
- 코치 메시지 "도움 됐어요" 반응률 ≥ 40%

---

## 15. 로드맵

### 15.1 MVP (0 ~ 3개월)
- F1 사진 기록, F2 자동 분류, F3 영양소 분석, F4 기본 코칭, F5 목표, F6 PT 공유(읽기 전용·사진+kcal만), F7 조회
- **Flutter 단일 코드베이스** → iOS + Android 동시 출시, PT용 웹뷰(Edge Function 렌더)
- **i18n 골격 장착**: `intl` + ARB(`ko`, `en`), 단위(kcal/kJ, kg/lb) 추상화, 로케일별 식품 DB 태그 컬럼
- Supabase 스키마·RLS·Storage·Edge Functions(`analyze-entry`, `generate-coach`, `render-share`)

### 15.2 v1.1 (3 ~ 6개월)
- 체중계 연동(BLE), HealthKit / Google Fit 활동량 연동
- 코치 메시지의 제안 식단을 근처 편의점/배달로 연결
- PT가 회원에게 코멘트 남기기(승인한 경우) — 단, PT 공유 범위는 여전히 "사진 + kcal"으로 유지. 코멘트는 쌤→회원 단방향 텍스트만.
- 로케일 추가: **ja**, **zh-Hans** — 일식/중식 식품 DB 확장

### 15.3 v1.2+ (6 ~ 12개월)
- 챌린지/그룹
- 음식 리뷰 DB 자정(사용자 집단 피드백 기반)
- 글로벌 확장: **en-US/en-GB**, **es**, **de** 추가 — 현지 프랜차이즈·편의점 DB 큐레이션, 단위 기본값 로컬라이즈(미국=kcal/lb, 유럽=kJ/kg)
- 결제·구독(§17) 전개 — Apple/Google + 지역 PG(카카오페이 국내, Stripe 해외)

---

## 16. 리스크 & 완화

| 리스크 | 영향 | 완화 |
|---|---|---|
| AI 분류 오류로 사용자 이탈 | 고 | 경계값에서만 1탭 확인, 수정 사용성 최상으로 |
| 한식/배달 음식 커버리지 부족 | 고 | 초기 DB를 한식·편의점·프랜차이즈 집중 큐레이션 |
| 프라이버시 우려(건강 데이터) | 고 | 공유 링크 토큰 만료 기본값 30일, 앱 내 삭제/엑스포트 제공 |
| 섭식장애 유발 가능성 | 중 | 과도 감량 방지 로직, 미성년자 제한, 언어 가드레일 |
| 공유 링크 유출 | 중 | 토큰 레이트리밋, 열람 로그 회원 공개, 즉시 철회 |
| 푸시 과다로 인한 피로 | 중 | 하루 상한, 토글, 사용자 패턴 학습 |
| 비용(LLM/비전 호출) | 중 | 클라이언트 전처리, 배치·캐시, 신뢰도 높을 땐 경량 모델 |

---

## 17. 수익화 가설 (선택, v1.1 이후 검증)

- **MVP 무료**: 전면 무제한 기록 + 기본 코치 (일일 상한 없음 — §18.1 #14)
- Pro 구독 (v1.1+ 검증, 월 ₩4,900 / 연 ₩39,000 잠정):
  - 주간/월간 심화 인사이트 리포트, PT 공유 장기 기간
  - 코치 심화 조언(주간 플랜 생성, 식단 추천 다양화)
  - 차별화 요소는 Pro 개시 시점에 재확정
- 제휴: 건강 간식·식단 커머스 파트너십 (중립성 유지를 위해 코치 조언에는 광고 포함하지 않음)

---

## 18. 오픈 이슈 / 의사결정 필요

### 18.1 v1.2에서 확정된 항목 (더 이상 오픈 이슈 아님)
1. ~~**네이티브 vs Flutter**~~ → ✅ **Flutter 단일 코드베이스 확정** (§8.1). iOS+Android 동시 출시.
2. ~~**PT 코멘트 기능**~~ → ✅ **MVP 제외, v1.1로 분리** (§15.2). MVP PT 공유는 읽기 전용.
3. ~~**체중 공유**~~ → ✅ **완전 제외 확정**. PT 뷰에 체중 영역 없음, 데이터 모델 단에서 차단(§11.1, §13.4).
4. ~~**디자인 원본**~~ → ✅ **zip 번들 수신·적용 완료** (`design-system/`). §7은 해당 토큰/컴포넌트 기준으로 확정.
5. ~~**해외 확장 시점**~~ → ✅ **MVP부터 i18n 골격 포함**, ja/zh는 v1.1, es/de/en-US는 v1.2+ (§15). 단위(kcal/kJ, kg/lb)·로케일 스냅샷은 `profiles`에 컬럼화(§13.2).
6. ~~**백엔드 선택**~~ → ✅ **Supabase 확정** (Auth/Postgres/Storage/Edge Functions/Realtime). publishable 키 `.env` 관리.
7. ~~**LLM 벤더**~~ → ✅ **OpenAI `gpt-5.4-mini` (Vision)** 확정. Edge Function `analyze-entry`·`generate-coach`에서 호출. `OPENAI_API_KEY`·`OPENAI_MODEL`은 Edge Function 환경변수로만 주입.
8. ~~**Supabase 리전**~~ → ✅ **ap-northeast-2 (Seoul)** 확정. 해외 확장 시 CDN/서명 URL로 지연 보정.
9. ~~**식품 DB 소스**~~ → ✅ **하이브리드** 확정: 식약처 공공 DB 베이스 + 한식·편의점·프랜차이즈 상위 **500개** 자체 큐레이션. 미커버 음식은 LLM 추정(confidence 낮게).
10. ~~**소셜 로그인 조합**~~ → ✅ **Apple + Google + Kakao** 확정. `profiles.locale != 'ko'` 인 경우 UI 단에서 Kakao 버튼 숨김.
11. ~~**푸시 인프라**~~ → ✅ **Firebase Cloud Messaging v1** 확정. Firebase Project `foodiet-4f861`, Bundle `com.jihun.foodiet`. Edge Function `send-push`에서 FCM v1 호출, APNs는 FCM 브리지.
12. ~~**상태 관리**~~ → ✅ **Riverpod 2.x** 확정 (§8.1). Supabase Realtime 스트림과 결합해 테스트 용이.
13. ~~**사진 저장 전략**~~ → ✅ **Supabase Storage(객체)** + DB `entries.image_path` 경로만 저장 확정. 클라이언트 1600px 리사이즈 + **HEIC 우선 / JPEG q80 fallback** (§8.2). bytea/Base64 DB 저장은 용량·CDN·서명 URL 손실로 금지.
14. ~~**일일 상한**~~ → ✅ **MVP 전면 무제한** 확정. 유료화/상한 정책은 Pro 개시 시점(§17)에 재검토.

### 18.2 아직 열린 이슈
_(2026-04-18 업데이트)_ **모든 오픈 이슈가 §18.1로 이동해 확정되었습니다.** 새 이슈가 발견되면 이 섹션을 재활성화합니다.

---

## 부록 A. MVP 화면 리스트 (일관성 체크용)

1. Splash
2. Onboarding 1~3 (가치 제안)
3. Sign-in (Apple/Google/Kakao)
4. Onboarding Survey 1~4 (신체/목표/활동량/식이제한)
5. Permissions (카메라/알림)
6. Home(오늘)
7. Camera
8. Upload Progress Inline
9. Analysis Result Card
10. Correction Sheet (품목/양/끼니/식사유형)
11. Day Detail (타임라인)
12. Calendar (월 히트맵)
13. Insight Weekly/Monthly
14. Coach Message Detail
15. Profile & Goal Edit
16. PT Share Settings (링크/만료/범위)
17. Web PT View (타임라인 + 요약, 읽기 전용)
18. Settings (알림/프라이버시/데이터 내보내기·삭제)
19. Error/Empty States (네트워크/분석실패/빈달력)

## 부록 B. 용어집 (서비스 전체에서 동일하게 사용)

- **기록(entry)**: 사진 1장 단위의 식사 기록 (1장 안에 여러 품목 가능)
- **품목(item)**: 사진 안 개별 음식
- **끼니(meal_slot)**: 아침/점심/저녁/야식
- **식사 종류(eating_type)**: 식사/간식/음료
- **코치 메시지(coach message)**: AI가 생성한 조언 단위. UI에서는 **"푸디의 한마디"** 로 노출.
- **푸디(Foodie)**: 잎사귀 달린 동글동글 딸기 마스코트. 모든 AI 조언의 화자.
- **공유 링크(share link)**: PT 공유용 토큰 URL

---

*본 기획안은 MVP 합의용 초안입니다. §18 오픈 이슈를 확정한 뒤 각 화면의 와이어프레임과 스펙 문서(§6, §8, §13 기반)로 분기해 실행합니다.*
