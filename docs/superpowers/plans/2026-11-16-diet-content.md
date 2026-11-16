# 다이어트 콘텐츠·기능 확장 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 한 끼 피드백·식단 실행 연결·패턴 인사이트·주간 체크인·뭐 먹지·마이크로 레슨·추세 체중·GLP-1 투약 관리를 기존 파이프라인 위에 추가한다.

**Architecture:** Task 1 이 DB 마이그레이션·공용 모델·이벤트·알림 서비스를 깔고, Task 2~11 은 서로 다른 파일만 건드려 병렬로 구현한다. 공유 파일(홈 화면, 라우터, main.dart)은 Task 12 통합에서만 수정한다. LLM 은 모두 `_shared/claude.ts` 의 `claudeJson`.

**Tech Stack:** Flutter 3.41, Riverpod 2, go_router 14, supabase_flutter 2, flutter_local_notifications 21, Deno Edge Functions, Postgres(Supabase).

**Spec:** `docs/superpowers/specs/2026-11-16-diet-content-design.md`

## Global Constraints

- 작업 디렉토리: `app/` (경로는 모두 `app/` 기준). UI 문구는 한국어 하드코딩, 푸디 반말 톤. 디자인 토큰 `FoodietColors`/`FoodietText`/`FoodietShape`(lib/theme/foodiet_tokens.dart) 사용.
- 금지 어휘(모든 LLM 출력·고정 문구): "실패", "어겼다", "망쳤다", "해주세요", "나쁜 음식". 적게 먹은 걸 칭찬 금지. 효과 보장 문구 금지.
- 일일 kcal 하한: 남 1500 / 여·미입력 1200 (`kcal_calc.dart` 의 safeMin 과 동일). 어떤 제안·목표도 이 하한 아래 권장 금지.
- structured outputs 스키마에 `minimum/maximum/minItems/maxItems/minLength/maxLength` 금지 → description + 서버 후처리.
- 사진 없는 기록: `image_path = ''`, `source in ('meal_plan','suggestion')`. `Entry.hasPhoto == imagePath.isNotEmpty`.
- 로컬 알림 ID: 200 = 주간 체크인, 201 = 투약. (100~102 는 끼니 리마인더)
- GLP-1: 용량 증감·놓친 투약 처리 조언 금지. 고정 문구 `kMedicationDisclaimer` = "기록·알림 도구야. 용량 변경이나 투약을 놓쳤을 때는 처방한 의료진의 안내를 따라줘."
- 병렬 실행 규칙: 각 Task 는 자기 Files 목록만 수정한다. `git commit` 하지 않는다(오케스트레이터가 커밋). analyze 는 `flutter analyze <자기 파일들>`, 테스트는 자기 테스트 파일만.
- 운영 DB·함수 배포 금지(별도 승인). 마이그레이션 파일만 작성.

## Review Focus

1. 구버전 앱/구 데이터: `feedback` 이 null 이거나 `check` 가 없는 entry, 사진 없는(`''`) entry 가 모든 화면(타임라인·상세·캘린더·공유 카드·커뮤니티 공유·즐겨찾기 추가)에서 크래시 없이 플레이스홀더로 보인다. → Task 1 테스트 `entry_from_json_test` + Task 12 수동 점검 목록.
2. 1탭 보정 두 번 탭/네트워크 실패: 두 번째 탭은 무시되고, 실패 시 값이 반쯤 바뀐 채 남지 않는다(entries 먼저, items 다음, 실패 시 스낵바). → Task 3 `applyCheckAnswer` 테스트(이미 answered 면 null 반환).
3. 기록 1~2일뿐인 신규 사용자: 패턴 카드·주간 체크인·정체기 감지가 억지 결론을 내지 않는다. → Task 6 `patterns_sparse` 테스트, Task 8 결정적 응답, Task 10 `plateau_requires_14_days` 테스트.
4. 시간대 경계: 일요일 23시 체크인·자정 직후 투약 기록이 올바른 주/날짜로 계산된다(로컬 날짜 기준). → Task 8 `weekStartFor` 테스트, Task 11 `nextDueDate` 테스트.
5. 남은 kcal 이 0 이하일 때 뭐 먹지: 굶기를 권하지 않고 가벼운 단백질 위주 1~2개 + 하한 문구. → Task 5 서버 후처리 + 프롬프트 규칙, probe 케이스 `remaining=0`.

