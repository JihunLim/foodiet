# foodiet — Flutter 앱 스캐폴드

foodiet MVP(v1.2)의 클라이언트 뼈대입니다. 디자인 토큰·푸디 버블·Meal chip·Supabase 초기화·i18n 스켈레톤이 포함되어 있어, `flutter run` 시 바로 프리뷰 화면이 뜹니다.

## 폴더 구조

```
app/
├─ pubspec.yaml              # supabase_flutter, intl, image_picker, flutter_dotenv 등
├─ .env.example              # 실제 .env 는 gitignore. publishable 키만 보관
├─ .gitignore
├─ lib/
│  ├─ main.dart              # 부트스트랩 + 프리뷰 화면
│  ├─ config/env.dart        # .env 래퍼
│  ├─ supabase/client.dart   # Supabase 싱글턴
│  ├─ theme/foodiet_tokens.dart  # CSS → Dart 토큰 포트 (color/shape/text)
│  ├─ widgets/
│  │  ├─ foodie_bubble.dart   # 모든 AI 메시지 전용 (§4.4)
│  │  ├─ meal_chip.dart       # meal_slot / eating_type 두 축
│  │  └─ primary_button.dart
│  ├─ features/              # onboarding, home, camera, share … (TBD)
│  └─ l10n/
│     ├─ app_ko.arb           # 기본 로케일
│     └─ app_en.arb           # 해외 확장 기준점
├─ assets/
│  ├─ fonts/                 # GmarketSans {Light, Medium, Bold}.woff
│  └─ illust/                # design-system 일러스트 복사본
└─ supabase/
   ├─ migrations/
   │  └─ 0001_init.sql       # §13 스키마 + RLS + share_links scope 트리거
   └─ functions/
      ├─ analyze-entry/      # LLM 비전 분석 (§8.2)
      ├─ generate-coach/     # 푸디의 한마디 (§8.3)
      └─ render-share/       # PT 공유 웹뷰 (§11) — 사진+kcal만 노출
```

## 시작 전에

1. `cp .env.example .env` 후 `SUPABASE_URL`을 실제 프로젝트 URL로 교체.
2. 자산 복사:
   ```
   cp ../design-system/fonts/GmarketSans*.woff assets/fonts/
   cp ../design-system/assets/*.svg assets/illust/
   ```
3. Flutter 버전: `>=3.19`.

## 실행

```
flutter pub get
flutter gen-l10n          # ARB → AppLocalizations 생성
flutter run
```

프리뷰 화면(`lib/main.dart`)은 3가지를 한눈에 보여줍니다.
- 푸디의 한마디(`FoodieBubble`) — 라벨·headline·why·CTA
- `MealSlotChip`(시간대 축) vs `EatingTypeChip`(식사 종류 축) 구분
- Primary CTA 버튼

## Supabase 배포

```
# Supabase CLI 로그인 후
supabase link --project-ref <YOUR_PROJECT_REF>
supabase db push                                # 0001_init.sql 적용
supabase functions deploy analyze-entry
supabase functions deploy generate-coach
supabase functions deploy render-share
```

Storage 버킷 `food-photos` (private) 를 대시보드에서 생성.

## 정책 상 반드시 지켜야 할 것

- **PT 공유 응답에는 macros/weight/coach 필드가 절대 포함되지 않는다.** `render-share/index.ts` 의 SELECT 컬럼 화이트리스트가 1차 방어, `share_links.scope_json` 트리거가 2차 방어.
- **service_role 키는 클라이언트 `.env` 에 절대 넣지 않는다.** publishable 키만 허용.
- **디자인 토큰은 `colors_and_type.css` 를 원본으로 삼는다.** Dart 토큰이 바뀌면 CSS도 같이 수정해야 한다.
- **meal_slot 과 eating_type 두 축을 혼동하지 않는다.** UI 색·DB 컬럼·ARB 키 모두 분리되어 있다.
