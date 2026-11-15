// checkin_probe — weekly-checkin 이 보내는 Claude 요청을 실제 모델로 때려보는 진단.
// (배포되는 함수가 아님 — `_`-prefix 라 supabase 가 무시)
//
// weekly-checkin/schema.ts 의 SYSTEM_PROMPT · buildUserPrompt · RESPONSE_SCHEMA ·
// postProcessReport 를 그대로 쓴다 = 배포 코드와 같은 경로. 가짜 7일 데이터 2케이스:
//   A) 감량 모드 · 주말 과식 + 야식 · 지난 주 실험 있음
//   B) GLP-1 사용 중 · 증량 아닌 감량 · 한 끼만 기록한 날 많음(부분 기록)
//
// 확인: 스키마 400 없음, raw 응답이 이미 규칙(실험 3개, wins 1~2, headline ≤20자,
// 금지어·효과 보장·굶기 없음)을 지키는가. 후처리가 개입했으면 경고로 출력.
//
// 실행:
//   ANTHROPIC_API_KEY=$(cat ~/.config/foodiet/anthropic-key) \
//   deno run --allow-net --allow-env --allow-read --node-modules-dir=none \
//     app/supabase/functions/_tests/checkin_probe.ts

import { CLAUDE_MODEL, claudeJson } from '../_shared/claude.ts';
import {
  BANNED,
  buildUserPrompt,
  type EntryRow,
  postProcessReport,
  RESPONSE_SCHEMA,
  summarizeWeek,
  SYSTEM_PROMPT,
} from '../weekly-checkin/schema.ts';

if (!Deno.env.get('ANTHROPIC_API_KEY')) {
  console.error('✗ ANTHROPIC_API_KEY 가 필요합니다.');
  Deno.exit(2);
}

const KST = 540;
const WEEK = '2026-11-09'; // 월

/// 로컬(KST) 'MM-DD HH:mm' → UTC ISO
function at(day: number, hh: number, mm = 0): string {
  return new Date(Date.UTC(2026, 10, 9 + day, hh, mm) - KST * 60_000).toISOString();
}
function meal(
  day: number,
  hh: number,
  kcal: number,
  slot: string,
  extra: Partial<EntryRow> = {},
): EntryRow {
  return {
    captured_at: at(day, hh),
    kcal_total: kcal,
    shared_with_count: 1,
    meal_slot: slot,
    eating_type: 'meal',
    macros: {
      protein_g: Math.round(kcal / 25),
      sodium_mg: Math.round(kcal * 1.6),
      sugar_g: Math.round(kcal / 60),
    },
    ...extra,
  };
}

const caseA: EntryRow[] = [];
for (let d = 0; d < 5; d++) {
  caseA.push(meal(d, 8, 350, 'breakfast'));
  caseA.push(meal(d, 12, 650, 'lunch'));
  caseA.push(meal(d, 19, 600, 'dinner'));
}
caseA.push(meal(3, 22, 450, 'late_night', { eating_type: 'snack' }));
caseA.push(meal(5, 13, 900, 'lunch'));
caseA.push(meal(5, 19, 1400, 'dinner', { shared_with_count: 1 }));
caseA.push(meal(5, 23, 700, 'late_night'));
caseA.push(meal(6, 12, 800, 'lunch'));
caseA.push(meal(6, 15, 300, 'lunch', { eating_type: 'beverage' }));

const caseB: EntryRow[] = [
  meal(0, 12, 450, 'lunch'),
  meal(2, 13, 400, 'lunch'),
  meal(3, 19, 500, 'dinner'),
  meal(3, 8, 250, 'breakfast'),
  meal(5, 12, 550, 'lunch'),
];

type Case = {
  name: string;
  entries: EntryRow[];
  glp1: boolean;
  prev: string | null;
  weight: { first: number; last: number; count: number } | null;
  sex: 'male' | 'female';
  target: number;
};