---

### Task 1: 기반 — 마이그레이션·모델·이벤트·알림 서비스

**Files:**
- Create: `supabase/migrations/0017_diet_content.sql`
- Create: `lib/services/app_events.dart`
- Create: `lib/services/content_notifications.dart`
- Create: `lib/widgets/no_photo_tile.dart`
- Modify: `lib/providers/entries_provider.dart` (Entry: `hasPhoto`, `feedback`, `source`; select 문)
- Modify: `lib/providers/profile_provider.dart` (AppProfile: `goalMode`, `targetWeightBasisKg`; select 문)
- Modify (사진 없음 가드): `lib/features/calendar/calendar_page.dart`, `lib/features/community/community_share_today_page.dart`, `lib/features/entry/entry_detail_page.dart`(사진 영역·삭제·즐겨찾기 메뉴만), `lib/features/home/daily_share_card.dart`, `lib/features/home/home_today_page.dart`(_TimelineRow 썸네일만), `lib/features/insight/insight_page.dart`(썸네일만), `lib/features/profile/profile_page.dart`(삭제 시 storage 경로 필터 + 새 테이블 삭제·내보내기), `lib/providers/favorites_provider.dart`(addFromEntry 가 사진 없음이면 FavoriteException), `lib/services/daily_share_service.dart`
- Test: `test/entry_from_json_test.dart`

**Interfaces:**
- Produces:
  - SQL: `entries.feedback jsonb`; `entries_source_check` = camera|gallery|favorite|meal_plan|suggestion; `profiles.goal_mode text not null default 'lose' check in ('lose','maintain')`; `profiles.target_weight_basis_kg numeric(5,1)`; 테이블 `weekly_checkins`, `lessons`, `lesson_reads`, `medication_plans`, `medication_logs`, `app_events` (컬럼은 spec 그대로). RLS: 사용자 소유 테이블 `using (user_id = auth.uid()) with check (user_id = auth.uid())`; `lessons` 는 `for select to authenticated using (published)`; `app_events` 는 insert/select own 만. 모든 create 는 `if not exists`, 제약 교체는 `drop constraint if exists`.
  - `Entry.hasPhoto` (bool), `Entry.source` (String?), `Entry.feedback` (`MealFeedback?`) — `MealFeedback{headline, good, next, check: FeedbackCheck?}`, `FeedbackCheck{kind, question, options: List<CheckOption{label, kcalFactor, sodiumFactor}>, answered: String?}`, `MealFeedback.fromJson(Map?)` 는 잘못된 형태면 null.
  - `AppProfile.goalMode` (`'lose'|'maintain'`, 기본 'lose'), `AppProfile.targetWeightBasisKg` (double?).
  - `AppEvents.log(String name, [Map<String, Object?> props = const {}])` → `Future<void>`, 실패 무시.
  - `ContentNotifications.instance`: `ensureInit()`, `scheduleWeeklyCheckin({required bool enabled})` (ID 200, 매주 일 20:00 Asia/Seoul, payload `route:/weekly-checkin`), `scheduleMedication(DateTime? dueAtLocal)` (ID 201, null 이면 취소, payload `route:/medication`), `cancelAll()`; `weeklyCheckinEnabled()`/`setWeeklyCheckinEnabled(bool)` (SharedPreferences `content.weeklyCheckin.enabled`, 기본 true). 기존 `MealReminderService` 의 플러그인 초기화 패턴을 따른다.
  - `NoPhotoTile({double size, String? mealSlot, BorderRadius? radius})` — 끼니 이모지(🍳🍱🍽️🌙, 기본 🍽️) 타일.

