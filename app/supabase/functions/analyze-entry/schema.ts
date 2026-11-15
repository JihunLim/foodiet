// analyze-entry 응답 스키마 + 한 끼 피드백 후처리.
//
// index.ts 와 _tests/claude_probe.ts 가 같은 스키마·규칙을 쓰도록 여기 모은다.
// 이 파일은 순수 모듈만 import 한다 (테스트가 env/네트워크 권한 없이 import).
//
// structured outputs 는 minimum/maximum/minItems/maxItems/minLength/maxLength 를
// 지원하지 않는다(400). 범위는 description 으로 알리고 postProcessFeedback 에서 강제한다.

import { unsafeText } from '../_shared/safety.ts';
export const CHECK_KINDS = ['none', 'portion', 'rice', 'soup', 'sauce'] as const;
export type CheckKind = typeof CHECK_KINDS[number];

const FEEDBACK_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['headline', 'good', 'next', 'check'],
  properties: {
    headline: {
      type: 'string',
      description: '이 끼니 한 줄 요약. 한국어 반말, 20자 이내, 이모지 없이. 평가·점수 금지.',
    },
    good: {
      type: 'string',
      description: '이 끼니에서 잘 챙긴 점 1문장(반말). 적게 먹은 것 자체를 칭찬하지 말 것.',
    },
    next: {
      type: 'string',
      description: '다음 끼니에 "더해보거나 바꿔볼" 것 딱 1개, 1문장(반말). 금지·굶기·평가 금지.',
    },
    check: {
      type: 'object',
      additionalProperties: false,
      required: ['kind', 'question', 'options'],
      description: '사진만으로 양이 가장 불확실한 부분을 1탭으로 확인하는 질문. ' +
        '확신이 높으면 kind=none, question="", options=[].',
      properties: {
        kind: {
          type: 'string',
          enum: [...CHECK_KINDS],
          description: 'portion=전체 양, rice=밥 양, soup=국물 섭취, sauce=소스·양념. 확신 높으면 none.',
        },
        question: {
          type: 'string',
          description: '반말 짧은 질문 (예: "밥은 얼마나 먹었어?"). kind=none 이면 빈 문자열.',
        },
        options: {
          type: 'array',
          description: '2~4개. 첫 옵션은 사진 그대로 다 먹은 경우 "다 먹었어"(kcal_factor 1.0, ' +
            'sodium_factor 1.0). kind=none 이면 빈 배열.',
          items: {
            type: 'object',
            additionalProperties: false,
            required: ['label', 'kcal_factor', 'sodium_factor'],
            properties: {
              label: { type: 'string', description: '칩에 들어갈 짧은 반말 (예: "반 공기")' },
              kcal_factor: {
                type: 'number',
                description: '사진 추정 대비 실제 섭취 비율, 0.2~1.3. kcal·탄단지·당에 곱한다.',
              },
              sodium_factor: {
                type: 'number',
                description: '나트륨 비율, 0.2~1.3. 국물을 남겼으면 kcal_factor 보다 더 낮게.',
              },
            },
          },
        },
      },
    },
  },
} as const;

export const RESPONSE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['meal_slot', 'eating_type', 'items', 'totals', 'confidence', 'feedback'],
  properties: {
    meal_slot: {
      type: 'string',
      enum: ['breakfast', 'lunch', 'dinner', 'late_night'],
    },
    eating_type: {
      type: 'string',
      enum: ['meal', 'snack', 'beverage'],
    },
    items: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: [
          'name', 'qty_g', 'kcal',
          'carb_g', 'protein_g', 'fat_g',
          'sodium_mg', 'sugar_g', 'confidence',
        ],
        properties: {
          name: { type: 'string' },
          qty_g: { type: 'number' },
          kcal: { type: 'integer' },
          carb_g: { type: 'number' },
          protein_g: { type: 'number' },
          fat_g: { type: 'number' },
          sodium_mg: { type: 'integer' },
          sugar_g: { type: 'number' },
          confidence: { type: 'number', description: '0~1' },
        },
      },
    },
    totals: {
      type: 'object',
      additionalProperties: false,
      required: ['kcal', 'carb_g', 'protein_g', 'fat_g',
                 'sodium_mg', 'sugar_g'],
      properties: {
        kcal: { type: 'integer' },
        carb_g: { type: 'number' },
        protein_g: { type: 'number' },
        fat_g: { type: 'number' },
        sodium_mg: { type: 'integer' },
        sugar_g: { type: 'number' },
      },
    },
    confidence: { type: 'number', description: '0~1' },
    feedback: FEEDBACK_SCHEMA,
  },
} as const;

export type LlmItem = {
  name: string;
  qty_g: number;
  kcal: number;
  carb_g: number;
  protein_g: number;
  fat_g: number;
  sodium_mg: number;
  sugar_g: number;
  confidence: number;
};

