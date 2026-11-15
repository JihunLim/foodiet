// home_coach_probe — home-coach 가 실제로 보내는 프롬프트(context.ts 의 buildSystemPrompt /
// buildUserPrompt + RESPONSE_SCHEMA)를 실제 Claude 에 2회 호출해 본다. (배포 함수 아님)
//
//   A) 어제 과식(+1100) + 이번 주 실험 + GLP-1 사용 + 오늘 추천 식단, 감량 모드
//   B) 최근 7일 기록 없음, 유지 모드
//
// 확인: 스키마 JSON, headline 20자 이내, 금지어 없음, 굶기/끼니 거르기 권유 없음,
//       투약·용량 언급 없음.
//
// 실행 (키는 코드/리포에 넣지 말 것):
//   ANTHROPIC_API_KEY=$(cat ~/.config/foodiet/anthropic-key) \
//   deno run --allow-net --allow-env --allow-read --node-modules-dir=none \
//     app/supabase/functions/_tests/home_coach_probe.ts

import { CLAUDE_MODEL, claudeJson } from '../_shared/claude.ts';
import {
  BANNED,
  buildSystemPrompt,
  buildUserPrompt,
  type CoachContext,
  type CoachResult,
  RESPONSE_SCHEMA,
  summarizeWeek,
  type WeekRow,
} from '../home-coach/context.ts';

if (!Deno.env.get('ANTHROPIC_API_KEY')) {
  console.error('✗ ANTHROPIC_API_KEY 가 필요합니다.');
  Deno.exit(2);
}

const KST = 540;
const TODAY = '2026-11-16'; // 월

function row(localIso: string, kcal: number, slot = 'lunch', sodium = 900): WeekRow {
  return {
    captured_at: new Date(`${localIso}+09:00`).toISOString(),
    kcal_total: kcal,
    macros: { sodium_mg: sodium },
    shared_with_count: 1,
    meal_slot: slot,
  };
}

const weekRows: WeekRow[] = [
  row('2026-11-11T12:30:00', 700),
  row('2026-11-11T19:00:00', 800),
  row('2026-11-12T12:30:00', 650),
  row('2026-11-12T19:30:00', 900),
  row('2026-11-14T13:00:00', 1100, 'lunch', 2500),
  row('2026-11-14T23:10:00', 600, 'late_night', 1200),
  row('2026-11-15T12:00:00', 1300, 'lunch', 2600), // 어제 합 2900
  row('2026-11-15T19:30:00', 1000, 'dinner', 2200),
  row('2026-11-15T23:30:00', 600, 'late_night', 900),
];

const base: Omit<CoachContext, 'week' | 'experiment' | 'mode' | 'glp1' | 'planMeals'> = {
  nickname: '지훈',
  target: 1800,
  floor: 1500,
  goalWeightKg: 72,
  activityLevel: 3,
  dietRestrictions: [],
  nowLabel: '11:40',
  eaten: [{ time: '08:10', slot: 'breakfast', title: '그릭요거트 · 바나나', kcal: 320 }],
  kcalConsumed: 320,
  remaining: 1480,
  carb: 48,
  protein: 18,
  fat: 6,
  sodium: 110,
  sugar: 30,
};

const cases: Array<{ name: string; ctx: CoachContext }> = [
  {
    name: 'A) 어제 과식 + 실험 + GLP-1 + 식단 (lose)',
    ctx: {
      ...base,
      week: summarizeWeek(weekRows, KST, TODAY),
      experiment: '야식이 당기면 따뜻한 보리차 먼저 한 잔',
      mode: 'lose',
      glp1: true,
      planMeals: [
        { slot: 'lunch', name: '닭가슴살 현미 비빔밥' },
        { slot: 'dinner', name: '두부 버섯 전골' },
      ],
    },
  },
  {
    name: 'B) 7일 기록 없음 (maintain)',
    ctx: {
      ...base,
      floor: 1200,
      week: summarizeWeek([], KST, TODAY),
      experiment: null,
      mode: 'maintain',
      glp1: false,
      planMeals: [],
    },
  },
];

const FORBIDDEN_ADVICE = ['굶', '거르', '건너뛰', '용량', '투약', '주사'];

console.log(`모델=${CLAUDE_MODEL}`);
let allOk = true;
for (const c of cases) {
  console.log('\n' + '─'.repeat(72) + '\n' + c.name + '\n' + '─'.repeat(72));
  try {
    const t = Date.now();
    const r = await claudeJson<CoachResult>({
      tag: 'probe-home-coach',
      system: buildSystemPrompt(c.ctx.floor),
      content: buildUserPrompt(c.ctx),
      schema: RESPONSE_SCHEMA,
    });
    const text = [r.headline, r.review, r.next_tip, r.focus].join(' ');
    const headLen = [...r.headline].length;
    const banned = BANNED.filter((b) => text.includes(b));
    const advice = FORBIDDEN_ADVICE.filter((w) => text.includes(w));
    console.log(`  ${Date.now() - t}ms  ${r.emoji} ${r.headline} (${headLen}자) / focus=${r.focus}`);
    console.log(`  review: ${r.review}\n  next_tip: ${r.next_tip}`);
    const ok = typeof r.headline === 'string' && headLen > 0 && headLen <= 20 &&
      banned.length === 0 && advice.length === 0;
    if (banned.length) console.log(`  ✗ 금지어: ${banned.join(', ')}`);
    if (advice.length) console.log(`  ✗ 금지 조언 의심 단어: ${advice.join(', ')}`);
    if (headLen > 20) console.log('  ✗ headline 20자 초과');
    console.log(ok ? '  ✓ PASS' : '  ✗ FAIL');
    allOk &&= ok;
  } catch (e) {
    console.log(`  ✗ ${e}`);
    allOk = false;
  }
}

Deno.exit(allOk ? 0 : 1);
