// suggest_probe — meal-suggest 가 보내는 Claude 요청을 실제 모델로 3번 때려보는
// 진단 스크립트. (배포되는 함수가 아님 — `_`-prefix 라 supabase 가 무시)
//
// meal-suggest/schema.ts 의 스키마·프롬프트·후처리를 그대로 import 하므로 배포 코드와
// 같은 요청 모양이다 (복사본 드리프트 없음). DB 는 건드리지 않는다.
//
// 케이스
//   1) convenience, 남은 700 kcal  → options 3개
//   2) home, 남은 0 kcal          → options ≤ 2개 + 고정 intro (굶기 권유 없음)
//   3) hoesik (GLP-1 사용, 유지 모드) → 4개 배열 모두 비어있지 않음
//   공통: 금지어 없음, structured outputs 400 없음
//
// 실행 (키는 절대 코드/리포에 넣지 말 것):
//   ANTHROPIC_API_KEY=sk-ant-... \
//   deno run --allow-net --allow-env --allow-read --node-modules-dir=none \
//     app/supabase/functions/_tests/suggest_probe.ts

import { CLAUDE_MODEL, claudeJson } from '../_shared/claude.ts';
import {
  buildSystemPrompt,
  buildUserPrompt,
  hasBanned,
  HOESIK_SCHEMA,
  OPTIONS_SCHEMA,
  postprocessHoesik,
  postprocessOptions,
  type SuggestContext,
} from '../meal-suggest/schema.ts';

if (!Deno.env.get('ANTHROPIC_API_KEY')) {
  console.error('✗ ANTHROPIC_API_KEY 가 필요합니다. (Edge Function Secrets 의 그 키)');
  Deno.exit(2);
}

function header(t: string) {
  console.log('\n' + '─'.repeat(72) + '\n' + t + '\n' + '─'.repeat(72));
}

const base: SuggestContext = {
  situation: 'convenience',
  nowLabel: '13:10',
  target: 1800,
  consumed: 1100,
  remaining: 700,
  proteinG: 48,
  eatenTitles: ['그릭요거트 · 바나나 (320 kcal)', '제육덮밥 · 미역국 (780 kcal)'],
  mode: 'lose',
  glp1: false,
  dietRestrictions: [],
};

const cases: Array<{ name: string; ctx: SuggestContext }> = [
  { name: 'convenience_700', ctx: { ...base } },
  {
    name: 'home_remaining_0',
    ctx: {
      ...base,
      situation: 'home',
      nowLabel: '21:30',
      consumed: 1950,
      remaining: 0,
      proteinG: 70,
      eatenTitles: [...base.eatenTitles, '치킨 반 마리 (850 kcal)'],
    },
  },
  {
    name: 'hoesik_glp1_maintain',
    ctx: {
      ...base,
      situation: 'hoesik',
      nowLabel: '17:40',
      mode: 'maintain',
      glp1: true,
    },
  },
];

const results: Record<string, boolean> = {};
console.log(`모델=${CLAUDE_MODEL}`);

for (const c of cases) {
  header(c.name);
  try {
    const t = Date.now();
    const raw = await claudeJson<unknown>({
      tag: `probe-suggest-${c.name}`,
      system: buildSystemPrompt(c.ctx),
      content: buildUserPrompt(c.ctx),
      schema: c.ctx.situation === 'hoesik' ? HOESIK_SCHEMA : OPTIONS_SCHEMA,
    });
    const ms = Date.now() - t;
    console.log(`raw: ${JSON.stringify(raw)}`);
    if (c.ctx.situation === 'hoesik') {
      const r = postprocessHoesik(raw);
      console.log(`✓ ${ms}ms  ${JSON.stringify(r, null, 2)}`);
      const all = [r.intro, ...r.before, ...r.order_tips, ...r.drink_tips, ...r.next_day];
      const rawObj = raw as Record<string, unknown[]>;
      const rawNonEmpty = ['before', 'order_tips', 'drink_tips', 'next_day']
        .every((k) => Array.isArray(rawObj?.[k]) && rawObj[k].length > 0);
      results[c.name] = rawNonEmpty && !all.some(hasBanned);
    } else {
      const r = postprocessOptions(raw, c.ctx.remaining);
      console.log(`✓ ${ms}ms  ${JSON.stringify(r, null, 2)}`);
      const rawOpts = (raw as { options?: unknown[] })?.options ?? [];
      const all = [r.intro, ...r.options.flatMap((o) => [o.name, o.why, o.tip])];
      const countOk = c.ctx.remaining <= 0
        ? r.options.length >= 1 && r.options.length <= 2
        : r.options.length === 3;
      console.log(`  raw options=${rawOpts.length}  final=${r.options.length}  ` +
        r.options.map((o) => `${o.name}(${o.kcal})`).join(', '));
      results[c.name] = countOk && !all.some(hasBanned);
    }
  } catch (e) {
    console.log(`✗ ${e}`);
    results[c.name] = false;
  }
}

header('결과');
for (const [k, v] of Object.entries(results)) console.log(`${v ? '✓' : '✗'} ${k}`);
Deno.exit(Object.values(results).every(Boolean) ? 0 : 1);
