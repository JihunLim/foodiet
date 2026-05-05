// render-share — PT 공유 링크 웹뷰 전용 렌더러.
//
// 기획안 §11 · §13.5 — 허용 컬럼만 SELECT 하여 JSON 으로 반환.
//   포함: 사진 URL, 촬영 시각, meal_slot, kcal_total, 일별 합계, 주간 평균
//   제외: macros, weight_logs, coach_messages, profiles.weight_* 등
//
// 이 함수는 **service_role** 키로 실행되므로, 반드시 아래의 SELECT 컬럼 화이트리스트를
// 수정하지 않는 한 매크로/체중/코치 메시지가 응답 JSON 에 포함될 수 없다.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { createHash } from 'node:crypto';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!; // 클라이언트에는 절대 노출 금지

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

function sha256Hex(s: string): string {
  return createHash('sha256').update(s).digest('hex');
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const token = url.searchParams.get('token');
  if (!token) return new Response('missing token', { status: 400 });

  const tokenHash = sha256Hex(token);

  const { data: link, error: linkErr } = await admin
    .from('share_links')
    .select('id, user_id, scope_json, expires_at, revoked_at')
    .eq('token_hash', tokenHash)
    .maybeSingle();
  if (linkErr || !link) return new Response('not found', { status: 404 });
  if (link.revoked_at) return new Response('revoked', { status: 403 });
  if (link.expires_at && new Date(link.expires_at) < new Date()) {
    return new Response('expired', { status: 403 });
  }

  // scope_json 고정 검증 — DB 트리거가 이미 보장하지만, 함수 단에서도 2차 방어.
  const scope = link.scope_json as Record<string, boolean>;
  if (!scope.photos || !scope.kcal_per_entry || scope.macros || scope.weight || scope.coach_messages) {
    return new Response('forbidden scope', { status: 403 });
  }

  // 닉네임만 꺼낸다. weight_kg / goal_* 은 조회조차 하지 않는다.
  const { data: profile } = await admin
    .from('profiles')
    .select('nickname, locale, unit_energy')
    .eq('user_id', link.user_id)
    .maybeSingle();

  // 기록 — 허용 컬럼만. macros · confidence · source 등은 PT 뷰에 필요 없으므로 제외.
  const { data: entries, error: entriesErr } = await admin
    .from('entries')
    .select('id, captured_at, meal_slot, kcal_total, image_path')
    .eq('user_id', link.user_id)
    .eq('status', 'done')
    .order('captured_at', { ascending: false })
    .limit(200);
  if (entriesErr) return new Response('db error', { status: 500 });

  // 서명 URL (7일 유효, PT 가 탭 열고 볼 수 있을 정도의 수명)
  const withPhotos = await Promise.all((entries ?? []).map(async (e) => {
    const { data: signed } = await admin.storage
      .from('food-photos')
      .createSignedUrl(e.image_path, 60 * 60 * 24 * 7);
    return {
      id: e.id,
      captured_at: e.captured_at,
      meal_slot: e.meal_slot,
      kcal: e.kcal_total,
      photo_url: signed?.signedUrl ?? null,
    };
  }));

  // 일자별·주간 집계
  const dailyTotals = new Map<string, number>();
  for (const e of entries ?? []) {
    const day = (e.captured_at as string).slice(0, 10);
    dailyTotals.set(day, (dailyTotals.get(day) ?? 0) + (e.kcal_total ?? 0));
  }
  const totalsArr = [...dailyTotals.entries()]
    .sort((a, b) => (a[0] < b[0] ? 1 : -1))
    .map(([day, kcal]) => ({ day, kcal }));
  const weeklyAvg = totalsArr.slice(0, 7).reduce((s, x) => s + x.kcal, 0)
    / Math.max(1, Math.min(7, totalsArr.length));

  // 열람 로그 (country/ua_family 는 Edge Runtime 헤더에서 best-effort)
  await admin.from('share_access_logs').insert({
    share_link_id: link.id,
    country: req.headers.get('cf-ipcountry') ?? null,
    ua_family: req.headers.get('user-agent')?.split(' ')[0] ?? null,
  });

  return new Response(
    JSON.stringify({
      owner: { nickname: profile?.nickname, locale: profile?.locale, unit_energy: profile?.unit_energy ?? 'kcal' },
      entries: withPhotos,
      daily_totals: totalsArr,
      weekly_avg_kcal: Math.round(weeklyAvg),
      // 다음 필드는 의도적으로 응답에 포함하지 않는다:
      // macros, weight_logs, coach_messages, goal_weight_kg, nutrients_per_item
    }),
    { headers: { 'content-type': 'application/json', 'cache-control': 'no-store', 'x-robots-tag': 'noindex, nofollow' } },
  );
});