- [ ] **Step 1: 테스트 작성** `test/entry_from_json_test.dart`
  - `image_path: ''` → `hasPhoto == false`; 경로 있으면 true.
  - `feedback: null` → `entry.feedback == null`.
  - `feedback` 정상 → headline/good/next, `check.options.length == 2`, `kcalFactor == 0.5`.
  - `feedback: {'headline': 3}`(잘못된 타입) → null, 예외 없음.
  - `check.kind == 'none'` → `feedback.check == null`.
- [ ] **Step 2:** `cd app && flutter test test/entry_from_json_test.dart` → FAIL(심볼 없음).
- [ ] **Step 3:** 모델·마이그레이션·서비스·위젯 구현. `_entrySelect` 에 `source, feedback` 추가. 사진 쓰는 각 화면은 `hasPhoto` 가 false 면 `NoPhotoTile`. 삭제 흐름은 빈 경로를 storage remove 목록에서 제외. 계정 삭제는 `weekly_checkins, lesson_reads, medication_logs, medication_plans, app_events` 를 profiles 삭제 전에 delete, 내보내기 JSON 에 weekly_checkins·medication_logs·medication_plans 포함.
- [ ] **Step 4:** `flutter test test/entry_from_json_test.dart` PASS, `flutter analyze` 0 error.
- [ ] **Step 5:** commit `feat(base): 콘텐츠 확장 기반 — 0017 마이그레이션·Entry 피드백·사진 없는 기록·이벤트·콘텐츠 알림`

### Task 2: analyze-entry 한 끼 피드백 (서버)

**Files:**
- Create: `supabase/functions/analyze-entry/schema.ts` (RESPONSE_SCHEMA + `postProcessFeedback`)
- Modify: `supabase/functions/analyze-entry/index.ts`
- Modify: `supabase/functions/_tests/claude_probe.ts` (analyze 스키마를 schema.ts 에서 import)
- Create: `supabase/functions/_tests/feedback_postprocess_test.ts`

**Interfaces:**
- Produces: `entries.feedback` = `{headline, good, next, check:{kind, question, options:[{label, kcal_factor, sodium_factor}]}}` (Task 1 `MealFeedback.fromJson` 이 읽는 형태). `postProcessFeedback(raw: unknown): Feedback | null`.

- [ ] **Step 1:** `feedback_postprocess_test.ts` — factor 5.0 → 1.3, -1 → 0.2 clamp; options 6개 → 4개; kind 'none' → options []; headline 에 금지어 → '오늘도 잘 챙겼어'; 구조 깨짐 → null. `deno test --node-modules-dir=none supabase/functions/_tests/feedback_postprocess_test.ts` FAIL 확인.
- [ ] **Step 2:** schema.ts 작성: 기존 필드 + `feedback`(required). kind enum `none|portion|rice|soup|sauce`. description 으로 "options 2~4개, 기본 옵션 '다 먹었어'(1.0,1.0) 포함, 확신 높으면 kind none".
- [ ] **Step 3:** index.ts: entry 조회 후 profiles(`daily_kcal_target, goal_mode, sex`) + medication_plans(`active`) + 오늘(Asia/Seoul) 이전 done entries kcal 합(1인분 환산) 조회 → user 프롬프트에 `[사용자] 목표 N kcal · 이 끼니 전 오늘 M kcal · 모드 · GLP-1 사용 중 여부`. system 프롬프트에 피드백 규칙(평가·금지 표현 금지, next 는 '더하기/바꿔보기' 1개, GLP-1 이면 단백질·수분 우선, 투약 언급 금지). UPDATE 에 `feedback: postProcessFeedback(result.feedback)`. 사용자 컨텍스트 조회 실패는 무시하고 기본 프롬프트로 진행.
- [ ] **Step 4:** postprocess 테스트 PASS; `deno check --node-modules-dir=none supabase/functions/analyze-entry/index.ts` PASS; `ANTHROPIC_API_KEY=$(cat ~/.config/foodiet/anthropic-key) deno run --allow-net --allow-env --allow-read --node-modules-dir=none supabase/functions/_tests/claude_probe.ts` 의 VISION 단계가 feedback 포함 JSON 반환.
- [ ] **Step 5:** commit `feat(analyze-entry): 한 끼 피드백 + 1탭 보정 질문 생성`

