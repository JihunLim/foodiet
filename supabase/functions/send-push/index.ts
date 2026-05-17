/// `send-push` — 특정 사용자에게 FCM 푸시.
///
/// `verify_jwt: false` 로 배포 — 서비스 롤 키 또는 cron 에서 호출하는 내부 API.
/// 외부에서 임의로 호출하지 못하도록 `INTERNAL_PUSH_TOKEN` 환경 변수를 검사.
///
/// 요청 본문:
///   {
///     "user_id": "<uuid>",
///     "kind":    "coach_daily" | "meal_reminder" | "entry_done" | ...,
///     "title":   "오늘 식단 어땠어?",
///     "body":    "남은 칼로리 320kcal · 가벼운 저녁 어때?",
///     "data":    { "route": "/home" }   // optional, 알림 탭 → 라우팅
///   }
///
/// 응답:
///   { "sent": 2, "failed": 0, "stale_removed": 0 }
import 'jsr:@supabase/functions-js/edge-runtime.d.ts';

import { sendOne, STALE_TOKEN_CODES } from '../_shared/fcm.ts';
import { srDelete, srInsert, srSelect } from '../_shared/supabase.ts';

interface Req {
  user_id: string;
  kind: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}

interface DeviceTokenRow {
  token: string;
  platform: string;
  locale: string | null;
}

function _checkInternalAuth(req: Request): boolean {
  const expected = Deno.env.get('INTERNAL_PUSH_TOKEN');
  // 시크릿이 설정 안 되어 있으면 누구나 호출 가능한 상태가 되므로 거절.
  // 로컬 dev 에서는 supabase secrets set INTERNAL_PUSH_TOKEN=<any> 로 명시.
  if (!expected) return false;
  const got = req.headers.get('x-foodiet-internal') ?? '';
  // 길이 비교는 timing attack 표면이지만 짧은 토큰 + 짧은 응답 시간이라 영향
  // 미미. 그래도 동등성 비교는 동일 길이일 때만 통과.
  if (got.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < got.length; i++) {
    diff |= got.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }
  if (!_checkInternalAuth(req)) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let body: Req;
  try {
    body = (await req.json()) as Req;
  } catch (_) {
    return new Response(JSON.stringify({ error: 'invalid json' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }
  if (!body.user_id || !body.kind || !body.title) {
    return new Response(
      JSON.stringify({ error: 'missing user_id, kind, or title' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // 토큰 조회.
  const tokens = (await srSelect(
    'device_tokens',
    `user_id=eq.${body.user_id}&select=token,platform,locale`,
  )) as DeviceTokenRow[];

  if (tokens.length === 0) {
    // 발송 시도조차 못하니 notifications 에는 sent_at=null 로만 기록.
    await srInsert('notifications', {
      user_id: body.user_id,
      kind: body.kind,
      scheduled_at: new Date().toISOString(),
      sent_at: null,
    });
    return new Response(
      JSON.stringify({ sent: 0, failed: 0, reason: 'no_devices' }),
      { headers: { 'Content-Type': 'application/json' } },
    );
  }

  let sent = 0;
  let failed = 0;
  const stale: string[] = [];
  const errors: Array<{ token: string; code?: string }> = [];

  // FCM v1 은 디바이스 1개씩만 → 직렬 호출. 보통 한 사용자당 1~3 토큰이라 OK.
  for (const t of tokens) {
    const r = await sendOne({
      token: t.token,
      title: body.title,
      body: body.body,
      data: { kind: body.kind, ...(body.data ?? {}) },
    });
    if (r.ok) {
      sent++;
    } else {
      failed++;
      if (r.errorCode && STALE_TOKEN_CODES.has(r.errorCode)) {
        stale.push(t.token);
      }
      errors.push({ token: t.token.substring(0, 12) + '…', code: r.errorCode });
    }
  }

  // 무효 토큰 청소. 토큰 값을 PostgREST 필터에 직접 보간하지 않고 각 토큰을
  // URL-encoded eq.<value> 로 따로 삭제 — quote/comma/특수문자 주입 방어.
  if (stale.length > 0) {
    await Promise.all(stale.map((t) =>
      srDelete('device_tokens', `token=eq.${encodeURIComponent(t)}`)));
  }

  // 발송 로그 (sent>0 일 때만 sent_at 기록).
  await srInsert('notifications', {
    user_id: body.user_id,
    kind: body.kind,
    scheduled_at: new Date().toISOString(),
    sent_at: sent > 0 ? new Date().toISOString() : null,
  });

  return new Response(
    JSON.stringify({
      sent,
      failed,
      stale_removed: stale.length,
      errors: errors.slice(0, 5),
    }),
    { headers: { 'Content-Type': 'application/json' } },
  );
});
