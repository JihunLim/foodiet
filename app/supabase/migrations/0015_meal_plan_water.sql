-- 0015_meal_plan_water.sql
-- 식단 추천(meal_plans) + 물 마시기 트래킹(water_logs) 인프라.
--
-- 정책 요약:
--   * 식단은 한 주에 1회만 생성 가능 (week_start_date 단위 unique).
--   * 1일 1회 추가 cooldown 은 클라/Edge Function 레벨에서도 검증 — 단,
--     DB 진입 이중 안전망으로 동일 주차 unique 가 fallback.
--   * 물은 user_id + log_date 키로 일별 카운트.

-- ── 식단 추천 ─────────────────────────────────────────────────────────
create table if not exists public.meal_plans (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users(id) on delete cascade,
  created_at          timestamptz not null default now(),
  week_start_date     date not null,  -- 월요일 기준 (KST)

  -- 폼 입력 (산출 근거 표시용)
  allergies           text[] not null default '{}',
  allergy_notes       text,
  ingredients         text[] not null default '{}',
  ingredient_notes    text,
  cuisine_styles      text[] not null default '{}',
  meal_slots          text[] not null default '{}',  -- ['breakfast','lunch','dinner','snack'] 중 선택

  -- 생성 시점 스냅샷 (사용자 프로필이 바뀌어도 카드의 근거는 보존)
  goal_weight_kg      numeric(5,1),
  current_weight_kg   numeric(5,1),
  daily_kcal_target   int,
  activity_level      smallint,

  -- GPT 응답 본문 + 메타
  plan_json           jsonb not null,
  source_model        text not null,
  status              text not null default 'done'
                          check (status in ('pending','done','failed')),

  -- 한 주에 한 번만
  unique (user_id, week_start_date)
);
create index if not exists meal_plans_user_created_idx
  on public.meal_plans (user_id, created_at desc);

alter table public.meal_plans enable row level security;
drop policy if exists meal_plans_own_select on public.meal_plans;
create policy meal_plans_own_select on public.meal_plans
  for select to authenticated
  using (user_id = auth.uid());
drop policy if exists meal_plans_own_insert on public.meal_plans;
create policy meal_plans_own_insert on public.meal_plans
  for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists meal_plans_own_update on public.meal_plans;
create policy meal_plans_own_update on public.meal_plans
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
drop policy if exists meal_plans_own_delete on public.meal_plans;
create policy meal_plans_own_delete on public.meal_plans
  for delete to authenticated
  using (user_id = auth.uid());

-- ── 물 트래킹 ────────────────────────────────────────────────────────
create table if not exists public.water_logs (
  user_id     uuid not null references auth.users(id) on delete cascade,
  log_date    date not null,
  cups        int  not null default 0 check (cups >= 0),
  target_cups int  not null default 8 check (target_cups > 0),
  cup_ml      int  not null default 150 check (cup_ml > 0),
  updated_at  timestamptz not null default now(),
  primary key (user_id, log_date)
);

alter table public.water_logs enable row level security;
drop policy if exists water_logs_own_select on public.water_logs;
create policy water_logs_own_select on public.water_logs
  for select to authenticated
  using (user_id = auth.uid());
drop policy if exists water_logs_own_insert on public.water_logs;
create policy water_logs_own_insert on public.water_logs
  for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists water_logs_own_update on public.water_logs;
create policy water_logs_own_update on public.water_logs
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ── 권장 물 컵 수 계산 RPC ──────────────────────────────────────────
-- 공식 (단순·보수적):
--   base_ml      = weight_kg * 32 (없으면 60kg 가정)
--   sex_factor   = 남: ×1.05, 여: ×0.95 (없으면 1.0)
--   activity_ml  = (activity_level - 1) × 200   (1=0, 5=800)
--   kcal_ml      = (daily_kcal_target - 1600) × 0.4  (음수면 0)
--   total_ml     = base_ml × sex_factor + activity_ml + kcal_ml
--   target_cups  = round(total_ml / 150),  최소 6 / 최대 16
-- 모든 인자는 profiles 에서 읽되 null 안전.
create or replace function public.recommended_water_cups(p_user_id uuid default null)
returns table (target_cups int, cup_ml int, daily_ml int)
language sql security invoker
set search_path = public
as $$
  with p as (
    select coalesce(weight_kg, 60) as weight_kg,
           sex,
           coalesce(activity_level, 2) as activity_level,
           coalesce(daily_kcal_target, 1800) as daily_kcal_target
    from public.profiles
    where user_id = coalesce(p_user_id, auth.uid())
  ),
  calc as (
    select
      (weight_kg * 32) *
        case sex when 'male' then 1.05 when 'female' then 0.95 else 1.0 end
      + (activity_level - 1) * 200
      + greatest(0, (daily_kcal_target - 1600) * 0.4)
      as total_ml
    from p
  )
  select
    least(16, greatest(6, round(total_ml / 150.0)::int)) as target_cups,
    150 as cup_ml,
    round(total_ml)::int as daily_ml
  from calc;
$$;

revoke all on function public.recommended_water_cups(uuid) from public;
grant execute on function public.recommended_water_cups(uuid) to authenticated;

-- ── 물 컵 증감 upsert (편의 RPC) ─────────────────────────────────────
-- 클라가 single round-trip 으로 카운트 갱신.
create or replace function public.upsert_water_log(
  p_log_date date,
  p_cups     int,
  p_target_cups int default null,
  p_cup_ml   int default 150
) returns void
language plpgsql security invoker
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  insert into public.water_logs (user_id, log_date, cups, target_cups, cup_ml)
  values (uid, p_log_date, greatest(0, p_cups),
          coalesce(p_target_cups, 8), p_cup_ml)
  on conflict (user_id, log_date) do update
    set cups        = greatest(0, p_cups),
        target_cups = coalesce(p_target_cups, public.water_logs.target_cups),
        cup_ml      = p_cup_ml,
        updated_at  = now();
end;
$$;

revoke all on function public.upsert_water_log(date, int, int, int) from public;
grant execute on function public.upsert_water_log(date, int, int, int) to authenticated;
