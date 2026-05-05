# Foodiet 디자인 시스템

> 봄의 따뜻한 코랄 × 연두로 그린, 사진 한 장으로 기록하는 다이어트 관리 앱

> ⚠️ **v1.2 범위 안내 (2026-04-18)** — 이 문서의 JSX/HTML 샘플(`ui_kits/ios_app/*`)과 일부 기능 설명(몸무게·냉장고 AI)은 **초기 무드 탐색 산출물**입니다. v1.2부터 클라이언트 구현은 **Flutter 코드베이스 `app/`** 를 정답으로 하고, MVP 기능은 `foodiet_기획안.md §4` 기준(F1~F7)만 포함합니다. PT 공유는 **사진 + kcal만** 공개(체중·매크로·코치 메시지 비공개). 아래 원문은 디자인 토큰/보이스 참조용으로 유지합니다.

## Foodiet 이란?

**Foodiet**는 모바일(iOS+Android, Flutter 단일 코드베이스)에서 동작하는 다이어트 관리 서비스입니다. 핵심 기능:

1. **사진 식단 기록** — 찍기만 하면 시간대별로 아침·점심·저녁·야식 자동 분류(`meal_slot`), 식사/간식/음료 축 분리(`eating_type`), 칼로리 계산, 푸디의 다이어트 조언
2. **목표·진행 추적** — 개인 체중·목표 기록(본인만 열람, PT 공유 대상 아님), 추세 그래프
3. **PT 공유 (읽기 전용)** — 사진 + 예상 섭취 칼로리만 포함한 공유 링크
4. (v1.2+ 탐색) **AI 요리 추천** — 냉장고 재료 기반 추천. MVP 범위 아님.

### 디자인 방향

**봄 느낌의 따뜻하고 친근한 다이어트 앱.**
"오늘 뭐 먹었어?" 같이 친구처럼 말 거는 반말 톤, 둥글둥글한 손그림 일러스트, 파스텔 코랄·연두·버터옐로·라벤더로 물든 파스텔 그라데이션. **마스코트는 '푸디(Foodie)'** — 잎사귀가 달린 동글동글 딸기 캐릭터.

### 제공된 자원
- **코드베이스**: 없음 (컨셉 프로젝트)
- **Figma**: 없음
- **참고**: 스프링 무드보드 키워드 (딸기/나물/쑥, 코랄+연두, 손그림)

---

## 📑 파일 인덱스

| 파일 | 설명 |
|---|---|
| `README.md` | 이 문서 — 시스템 전체 가이드 |
| `SKILL.md` | Agent SKill 포맷 — Claude Code에서도 사용 가능 |
| `colors_and_type.css` | CSS 변수 (컬러/타입/스페이싱/섀도/그라데이션) |
| `fonts/` | Gmarket Sans (Light/Medium/Bold woff) |
| `assets/` | 로고, 마스코트, 손그림 일러스트(SVG) |
| `preview/` | Design System 탭용 카드 (21개) |
| `ui_kits/ios_app/` | iOS 앱 UI 킷 — 5개 스크린 |

## 🎨 디자인 시스템 카드 (preview/)

Design System 탭에서 볼 수 있는 카드들:
- **Type** — `type-scale.html`, `type-numbers.html`
- **Colors** — `colors-coral.html`, `colors-leaf.html`, `colors-neutral.html`, `colors-meals.html`, `colors-semantic.html`, `colors-gradients.html`
- **Spacing** — `spacing-scale.html`, `spacing-radius.html`, `spacing-shadow.html`
- **Components** — `comp-buttons.html`, `comp-chips.html`, `comp-meal-cards.html`, `comp-input.html`, `comp-progress.html`, `comp-tabbar.html`, `comp-ai-bubble.html`
- **Brand** — `brand-logo.html`, `brand-illustrations.html`, `brand-icons.html`

---

## ✍️ CONTENT FUNDAMENTALS (카피 톤)