### Task 3: 한 끼 피드백 UI + 1탭 보정 + 완료 스낵바 (클라이언트)

**Files:**
- Create: `lib/services/meal_feedback_service.dart`
- Create: `lib/features/entry/meal_feedback_card.dart`
- Create: `lib/providers/entry_done_notifier.dart`
- Modify: `lib/features/entry/entry_detail_page.dart` (kcal 카드 아래 MealFeedbackCard 삽입. pending 배너 아래 레슨 카드는 Task 12 가 넣는다)
- Test: `test/meal_feedback_service_test.dart`

**Interfaces:**
- Consumes: Task 1 `MealFeedback`, `FeedbackCheck`, `CheckOption`, `AppEvents.log`.
- Produces:
  - `ScaledMeal? applyCheckAnswer({required Map<String,dynamic>? macros, required int? kcalTotal, required List<Map<String,dynamic>> items, required FeedbackCheck check, required CheckOption option})` — 이미 answered 면 null. kcal·carb/protein/fat/sugar 는 kcalFactor, sodium 은 sodiumFactor, kcal 정수 반올림, g 는 소수 1자리.
  - `MealFeedbackService.answer(Entry, CheckOption)` — entries UPDATE(kcal_total, macros, feedback.check.answered) → entry_items 각각 UPDATE → corrections INSERT(field `check:<kind>`, before/after) → `AppEvents.log('check_answered')`.
  - `entryDoneNotifierProvider` — todayEntries 의 pending→done 전환을 감지해 콜백 스트림 제공; Task 12 가 home_shell 에서 구독.
- [ ] Step 1 테스트: factor 0.5 → kcal 600→300, protein 20→10.0, sodium(0.3) 1000→300; answered 있으면 null; items 각각 스케일.
- [ ] Step 2 FAIL 확인 → Step 3 구현(카드: headline/good/next + 질문 칩, 답한 뒤 "반영했어 ✓ (조정됨)") → Step 4 테스트 PASS + analyze → Step 5 commit `feat(entry): 한 끼 피드백 카드·1탭 보정`.

### Task 4: 사진 없는 기록 서비스 + 식단 상세 "이대로 먹었어"

**Files:**
- Create: `lib/services/manual_entry_service.dart`
- Modify: `lib/features/insight/meal_detail_page.dart`
- Create: `lib/features/home/today_plan_strip.dart` (오늘 식단 칩 행 위젯, 홈 삽입은 Task 12)
- Test: `test/manual_entry_service_test.dart`

**Interfaces:**
- Produces:
  - `Map<String,dynamic> buildManualEntryRow({required String id, required String userId, required DateTime now, required String source, required String title, required int kcal, required double carbG, required double proteinG, required double fatG, String? planSlot})` — `image_path:''`, `status:'done'`, `shared_with_count:1`, `meal_slot` = planSlot(breakfast/lunch/dinner) 또는 snack/null 이면 시각 추론(favorites 의 `_inferMealSlot` 과 같은 경계 05/11/16/22 를 공용 함수 `inferMealSlot(DateTime)` 로 추출해 이 파일에 둔다), `eating_type` = planSlot=='snack' ? 'snack':'meal'.
  - `ManualEntryService.record(...)` → entryId; `undo(entryId)`.
  - `TodayPlanStrip()` — thisWeekMealPlanProvider 에서 오늘(date_offset = weekday-1) 끼니 칩, 현재 시각 다음 끼니 강조, 탭 → 기존 MealDetailPage 라우팅 방식. 식단 없으면 `SizedBox.shrink()`.
- [ ] 테스트: plan slot lunch → meal_slot lunch, eating_type meal; snack at 15:00 → meal_slot lunch(경계 11~16) eating_type snack; image_path ''; source 'meal_plan'.
- [ ] 구현: MealDetailPage 하단 "이대로 먹었어 🍽️" → record(source 'meal_plan') → 스낵바 "기록했어 · 실행취소" → `AppEvents.log('plan_logged')`.
- [ ] analyze + 테스트 PASS → commit `feat(meal-plan): 식단 끼니 1탭 기록·오늘의 추천 칩`.

