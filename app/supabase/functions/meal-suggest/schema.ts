// meal-suggest 순수 로직 — 스키마 · 프롬프트 · 서버 후처리.
//
// index.ts(I/O)와 _tests/suggest_probe.ts(실제 Claude 호출)가 같은 것을 import 한다.
// 이 파일은 _shared/claude.ts 를 import 하지 않는다 (모듈 로드시 env/네트워크
// 의존이 없어야 단위 테스트가 순수하게 돈다).
//
// structured outputs 는 minimum/maximum/minItems/maxItems/minLength/maxLength 를
// 지원하지 않는다(400). 개수·범위는 description 으로 안내하고 아래 후처리로 강제한다.

import { unsafeText } from '../_shared/safety.ts';
export const SITUATIONS = [
  'home',
  'convenience',
  'delivery',
  'eating_out',
  'hoesik',
] as const;
export type Situation = typeof SITUATIONS[number];

export type GoalMode = 'lose' | 'maintain' | 'gain';

export function parseSituation(raw: unknown): Situation | null {
  return typeof raw === 'string' && (SITUATIONS as readonly string[]).includes(raw)
    ? raw as Situation
    : null;
}

// ── 금지 어휘 ───────────────────────────────────────────────────────
// 죄책감·도덕 평가·사무적 어휘. 걸리면 해당 문장/옵션을 통째로 버린다.
export const BANNED = ['실패', '어겼다', '망쳤다', '해주세요', '나쁜 음식'];
// 효과 보장 문구 ("3kg 감량", "2키로 빠져", "살 빠지는 음식", "효과 보장").
const EFFICACY_RE = /\d+(\.\d+)?\s*(kg|킬로|키로)\s*(감량|빠|뺄|뺀)/i;
const EFFICACY_WORDS_RE = /살\s*(이\s*)?(쭉\s*|잘\s*|확\s*)?빠(지|져|진|짐|질)|효과\s*보장/;
// 투약·약 이름 언급 (GLP-1 용량·투약 조언 금지 — 음식 추천엔 나올 일이 없다).
const MEDICAL_RE = /투약|주사|위고비|마운자로|오젬픽|삭센다|젭바운드/;

export function hasBanned(text: string): boolean {
  return BANNED.some((b) => text.includes(b)) || EFFICACY_RE.test(text) ||
    EFFICACY_WORDS_RE.test(text) || MEDICAL_RE.test(text) ||
    unsafeText(text); // 굶기·끼니 거르기 권유까지 (공통 필터)
}

// ── 목표 · 모드 ─────────────────────────────────────────────────────
export const DEFAULT_TARGET_KCAL = 1800;

/// 일일 목표에 안전 하한(남 1500 / 여·미입력 1200)을 적용한다.
/// (앱 kcal_calc.dart 의 safeMin 과 동일)
export function effectiveTarget(
  target: number | null | undefined,
  sex: string | null | undefined,
): number {
  const t = typeof target === 'number' && Number.isFinite(target) && target > 0
    ? Math.round(target)
    : DEFAULT_TARGET_KCAL;
  const floor = sex === 'male' ? 1500 : 1200;
  return Math.max(t, floor);
}

/// profiles.goal_mode 를 실효 모드로. 'lose' 인데 목표 체중이 현재보다 무거우면 'gain'.
export function effectiveMode(
  p: {
    goal_mode?: unknown;
    goal_weight_kg?: unknown;
    weight_kg?: unknown;
  } | null | undefined,
): GoalMode {
  const raw = p?.goal_mode;
  const mode: GoalMode = raw === 'maintain' || raw === 'gain' ? raw : 'lose';
  if (mode !== 'lose') return mode;
  const goal = Number(p?.goal_weight_kg);
  const cur = Number(p?.weight_kg);
  if (
    p?.goal_weight_kg != null && p?.weight_kg != null &&
    Number.isFinite(goal) && Number.isFinite(cur) && goal > cur
  ) {
    return 'gain';
  }
  return 'lose';
}

