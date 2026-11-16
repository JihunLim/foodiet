# 다이어트 콘텐츠·기능 확장 설계 (2026-11-16)

## 의도와 이유

foodiet 는 "먹은 뒤 사진 기록"은 강하지만 ① 먹기 전 판단("지금 뭐 먹지?"), ② 왜 그렇게 먹었고 다음엔 뭘 바꿀지에 답하는 콘텐츠가 비어 있다. 이미 수집하지만 쓰지 않는 데이터(eating_type, 나트륨·당, 품목별 영양, in_meal 확인 메시지, weekly 범위, macros_target)와 기존 파이프라인(analyze-entry, home-coach, 식단추천, 로컬 알림, 공유 카드)을 이어서 식사 조절을 돕는다. 소유자가 고른 범위: 추천안 1·2·3·4·6·7·8번 + GLP-1 투약 기록/일정 관리.

## 목표 / 비목표 / 반목표

- 목표: 기록 직후 개인화 피드백, 계획→실행 연결, 패턴 인식, 주간 회고 습관, 먹기 전 선택 지원, 짧은 교육, 체중 변동 불안 완화, GLP-1 사용자 투약 일정 관리. 새 콘텐츠의 열람·행동을 측정.
- 비목표: 스트릭/프리즈(5번), 그룹 챌린지(9번), 영양성분표 OCR(10번), 배고픔·기분 태그(12번), 품목 단위 자유 수정 UI, 분석 완료 서버 푸시, 다국어.
- 반목표 (기술적으로 돌아가도 실패로 본다):
  - 죄책감·도덕적 평가 문구("나쁜 음식", "망쳤다"), 적게 먹은 것을 칭찬.
  - 일일 목표 하한(남 1500 / 여·미입력 1200 kcal) 아래를 권장하는 제안·목표.
  - 투약 용량 증감·놓친 투약 처리 등 의료 조언. 효과 보장 문구("○kg 감량").
  - 홈 화면을 카드로 다시 비대하게 만드는 것(6be390d 에서 의도적으로 줄였다). 물 카드 재부착.
  - 구버전 앱을 깨뜨리는 스키마 변경.

## 제약

- Flutter(Riverpod, go_router) + Supabase. UI 문구는 한국어 하드코딩(기존 관례). 푸디 반말 톤.
- LLM: `_shared/claude.ts` 의 `claudeJson` (claude-opus-5-5, effort low). structured outputs 는 min/max/minItems/maxLength 미지원 → description + 서버 후처리로 범위 강제.
- 라이브 DB 는 커밋된 마이그레이션과 드리프트가 있다(entries.title/note/shared_with_count 존재). 새 마이그레이션은 additive + `if not exists`.
- entries RLS 는 `own_entries`(ALL, user_id = auth.uid()) — 클라이언트가 kcal_total/macros/entry_items 를 직접 UPDATE 가능. entries 트리거 없음. image_path 는 NOT NULL 유지.
- 구버전 앱이 같은 함수·테이블을 계속 쓴다. analyze-entry 는 피드백 생성 실패와 무관하게 기록을 done 처리해야 한다.
- 운영 반영(마이그레이션 적용·함수 배포)은 별도 승인. 순서: 마이그레이션 → 함수 → 앱 릴리스.
- 로컬 알림 ID 100~102 는 끼니 리마인더 사용 중 → 새 알림은 200번대.

## 접근 방식 (검토한 대안)