### Task 5: meal-suggest Edge Function (서버)

**Files:**
- Create: `supabase/functions/meal-suggest/index.ts`, `supabase/functions/meal-suggest/schema.ts`
- Create: `supabase/functions/_tests/suggest_probe.ts`

**Interfaces:**
- Request `{situation: 'home'|'convenience'|'delivery'|'eating_out'|'hoesik', tz_offset_min?: number}` + 사용자 JWT(home-coach 의 getUserId 패턴 복사).
- Response 일반: `{kind:'options', intro, remaining_kcal, options:[{name, kcal, protein_g, carb_g, fat_g, why, tip}]}` (서버가 3개로 자르고 kcal 정수화). hoesik: `{kind:'hoesik', intro, before:[], order_tips:[], drink_tips:[], next_day:[]}`. 한도 초과: 429 `{error:'rate_limited'}`. 하루 10회, coach_messages(scope 'daily', body_json.kind 'meal_suggest') 카운트로 집계·기록.
- 규칙(시스템 프롬프트): 남은 kcal 이 0 이하이면 굶기 권유 금지 — 가벼운 단백질/채소 1~2개와 "오늘은 여기까지 가볍게"; GLP-1 이면 단백질·수분 우선; 유지 모드면 목표=유지; 편의점은 실제 한국 편의점에서 살 수 있는 조합; 금지 어휘.
- [ ] `deno check` PASS; `suggest_probe.ts` 로 convenience(remaining 700) / remaining 0 / hoesik 3케이스 실제 호출 → 스키마 JSON. commit `feat(meal-suggest): 뭐 먹지·회식 가이드 함수`.

### Task 6: 패턴 인사이트 (클라이언트)

**Files:**
- Modify: `lib/providers/insight_provider.dart`
- Create: `lib/features/insight/pattern_card.dart`
- Modify: `lib/features/insight/insight_page.dart` (영양 탭에 PatternCard 삽입 + 하단 "읽을거리 📚" 링크 → `/lessons`)
- Test: `test/insight_provider_test.dart` (기존 파일에 추가)

**Interfaces:**
- Produces on `InsightSummary`: `lateNightDays`, `weekdayAvgKcal`, `weekendAvgKcal` (int, 기록일 기준, 없으면 0), `snackBeverageShare` (double 0~1), `avgSodiumMg`, `avgSugarG` (기록일 기준), `partialDays` (완료 기록 ≤1 인 기록일 수), `List<PatternFlag> patternFlags` — `PatternFlag{key, emoji, text}`, key ∈ `late_night`(≥2일), `weekend_gap`(주말-평일 ≥300), `snack_share`(≥0.25), `sodium_high`(≥2000), `partial_days`(≥2). 기록일 <3 이면 빈 리스트.
- 변경: `underDays` 는 완료 기록 ≥2 인 날만.
- [ ] 테스트: `patterns_sparse`(기록 2일 → flags 비어 있음), 야식 2일 → late_night, 한 끼만 기록한 날은 underDays 에 미포함·partialDays 에 포함, 주말 평균 계산.
- [ ] 구현 → 테스트 PASS → commit `feat(insight): 패턴 인사이트·부분 기록일 판정 수정`.

### Task 7: home-coach 맥락 확장 (서버)

**Files:**
- Modify: `supabase/functions/home-coach/index.ts`

**Interfaces:**
- 추가 조회: 지난 7일(오늘 제외) done entries(captured_at, kcal_total, macros, shared_with_count, meal_slot) → 기록일수·평균 kcal·야식 일수·주말/평일 평균·평균 나트륨·어제 kcal; 최신 `weekly_checkins.chosen_experiment`(최근 14일); `profiles.goal_mode`; `medication_plans.active`; 이번 주 `meal_plans` 의 오늘 끼니 이름(plan_json.days[date_offset].meals[].name).
- 프롬프트에 `[최근 7일]`, `[이번 주 실험]`, `[모드]`, `[GLP-1]`, `[오늘 추천 식단]` 블록. 규칙 추가: 어제 많이 먹었어도 오늘 굶기·과한 감량 권유 금지; 하한 미만 권유 금지; GLP-1 투약 조언 금지; 실험이 있으면 next_tip 에서 가끔 상기.
- 캐시 시그니처에 `|day:<로컬 날짜>|w:<7일 요약 문자열>|x:<실험>|m:<모드>|g:<0/1>` 추가.
- [ ] `deno check` PASS, claude_probe home-coach 단계 PASS → commit `feat(home-coach): 7일 패턴·실험·모드·GLP-1 맥락`.

