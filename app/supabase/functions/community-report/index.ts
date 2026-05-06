/// `community-report` — 커뮤니티 신고 접수 시 개발자에게 즉시 FCM 푸시.
///
/// 트리거: `reports` 테이블 INSERT Database Webhook.
/// (Supabase 대시보드 → Database → Webhooks → POST → x-foodiet-internal 헤더)
///
/// 흐름:
///   1. webhook payload (record) 에서 신고 정보 읽기.
///   2. profiles 에서 신고자 / 대상자 닉네임 조회 (가능한 경우).
///   3. 대상 콘텐츠 미리보기 (post 캡션 또는 tip body 일부) 조회.
///   4. `DEVELOPER_USER_ID` 환경 변수의 사용자에게 FCM 푸시.
///        title: "🚨 신고 접수: {대상} / {닉네임}"
///        body:  "{사유}: {미리보기}"
///        data:  { route: '/admin/reports/{report_id}' }
///
/// 환경 변수:
///   - `DEVELOPER_USER_ID` : 신고 알림을 받을 개발자 계정의 auth.users.id
///   - `REPORT_WEBHOOK_TOKEN` : webhook 검증 (선택). Supabase Database Webhook 의
///     `x-foodiet-internal` 헤더와 일치해야 한다. 기존 `INTERNAL_PUSH_TOKEN` 과
///     keyspace 를 분리해 cron / send-push 회로를 건드리지 않는다.

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';

import { sendOne } from '../_shared/fcm.ts';
import { srSelect } from '../_shared/supabase.ts';

interface ReportRecord {
  id: string;
  reporter_id: string;
  group_id: string | null;
  target_type: 'post' | 'tip' | 'user';
  target_id: string;
  reason: string;
  detail: string | null;
  status: string;
  created_at: string;
}

interface WebhookPayload {
  type: 'INSERT' | 'UPDATE' | 'DELETE';
  table: string;
  record: ReportRecord;
  old_record?: unknown;
}

interface DeviceTokenRow {
  token: string;
  platform: string;
  locale: string | null;
}

interface ProfileHandle {
  user_id: string;
  nickname: string;
}

interface PostRow {
  user_id: string;
  caption: string | null;
}

interface TipRow {
  user_id: string;
  body: string;
}

const REASON_LABEL: Record<string, string> = {
  inappropriate: '부적절',
  spam: '스팸',
  harassment: '괴롭힘',
  other: '기타',
};

const TARGET_LABEL: Record<string, string> = {
  post: '게시물',
  tip: '조언',
  user: '사용자',
};

function _checkInternalAuth(req: Request): boolean {
  const expected = Deno.env.get('REPORT_WEBHOOK_TOKEN');
  if (!expected) return true;
  const got = req.headers.get('x-foodiet-internal') ?? '';
  return got === expected;
}

async function _lookupNickname(userId: string): Promise<string> {
  try {
    const rows = (await srSelect(
      'profiles',
      `user_id=eq.${userId}&select=user_id,nickname&limit=1`,
    )) as ProfileHandle[];
    return rows[0]?.nickname ?? '알 수 없음';
  } catch {
    return '알 수 없음';
  }
}

async function _lookupTarget(
  type: string,
  id: string,
): Promise<{ ownerId: string | null; preview: string }> {
  try {
    if (type === 'post') {
      const rows = (await srSelect(
        'community_posts',
        `id=eq.${id}&select=user_id,caption&limit=1`,
      )) as PostRow[];
      const r = rows[0];
      return {
        ownerId: r?.user_id ?? null,
        preview: r?.caption ?? '(캡션 없음)',
      };
    } else if (type === 'tip') {
      const rows = (await srSelect(
        'post_tips',
        `id=eq.${id}&select=user_id,body&limit=1`,
      )) as TipRow[];
      const r = rows[0];
      return { ownerId: r?.user_id ?? null, preview: r?.body ?? '' };
    } else if (type === 'user') {
      return { ownerId: id, preview: '' };
    }
  } catch {
    /* fall-through */
  }
  return { ownerId: null, preview: '' };
}

function _truncate(s: string, n: number): string {
  if (!s) return '';
  return s.length > n ? `${s.substring(0, n)}…` : s;
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

  let payload: WebhookPayload;
  try {
    payload = (await req.json()) as WebhookPayload;
  } catch (_) {
    return new Response(JSON.stringify({ error: 'invalid json' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }
  if (payload.type !== 'INSERT' || payload.table !== 'reports') {
    return new Response(JSON.stringify({ skipped: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const r = payload.record;
  const developerId = Deno.env.get('DEVELOPER_USER_ID') ?? '';
  if (!developerId) {
    return new Response(
      JSON.stringify({ error: 'DEVELOPER_USER_ID not set' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // 대상 정보 + 닉네임 조회 (병렬).
  const [reporterNick, target] = await Promise.all([
    _lookupNickname(r.reporter_id),
    _lookupTarget(r.target_type, r.target_id),
  ]);
  const ownerNick = target.ownerId
    ? await _lookupNickname(target.ownerId)
    : '알 수 없음';

  const reasonLabel = REASON_LABEL[r.reason] ?? r.reason;
  const targetLabel = TARGET_LABEL[r.target_type] ?? r.target_type;
  const preview = _truncate(target.preview, 60);

  // 개발자 디바이스 토큰 조회.
  const tokens = (await srSelect(
    'device_tokens',
    `user_id=eq.${developerId}&select=token,platform,locale`,
  )) as DeviceTokenRow[];
  if (tokens.length === 0) {
    return new Response(
      JSON.stringify({ sent: 0, reason: 'no_developer_devices' }),
      { headers: { 'Content-Type': 'application/json' } },
    );
  }

  const title = `🚨 신고 접수: ${targetLabel} / ${ownerNick}`;
  const body =
    `${reasonLabel} · 신고자 ${reporterNick}` +
    (preview ? ` · "${preview}"` : '');

  let sent = 0;
  let failed = 0;
  for (const t of tokens) {
    const result = await sendOne({
      token: t.token,
      title,
      body,
      data: {
        kind: 'community_report',
        report_id: r.id,
        target_type: r.target_type,
        target_id: r.target_id,
        route: `/admin/reports/${r.id}`,
      },
    });
    if (result.ok) sent++;
    else failed++;
  }

  return new Response(
    JSON.stringify({ sent, failed, report_id: r.id }),
    { headers: { 'Content-Type': 'application/json' } },
  );
});
