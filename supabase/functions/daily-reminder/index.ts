/// `daily-reminder` — 매일 한 번 cron 으로 호출되어 "오늘 아직 식단 기록 안 한"
/// 사용자에게 부드러운 리마인더 푸시.
///
/// 호출 방식:
///   pg_cron 이 SQL extension `pg_net` 으로 매일 KST 20:00 (= UTC 11:00) 에
///   이 엔드포인트를 POST.
///
/// 환경 변수:
///   - INTERNAL_PUSH_TOKEN : send-push 호출 시 헤더에 실어줘야 함.
///
/// 동작:
///   1. 모든 활성 프로필 (deleted_at IS NULL) 조회
///   2. 각 사용자에 대해 오늘(로컬 자정~now) 사이 entries.status='done' 이 있는지 확인
///   3. 없으면 send-push 호출
///
/// 메시지 예시 (한국어):
///   - "🍓 오늘 식단, 아직 한 끼도 안 찍었네. 빈 그릇이 외로워해"
///   - "오늘은 어떤 식단이었어? 사진 한 장이면 끝"
import 'jsr:@supabase/functions-js/edge-runtime.d.ts';

import { srSelect } from '../_shared/supabase.ts';

interface Profile {
  user_id: string;
  locale: string | null;
}

const KO_LINES = [
  { title: '🍓 오늘 식단, 아직이야?', body: '하루 마무리 전에 한 컷 찍어두자. 사진 한 장이면 끝.' },
  { title: '오늘은 어땠어?', body: '딱 한 끼만 찍어도 푸디가 분석해줄게.' },
  { title: '🥗 빈 그릇이 외로워해', body: '오늘 먹은 거 사진 한 장이면 인사이트가 채워져.' },
];

const EN_LINES = [
  { title: '🍓 Snap today\'s plate?', body: 'A single photo gets your day logged.' },
  { title: 'How was today?', body: 'One photo and Foodie does the math.' },
];

function _pickMessage(locale: string | null): { title: string; body: string } {
  const lines = (locale ?? 'ko').startsWith('en') ? EN_LINES : KO_LINES;
  return lines[Math.floor(Math.random() * lines.length)];
}

async function _hasLoggedToday(userId: string): Promise<boolean> {
  // 로컬 타임존을 모르니 단순화: 직전 24시간 안에 done 레코드 있는지 확인.
  // 정확한 "오늘 자정 이후" 는 사용자 프로필 timezone 컬럼이 추가되면 그때 정밀화.
  const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const rows = (await srSelect(
    'entries',
    `user_id=eq.${userId}&status=eq.done&captured_at=gte.${since}&select=id&limit=1`,
  )) as Array<{ id: string }>;
  return rows.length > 0;
}

function _checkInternalAuth(req: Request): boolean {
  const expected = Deno.env.get('INTERNAL_PUSH_TOKEN');
  // 시크릿 미설정 시 거절. dev 에서도 명시적으로 set 해야 함.
  if (!expected) return false;
  const got = req.headers.get('x-foodiet-internal') ?? '';
  if (got.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < got.length; i++) {
    diff |= got.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

Deno.serve(async (req: Request) => {
  if (!_checkInternalAuth(req)) {
    return new Response('unauthorized', { status: 401 });
  }

  // 활성 프로필.
  const profiles = (await srSelect(
    'profiles',
    'deleted_at=is.null&select=user_id,locale',
  )) as Profile[];

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const internalToken = Deno.env.get('INTERNAL_PUSH_TOKEN') ?? '';
  const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  let queued = 0;
  let skipped = 0;
  const errors: string[] = [];

  for (const p of profiles) {
    try {
      if (await _hasLoggedToday(p.user_id)) {
        skipped++;
        continue;
      }
      const msg = _pickMessage(p.locale);
      const r = await fetch(`${supabaseUrl}/functions/v1/send-push`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          // Edge function 간 호출 시 Authorization 헤더 필수 (Supabase 게이트웨이).
          Authorization: `Bearer ${serviceRole}`,
          'x-foodiet-internal': internalToken,
        },
        body: JSON.stringify({
          user_id: p.user_id,
          kind: 'meal_reminder',
          title: msg.title,
          body: msg.body,
          data: { route: '/home' },
        }),
      });
      if (r.ok) queued++;
      else errors.push(`${p.user_id}: ${r.status}`);
    } catch (e) {
      errors.push(`${p.user_id}: ${(e as Error).message}`);
    }
  }

  return new Response(
    JSON.stringify({
      queued,
      skipped_already_logged: skipped,
      total_profiles: profiles.length,
      errors: errors.slice(0, 5),
    }),
    { headers: { 'Content-Type': 'application/json' } },
  );
});