// ── 스키마 ──────────────────────────────────────────────────────────
export const OPTIONS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['intro', 'options'],
  properties: {
    intro: {
      type: 'string',
      description: '푸디 반말 한두 문장. 지금 상황과 남은 칼로리를 짧게 짚는다.',
    },
    options: {
      type: 'array',
      description:
        '정확히 3개. 단, 남은 kcal 이 0 이하면 가벼운 단백질·채소 위주 1~2개만.',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'kcal', 'protein_g', 'carb_g', 'fat_g', 'why', 'tip'],
        properties: {
          name: {
            type: 'string',
            description: '메뉴/조합 이름 (예: "닭가슴살 샐러드 + 삶은 계란"). 30자 이내.',
          },
          kcal: { type: 'integer', description: '1인분 합계 kcal (정수).' },
          protein_g: { type: 'integer', description: '단백질 g (정수).' },
          carb_g: { type: 'integer', description: '탄수화물 g (정수).' },
          fat_g: { type: 'integer', description: '지방 g (정수).' },
          why: { type: 'string', description: '왜 지금 이게 좋은지 1문장 반말.' },
          tip: {
            type: 'string',
            description: '주문·조리·먹는 요령 1문장 반말 (예: 소스는 따로).',
          },
        },
      },
    },
  },
} as const;

export const HOESIK_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['intro', 'before', 'order_tips', 'drink_tips', 'next_day'],
  properties: {
    intro: {
      type: 'string',
      description: '푸디 반말 한두 문장. 회식도 즐기면서 가자는 톤.',
    },
    before: {
      type: 'array',
      items: { type: 'string' },
      description: '회식 가기 전 준비 2~3개, 각 1문장 반말.',
    },
    order_tips: {
      type: 'array',
      items: { type: 'string' },
      description: '메뉴 고르기·먹는 순서 요령 2~4개, 각 1문장 반말.',
    },
    drink_tips: {
      type: 'array',
      items: { type: 'string' },
      description: '술자리 요령 2~3개, 각 1문장 반말. 술을 권하지 않는다.',
    },
    next_day: {
      type: 'array',
      items: { type: 'string' },
      description: '다음 날 회복 2~3개, 각 1문장 반말. 굶기·단식 권유 금지.',
    },
  },
} as const;

// ── 응답 타입 ───────────────────────────────────────────────────────
export type SuggestOption = {
  name: string;
  kcal: number;
  protein_g: number;
  carb_g: number;
  fat_g: number;
  why: string;
  tip: string;
};

export type OptionsResponse = {
  kind: 'options';
  intro: string;
  remaining_kcal: number;
  options: SuggestOption[];
};

export type HoesikResponse = {
  kind: 'hoesik';
  intro: string;
  before: string[];
  order_tips: string[];
  drink_tips: string[];
  next_day: string[];
};

// ── 후처리 ──────────────────────────────────────────────────────────
export const MAX_OPTIONS = 3;
export const MAX_OPTIONS_LIGHT = 2;
export const MAX_HOESIK_ITEMS = 4;

/// 남은 kcal 이 0 이하일 때 intro 로 고정 사용 (굶기 권유 없이, 가볍게 마무리).
export const LIGHT_INTRO =
  '오늘 목표만큼은 챙겨 먹었어. 그래도 배고프면 참지 말고, ' +
  '오늘은 여기까지 가볍게 단백질 위주로 골라보자.';
const DEFAULT_INTRO = '지금 상황에 맞게 몇 가지 골라봤어.';

function str(v: unknown): string {
  return typeof v === 'string' ? v.trim() : '';
}

function nonNegInt(v: unknown): number {
  const n = typeof v === 'number' ? v : Number(v);
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.round(n);
}

export function postprocessOptions(
  raw: unknown,
  remainingKcal: number,
): OptionsResponse {
  const r = (raw && typeof raw === 'object') ? raw as Record<string, unknown> : {};
  const remaining = Math.max(0, Math.round(Number(remainingKcal) || 0));
  const light = remaining <= 0;

  const list = Array.isArray(r.options) ? r.options : [];
  let options: SuggestOption[] = [];
  for (const o of list) {
    if (!o || typeof o !== 'object') continue;
    const m = o as Record<string, unknown>;
    const opt: SuggestOption = {
      name: str(m.name),
      kcal: nonNegInt(m.kcal),
      protein_g: nonNegInt(m.protein_g),
      carb_g: nonNegInt(m.carb_g),
      fat_g: nonNegInt(m.fat_g),
      why: str(m.why),
      tip: str(m.tip),
    };
    if (!opt.name) continue;
    if (hasBanned(`${opt.name} ${opt.why} ${opt.tip}`)) continue;
    options.push(opt);
  }

  if (light) {
    // 목표 도달 이후엔 가장 가벼운 1~2개만 (숫자는 고치지 않고 고르기만 한다).
    options = [...options].sort((a, b) => a.kcal - b.kcal)
      .slice(0, MAX_OPTIONS_LIGHT);
  } else {
    options = options.slice(0, MAX_OPTIONS);
  }

  let intro = str(r.intro);
  if (light) {
    intro = LIGHT_INTRO;
  } else if (!intro || hasBanned(intro)) {
    intro = DEFAULT_INTRO;
  }

  return { kind: 'options', intro, remaining_kcal: remaining, options };
}

