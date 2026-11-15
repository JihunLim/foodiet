// weekly-checkin 순수 로직 — 주 계산·한 주 집계·프롬프트·응답 스키마·후처리.
//
// index.ts(배포 함수)와 _tests/checkin_probe.ts(실제 Claude 진단)가 같은 코드를
// 쓰도록 여기에 모았다. 네트워크·DB 접근 없음 → schema_test.ts 로 단위 테스트.

// ── 상수 ──────────────────────────────────────────────────────────────

/// 체크인을 만들 최소 기록일 수. 이보다 적으면 LLM 없이 결정적 응답.
import { unsafeText } from '../_shared/safety.ts';
export const MIN_DAYS = 2;

/// 금지 어휘 (Global Constraints). 하나라도 들어간 문장은 버린다.
export const BANNED = ['실패', '어겼다', '망쳤다', '해주세요', '나쁜 음식'];

/// 효과 보장("3kg 감량", "5킬로 빠져") 문구.
const EFFICACY_RE = /\d+(?:\.\d+)?\s*(?:kg|킬로)\s*(?:감량|빠|뺄|뺀|줄)/i;


/// LLM 실험이 3개가 안 될 때 채우는 안전한 기본 실험.
export const DEFAULT_EXPERIMENTS: Experiment[] = [
  {
    if_then: '배고프면 물 한 잔 마시고 10분 뒤에 다시 생각하기',
    why: '갈증이랑 허기를 구분하는 데 도움이 돼.',
  },
  {
    if_then: '점심엔 단백질 반찬 하나 더 담기',
    why: '오후에 간식 생각이 덜 날 수 있어.',
  },
  {
    if_then: '국물 요리를 먹으면 국물은 반만 먹기',
    why: '나트륨이 줄면 다음 날 붓기가 덜할 수 있어.',
  },
  {
    if_then: '먹기 전에 사진부터 찍기',
    why: '기록이 쌓이면 다음 주 돌아보기가 더 정확해져.',
  },
];

const FALLBACK_HEADLINE = '한 주 같이 돌아보자';
const FALLBACK_WIN = '이번 주도 기록을 이어갔어';
const FALLBACK_PATTERN = '기록된 날을 기준으로 한 주를 살펴봤어.';
const FALLBACK_EMOJI = '🌿';

// ── 타입 ──────────────────────────────────────────────────────────────

export type Experiment = { if_then: string; why: string };

export type CheckinReport = {
  emoji: string;
  headline: string;
  wins: string[];
  pattern: string;
  experiments: Experiment[];
  note: string;
  /// 서버가 채운다 (LLM 아님). 화면의 "7일 중 N일 기록" 용.
  days_logged?: number;
};

export type EntryRow = {
  captured_at: string;
  kcal_total: number | null;
  shared_with_count?: number | null;
  meal_slot?: string | null;
  eating_type?: string | null;
  macros?: Record<string, unknown> | null;
};

export type DaySummary = {
  date: string; // YYYY-MM-DD (로컬)
  weekday: number; // 0=일 … 6=토
  kcal: number;
  count: number;
};

export type WeekSummary = {
  daysLogged: number;
  perDay: DaySummary[];
  avgKcal: number;
  weekdayAvgKcal: number;
  weekendAvgKcal: number;
  lateNightDays: number;
  snackBeverageShare: number; // 0~1
  avgSodiumMg: number;
  avgProteinG: number;
  avgSugarG: number;
  partialDays: number; // 완료 기록 1건 이하인 기록일
};

// ── 날짜 ──────────────────────────────────────────────────────────────

const DAY_MS = 86_400_000;

function ymd(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/// 체크인이 다루는 주의 월요일(로컬, 'YYYY-MM-DD').
/// 일요일 17시 이후면 이번 주 월요일, 그 외(월~일 17시 전)면 지난 주 월요일.
export function weekStartFor(nowMs: number, tzOffsetMin: number): string {
  const local = new Date(nowMs + tzOffsetMin * 60_000);
  const dow = local.getUTCDay(); // 0=일
  const sinceMonday = (dow + 6) % 7;
  const back = dow === 0 && local.getUTCHours() >= 17
    ? sinceMonday
    : sinceMonday + 7;
  return ymd(new Date(Date.UTC(
    local.getUTCFullYear(),
    local.getUTCMonth(),
    local.getUTCDate() - back,
  )));
}

/// week_start(로컬 월 00:00) ~ 다음 월 00:00 을 UTC ISO 로.
export function weekRangeUtc(
  weekStart: string,
  tzOffsetMin: number,
): { fromIso: string; toIso: string } {
  const from = Date.parse(`${weekStart}T00:00:00Z`) - tzOffsetMin * 60_000;
  return {
    fromIso: new Date(from).toISOString(),
    toIso: new Date(from + 7 * DAY_MS).toISOString(),
  };
}

// ── 집계 ──────────────────────────────────────────────────────────────

function num(v: unknown): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : 0;
}