### Task 8: 주간 체크인

**Files:**
- Create: `supabase/functions/weekly-checkin/index.ts`, `supabase/functions/weekly-checkin/schema.ts`
- Create: `lib/providers/weekly_checkin_provider.dart`, `lib/features/checkin/weekly_checkin_page.dart`, `lib/features/checkin/checkin_share_card.dart`
- Test: `test/weekly_checkin_test.dart`, `supabase/functions/_tests/checkin_probe.ts`

**Interfaces:**
- 서버 Request `{tz_offset_min?}`; week_start = 요청 시각 로컬 기준 "직전 완료 주"의 월요일: 일요일 17시 이후면 이번 주 월요일, 그 외(월~일 17시 전)면 지난 주 월요일. 같은 (user, week_start) 행 있으면 그대로 반환. 기록일 <2 → LLM 없이 `{insufficient:true, headline:'기록이 쌓이면 같이 돌아보자'}` (저장 안 함). 응답 `{week_start, report:{emoji, headline, wins:[..2], pattern, experiments:[{if_then, why}x3], note}, chosen_experiment, completed_at}`.
- Dart: `DateTime weekStartFor(DateTime localNow)` (위 규칙), `bool shouldShowCheckinPrompt(DateTime localNow, WeeklyCheckin? existing)` — 일 17시~수 23:59 이고 completed_at 이 null 일 때 true. `weeklyCheckinProvider` (FutureProvider, 함수 호출), `WeeklyCheckinRepo.complete(weekStart, experiment)` → weekly_checkins UPDATE(chosen_experiment, completed_at) + `AppEvents.log('checkin_completed')`.
- 화면 `/weekly-checkin` (라우트 등록은 Task 12): 요약 → 실험 3개 라디오 + 직접 입력 → "이번 주 이걸로 해볼게" → 공유 버튼(CheckinShareCard 를 DailyShareService 의 오프스크린 렌더 방식으로 PNG → share_plus).
- [ ] 테스트: 일 23:00 → 이번 주 월요일; 월 09:00 → 지난 주 월요일; 일 16:59 → 지난 주 월요일; prompt 창 경계(수 23:59 true, 목 00:00 false).
- [ ] deno check + checkin_probe(가짜 7일 데이터) PASS → commit `feat(checkin): 주간 체크인`.

### Task 9: 마이크로 레슨

**Files:**
- Create: `supabase/migrations/0018_lessons_seed.sql` (12편, `on conflict (slug) do update`)
- Create: `lib/providers/lessons_provider.dart`, `lib/features/lessons/lesson_page.dart`, `lib/features/lessons/lessons_list_page.dart`, `lib/features/lessons/lesson_card.dart`, `lib/features/lessons/pending_lesson_card.dart`
- Test: `test/lessons_select_test.dart`