const HOESIK_FALLBACK = {
  intro: '회식도 즐기면서, 몇 가지만 챙겨 가자.',
  before: ['출발 전에 삶은 계란이나 두유처럼 단백질 간식 하나 먹고 가자.'],
  order_tips: [
    '구이·수육·두부처럼 단백질 메뉴부터 먼저 집자.',
    '쌈 채소를 넉넉히 곁들이면 천천히 먹게 돼.',
  ],
  drink_tips: ['술 한 잔 마실 때마다 물 한 잔 같이 마시자.'],
  next_day: [
    '다음 날도 평소처럼 끼니 챙기고, 물이랑 채소를 넉넉히 먹자.',
  ],
};

function cleanList(v: unknown, fallback: string[]): string[] {
  const out: string[] = [];
  if (Array.isArray(v)) {
    for (const it of v) {
      const s = str(it);
      if (!s || hasBanned(s)) continue;
      out.push(s);
      if (out.length >= MAX_HOESIK_ITEMS) break;
    }
  }
  return out.length ? out : [...fallback];
}

export function postprocessHoesik(raw: unknown): HoesikResponse {
  const r = (raw && typeof raw === 'object') ? raw as Record<string, unknown> : {};
  let intro = str(r.intro);
  if (!intro || hasBanned(intro)) intro = HOESIK_FALLBACK.intro;
  return {
    kind: 'hoesik',
    intro,
    before: cleanList(r.before, HOESIK_FALLBACK.before),
    order_tips: cleanList(r.order_tips, HOESIK_FALLBACK.order_tips),
    drink_tips: cleanList(r.drink_tips, HOESIK_FALLBACK.drink_tips),
    next_day: cleanList(r.next_day, HOESIK_FALLBACK.next_day),
  };
}

// ── 프롬프트 ────────────────────────────────────────────────────────
export type SuggestContext = {
  situation: Situation;
  nowLabel: string; // 사용자 로컬 'HH:MM'
  target: number; // 하한 적용된 일일 목표
  consumed: number; // 오늘 섭취 kcal (1인분 환산)
  remaining: number; // max(0, target - consumed)
  proteinG: number; // 오늘 섭취 단백질 g
  eatenTitles: string[];
  mode: GoalMode;
  glp1: boolean;
  dietRestrictions: string[];
};

const SITUATION_LABEL: Record<Situation, string> = {
  home: '집 (있는 재료로 간단히 해먹기)',
  convenience: '편의점',
  delivery: '배달',
  eating_out: '외식 (식당)',
  hoesik: '회식',
};

const SITUATION_GUIDE: Record<Situation, string> = {
  home:
    '- 집: 냉장고에 흔히 있는 재료(계란, 두부, 김치, 채소, 밥, 닭가슴살 등)로 15분 안에 만드는 메뉴.',
  convenience:
    '- 편의점: 실제 한국 편의점(CU·GS25·세븐일레븐 등)에서 흔히 파는 상품 조합만. ' +
    '예: 삼각김밥, 샐러드, 닭가슴살, 삶은 계란, 두유, 그릭요거트, 컵 샐러드, 바나나, 우유. ' +
    '존재하지 않는 상품명이나 특정 브랜드 신상품명은 지어내지 마.',
  delivery:
    '- 배달: 한국 배달앱에서 흔한 메뉴 중에서 고르고, 주문 옵션 요령(밥 양, 소스 따로, 튀김 대신 구이)을 tip 에.',
  eating_out:
    '- 외식: 한국 식당에서 흔한 메뉴(백반, 국밥, 쌀국수, 포케, 샤브샤브 등) 중 고르고, 먹는 요령을 tip 에.',
  hoesik:
    '- 회식: 메뉴 추천이 아니라 가이드. 고깃집·술자리 기준으로 가기 전 준비, 메뉴·먹는 순서, 술자리 요령, 다음 날 회복.',
};