### 말투 규칙
- **친근한 반말** — "오늘 뭐 먹었어?", "사진만 찍으면 돼", "목표까지 4.4kg 남았어"
- **'너' 대신 이름 부르기** — "지은아 👋" / "오늘도 고생했어"
- **수치는 쉽게** — "220kcal 남았어!" (O) / "잔여 칼로리: 220kcal" (X)
- **명령형 자제** — "기록해주세요" 대신 "기록해볼까?", "~해봐"
- **짧고 따뜻한 문장** — 한 화면 한 메시지, 문장당 ~20자

### 푸디(마스코트) 보이스
- AI 조언은 모두 푸디 입으로 전달: "푸디의 한마디"
- 핀잔이나 경고 NO — 제안과 칭찬만
  - ✅ "단백질이 조금 부족해 보여! 두부 어때?"
  - ❌ "단백질 섭취량이 부족합니다. 보충하세요."
- 이모지는 포인트로만 (🌸 🥗 🍓). 남발 금지.

### 예시 문구
- 홈 인사: "안녕, 지은아 👋"
- 빈 상태: "아직 기록이 없네! 첫 사진 찍어보자"
- 완료 피드백: "기록 완료 ✨ 오늘도 잘하고 있어"
- 경고(부드럽게): "오늘 칼로리가 살짝 많아. 내일은 가볍게 가자"

---

## 🎨 VISUAL FOUNDATIONS

### 컬러 시스템
- **Primary 코랄** `#FF8A5B` — CTA, 포인트, 칼로리 숫자
- **Secondary 연두** `#7FB77E` — 성공, 그린/야채 요소, 목표 달성
- **Neutrals 크림-웜톤** `#FFFDFA → #221F1A` — 차가운 그레이 대신 웜톤 `#3E3A31` 사용
- **식사 전용 컬러** — 아침(버터 `#F7D36A`), 점심(코랄 `#FF8A5B`), 저녁(라벤더 `#8B6FB3`), 간식(그린 `#7FB77E`)
- **봄 악센트** — 딸기 `#F06A7A`, 쑥 `#6B8E5C`, 봄하늘 `#9BC6E3`
- **파스텔 그라데이션**: `--grad-spring` (피치→옐로→연두), `--grad-sunrise`, `--grad-sprout`, `--grad-bloom`

### 타이포그래피
- **Gmarket Sans** 300/500/700 — 둥글둥글한 한글 자소, 브랜드 보이스와 맞음
- 자간은 항상 살짝 좁혀 (`-0.01em` 기본, 헤드라인 `-0.02em`)
- 숫자는 항상 Bold + `'tnum' 1` — 칼로리·몸무게 숫자가 주인공
- 최대 5개 스텝: Display 42 / H1 34 / H2 28 / H3 24 / Body 16 / Caption 12

### 배경
- 기본 배경은 순백 아닌 **크림 `#FFFDFA`**
- 히어로 섹션엔 파스텔 그라데이션 블록
- 풀블리드 이미지는 지양 (사진 카드는 둥근 모서리 컨테이너)
- 반복 패턴 없음 — 여백 + 일러스트 액센트

### 일러스트 & 이미지
- **손그림 느낌 SVG** — 얇은 외곽선(`#3E3A31` 1.2-1.6px), 파스텔 필, 가볍게 비대칭
- 마스코트 푸디는 AI 대화에서만 — 아무데나 배치 안 함
- 일러스트는 "점심 시간" 같은 시간/맥락에 맞게. 장식용으로만 쓰지 않음
- 사진 컨테이너: 둥근 모서리(14-18px), 부드러운 섀도

### 애니메이션
- **부드럽게 fade + slight scale** — 기본 `transition: all 0.15s ease`
- 버튼 press: `scale(0.97)` 즉시
- 링 프로그레스: `.6s ease` stroke-dashoffset
- 바운스는 마스코트 한정