/// done entries → 한 주 요약. 공유 식사는 1인분 환산, 날짜는 로컬 기준.
/// 범위 밖 entry 는 무시한다.
export function summarizeWeek(
  entries: EntryRow[],
  tzOffsetMin: number,
  weekStart: string,
): WeekSummary {
  const { fromIso, toIso } = weekRangeUtc(weekStart, tzOffsetMin);
  const from = Date.parse(fromIso);
  const to = Date.parse(toIso);

  type Acc = DaySummary & {
    sodium: number;
    protein: number;
    sugar: number;
    lateNight: boolean;
  };
  const days = new Map<string, Acc>();
  let totalKcal = 0;
  let snackKcal = 0;

  for (const e of entries) {
    const t = Date.parse(e.captured_at);
    if (!Number.isFinite(t) || t < from || t >= to) continue;
    const local = new Date(t + tzOffsetMin * 60_000);
    const key = ymd(local);
    const share = Math.max(1, num(e.shared_with_count) || 1);
    const kcal = num(e.kcal_total) / share;
    const m = e.macros ?? {};
    const acc = days.get(key) ?? {
      date: key,
      weekday: local.getUTCDay(),
      kcal: 0,
      count: 0,
      sodium: 0,
      protein: 0,
      sugar: 0,
      lateNight: false,
    };
    acc.kcal += kcal;
    acc.count += 1;
    acc.sodium += num(m.sodium_mg) / share;
    acc.protein += num(m.protein_g) / share;
    acc.sugar += num(m.sugar_g) / share;
    if (e.meal_slot === 'late_night') acc.lateNight = true;
    days.set(key, acc);
    totalKcal += kcal;
    if (e.eating_type === 'snack' || e.eating_type === 'beverage') {
      snackKcal += kcal;
    }
  }

  const list = [...days.values()].sort((a, b) => a.date.localeCompare(b.date));
  const n = list.length;
  const avg = (xs: number[]) =>
    xs.length === 0 ? 0 : Math.round(xs.reduce((s, x) => s + x, 0) / xs.length);
  const isWeekend = (d: Acc) => d.weekday === 0 || d.weekday === 6;

  return {
    daysLogged: n,
    perDay: list.map((d) => ({
      date: d.date,
      weekday: d.weekday,
      kcal: Math.round(d.kcal),
      count: d.count,
    })),
    avgKcal: avg(list.map((d) => d.kcal)),
    weekdayAvgKcal: avg(list.filter((d) => !isWeekend(d)).map((d) => d.kcal)),
    weekendAvgKcal: avg(list.filter(isWeekend).map((d) => d.kcal)),
    lateNightDays: list.filter((d) => d.lateNight).length,
    snackBeverageShare: totalKcal > 0 ? snackKcal / totalKcal : 0,
    avgSodiumMg: avg(list.map((d) => d.sodium)),
    avgProteinG: avg(list.map((d) => d.protein)),
    avgSugarG: avg(list.map((d) => d.sugar)),
    partialDays: list.filter((d) => d.count <= 1).length,
  };
}

/// 기록이 부족한 주 — LLM 없이 고정 응답 (저장하지 않는다).
export function insufficientBody(weekStart: string, daysLogged: number) {
  return {
    insufficient: true,
    week_start: weekStart,
    days_logged: daysLogged,
    headline: '기록이 쌓이면 같이 돌아보자',
    report: null,
    chosen_experiment: null,
    completed_at: null,
  };
}

// ── 프롬프트 ──────────────────────────────────────────────────────────

export type PromptContext = {
  nickname: string;
  targetKcal: number;
  floorKcal: number; // 남 1500 / 여·미입력 1200
  mode: 'lose' | 'maintain' | 'gain';
  glp1: boolean;
  prevExperiment: string | null;
  weekStart: string;
  summary: WeekSummary;
  weight: { first: number; last: number; count: number } | null;
};

const MODE_LABEL = { lose: '감량', maintain: '유지', gain: '증량' } as const;
const WEEKDAY_KO = ['일', '월', '화', '수', '목', '금', '토'];