export type LlmResult = {
  meal_slot: 'breakfast' | 'lunch' | 'dinner' | 'late_night';
  eating_type: 'meal' | 'snack' | 'beverage';
  items: LlmItem[];
  totals: {
    kcal: number;
    carb_g: number;
    protein_g: number;
    fat_g: number;
    sodium_mg: number;
    sugar_g: number;
  };
  confidence: number;
  /// 모델 출력 그대로 — 반드시 postProcessFeedback 을 거쳐 저장한다.
  feedback?: unknown;
};

export type FeedbackOption = {
  label: string;
  kcal_factor: number;
  sodium_factor: number;
};

/// entries.feedback 에 저장되는 형태 (Dart MealFeedback.fromJson 이 읽는다).
/// `check.answered` 는 앱이 1탭 보정 후에만 쓴다 — 서버는 내보내지 않는다.
export type Feedback = {
  headline: string;
  good: string;
  next: string;
  check: { kind: CheckKind; question: string; options: FeedbackOption[] };
};

/// 모든 LLM 출력·고정 문구 금지 어휘 (Global Constraints).
export const BANNED = ['실패', '어겼다', '망쳤다', '해주세요', '나쁜 음식'];

export const FEEDBACK_FALLBACK_HEADLINE = '오늘도 잘 챙겼어';
const FALLBACK_GOOD = '이렇게 기록으로 남겨둔 게 제일 든든한 한 걸음이야.';
const FALLBACK_NEXT = '다음 끼니엔 채소나 단백질 반찬 하나를 더해보자.';

export const FACTOR_MIN = 0.2;
export const FACTOR_MAX = 1.3;
const HEADLINE_MAX = 20;
const OPTIONS_MAX = 4;
const OPTIONS_MIN = 2;
const FULL_LABEL = '다 먹었어';

const NO_CHECK = (): Feedback['check'] => ({ kind: 'none', question: '', options: [] });

function hasBanned(s: string): boolean {
  // 금지어 + 효과 보장 + 굶기 권유 + 투약 언급 (공통 필터).
  return unsafeText(s);
}

function clampFactor(x: unknown): number {
  if (typeof x !== 'number' || !Number.isFinite(x)) return 1;
  return Math.min(FACTOR_MAX, Math.max(FACTOR_MIN, x));
}

function nonEmptyString(x: unknown): string | null {
  if (typeof x !== 'string') return null;
  const t = x.trim();
  return t.length > 0 ? t : null;
}

/// 코드포인트 기준으로 자른다 (이모지·한글 서로게이트 안전).
function truncateCodePoints(s: string, max: number): string {
  const cps = [...s];
  return cps.length > max ? cps.slice(0, max).join('').trimEnd() : s;
}

function isRecord(x: unknown): x is Record<string, unknown> {
  return typeof x === 'object' && x !== null && !Array.isArray(x);
}

function processCheck(raw: unknown): Feedback['check'] {
  if (!isRecord(raw)) return NO_CHECK();
  const kind = raw.kind;
  if (typeof kind !== 'string' || !(CHECK_KINDS as readonly string[]).includes(kind)) {
    return NO_CHECK();
  }
  if (kind === 'none') return NO_CHECK();
  const question = nonEmptyString(raw.question);
  if (!question || hasBanned(question) || !Array.isArray(raw.options)) return NO_CHECK();

  const seen = new Set<string>();
  const options: FeedbackOption[] = [];
  for (const o of raw.options) {
    if (!isRecord(o)) continue;
    const label = nonEmptyString(o.label);
    if (!label || hasBanned(label) || seen.has(label)) continue;
    if (typeof o.kcal_factor !== 'number' || !Number.isFinite(o.kcal_factor)) continue;
    seen.add(label);
    options.push({
      label,
      kcal_factor: clampFactor(o.kcal_factor),
      sodium_factor: clampFactor(o.sodium_factor),
    });
  }

  if (options.length < OPTIONS_MIN) return NO_CHECK();

  // "사진 그대로 다 먹음" 옵션(kcal·sodium 모두 1.0)은 항상 첫 자리에 둔다.
  // kcal 만 1.0 인 옵션(예: soup "국물은 남겼어" 1.0/0.4)은 이 옵션이 아니다.
  // 모델이 빠뜨렸으면 '다 먹었어'(1.0, 1.0) 를 채워 넣는다 (같은 label 이 이미 있으면 생략).
  const full = options.find((o) => o.kcal_factor === 1 && o.sodium_factor === 1) ??
    (seen.has(FULL_LABEL)
      ? undefined
      : { label: FULL_LABEL, kcal_factor: 1, sodium_factor: 1 });
  const ordered = full ? [full, ...options.filter((o) => o !== full)] : options;
  const kept = ordered.slice(0, OPTIONS_MAX);

  return { kind: kind as CheckKind, question, options: kept };
}