### 상태
- **Hover** (웹) — 코랄은 `coral-600`으로 어둡게
- **Press** — `transform: scale(0.97)`, 색 불변
- **Focus** — 4px soft ring `rgba(255,138,91,0.12)`
- **Disabled** — opacity 0.4 + 커서 not-allowed

### 모서리
- 기본 카드 **14px**
- 큰 카드/시트 **18-20px**
- 버튼 **14px**
- Pill/칩 **999px**

### 섀도
- 항상 **웜톤** — `rgba(58,38,20,0.xx)`, 블루 그레이 금지
- 5단계: xs / sm(카드) / md(elevated) / lg(모달) / coral(CTA glow)

### 보더
- 얇은 크림 헤어라인 `#F4EDE2` — 컨테이너 구분
- 진한 보더 `#E6DDCF` — 입력필드, 선택형 카드

### 레이아웃
- iOS 컨테이너 패딩 **16px** (좌우)
- 카드 내부 패딩 **16-20px**
- 컴포넌트 간 갭 **10-14px**
- 하단 탭바 fixed + FAB 가운데 돌출

### 투명도/블러
- 탭바는 반투명 크림 + `backdrop-filter: blur(14px)`
- 카메라 오버레이는 `rgba(26,17,8,0.55)` 웜톤 어둠 + 블러 2px
- 다른 곳은 불투명 — 블러 남발 금지

---

## 🎨 ICONOGRAPHY

### 접근
- **UI 기능 아이콘**: **Lucide 스타일 2px stroke** (홈/카메라/차트/사람/시계 등)
  - 프로젝트는 인라인 SVG 경로로 직접 구현 (`Components.jsx` 의 `<Icon/>`)
  - 규칙: `stroke-linecap="round"`, `stroke-linejoin="round"`, strokeWidth 2 (active 2.4)
  - 색상은 `currentColor`로 받아서 상황별 변경
- **콘텐츠/무드 아이콘**: **손그림 SVG 일러스트** (`assets/illust-*.svg`)
  - 딸기, 샐러드, 비빔밥, 나물, 카메라, 벚꽃
  - 외곽선 1.2-1.6px + 파스텔 필 조합
- **이모지**: 포인트로만 🌸🥗🍓🌱 — 텍스트 내 1-2개/화면 제한
- **유니코드**: 사용 안 함

### 출처/substitution
- Lucide 아이콘은 **공식 CDN이 아닌 인라인 path 복제** — 라이선스 문제 없음
- 추후 `lucide-react` 패키지로 교체 가능

---

## 📱 UI KIT: ui_kits/ios_app/

5개 핵심 스크린 (상단 탭에서 전환):
1. **홈** — 오늘의 칼로리 링, 매크로, 푸디 코멘트, 식단 타임라인, 봄 레시피
2. **카메라** — 촬영 → AI 분석(1.6초) → 결과 카드 흐름
3. **몸무게** — 7일 라인 차트 + 목표선, 감량 진행 바
4. **냉장고 AI** — 촬영된 재료 태그 + 매칭도 높은 레시피 3개
5. **온보딩** — 목표 선택 (다이어트/유지/근육/기록)

컴포넌트: `Components.jsx` — Chip, Button, Icon, Card, ProgressBar, Ring, MealChip, TabBar, FoodieBubble

---

## ⚠️ 알려진 한계 / 사용자 확인 필요

- **Gmarket Sans**: 공개 CDN(jsdelivr/projectnoonnu)에서 받음. 상용 배포 시 공식 라이선스 확인 필요
- **Lucide 아이콘**: 경로를 직접 복제한 인라인 SVG. MIT 라이선스 내 사용
- **마스코트 '푸디'**: 첫 제안. 더 귀엽게 / 성격 추가 / 다른 동물(병아리·토끼 등)도 옵션
- **실제 음식 사진 없음** — 현재 일러스트로 대체. 실제 스톡/브랜드 포토가 들어가면 더 좋아짐
- **웹/랜딩 페이지는 미포함** — 요청하신 iOS 모바일 앱 중심으로 제작