| 결정 | 선택 | 대안과 버린 이유 |
|---|---|---|
| 사진 없는 기록 | `image_path = ''` + `source` 에 `meal_plan`·`suggestion` 추가, `Entry.hasPhoto` | NOT NULL 해제 → 구버전 앱 `as String` 캐스트에서 크래시 |
| 한 끼 피드백 생성 | analyze-entry 같은 Vision 호출의 응답 스키마 확장, `entries.feedback jsonb` | 별도 함수 호출 → 지연·비용 2배 |
| 분석 완료 알림 | 앱 사용 중 인앱 스낵바 | 끼니마다 서버 푸시 → 피로, 설정 인프라 필요 |
| 주간 체크인 생성 | 온디맨드(카드/화면 진입 시 생성) + 일요일 20시 로컬 알림 | pg_cron 일괄 생성 → 안 여는 사용자에게도 LLM 비용 |
| 레슨 저장 | DB `lessons` + `lesson_reads` (앱 릴리스 없이 갱신·열람 측정) | 앱 번들 JSON → 측정 불가·갱신에 릴리스 필요 |
| 측정 | `app_events` insert-only 테이블 + 얇은 Dart 서비스 | Firebase Analytics 도입 → 의존성·동의 범위 확대 |

## 기능 설계

### F1. 한 끼 피드백 + 1탭 보정 (추천 1번)
- analyze-entry: 사용자 컨텍스트(일일 목표 kcal, 이번 끼니 이전 오늘 섭취 kcal, 목표 모드, GLP-1 사용 여부)를 user 프롬프트에 추가. 응답에 `feedback` 객체 추가:
  `{ headline(≤20자), good(1문장, 잘한 점), next(1문장, 다음에 더하거나 바꿔볼 것 — 금지·평가 금지), check: { kind: 'none'|'portion'|'rice'|'soup'|'sauce', question, options:[{label, kcal_factor, sodium_factor}] } }`.
  서버 후처리: factor 를 [0.2, 1.3] 로 clamp, options 2~4개로 자르기, kind='none' 이면 options 비움, 금지어 필터.
- `entries.feedback jsonb` 저장. 피드백 파싱 실패 → feedback 없이 done (구버전 호환).
- 기존 저신뢰/경계시간 `coach_messages(in_meal)` INSERT 는 유지(무해).
- 앱: 기록 상세 kcal 카드 아래 `FoodieBubble` (headline/good/next). `check.kind != none` 이고 아직 답 안 했으면 질문 + 옵션 칩. 탭 시: entry `kcal_total`·`macros`(sodium 은 sodium_factor, 나머지 kcal_factor) 와 각 `entry_items` 의 kcal/탄단지(kcal_factor)·sodium(sodium_factor) 를 스케일, `corrections` 에 before/after 기록, `feedback.check.answered = label` 저장. 한 번만 적용(재탭 불가, 수정은 기존 시트).
- 앱 사용 중 pending → done 전환 감지 시 스낵바 "푸디의 조언 도착 ✨ [보기]" → /entry/:id.

### F2. 식단추천 ↔ 홈·기록 (추천 2번)
- 홈 콘텐츠 슬롯(F-Home 참조)에 "오늘의 추천" 칩 행: 이번 주 식단 중 오늘(date_offset = 월0) 끼니, 다음 끼니 강조. 탭 → 기존 MealDetailPage.
- MealDetailPage 하단 "이대로 먹었어" 버튼 → entries INSERT `{source:'meal_plan', status:'done', image_path:'', title, kcal_total, macros{carb_g,protein_g,fat_g}, meal_slot: 식단 slot(snack→현재 시각 추론), eating_type: slot==snack?'snack':'meal', shared_with_count:1}`. 실행취소 스낵바.
- 사진 없는 entry: 타임라인·상세·캘린더·공유 카드·커뮤니티 공유·즐겨찾기에서 플레이스홀더(이모지 타일). 즐겨찾기 추가는 사진 없는 기록에 대해 비활성. 삭제 흐름은 빈 경로면 storage remove 생략.

