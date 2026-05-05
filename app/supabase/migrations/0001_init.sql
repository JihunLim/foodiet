-- foodiet 초기 스키마 (기획안 §13).
-- 실행 전: 이 마이그레이션은 Supabase 프로젝트의 auth 스키마가 이미 존재한다고 가정한다.

-- ── ENUMS ───────────────────────────────────────────────────
create type meal_slot   as enum ('breakfast','lunch','dinner','late_night');
create type eating_type as enum ('meal','snack','beverage');
create type entry_status as enum ('pending','done','failed');
create type coach_scope  as enum ('in_meal','daily','weekly');

-- ── 프로필 ─────────────────────────────────────────────────
create table public.profiles (
  user_id          uuid primary key references auth.users(id) on delete cascade,
  nickname         text not null,
  locale           text not null default 'ko',
  unit_energy      text not null default 'kcal',
  unit_mass        text not null default 'kg',
  height_cm        numeric(5,1),
  weight_kg        numeric(5,1),
  goal_weight_kg   numeric(5,1),
  goal_deadline    date,
  activity_level   smallint,
  diet_restrictions text[] default '{}',
  daily_kcal_target int,
  macros_target    jsonb,
  created_at       timestamptz default now(),
  deleted_at       timestamptz
);

-- ── 기록 ───────────────────────────────────────────────────
create table public.entries (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  captured_at  timestamptz not null,
  image_path   text not null,
  meal_slot    meal_slot,
  eating_type  eating_type,
  kcal_total   int,
  macros       jsonb,
  confidence   numeric(3,2),
  source       text check (source in ('camera','gallery')),
  status       entry_status not null default 'pending',
  locale       text,
  created_at   timestamptz default now()
);
create index entries_user_captured_idx on public.entries (user_id, captured_at desc);

create table public.entry_items (
  id          uuid primary key default gen_random_uuid(),
  entry_id    uuid not null references public.entries(id) on delete cascade,
  name        text not null,
  qty_g       numeric(7,1),
  kcal        int,
  carb_g      numeric(6,1),
  protein_g   numeric(6,1),
  fat_g       numeric(6,1),
  sodium_mg   int,
  sugar_g     numeric(6,1),
  confidence  numeric(3,2)
);

create table public.corrections (
  id         uuid primary key default gen_random_uuid(),
  entry_id   uuid not null references public.entries(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  field      text not null,
  before_val jsonb,
  after_val  jsonb,
  created_at timestamptz default now()
);

create table public.coach_messages (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  scope      coach_scope not null,
  entry_id   uuid references public.entries(id) on delete set null,
  body_json  jsonb not null,
  created_at timestamptz default now(),
  read_at    timestamptz,
  acted_at   timestamptz
);

create table public.weight_logs (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  logged_at  timestamptz not null,
  weight_kg  numeric(5,1) not null,
  source     text check (source in ('manual','scale_sync'))
);

-- ── 공유 링크 (범위 고정) ──────────────────────────────────
create table public.share_links (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  token_hash  text not null unique,
  scope_json  jsonb not null default jsonb_build_object(
                 'photos', true,
                 'kcal_per_entry', true,
                 'kcal_daily_total', true,
                 'kcal_weekly_avg', true,
                 'macros', false,
                 'weight', false,
                 'coach_messages', false
               ),
  expires_at  timestamptz,
  revoked_at  timestamptz,
  created_at  timestamptz default now()
);

create or replace function public.enforce_share_scope() returns trigger language plpgsql as $$
begin
  if new.scope_json <> jsonb_build_object(
       'photos', true,
       'kcal_per_entry', true,
       'kcal_daily_total', true,
       'kcal_weekly_avg', true,
       'macros', false,
       'weight', false,
       'coach_messages', false
     ) then
    raise exception 'share_links.scope_json is fixed by policy';
  end if;
  return new;
end $$;
create trigger trg_share_scope_ins before insert or update on public.share_links
  for each row execute function public.enforce_share_scope();

create table public.share_access_logs (
  id            uuid primary key default gen_random_uuid(),
  share_link_id uuid not null references public.share_links(id) on delete cascade,
  accessed_at   timestamptz default now(),
  country       text,
  ua_family     text
);

create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  kind         text not null,
  scheduled_at timestamptz not null,
  sent_at      timestamptz,
  opened_at    timestamptz
);

-- ── RLS ────────────────────────────────────────────────────
alter table public.profiles          enable row level security;
alter table public.entries           enable row level security;
alter table public.entry_items       enable row level security;
alter table public.corrections       enable row level security;
alter table public.coach_messages    enable row level security;
alter table public.weight_logs       enable row level security;
alter table public.share_links       enable row level security;
alter table public.share_access_logs enable row level security;
alter table public.notifications     enable row level security;

create policy "own_profile" on public.profiles
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_entries" on public.entries
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_entry_items" on public.entry_items
  using (exists (select 1 from public.entries e where e.id = entry_id and e.user_id = auth.uid()))
  with check (exists (select 1 from public.entries e where e.id = entry_id and e.user_id = auth.uid()));
create policy "own_corrections" on public.corrections
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_coach_messages" on public.coach_messages
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_weight_logs" on public.weight_logs
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_share_links" on public.share_links
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own_share_access_logs_read" on public.share_access_logs
  for select using (exists (
    select 1 from public.share_links s where s.id = share_link_id and s.user_id = auth.uid()
  ));
create policy "own_notifications" on public.notifications
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- PT 뷰는 Edge Function `render-share` 가 service_role 로 처리하므로 RLS 정책을 별도 추가하지 않는다.
-- 함수 내부에서 scope_json 의 허용 컬럼만 SELECT 하도록 코드 레벨에서 보장한다. (§11.3)

-- ── Storage 버킷 (CLI 또는 대시보드에서 별도 생성) ────────────
-- food-photos   private
-- share-thumbs  public (선택)
