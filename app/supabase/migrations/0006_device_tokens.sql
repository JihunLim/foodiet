-- FCM/APNs 디바이스 토큰 저장소.
--
-- 기획안 §12 / §18.1 #11 — FCM v1 으로 푸시를 보내려면 사용자의 디바이스 토큰을
-- DB 에 보관해야 한다. 한 사용자가 여러 기기를 쓰는 걸 허용 (기기별 1row).
--
-- 토큰 자체가 식별 키 — upsert 시 conflict target. 앱이 켜질 때마다 refresh.
-- RLS: 본인 토큰만 읽기·쓰기·삭제 가능.
-- send-push Edge Function 은 service_role 키로 bypass 후 user_id 로 조회.

create table if not exists public.device_tokens (
  token       text primary key,                              -- FCM registration token
  user_id     uuid not null references auth.users(id) on delete cascade,
  platform    text not null check (platform in ('ios','android','macos','web')),
  app_version text,
  locale      text,
  updated_at  timestamptz not null default now()
);

create index if not exists idx_device_tokens_user
  on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

drop policy if exists "own_device_tokens" on public.device_tokens;
create policy "own_device_tokens" on public.device_tokens
  using (user_id = auth.uid()) with check (user_id = auth.uid());