const MODE_LABEL: Record<GoalMode, string> = {
  lose: '감량 (완만한 적자)',
  maintain: '체중 유지 (목표 = 유지 칼로리, 적자 없음)',
  gain: '증량 (충분히 먹는 것이 목표)',
};

export function buildSystemPrompt(ctx: SuggestContext): string {
  const lines = [
    '당신은 Foodiet 앱의 AI 식단 코치 "푸디"야. 한국어 반말, 친근하고 다정한 톤.',
    '사용자가 "지금 뭐 먹지?"를 물었어. 지금 상황에서 바로 고를 수 있는 현실적인 선택지를 제안해.',
    '',
    '반드시 지킬 규칙:',
    '- "실패", "어겼다", "망쳤다", "해주세요", "나쁜 음식" 같은 죄책감·평가·사무적 어휘 금지. 음식에 좋고 나쁨 딱지 붙이지 마.',
    '- 적게 먹는 것을 칭찬하지 마. 굶기·끼니 거르기·단식을 절대 권하지 마.',
    '- 하루 섭취 하한(남성 1500 kcal, 여성·미입력 1200 kcal) 아래로 먹으라는 제안 금지.',
    '- 남은 kcal 이 0 이하면: 굶으라고 하지 말고, 배고플 때 먹을 가벼운 단백질·채소 1~2개만 제안하고 "오늘은 여기까지 가볍게" 느낌으로 마무리.',
    '- 남은 kcal 이 적으면 그 안에 들어오는 가벼운 단백질 위주로. 여유가 있으면 각 옵션 kcal 은 남은 kcal 이내로.',
    '- 효과 보장 문구("○kg 감량", "살 빠지는 음식") 금지. 의료·치료 조언 금지.',
    '- kcal·탄단지는 1인분 현실적인 추정치로. 모르면 보수적으로.',
    '- 이모지는 쓰지 마. 각 문장은 짧게.',
    '',
    '상황별 기준:',
    SITUATION_GUIDE[ctx.situation],
  ];
  if (ctx.mode === 'maintain') {
    lines.push('- 사용자는 체중 유지 중이야. 목표는 유지 칼로리 — 줄이라고 하지 마.');
  } else if (ctx.mode === 'gain') {
    lines.push('- 사용자는 증량 목표야. 충분한 에너지와 단백질을 챙기는 쪽으로.');
  }
  if (ctx.glp1) {
    lines.push(
      '- 사용자는 GLP-1 계열 약을 쓰고 있어. 적은 양이어도 단백질과 수분을 우선으로, ' +
        '부담 없이 소량으로 먹기 좋은 메뉴로. 투약·용량·부작용 관련 말은 절대 하지 마.',
    );
  }
  lines.push('', '응답은 JSON 스키마에만 엄격히 맞춰.');
  return lines.join('\n');
}

export function buildUserPrompt(ctx: SuggestContext): string {
  const remainingLine = ctx.remaining <= 0
    ? `남은 0 kcal (오늘 목표만큼 이미 먹었어)`
    : `남은 ${ctx.remaining} kcal`;
  const eaten = ctx.eatenTitles.length
    ? ctx.eatenTitles.map((t) => `  - ${t}`).join('\n')
    : '  (아직 기록 없음)';
  const ask = ctx.situation === 'hoesik'
    ? '오늘 회식이 있어. 회식 가이드를 JSON 으로 줘.'
    : (ctx.remaining <= 0
      ? '지금 배고플 때 먹을 가벼운 선택지 1~2개를 JSON 으로 줘.'
      : '지금 먹을 선택지 3개를 JSON 으로 줘. 오늘 먹은 것과 겹치지 않게, 부족한 영양을 채우는 쪽으로.');
  return `[상황]
${SITUATION_LABEL[ctx.situation]}

[현재 시각]
${ctx.nowLabel} (사용자 로컬)

[목표]
모드: ${MODE_LABEL[ctx.mode]}
일일 목표: ${ctx.target} kcal
식단 제약: ${ctx.dietRestrictions.length ? ctx.dietRestrictions.join(', ') : '없음'}

[오늘 섭취]
${eaten}
합계 ${ctx.consumed} kcal · 단백질 ${Math.round(ctx.proteinG)}g
${remainingLine}

[요청]
${ask}`;
}
