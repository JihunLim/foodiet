// home-coach 의 순수 로직 — 7일 요약·실효 모드·오늘 식단·프롬프트·캐시 시그니처.
//
// DB/네트워크/env 에 의존하지 않는다 (단위 테스트·probe 가 그대로 import).
// 테스트: supabase/functions/_tests/home_coach_context_test.ts
// probe : supabase/functions/_tests/home_coach_probe.ts

// §7.9 — 금지어. 어떤 출력 필드에도 등장하면 안전 문구로 대체한다.
export const BANNED = ['실패', '어겼다', '망쳤다', '해주세요', '나쁜 음식'];

export const RESPONSE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['emoji', 'headline', 'review', 'next_tip', 'focus'],
  properties: {
    emoji: {
      type: 'string',
      description: '오늘의 분위기 이모지 1개.',
    },
    headline: {
      type: 'string',
      description: '15자 내외 반말, 긍정/격려. 20자 초과 금지.',
    },
    review: {
      type: 'string',
      description: '지금까지 먹은 음식에 대한 2~3문장 긍정 코멘트.',
    },
    next_tip: {
      type: 'string',
      description: '현재 시각 기준 다음 식사/간식 1~2문장 구체 가이드.',
    },
    focus: {
      type: 'string',
      description: '지금 신경쓰면 좋을 영양소 1~2단어 (예: 단백질, 식이섬유).',
    },
  },
} as const;

export type CoachResult = {
  emoji: string;
  headline: string;
  review: string;
  next_tip: string;
  focus: string;
};

export type GoalMode = 'lose' | 'maintain' | 'gain';

// ── 날짜 유틸 (모두 사용자 로컬 'YYYY-MM-DD' 키 기준) ─────────────────