const cases: Case[] = [
  {
    name: 'A 주말 과식·야식',
    entries: caseA,
    glp1: false,
    prev: '배고프면 물 한 잔 마시고 10분 뒤에 다시 생각하기',
    weight: { first: 72.4, last: 73.6, count: 3 },
    sex: 'male',
    target: 1900,
  },
  {
    name: 'B GLP-1·부분 기록',
    entries: caseB,
    glp1: true,
    prev: null,
    weight: null,
    sex: 'female',
    target: 1450,
  },
];

const UNSAFE = [/\d+(?:\.\d+)?\s*(?:kg|킬로)\s*(?:감량|빠|뺄|뺀|줄)/i, /굶|단식/];

console.log(`모델=${CLAUDE_MODEL}`);
const results: Record<string, boolean> = {};

for (const c of cases) {
  console.log('\n' + '─'.repeat(72) + `\n${c.name}\n` + '─'.repeat(72));
  const summary = summarizeWeek(c.entries, KST, WEEK);
  console.log(`기록일 ${summary.daysLogged} · 평균 ${summary.avgKcal} · 주말 ${summary.weekendAvgKcal} · 야식 ${summary.lateNightDays}일 · 부분 ${summary.partialDays}일`);
  try {
    const t = Date.now();
    const raw = await claudeJson<Record<string, unknown>>({
      tag: 'probe-checkin',
      system: SYSTEM_PROMPT,
      content: buildUserPrompt({
        nickname: '지훈',
        targetKcal: c.target,
        floorKcal: c.sex === 'male' ? 1500 : 1200,
        mode: 'lose',
        glp1: c.glp1,
        prevExperiment: c.prev,
        weekStart: WEEK,
        summary,
        weight: c.weight,
      }),
      schema: RESPONSE_SCHEMA,
      maxTokens: 8000,
    });
    const ms = Date.now() - t;
    const rawText = JSON.stringify(raw);
    const issues: string[] = [];
    const exps = Array.isArray(raw.experiments) ? raw.experiments : [];
    const wins = Array.isArray(raw.wins) ? raw.wins : [];
    if (exps.length !== 3) issues.push(`experiments=${exps.length}`);
    if (wins.length < 1 || wins.length > 2) issues.push(`wins=${wins.length}`);
    if (typeof raw.headline !== 'string' || [...raw.headline].length > 20) {
      issues.push(`headline 길이 ${[...String(raw.headline)].length}`);
    }
    for (const b of BANNED) if (rawText.includes(b)) issues.push(`금지어 ${b}`);
    for (const re of UNSAFE) if (re.test(rawText)) issues.push(`위험 문구 ${re}`);
    if (c.glp1 && /용량|투약|주사/.test(rawText)) issues.push('GLP-1 투약 언급');

    const r = postProcessReport(raw);
    console.log(`✓ ${ms}ms  ${r.emoji} ${r.headline}`);
    console.log(`  wins: ${r.wins.join(' / ')}`);
    console.log(`  pattern: ${r.pattern}`);
    r.experiments.forEach((x, i) => console.log(`  ${i + 1}. ${x.if_then} — ${x.why}`));
    console.log(`  note: ${r.note}`);
    if (issues.length) console.log(`  ⚠ raw 규칙 위반(후처리가 보정): ${issues.join(', ')}`);
    // 스키마/호출이 통과하고 후처리 결과가 형태를 지키면 PASS.
    const post = JSON.stringify(r);
    results[c.name] = r.experiments.length === 3 && r.wins.length >= 1 &&
      r.wins.length <= 2 && [...r.headline].length <= 20 &&
      !BANNED.some((b) => post.includes(b)) && !UNSAFE.some((re) => re.test(post));
  } catch (e) {
    console.log(`✗ ${e}`);
    results[c.name] = false;
  }
}

console.log('\n결과');
for (const [k, v] of Object.entries(results)) console.log(`${v ? '✓' : '✗'} ${k}`);
Deno.exit(Object.values(results).every(Boolean) ? 0 : 1);