**Interfaces:**
- `Lesson{id, slug, title, summary, blocks: List<LessonBlock{t, text, items}>, tags, readMinutes, sources: List<{label,url}>, sort}`.
- `Lesson? pickLesson({required List<Lesson> all, required Set<String> readIds, String? coachFocus, List<String> patternKeys = const []})` — 미열람 중 tags 가 coachFocus 포함 > patternKeys 매핑 태그 포함 > sort 오름차순. 매핑: late_night→'야식', weekend_gap→'주말', snack_share→'간식', sodium_high→'나트륨', partial_days→'기록'. coachFocus 는 공백 제거 후 태그와 부분 일치.
- `lessonsProvider`, `lessonReadsProvider`, `markLessonRead(lessonId)` (upsert + `AppEvents.log('lesson_opened', {slug})`).
- `LessonCard({Lesson lesson})` 홈 슬롯용; `PendingLessonCard()` 는 pickLesson 결과 1장(없으면 shrink).
- 레슨 주제/태그(spec F7 목록): protein[단백질], fiber[식이섬유,채소], energy-density[포만감,간식], soup-sodium[나트륨,국물,체중변동], late-night[야식], slow-eating[속도], convenience[편의점], delivery[배달], hoesik[회식,술], weight-trend[체중변동,기록], plateau[정체기,기록], after-overeating[과식,주말]. 본문 4~7블록, 2분 분량, 푸디 반말. 출처는 `/private/tmp/claude-502/-Users-jhclaw-Documents-dev-foodiet--claude-worktrees-diet-content-features-0c7a76/90f5ea7f-eba5-4e1a-be9a-5db3134fa2c1/scratchpad/all.json` 의 research findings 에 실제 있는 URL 만. 근거 수준을 넘는 효과 주장 금지(예: 거꾸로 식사법은 혈당 팁 수준). SQL 파일 상단 주석에 "출시 전 소유자 검토 필요".
- 화면: 블록 렌더, 하단 출처 목록(url_launcher), "의학적 조언이 아니야" 문구.
- [ ] 테스트: focus '단백질' → protein; 읽은 건 제외; 전부 읽음 → null; patternKeys late_night → late-night.
- [ ] commit `feat(lessons): 2분 레슨 12편·선택 로직·화면`.

### Task 10: 추세 체중·정체기·유지 모드

**Files:**
- Create: `lib/services/weight_trend.dart`
- Create: `lib/features/insight/weight_trend_cards.dart`
- Modify: `lib/features/insight/weight_insight_page.dart` (차트 추세선, 카드 삽입, 목표 도달 카드에 유지 모드 버튼)
- Modify: `lib/features/profile/profile_edit_page.dart` (유지 모드 ↔ 감량 모드 토글)
- Test: `test/weight_trend_test.dart`

**Interfaces:**
- `List<TrendPoint> trendSeries(List<({DateTime at, double kg})> logs)` — 로컬 날짜별 마지막 값, 정렬, EMA α=0.25(첫 값 그대로). `TrendPoint{date, kg, trendKg}`.
- `bool detectSpike(List<TrendPoint> s)` — 마지막 kg - 마지막 trendKg ≥ 1.0.
- `bool detectPlateau(List<TrendPoint> s, DateTime today)` — 최근 14일 내 점 ≥5, 그 기간 첫/마지막 trendKg 차 < 0.3, 첫 점이 14일 이상 전.
- `bool needsRecalc(double? basisKg, double? latestTrendKg)` — 둘 다 있고 |차| ≥ 2.0.
- `TargetUpdate recalcTarget(AppProfile p, {required double weightKg, required String mode})` — 기존 `computeKcalTarget` 사용, maintain 이면 적자 0(하한 유지) → `{dailyKcal, mode, basisKg}`; 저장은 profiles UPDATE(`daily_kcal_target, goal_mode, target_weight_basis_kg, weight_kg`) + `AppEvents.log('target_recalc')`.
- [ ] 테스트: `plateau_requires_14_days`(10일치 평평 → false), 15일 평평 6점 → true, 스파이크 +1.2 → true, EMA 첫값=원값, needsRecalc 1.9 false / 2.0 true, maintain 목표 ≥ 하한.
- [ ] commit `feat(weight): 추세선·스파이크/정체기 안내·목표 재계산·유지 모드`.

### Task 11: GLP-1 투약 관리 + 설정 연결

**Files:**
- Create: `lib/services/medication_schedule.dart`, `lib/providers/medication_provider.dart`, `lib/features/medication/medication_page.dart`, `lib/features/medication/medication_setup_sheet.dart`, `lib/features/medication/medication_log_sheet.dart`
- Modify: `lib/features/profile/profile_page.dart` (메뉴 "GLP-1 투약 관리 💉" → `/medication`; 알림 설정 시트에 "주간 체크인 알림" 토글 → ContentNotifications)
- Test: `test/medication_schedule_test.dart`

