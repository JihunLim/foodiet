# Foodiet iOS UI Kit

5개 핵심 스크린 + 재사용 컴포넌트.

## 파일
- `index.html` — 상단 탭으로 5개 스크린 전환 (브라우저에서 확인)
- `ios-frame.jsx` — iOS 기기 프레임 (Dynamic Island, Home indicator 포함)
- `Components.jsx` — Chip, Button, Icon, Card, ProgressBar, Ring, MealChip, TabBar, FoodieBubble
- `Screens.jsx` — HomeScreen, CameraScreen, WeightScreen, FridgeScreen, OnboardingScreen

## 스크린
| 스크린 | 설명 |
|---|---|
| 홈 | 오늘의 칼로리 링(`1,280/1,500`), 매크로 3종, 푸디 AI 코멘트, 식단 타임라인, 봄 레시피 슬라이더 |
| 카메라 | 촬영 → 1.6초 AI 분석 → 결과 카드(음식명·칼로리·매크로·수정/기록) |
| 몸무게 | 7일 라인차트 + 목표선, 감량 진행도, 오늘 기록 CTA |
| 냉장고 AI | 촬영 사진 + 감지 재료 8개 + 매칭도 순 레시피 3개 |
| 온보딩 | 목표 선택 4종 (다이어트/유지/근육/기록만) |

## 사용
```jsx
import './Components.jsx'  // window에 전역 노출
<Card elevated>...</Card>
<Button variant="primary">기록하기</Button>
<MealChip type="점심" time="12:40" />
<FoodieBubble>단백질 부족해! 두부 어때?</FoodieBubble>
```
