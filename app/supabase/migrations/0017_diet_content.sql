-- 0017_diet_content.sql
-- 다이어트 콘텐츠·기능 확장 (docs/superpowers/specs/2026-11-16-diet-content-design.md).
--
--   * entries.feedback          — analyze-entry 가 만드는 한 끼 피드백 + 1탭 보정 질문
--   * entries.source            — 사진 없는 기록(meal_plan / suggestion) 추가.
--                                 image_path 는 NOT NULL 유지, 사진 없음 = '' (구버전 앱 호환)
--   * profiles.goal_mode        — 'lose' | 'maintain' | 'gain' (유지 모드·증량 목표)
--   * profiles.target_weight_basis_kg — 일일 목표를 계산할 때 기준으로 쓴 체중
--   * weekly_checkins           — 주간 체크인 (주 1행)
--   * lessons / lesson_reads    — 2분 마이크로 레슨 + 열람 기록
--   * medication_plans / medication_logs — GLP-1 투약 계획·기록 (기록/알림 전용)
--   * app_events                — 콘텐츠 열람·행동 측정 (insert-only)
--
-- 모든 문장은 재실행해도 안전하도록 if not exists / drop ... if exists 로 작성.
-- 라이브 DB 에는 커밋되지 않은 컬럼(entries.title/note/shared_with_count)이 이미 있다.

-- ── entries ─────────────────────────────────────────────────────────
alter table public.entries add column if not exists feedback jsonb;

alter table public.entries drop constraint if exists entries_source_check;
alter table public.entries add constraint entries_source_check
  check (source in ('camera', 'gallery', 'favorite', 'meal_plan', 'suggestion'));

-- ── profiles ────────────────────────────────────────────────────────
alter table public.profiles add column if not exists goal_mode text not null default 'lose';
alter table public.profiles drop constraint if exists profiles_goal_mode_check;
alter table public.profiles add constraint profiles_goal_mode_check
  check (goal_mode in ('lose', 'maintain', 'gain'));
alter table public.profiles add column if not exists target_weight_basis_kg numeric(5,1);

-- ── 주간 체크인 ─────────────────────────────────────────────────────
create table if not exists public.weekly_checkins (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,
  week_start         date not null,          -- 돌아보는 주의 월요일 (로컬)
  report_json        jsonb not null,
  chosen_experiment  text,
  completed_at       timestamptz,
  source_model       text,
  created_at         timestamptz not null default now(),
  unique (user_id, week_start)
);
create index if not exists weekly_checkins_user_week_idx
  on public.weekly_checkins (user_id, week_start desc);
alter table public.weekly_checkins enable row level security;
drop policy if exists weekly_checkins_own on public.weekly_checkins;
create policy weekly_checkins_own on public.weekly_checkins
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── 레슨 ────────────────────────────────────────────────────────────
create table if not exists public.lessons (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique,
  title         text not null,
  summary       text not null default '',
  body          jsonb not null default '[]'::jsonb,   -- [{t:'p'|'h'|'tip'|'list', text?, items?}]
  tags          text[] not null default '{}',
  read_minutes  smallint not null default 2,
  sources       jsonb not null default '[]'::jsonb,   -- [{label, url}]
  sort          int not null default 100,
  published     boolean not null default true,
  updated_at    timestamptz not null default now()
);
alter table public.lessons enable row level security;
drop policy if exists lessons_read_published on public.lessons;
create policy lessons_read_published on public.lessons
  for select to authenticated
  using (published);

create table if not exists public.lesson_reads (
  user_id    uuid not null references auth.users(id) on delete cascade,
  lesson_id  uuid not null references public.lessons(id) on delete cascade,
  read_at    timestamptz not null default now(),
  primary key (user_id, lesson_id)
);
alter table public.lesson_reads enable row level security;
drop policy if exists lesson_reads_own on public.lesson_reads;
create policy lesson_reads_own on public.lesson_reads
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── GLP-1 투약 (기록·알림 전용 — 용량 조언 없음) ────────────────────
create table if not exists public.medication_plans (
  user_id           uuid primary key references auth.users(id) on delete cascade,
  drug              text not null check (drug in ('wegovy', 'mounjaro', 'other')),
  drug_label        text,
  current_dose_mg   numeric(6,3) not null,
  interval_days     int not null default 7 check (interval_days between 1 and 60),
  start_date        date,
  reminder_enabled  boolean not null default true,
  reminder_hour     smallint not null default 9 check (reminder_hour between 0 and 23),
  active            boolean not null default true,
  coach_context     boolean not null default true,  -- 푸디 조언(LLM)에 'GLP-1 사용 중' 여부만 전달할지
  updated_at        timestamptz not null default now()
);
alter table public.medication_plans enable row level security;
drop policy if exists medication_plans_own on public.medication_plans;
create policy medication_plans_own on public.medication_plans
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create table if not exists public.medication_logs (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  drug        text not null check (drug in ('wegovy', 'mounjaro', 'other')),
  drug_label  text,
  dose_mg     numeric(6,3) not null,
  taken_at    timestamptz not null,
  site        text check (site in ('abdomen', 'thigh', 'arm')),
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists medication_logs_user_taken_idx
  on public.medication_logs (user_id, taken_at desc);
alter table public.medication_logs enable row level security;
drop policy if exists medication_logs_own on public.medication_logs;
create policy medication_logs_own on public.medication_logs
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── 측정 이벤트 (insert-only) ───────────────────────────────────────
create table if not exists public.app_events (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  props       jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists app_events_name_created_idx
  on public.app_events (name, created_at desc);
alter table public.app_events enable row level security;
drop policy if exists app_events_own_insert on public.app_events;
create policy app_events_own_insert on public.app_events
  for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists app_events_own_select on public.app_events;
create policy app_events_own_select on public.app_events
  for select to authenticated
  using (user_id = auth.uid());
drop policy if exists app_events_own_delete on public.app_events;
create policy app_events_own_delete on public.app_events
  for delete to authenticated
  using (user_id = auth.uid());