**Interfaces:**
- 상수: `kWegovyDoses = [0.25, 0.5, 1.0, 1.7, 2.4]`, `kMounjaroDoses = [2.5, 5.0, 7.5, 10.0, 12.5, 15.0]`, `kMedicationDisclaimer`(Global Constraints 문구), `drugLabel('wegovy')='위고비'`, `'mounjaro'='마운자로'`.
- `DateTime? nextDueDate({DateTime? lastTakenLocal, required int intervalDays, DateTime? startDateLocal})` — 로컬 날짜(시각 버림) + interval. 기록 없으면 startDate, 둘 다 없으면 null.
- `int? dueInDays(DateTime? due, DateTime todayLocal)` (음수 = 지남), `String dueLabel(int? d)` → 'D-2' / '오늘' / 'N일 지남' / '-'.
- `medicationPlanProvider` (`MedicationPlan?`), `medicationLogsProvider`, `MedicationRepo.savePlan/logDose/deleteLog/setActive` — 저장 후 `ContentNotifications.instance.scheduleMedication(due at reminder_hour)`, `AppEvents.log('med_logged')`.
- 화면: 비활성/미설정이면 소개 + "시작하기"(setup sheet: 약·용량 프리셋/직접 입력·간격·시작일·알림 시각). 활성: D-day 큰 카드, "오늘 맞았어"(log sheet: 날짜시각, 용량 기본=current_dose, 부위 복부/허벅지/팔, 메모), 기록 리스트(스와이프 삭제), "계획 수정", "투약 관리 끄기", 하단 고정 `kMedicationDisclaimer`. 지난 예정일 표시 시에도 조언 문구 없음.
- [ ] 테스트: 2026-11-10 23:30 투약, 7일 → 2026-11-17; 기록 없음+start → start; 둘 다 없음 → null; dueLabel(0)='오늘', (-2)='2일 지남', (3)='D-3'.
- [ ] commit `feat(medication): GLP-1 투약 기록·다음 투약일·알림`.

### Task 12: 통합 (오케스트레이터 직접)

**Files:**
- Create: `lib/features/home/home_content_slot.dart`, `lib/features/suggest/meal_suggest_sheet.dart`, `lib/services/meal_suggest_service.dart`
- Modify: `lib/features/home/home_today_page.dart`, `lib/features/home/home_shell.dart`, `lib/providers/router_provider.dart`, `lib/main.dart`, `lib/features/entry/entry_detail_page.dart`(pending 배너 아래 `PendingLessonCard()`)

- 라우트: `/weekly-checkin`, `/lessons`, `/lesson/:slug`, `/medication`.
- main.dart: `ContentNotifications.instance.ensureInit()` + 부팅 시 주간 체크인 예약 + 알림 탭 payload `route:` 처리(기존 로컬 알림 탭 처리 방식에 맞춤).
- 홈: 인사말 아래 투약 칩(활성일 때만), AiCoachCard 아래 `HomeContentSlot`(우선순위: 투약 당일 > 체크인 프롬프트 > TodayPlanStrip(식단 있을 때) > LessonCard), kcal 카드에 "뭐 먹지?" 버튼 → MealSuggestSheet(상황 칩 → 결과 → "먹었어" = ManualEntryService.record(source 'suggestion'); hoesik 은 가이드만; 429 → "오늘은 여기까지 물어볼 수 있어").
- home_shell: `entryDoneNotifierProvider` 구독 → 스낵바 "푸디의 조언 도착 ✨ [보기]".
- [ ] `flutter analyze` 0 error/warning(신규), `flutter test` 전체 PASS, 모든 함수 `deno check` PASS → commit `feat(home): 콘텐츠 슬롯·뭐 먹지·라우트·알림 연결`.
- [ ] 최종: 브랜치 전체 리뷰 → 수정 → 운영 반영 승인 요청(마이그레이션 0017·0018 → 함수 analyze-entry, home-coach, meal-suggest, weekly-checkin 배포 → 앱 빌드).