/// LLM 이 만든 feedback 을 저장 가능한 형태로 다듬는다.
/// - headline/good/next 가 문자열이 아니거나 비면 null (feedback 없이 done).
/// - 금지어: headline → 기본 문구, good/next → 중립 문구, question → check 제거, label → 옵션 제거.
/// - factor [0.2, 1.3] clamp, options 2~4개, kind none 이면 options 비움.
export function postProcessFeedback(raw: unknown): Feedback | null {
  if (!isRecord(raw)) return null;
  const headline = nonEmptyString(raw.headline);
  const good = nonEmptyString(raw.good);
  const next = nonEmptyString(raw.next);
  if (!headline || !good || !next) return null;

  return {
    headline: hasBanned(headline)
      ? FEEDBACK_FALLBACK_HEADLINE
      : truncateCodePoints(headline, HEADLINE_MAX),
    good: hasBanned(good) ? FALLBACK_GOOD : good,
    next: hasBanned(next) ? FALLBACK_NEXT : next,
    check: processCheck(raw.check),
  };
}

/// 시스템 프롬프트에 붙는 피드백 규칙. index.ts 와 claude_probe 가 같이 쓴다.
export const FEEDBACK_RULES = `
feedback (Korean, casual 반말, voice of the app mascot "푸디" — warm, short):
- headline: ≤20 Korean characters, no emoji, no score or judgement.
- good: 1 sentence about something genuinely good in THIS meal (protein, vegetables,
  balance, regular mealtime, recording it). NEVER praise eating little or skipping food.
- next: exactly ONE thing to ADD or SWAP next time ("더해보자" / "바꿔보자" style).
  Never forbid foods, never suggest skipping a meal or eating less than a daily floor of
  1500 kcal (male) / 1200 kcal (female or unknown). No moral or good/bad food framing.
- Never use these words: 실패, 어겼다, 망쳤다, 해주세요, 나쁜 음식. No formal 존댓말.
- No promises of results (no "○kg 빠져", no guaranteed effects). No medical advice.
- Use the [사용자] context if given: daily target, kcal already eaten today before this
  meal, goal mode (lose = gentle deficit, maintain = steady balance, gain = enough
  energy and protein), GLP-1 use.
- If the user uses GLP-1 medication: even with small portions, prioritise protein and
  fluids in "next". NEVER mention the medication, dose, injections or side effects.
- check: pick the ONE portion uncertainty that changes kcal/sodium most
  (rice amount → rice, soup/broth drunk → soup, sauce/dressing → sauce, whole plate → portion).
  2~4 options, the first is "다 먹었어" with kcal_factor 1.0 and sodium_factor 1.0.
  Factors are relative to your estimate, between 0.2 and 1.3. For soup, leaving broth
  lowers sodium_factor much more than kcal_factor.
  If you are confident about the amount, use kind "none", question "" and options [].`;

/// analyze-entry 시스템 프롬프트 (분석 규칙 + 피드백 규칙).
export function buildSystemPrompt(priorSlot: string): string {
  return `You are a nutrition analyst for a Korean diet tracking app.
Analyze the meal photo and return strict JSON matching the provided schema.

Rules:
- meal_slot axis (time of day): breakfast / lunch / dinner / late_night.
  Time prior for this capture (local): ${priorSlot}.
  Use the prior as a strong hint unless the image strongly suggests otherwise.
- eating_type axis (food kind): meal / snack / beverage. Do NOT confuse with meal_slot.
  Coffee at 10pm → meal_slot=late_night, eating_type=beverage.
- Estimate per-item calories and macros in metric units (g, mg).
  If unsure of quantity, assume a typical serving for a Korean adult.
- totals.kcal MUST equal sum of items.kcal (within ±5%).
- items and totals always cover EVERYTHING visible in the photo. Even if the [사용자]
  line says the meal was shared by several people, NEVER divide by the number of people
  (the app does that itself). Sharing only changes the tone of feedback.
- confidence 0..1 overall; item-level confidence too. Lower is better than wrong.
- Names in Korean if locale starts with 'ko', English otherwise.
${FEEDBACK_RULES}`;
}

/// analyze-entry user 프롬프트. contextLine 은 context.ts 의 buildUserContextLine 결과
/// (조회 실패면 null → 기존 프롬프트와 같은 모양).
export function buildUserPrompt(
  capturedAt: string,
  locale: string,
  contextLine: string | null,
): string {
  return `Captured at: ${capturedAt} (locale=${locale}).
${contextLine ? `${contextLine}\n` : ''}Return JSON only. No prose.`;
}