export const SYSTEM_PROMPT = `당신은 Foodiet 앱의 AI 식단 코치 "푸디"야.
사용자의 지난 한 주 식사 기록을 같이 돌아보고, 다음 주에 해볼 작은 실험을 제안해.
한국어 반말, 따뜻하고 담백하게.

반드시 지킬 규칙:
- 다음 어휘는 절대 쓰지 마: "실패", "어겼다", "망쳤다", "해주세요", "나쁜 음식". 음식이나 사람을 도덕적으로 평가하지 마.
- 적게 먹은 걸 칭찬하지 마. 칭찬은 기록·규칙성·단백질/채소 챙기기 같은 행동에만.
- 굶기, 끼니 거르기, 단식, 과식한 다음 날 덜 먹어서 만회하기를 제안하지 마.
- 하루 섭취 하한(사용자 데이터의 [하한])보다 적게 먹도록 이끄는 제안 금지.
- "○kg 감량" 같은 효과 보장·수치 약속 금지.
- 의료·약물 조언 금지. GLP-1 사용 중이어도 용량·투약 시점·놓친 투약 얘기는 하지 말고, 단백질·수분 챙기기 정도만.
- 데이터에 있는 사실만 말해. 기록된 날이 적으면 "기록된 날 기준"이라고 조심스럽게 말하고 단정하지 마.
- experiments 는 정확히 3개. 각각 "~하면 ~하기" 꼴의 작고 구체적인 if-then 행동 하나. 이번 주 패턴과 연결된 것 위주로.
- 지난 주 실험이 있으면 그중 하나는 이어가거나 살짝 바꾼 버전이어도 좋아.
- 이모지는 emoji 필드에만. 다른 필드엔 넣지 마.
- 응답은 JSON 스키마에만 엄격히 맞춰.`;

export function buildUserPrompt(c: PromptContext): string {
  const s = c.summary;
  const dayLines = s.perDay.length === 0
    ? '  (기록 없음)'
    : s.perDay
      .map((d) =>
        `  - ${d.date}(${WEEKDAY_KO[d.weekday]}) ${d.kcal} kcal · ${d.count}건`
      )
      .join('\n');
  const weightLine = c.weight && c.weight.count >= 2
    ? `${c.weight.first}kg → ${c.weight.last}kg (${c.weight.count}회 기록)`
    : c.weight && c.weight.count === 1
    ? `${c.weight.last}kg (1회 기록)`
    : '기록 없음';
  return `[프로필]
닉네임: ${c.nickname}
일일 목표: ${c.targetKcal} kcal
[하한]: ${c.floorKcal} kcal (이보다 적게 먹으라는 제안 금지)
모드: ${MODE_LABEL[c.mode]}
GLP-1: ${c.glp1 ? '사용 중 (투약 조언 금지, 단백질·수분 우선)' : '해당 없음'}

[돌아볼 주] ${c.weekStart}(월) 부터 7일
기록한 날: ${s.daysLogged}일 / 7일
날짜별:
${dayLines}

[요약 — 기록된 날 기준]
평균 ${s.avgKcal} kcal · 평일 평균 ${s.weekdayAvgKcal} · 주말 평균 ${s.weekendAvgKcal}
야식 있는 날: ${s.lateNightDays}일
간식·음료 비중: ${Math.round(s.snackBeverageShare * 100)}%
평균 단백질 ${s.avgProteinG}g · 평균 나트륨 ${s.avgSodiumMg}mg · 평균 당 ${s.avgSugarG}g
한 끼만 기록한 날: ${s.partialDays}일 (이 날은 기록이 빠졌을 수 있어 — 적게 먹었다고 단정 금지)

[체중] ${weightLine}
[지난 주 실험] ${c.prevExperiment ?? '없음'}

이 데이터로 JSON 을 만들어:
- emoji: 한 주 분위기 이모지 1개
- headline: 20자 이내 반말 한 줄
- wins: 잘한 점 1~2개 (행동 중심, 각 1문장)
- pattern: 눈에 띄는 패턴 1~2문장 (평가 없이 관찰만)
- experiments: 다음 주 실험 정확히 3개 {if_then, why}
- note: 응원 한 문장`;
}

// ── 응답 스키마 (min/max 류 키워드 금지 → description + 후처리) ──────────