### F3. 패턴 인사이트 (추천 3번)
- `insight_provider._compute` 확장(순수 함수, 단위 테스트): lateNightDays, weekdayAvgKcal / weekendAvgKcal(기록일 기준), snackBeverageKcalShare(eating_type), avgSodiumMg / avgSugarG(기록일 기준), partialDays(완료 기록 1건 이하인 날).
- 부족일 판정 수정: 완료 기록 2건 이상인 날만 under 로 센다. 1건 이하는 '기록 적은 날'.
- 영양 탭에 "푸디가 찾은 패턴" 카드 — 의미 있는 항목만(예: 야식 ≥2일, 주말-평일 차이 ≥300kcal, 간식·음료 비중 ≥25%, 평균 나트륨 ≥2000mg). 해당 없으면 "아직 뚜렷한 패턴이 없어".
- home-coach: 최근 7일(오늘 제외) 요약 블록(기록일수, 평균 kcal, 야식 일수, 주말/평일, 평균 나트륨, 어제 kcal 대비 목표) + 이번 주 실험(F4) + 목표 모드 + GLP-1 여부 + 오늘 추천 식단 메뉴명을 프롬프트에 추가. 캐시 시그니처에 `날짜|7일요약해시|실험|모드` 포함. 프롬프트 규칙: 과식 다음 날 굶기 권유 금지, 하한 미만 권유 금지.

### F4. 주간 체크인 (추천 4번)
- 테이블 `weekly_checkins(id, user_id, week_start date, report_json jsonb, chosen_experiment text, completed_at, created_at, unique(user_id, week_start))`, RLS own.
- Edge Function `weekly-checkin` (JWT 사용자): 직전 7일 entries + weight_logs + 지난 체크인 실험 → `{ emoji, headline, wins[1~2], pattern, experiments[3]{if_then, why}, note }`. 같은 week_start 이미 있으면 캐시 반환. 기록 2일 미만이면 LLM 없이 결정적 "기록이 쌓이면 돌아볼게" 응답.
- week_start = 체크인이 다루는 주의 월요일(로컬). 일요일 17시 이후 ~ 다음 주 수요일까지 홈 슬롯에 "이번 주 돌아보기" 노출(완료 전).
- 화면 `/weekly-checkin`: 요약 → 실험 3개 중 1개 선택(또는 직접 입력) → 완료. 공유 버튼: 오프스크린 카드 PNG → 공유 시트(DailyShareService 패턴).
- 로컬 알림 ID 200, 매주 일요일 20:00 "이번 주 돌아볼까?" (프로필 알림 설정에 토글, 기본 on).
- 선택한 실험은 home-coach 프롬프트로 전달(F3).

### F6. 뭐 먹지 + 상황 모드 (추천 6번)
- Edge Function `meal-suggest` (JWT 사용자): 입력 `{ situation: home|convenience|delivery|eating_out|hoesik, tz_offset_min }`. 서버가 오늘 섭취·목표·GLP-1·모드 조회.
  - 일반 상황 → `{ intro, options[3]{ name, kcal, protein_g, carb_g, fat_g, why, tip } }`. 각 kcal 은 남은 kcal 이내 권장(남은 게 적으면 가벼운 단백질 위주, 굶기 권유 금지).
  - hoesik → `{ intro, before[], order_tips[], drink_tips[], next_day[] }` (가이드 전용, 기록 버튼 없음).
  - 사용자당 하루 10회 제한(coach_messages kind='meal_suggest' 카운트).
- 앱: 홈 kcal 카드에 "뭐 먹지?" 버튼 → 바텀시트(상황 칩 → 결과). 옵션별 "먹었어" → entries INSERT `source:'suggestion'` (F2 와 동일 경로).
- 급찐·명절 회복은 F8(체중 스파이크 설명)과 F3(과식 다음 날 회복 규칙)으로 커버.