function keyOf(d: Date): string {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function parseKey(key: string): Date {
  return new Date(`${key}T00:00:00Z`);
}

/// UTC ISO 시각 → 사용자 로컬 날짜 키.
export function localDateKey(iso: string, tzOffsetMin: number): string {
  return keyOf(new Date(new Date(iso).getTime() + tzOffsetMin * 60_000));
}

/// 현재 시각의 로컬 날짜 키.
export function todayKeyFor(nowMs: number, tzOffsetMin: number): string {
  return keyOf(new Date(nowMs + tzOffsetMin * 60_000));
}

export function shiftDateKey(key: string, days: number): string {
  const d = parseKey(key);
  d.setUTCDate(d.getUTCDate() + days);
  return keyOf(d);
}

/// 0=월 … 6=일 (식단 date_offset 과 같은 기준).
export function weekdayIndex(key: string): number {
  return (parseKey(key).getUTCDay() + 6) % 7;
}

/// 그 날짜가 속한 주의 월요일 키 (meal_plans.week_start_date 와 같은 규칙).
export function mondayKey(key: string): string {
  return shiftDateKey(key, -weekdayIndex(key));
}

// ── 최근 7일 요약 ────────────────────────────────────────────────────

export type WeekRow = {
  captured_at: string | null;
  kcal_total: number | null;
  macros: Record<string, unknown> | null;
  shared_with_count: number | null;
  meal_slot: string | null;
};

export type WeekSummary = {
  /// 오늘 제외 지난 7일 중 done 기록이 있는 날 수.
  loggedDays: number;
  /// 기록일 기준 하루 평균 kcal (1인분 환산). 기록 없으면 0.
  avgKcal: number;
  /// meal_slot = late_night 기록이 있던 날 수.
  lateNightDays: number;
  /// 평일/주말 기록일 평균. 그 구간 기록이 없으면 null.
  weekdayAvgKcal: number | null;
  weekendAvgKcal: number | null;
  /// 기록일 기준 하루 평균 나트륨(mg).
  avgSodiumMg: number;
  /// 어제 섭취 kcal. 어제 기록이 없으면 null.
  yesterdayKcal: number | null;
};

function num(v: unknown): number {
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : 0;
}

/// 지난 7일(오늘 제외) done 기록을 일 단위로 묶어 요약한다.
/// rows 에 범위 밖(오늘·8일 전) 기록이 섞여 있어도 걸러낸다.
export function summarizeWeek(
  rows: WeekRow[],
  tzOffsetMin: number,
  todayKey: string,
): WeekSummary {
  const from = shiftDateKey(todayKey, -7);
  const yesterday = shiftDateKey(todayKey, -1);
  const days = new Map<string, { kcal: number; sodium: number; late: boolean }>();

  for (const r of rows) {
    if (!r.captured_at) continue;
    const key = localDateKey(r.captured_at, tzOffsetMin);
    if (key < from || key >= todayKey) continue;
    const share = Math.max(1, num(r.shared_with_count) || 1);
    const m = r.macros ?? {};
    const d = days.get(key) ?? { kcal: 0, sodium: 0, late: false };
    d.kcal += num(r.kcal_total) / share;
    d.sodium += num(m.sodium_mg) / share;
    if (r.meal_slot === 'late_night') d.late = true;
    days.set(key, d);
  }

  const avg = (xs: number[]) =>
    xs.length === 0 ? 0 : Math.round(xs.reduce((a, b) => a + b, 0) / xs.length);

  const all = [...days.entries()];
  const weekday = all.filter(([k]) => weekdayIndex(k) < 5).map(([, d]) => d.kcal);
  const weekend = all.filter(([k]) => weekdayIndex(k) >= 5).map(([, d]) => d.kcal);
  const y = days.get(yesterday);

  return {
    loggedDays: all.length,
    avgKcal: avg(all.map(([, d]) => d.kcal)),
    lateNightDays: all.filter(([, d]) => d.late).length,
    weekdayAvgKcal: weekday.length ? avg(weekday) : null,
    weekendAvgKcal: weekend.length ? avg(weekend) : null,
    avgSodiumMg: avg(all.map(([, d]) => d.sodium)),
    yesterdayKcal: y ? Math.round(y.kcal) : null,
  };
}

/// 캐시 시그니처용 짧은 문자열. '|' 를 쓰지 않는다.
export function weekSummaryKey(s: WeekSummary): string {
  return [
    s.loggedDays,
    s.avgKcal,
    s.lateNightDays,
    s.weekdayAvgKcal ?? '-',
    s.weekendAvgKcal ?? '-',
    s.avgSodiumMg,
    s.yesterdayKcal ?? '-',
  ].join('/');
}

// ── 모드·하한 ────────────────────────────────────────────────────────

/// profiles.goal_mode 를 실효 모드로. 'lose' 인데 목표 체중 > 현재 체중이면 'gain'.
/// 알 수 없는 값은 'lose' 로 본다 (0017 전 DB 포함).
export function effectiveMode(
  goalMode: unknown,
  goalWeightKg: unknown,
  weightKg: unknown,
): GoalMode {
  if (goalMode === 'maintain') return 'maintain';
  if (goalMode === 'gain') return 'gain';
  const goal = Number(goalWeightKg);
  const cur = Number(weightKg);
  if (
    goalWeightKg != null && weightKg != null &&
    Number.isFinite(goal) && Number.isFinite(cur) && goal > 0 && cur > 0 &&
    goal > cur
  ) {
    return 'gain';
  }
  return 'lose';
}

/// 일일 섭취 안전 하한 (kcal_calc.dart 의 safeMin 과 동일): 남 1500 / 여·미입력 1200.
export function kcalFloor(sex: unknown): number {
  return sex === 'male' ? 1500 : 1200;
}

// ── 오늘 추천 식단 ───────────────────────────────────────────────────

export type PlanMeal = { slot: string; name: string };

/// meal_plans.plan_json.days 에서 date_offset 이 일치하는 날의 끼니 이름들.
/// 모양이 깨졌으면 빈 배열.
export function todayPlanMeals(planJson: unknown, dateOffset: number): PlanMeal[] {
  if (!planJson || typeof planJson !== 'object') return [];
  const days = (planJson as { days?: unknown }).days;
  if (!Array.isArray(days)) return [];
  const day = days.find((d) =>
    d && typeof d === 'object' &&
    Number((d as { date_offset?: unknown }).date_offset) === dateOffset
  ) as { meals?: unknown } | undefined;
  if (!day || !Array.isArray(day.meals)) return [];
  const out: PlanMeal[] = [];
  for (const m of day.meals) {
    if (!m || typeof m !== 'object') continue;
    const name = (m as { name?: unknown }).name;
    const slot = (m as { slot?: unknown }).slot;
    if (typeof name !== 'string' || name.trim() === '') continue;
    out.push({ slot: typeof slot === 'string' ? slot : 'unknown', name: name.trim() });
  }
  return out;
}

// ── 프롬프트 ─────────────────────────────────────────────────────────

export type CoachContext = {
  nickname: string;
  target: number;
  floor: number;
  goalWeightKg: unknown;
  activityLevel: unknown;
  dietRestrictions: string[];
  nowLabel: string;
  eaten: Array<{ time: string; slot: string; title: string; kcal: number }>;
  kcalConsumed: number;
  remaining: number;
  carb: number;
  protein: number;
  fat: number;
  sodium: number;
  sugar: number;
  week: WeekSummary;
  experiment: string | null;
  mode: GoalMode;
  glp1: boolean;
  planMeals: PlanMeal[];
};

const SLOT_KO: Record<string, string> = {
  breakfast: '아침',
  lunch: '점심',
  dinner: '저녁',
  snack: '간식',
  late_night: '야식',
};

const MODE_KO: Record<GoalMode, string> = {
  lose: '감량 — 하루 목표 안에서 천천히 줄여가는 중',
  maintain: '유지 — 지금 체중을 편하게 지키는 중 (감량 압박 금지)',
  gain: '증량 — 충분히 먹는 게 목표 (적게 먹으라는 말 금지)',
};

export function buildSystemPrompt(floor: number): string {
  return `당신은 Foodiet 앱의 AI 식단 코치 "푸디"입니다.
한국어 반말, 친근하고 긍정적인 톤으로 사용자의 다이어트를 응원하세요.

반드시 지킬 규칙:
- ${BANNED.map((b) => `"${b}"`).join(', ')} 같은 부정/사무적/도덕적 평가 어휘는 금지.
- 적게 먹은 것을 칭찬하지 마. 효과를 보장하는 말("○kg 빠져")도 금지.
- 의료·치료 조언 금지. 일반적인 영양 균형 가이드만.
- 하루 섭취가 ${floor} kcal 아래로 내려가도록 권하지 마 (안전 하한).
- 어제나 최근에 많이 먹었어도 오늘 굶기·끼니 거르기·과한 감량을 권하지 마.
  평소처럼 균형 있게 먹으면 된다는 쪽으로, 자책 없이.
- [최근 7일] 은 흐름 참고용. 기록한 날이 3일 미만이면 패턴을 단정하지 마.
  수치는 평가 없이 사실로만 짧게 언급해도 돼.
- [모드] 를 따라: 유지면 감량 압박 금지, 증량이면 충분히 먹기를 응원.
- [GLP-1] 사용 중이면: 양이 적어도 단백질·수분을 먼저 챙기게 안내.
  투약·용량·부작용·주사 관련 조언은 절대 하지 마.
- [이번 주 실험] 이 있으면 next_tip 에서 자연스러울 때 가끔 가볍게 상기시켜 (매번은 아님).
  단, 실험이 끼니 거르기·굶기·단식이거나 하루 ${floor} kcal 아래로 먹는 내용이면 상기하지 말고
  위 균형 규칙을 따라.
- [오늘 추천 식단] 이 있으면 다음 끼니 가이드에 그 메뉴를 활용해도 좋아.
- 현재 시각(사용자 로컬)을 고려해 다음 가이드를 제안:
  · 아침(06~10): 단백질+탄수 균형, 커피는 식후로.
  · 점심 전(10~13): 점심으로 채소+단백질 추천.
  · 오후(14~17): 당 과다 피하기, 간식이면 견과·과일.
  · 저녁(17~20): 지방 낮고 식이섬유 풍부하게.
  · 야간(21~): 가벼운 수분·단백질 위주, 탄수 자제.
- 응답은 JSON 스키마에만 엄격히 맞춰.
- headline 은 20자 이내. 이모지는 emoji 필드에만 넣고 본문에는 금지.`;
}

function weekBlock(w: WeekSummary, target: number): string {
  if (w.loggedDays === 0) return '최근 7일 기록 없음';
  const lines = [
    `기록한 날 ${w.loggedDays}/7일 · 기록일 평균 ${w.avgKcal} kcal (목표 ${target})`,
    `야식 있던 날 ${w.lateNightDays}일`,
    `평일 평균 ${w.weekdayAvgKcal ?? '-'} kcal · 주말 평균 ${w.weekendAvgKcal ?? '-'} kcal`,
    `평균 나트륨 ${w.avgSodiumMg} mg`,
  ];
  if (w.yesterdayKcal == null) {
    lines.push('어제: 기록 없음');
  } else {
    const diff = w.yesterdayKcal - target;
    const rel = diff === 0 ? '목표와 같음' : `목표 대비 ${diff > 0 ? '+' : ''}${diff}`;
    lines.push(`어제: ${w.yesterdayKcal} kcal (${rel})`);
  }
  return lines.join('\n');
}

export function buildUserPrompt(c: CoachContext): string {
  const restrictions = c.dietRestrictions.length ? c.dietRestrictions.join(', ') : '없음';
  const eatenLines = c.eaten.length === 0
    ? '  (아직 기록 없음)'
    : c.eaten.map((e) => `  - ${e.time} · ${e.slot} · ${e.title} (${e.kcal} kcal)`).join('\n');
  const plan = c.planMeals.length === 0
    ? '없음'
    : c.planMeals.map((m) => `- ${SLOT_KO[m.slot] ?? m.slot}: ${m.name}`).join('\n');

  return `[프로필]
닉네임: ${c.nickname}
일일 목표: ${c.target} kcal (안전 하한 ${c.floor} kcal)
목표 체중: ${c.goalWeightKg ?? '미설정'} kg
활동 수준(1~5): ${c.activityLevel ?? 3}
식단 제약: ${restrictions}

[모드]
${MODE_KO[c.mode]}

[GLP-1]
${c.glp1 ? '사용 중 — 소식이어도 단백질·수분 우선, 투약 관련 조언 금지' : '사용 안 함'}

[현재 시각]
${c.nowLabel} (사용자 로컬)

[오늘 섭취 현황]
먹은 끼니 ${c.eaten.length}건:
${eatenLines}

합계: ${c.kcalConsumed} / ${c.target} kcal (남은 ${c.remaining} kcal)
탄수 ${c.carb.toFixed(0)}g · 단백 ${c.protein.toFixed(0)}g · 지방 ${c.fat.toFixed(0)}g
나트륨 ${Math.round(c.sodium)}mg · 당 ${c.sugar.toFixed(0)}g

[최근 7일]
${weekBlock(c.week, c.target)}

[이번 주 실험]
${c.experiment ?? '없음'}

[오늘 추천 식단]
${plan}

이 데이터를 바탕으로 JSON 으로 응답해:
- emoji: 오늘 분위기 이모지 1개
- headline: 15~20자 반말 요약 한 줄
- review: 지금까지 섭취에 대한 2~3문장 긍정 코멘트 (수치 언급 OK)
- next_tip: 현재 시각에 맞춰 다음 식사/간식 1~2문장 구체 가이드
- focus: 지금 신경쓰면 좋을 영양소 1~2단어`;
}

// ── 캐시 시그니처 ────────────────────────────────────────────────────

export function buildSignature(p: {
  base: string;
  dayKey: string;
  weekKey: string;
  experiment: string | null;
  mode: GoalMode;
  glp1: boolean;
  planCount: number;
}): string {
  const x = (p.experiment ?? '').replaceAll('|', '/');
  return `${p.base}|day:${p.dayKey}|w:${p.weekKey}|x:${x}` +
    `|m:${p.mode}|g:${p.glp1 ? 1 : 0}|pl:${p.planCount}`;
}

// ── 출력 후처리 ──────────────────────────────────────────────────────

const SAFE = {
  headline: '오늘도 같이 가보자',
  review: '오늘 먹은 걸 차근차근 기록하고 있어. 이렇게 쌓이면 나한테 맞는 흐름이 보여.',
  next_tip: '다음 끼니는 단백질이랑 채소를 먼저 챙겨보자.',
};

/// 투약 조언 의심 어휘 — 코치는 GLP-1 투약·용량을 언급하지 않는다.
export const MEDICATION_WORDS = ['투약', '용량', '주사'];

/// headline 최대 길이(코드포인트). 스키마로 강제할 수 없어 서버에서 확인한다.
export const HEADLINE_MAX = 20;

/// 문자열이 아니거나 비었거나 금지어·투약 어휘가 들어가면 true.
function unsafe(s: unknown): boolean {
  if (typeof s !== 'string' || s.trim() === '') return true;
  return BANNED.some((b) => s.includes(b)) ||
    MEDICATION_WORDS.some((w) => s.includes(w));
}

/// 금지어·투약 어휘가 들어간(또는 비어 있는) 필드는 중립 문구로 교체하고,
/// 20자를 넘는 headline 은 중간에서 자르지 않고 안전 문구로 바꾼다.
export function sanitizeResult(r: CoachResult): CoachResult {
  const headline = unsafe(r.headline) || [...r.headline].length > HEADLINE_MAX
    ? SAFE.headline
    : r.headline;
  return {
    emoji: typeof r.emoji === 'string' && r.emoji.trim() !== '' ? r.emoji : '🍓',
    headline,
    review: unsafe(r.review) ? SAFE.review : r.review,
    next_tip: unsafe(r.next_tip) ? SAFE.next_tip : r.next_tip,
    focus: unsafe(r.focus) ? '균형' : r.focus,
  };
}