export const RESPONSE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['emoji', 'headline', 'wins', 'pattern', 'experiments', 'note'],
  properties: {
    emoji: { type: 'string', description: '한 주 분위기 이모지 1개.' },
    headline: {
      type: 'string',
      description: '20자 이내 반말 한 줄 요약. 긍정적이되 과장 없이.',
    },
    wins: {
      type: 'array',
      items: { type: 'string' },
      description: '잘한 점 1~2개. 각 1문장 반말. 적게 먹은 것 칭찬 금지.',
    },
    pattern: {
      type: 'string',
      description: '눈에 띄는 패턴 1~2문장. 평가·비난 없이 관찰만.',
    },
    experiments: {
      type: 'array',
      description: '다음 주에 해볼 실험 정확히 3개.',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['if_then', 'why'],
        properties: {
          if_then: {
            type: 'string',
            description: '"~하면 ~하기" 꼴의 작은 행동 1개. 40자 이내 반말.',
          },
          why: { type: 'string', description: '이유 1문장 반말.' },
        },
      },
    },
    note: { type: 'string', description: '응원 한 문장 반말.' },
  },
} as const;

// ── 후처리 ────────────────────────────────────────────────────────────

function isUnsafe(s: string): boolean {
  // 공통 필터(금지어·효과 보장·굶기 권유·투약) + 체크인 전용 효과 문구.
  return unsafeText(s) || EFFICACY_RE.test(s);
}

/// 지난 주 실험(사용자가 직접 쓴 문구일 수 있음) → 프롬프트에 넣어도 되는 형태.
/// 프롬프트가 "이어가도 좋다" 고 하므로, 굶기·금지어 등이 든 문구는 아예 빼서
/// 모델이 되풀이하지 않게 한다. 120자로 자른다.
export function safePrevExperiment(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const t = v.trim();
  if (!t || isUnsafe(t)) return null;
  const chars = [...t];
  return chars.length > 120 ? chars.slice(0, 120).join('') : t;
}

/// 문자열이고 비어 있지 않고 안전하면 trim + 길이 제한, 아니면 null.
function safeText(v: unknown, maxChars: number): string | null {
  if (typeof v !== 'string') return null;
  const t = v.trim();
  if (!t || isUnsafe(t)) return null;
  const chars = [...t];
  return chars.length > maxChars ? chars.slice(0, maxChars).join('') : t;
}

/// LLM 응답 → 화면에 그대로 써도 되는 리포트. 어떤 모양이 와도 예외 없음.
///   * 금지어·효과 보장·굶기 권유가 든 문장은 버리고 기본값으로.
///   * headline ≤20자, wins 1~2개, experiments 정확히 3개.
export function postProcessReport(raw: unknown): CheckinReport {
  const r = (raw && typeof raw === 'object' ? raw : {}) as Record<
    string,
    unknown
  >;

  const emojiRaw = typeof r.emoji === 'string' ? r.emoji.trim() : '';
  // 글자(한글·영문 등)가 섞이면 이모지가 아니다 → 기본값.
  const emoji = emojiRaw && [...emojiRaw].length <= 4 && !/\p{L}/u.test(emojiRaw)
    ? emojiRaw
    : FALLBACK_EMOJI;

  const wins = (Array.isArray(r.wins) ? r.wins : [])
    .map((w) => safeText(w, 80))
    .filter((w): w is string => w !== null)
    .slice(0, 2);
  if (wins.length === 0) wins.push(FALLBACK_WIN);

  const experiments: Experiment[] = [];
  for (const x of Array.isArray(r.experiments) ? r.experiments : []) {
    if (experiments.length >= 3) break;
    if (!x || typeof x !== 'object') continue;
    const o = x as Record<string, unknown>;
    const ifThen = safeText(o.if_then, 60);
    if (!ifThen) continue;
    // why 만 위험하면 실험 자체를 버린다 (이유가 굶기 등이면 실험도 의심).
    const whyOk = o.why === undefined || o.why === null ||
      (typeof o.why === 'string' && !isUnsafe(o.why));
    if (!whyOk) continue;
    if (experiments.some((e) => e.if_then === ifThen)) continue;
    experiments.push({ if_then: ifThen, why: safeText(o.why, 80) ?? '' });
  }
  for (const d of DEFAULT_EXPERIMENTS) {
    if (experiments.length >= 3) break;
    if (!experiments.some((e) => e.if_then === d.if_then)) experiments.push(d);
  }

  return {
    emoji,
    headline: safeText(r.headline, 20) ?? FALLBACK_HEADLINE,
    wins,
    pattern: safeText(r.pattern, 160) ?? FALLBACK_PATTERN,
    experiments,
    note: safeText(r.note, 100) ?? '',
  };
}