### F7. 2분 마이크로 레슨 (추천 7번)
- 테이블 `lessons(id, slug unique, title, summary, body jsonb[블록: {t:'p'|'h'|'tip'|'list', text|items}], tags text[], read_minutes, sources jsonb[{label,url}], sort, published bool)`, RLS: authenticated select where published. `lesson_reads(user_id, lesson_id, read_at, primary key(user_id, lesson_id))`, RLS own.
- 시드 12편(한국어, 반말 아님·푸디 말투 반말 허용): 주제 — 단백질, 식이섬유·채소, 에너지 밀도(같은 양 덜 칼로리), 국물·나트륨과 체중 변동, 야식 대처(if-then), 천천히 먹기, 편의점 조합, 배달 주문 요령, 회식, 체중 변동·추세 읽기, 정체기, 과식 다음 날 회복(자기자비). 출처는 리서치에서 실제 연 자료만. **출시 전 소유자 검토 필수**(published 는 true 로 시드하되 문서에 명시).
- 선택 로직(클라이언트, 순수 함수 테스트): 안 읽은 레슨 중 (home-coach focus 매칭 태그) > (패턴 플래그 매칭 태그) > sort 순. 전부 읽었으면 표시 안 함.
- 노출: 홈 슬롯 "오늘의 2분 읽기" 1장, 기록 상세 pending 배너 아래 1장. 화면 `/lesson/:slug` — 블록 렌더 + 출처 + "의학적 조언이 아니야" 고지. 열면 lesson_reads upsert.
- 레슨 목록: 인사이트 영양 탭 하단 "읽을거리" 링크 → `/lessons`.

### F8. 추세 체중 + 정체기·유지 모드 (추천 8번)
- 순수 함수(테스트): `trendSeries(logs)` — 일 단위 마지막 값 기준 지수이동평균(α=0.25, 7일 근사). `detectSpike(logs, trend)` — 최신 값이 추세보다 ≥1.0kg 높음. `detectPlateau(logs, trend)` — 최근 14일 이상, 로그 ≥5개, 추세 변화 |Δ| < 0.3kg. `needsTargetRecalc(profile.weight at target set ...)` — 단순화: 현재 추세 체중과 목표 계산에 쓴 체중(profiles.weight_kg 갱신 시점 대신 `profiles.target_weight_basis_kg` 신규 컬럼) 차이 ≥2kg.
- 체중 탭: 차트에 추세선, 스파이크 카드("대부분 수분·염분일 가능성, 추세선 기준으로 봐줘"), 정체기 카드(점검 목록: 기록 빠진 끼니, 주말, 음료 → "목표 다시 계산" 버튼), 재계산 제안 카드. 재계산은 기존 `kcal_calc.computeKcalTarget`(하한 포함) 사용 후 profiles 업데이트(`daily_kcal_target`, `target_weight_basis_kg`).
- 유지 모드: `profiles.goal_mode text default 'lose' check in ('lose','maintain')`. 목표 도달 카드에 "유지 모드로 전환" → 유지 칼로리(적자 0, 하한 적용)로 목표 재설정. 프로필 편집에서 되돌리기. home-coach·meal-suggest 가 모드 반영.

### F11. GLP-1 투약 관리
- 테이블 `medication_plans(user_id pk, drug text check in ('wegovy','mounjaro','other'), drug_label text, current_dose_mg numeric, interval_days int default 7, reminder_enabled bool default true, reminder_hour int default 9, active bool default true, updated_at)`, `medication_logs(id, user_id, drug, dose_mg, taken_at timestamptz, site text check in ('abdomen','thigh','arm', null), note text, created_at)`. RLS own.
- 설정(마이) → "GLP-1 투약 관리" 진입(기본 꺼짐). 첫 진입 시 약 선택 + 현재 용량(프리셋: 위고비 0.25/0.5/1.0/1.7/2.4, 마운자로 2.5/5/7.5/10/12.5/15, 직접 입력) + 투약 간격(기본 7일) + 알림 시각.
- 화면 `/medication`: 다음 투약일·D-day(예정일 지남 표시 포함, 처리 조언 없음), "오늘 맞았어" (날짜·시각 변경 가능, 용량 = current_dose 기본, 부위 선택, 메모), 기록 목록(삭제 가능), 용량 변경은 사용자가 직접(계획 편집). 고정 문구: "기록·알림 도구야. 용량 변경이나 투약을 놓쳤을 때는 처방한 의료진의 안내를 따라줘."
- 다음 투약일 = 마지막 taken_at(로컬 날짜) + interval_days (순수 함수 테스트). 기록 없으면 사용자가 지정한 시작일.
- 로컬 알림 ID 201: 다음 투약일 reminder_hour 에 1회(기록/계획 변경 시 재예약).
- 홈: 활성 시 인사말 아래 작은 칩 "💉 다음 투약 D-2" (탭 → /medication). 투약 예정일 당일엔 슬롯 우선순위 최상.
- home-coach·meal-suggest·analyze-entry 프롬프트에 "GLP-1 사용 중 — 소식이어도 단백질·수분 우선, 투약 조언 금지".
- 데이터 내보내기·계정 삭제에 새 테이블 포함.

### F-Home. 홈 콘텐츠 슬롯 (공통)
- 인사말 아래: 작은 칩 행(투약 D-day, 있을 때만).
- AiCoachCard 아래 단일 `HomeContentSlot` — 우선순위 1개만: 투약 당일 > 주간 체크인 대기 > 오늘의 추천 식단(있을 때) > 오늘의 2분 읽기. 추천 식단과 레슨은 한 카드 안 탭/칩 대신 우선순위로 1장.
- kcal 카드: 초과 시 "N kcal 초과" 표시는 범위 밖(비목표) — 대신 "뭐 먹지?" 버튼만 추가.

### F-Measure. 측정
- `app_events(id, user_id, name, props jsonb, created_at)` insert-only RLS(own insert, own select). Dart `AppEvents.log(name, props)` fire-and-forget.
- 이벤트: feedback_viewed, check_answered, plan_logged, suggest_opened, suggest_logged, lesson_opened, checkin_opened, checkin_completed, med_logged, plateau_card_shown, target_recalc.

## 마이그레이션 0017_diet_content.sql
entries.feedback jsonb; entries_source_check 에 meal_plan·suggestion 추가; profiles.goal_mode, profiles.target_weight_basis_kg; weekly_checkins; lessons(+시드 별도 0018_lessons_seed.sql); lesson_reads; medication_plans; medication_logs; app_events. 모두 RLS. 계정 삭제 RPC/함수가 있으면 새 테이블 삭제 추가.

## 검증
- `flutter analyze`, `flutter test` (패턴 집계, 부족일 판정, EMA·스파이크·정체기, 레슨 선택, 다음 투약일, 보정 스케일링).
- `deno check --node-modules-dir=none` 로 변경·신규 함수.
- `_tests/claude_probe` 류 스크립트로 새/변경 스키마를 실제 Claude 에 1회씩 호출(structured outputs 400 은 런타임에서만 드러남).
- 운영 반영은 별도 승인.

## 빌더에게 남긴 것
화면 세부 레이아웃·카피(톤 규칙 준수), 레슨 본문 문장, 차트 추세선 스타일, 위젯 내부 구조.

## 빌더 체크 후 결정 (오케스트레이터 판단)

- `goal_mode` 에 `'gain'` 추가. 서버는 `goal_mode='lose'` 인데 목표 체중 > 현재 체중이면 실효 모드를 'gain' 으로 본다. 정체기 카드는 lose 모드에서만.
- GLP-1 정보의 LLM 전달: `medication_plans.coach_context`(기본 true). 설정 시트에서 "푸디 조언에 GLP-1 사용 여부만 반영" 체크박스로 고지·선택. 투약 기록·용량은 LLM 에 보내지 않는다.
- 계정 삭제는 서버 함수 없이 클라이언트가 새 테이블을 명시 삭제(best-effort). `app_events` 에 본인 delete 정책 추가.
- **출시 전 소유자 몫:** 개인정보처리방침 개정(투약 기록·식이 피드백·app_events 식별 이벤트), 앱스토어 개인정보 라벨, 레슨 원고 검토.
- 레슨 출처: 세션 리서치 결과(스크래치패드 all.json)에 실제로 열람된 URL 만.
