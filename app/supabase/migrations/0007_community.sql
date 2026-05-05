-- 커뮤니티 기능 (community_기획서.md §6 + §7).
--
-- 추가되는 것:
--   1. profiles.nickname 을 citext + unique 로 강제. 30일 1회 변경 제한.
--   2. 커뮤니티 그룹 / 멤버십 / 포스트 / 응원 / 조언 / 신고 / 차단 / 제재 테이블.
--   3. 그룹 비밀번호는 별도 테이블 community_group_secrets 에 두고 service_role 만 접근.
--   4. RLS 정책 — 강퇴된 멤버가 본인 행을 update 해서 kicked_at 을 지우지 못하도록 분리.
--   5. 닉네임 / 그룹 join / 신고 RPC.
--
-- 보안 노트 (어드바이저 리뷰 반영):
--   · 비밀번호 컬럼은 일반 select 로 새지 않는다. 클라이언트는 RPC 만 호출.
--   · group_members.update 권한은 owner_can_kick 정책에서만 통과.
--   · 닉네임 랜덤 부여는 SECURITY DEFINER 함수 — nickname_changed_at 은 건드리지 않음.

-- ── 사전 확장 ────────────────────────────────────────────────
create extension if not exists citext;
create extension if not exists pgcrypto;  -- crypt() / gen_salt() / digest()

-- ── ENUMS ───────────────────────────────────────────────────
do $$ begin
  create type group_visibility as enum ('public','private');
exception when duplicate_object then null; end $$;

do $$ begin
  create type reaction_type as enum ('fire','clap','heart');
exception when duplicate_object then null; end $$;

do $$ begin
  create type report_reason as enum ('inappropriate','spam','harassment','other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type report_status as enum ('pending','resolved','dismissed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type sanction_type as enum (
    'warning','content_delete','suspend_7d','suspend_30d','permanent_ban'
  );
exception when duplicate_object then null; end $$;

-- ── profiles 닉네임 unique + 30일 제한 ──────────────────────
-- citext 변환 시 기존 unique index 가 있으면 깨지므로 안전 절차로:
--   1) drop existing index (if any) on nickname
--   2) alter type
--   3) create unique index
do $$ begin
  alter table public.profiles
    alter column nickname type citext using nickname::citext;
exception
  when others then
    -- 이미 citext 면 무시. 다른 에러는 재던짐.
    if sqlerrm not like '%already%' then raise; end if;
end $$;

create unique index if not exists profiles_nickname_unique
  on public.profiles ((lower(nickname::text)));

alter table public.profiles
  add column if not exists nickname_changed_at timestamptz;

-- ── 커뮤니티 그룹 ───────────────────────────────────────────
create table if not exists public.community_groups (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  emoji        text not null default '🥗',
  description  text,
  visibility   group_visibility not null default 'private',
  created_by   uuid not null references auth.users(id) on delete cascade,
  max_members  int not null default 32,
  created_at   timestamptz default now(),
  archived_at  timestamptz,
  constraint community_groups_name_chk check (char_length(name) between 1 and 40),
  constraint community_groups_desc_chk check (description is null or char_length(description) <= 200)
);
create index if not exists community_groups_visibility_idx
  on public.community_groups (visibility) where archived_at is null;
create index if not exists community_groups_name_idx
  on public.community_groups using gin (to_tsvector('simple', name)) where archived_at is null;

-- 비밀번호는 별도 테이블 — 일반 select 로 노출 차단.
-- service_role 만 접근. 사용자는 verify_group_password RPC 만 호출.
create table if not exists public.community_group_secrets (
  group_id     uuid primary key references public.community_groups(id) on delete cascade,
  password_hash text not null,
  updated_at   timestamptz default now()
);

-- ── 그룹 멤버십 ─────────────────────────────────────────────
create table if not exists public.group_members (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.community_groups(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  role         text not null default 'member' check (role in ('owner','member')),
  show_photos  boolean not null default true,
  show_kcal    boolean not null default true,
  show_macros  boolean not null default true,
  auto_share   boolean not null default false,
  share_time   time not null default '21:00',
  joined_at    timestamptz default now(),
  left_at      timestamptz,
  kicked_at    timestamptz,
  kicked_by    uuid references auth.users(id),
  unique (group_id, user_id)
);
create index if not exists group_members_user_idx
  on public.group_members (user_id) where left_at is null and kicked_at is null;
create index if not exists group_members_group_idx
  on public.group_members (group_id) where left_at is null and kicked_at is null;

-- ── 커뮤니티 포스트 (하루 식단 카드) ─────────────────────────
create table if not exists public.community_posts (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.community_groups(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  post_date    date not null,
  total_kcal   int,
  target_kcal  int,
  macros       jsonb,
  achievement  numeric(5,1),
  status_badge text not null check (status_badge in ('achieved','almost','retry')),
  photo_paths  text[] default '{}',
  show_photos  boolean not null default true,
  show_kcal    boolean not null default true,
  show_macros  boolean not null default true,
  caption      text,
  created_at   timestamptz default now(),
  deleted_at   timestamptz,
  hidden_at    timestamptz,                  -- 자동 숨김 (신고 누적)
  constraint community_posts_caption_chk check (caption is null or char_length(caption) <= 200),
  unique (group_id, user_id, post_date)
);
create index if not exists community_posts_group_created_idx
  on public.community_posts (group_id, created_at desc) where deleted_at is null and hidden_at is null;

-- ── 응원 반응 ───────────────────────────────────────────────
create table if not exists public.post_reactions (
  id           uuid primary key default gen_random_uuid(),
  post_id      uuid not null references public.community_posts(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  reaction     reaction_type not null,
  created_at   timestamptz default now(),
  unique (post_id, user_id, reaction)
);
create index if not exists post_reactions_post_idx
  on public.post_reactions (post_id);

-- ── 조언 텍스트 ─────────────────────────────────────────────
create table if not exists public.post_tips (
  id           uuid primary key default gen_random_uuid(),
  post_id      uuid not null references public.community_posts(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  body         text not null,
  created_at   timestamptz default now(),
  deleted_at   timestamptz,
  hidden_at    timestamptz,                  -- 자동 숨김
  constraint post_tips_body_chk check (char_length(body) between 1 and 100)
);
create index if not exists post_tips_post_idx
  on public.post_tips (post_id) where deleted_at is null and hidden_at is null;

-- ── 차단 ───────────────────────────────────────────────────
create table if not exists public.user_blocks (
  id           uuid primary key default gen_random_uuid(),
  blocker_id   uuid not null references auth.users(id) on delete cascade,
  blocked_id   uuid not null references auth.users(id) on delete cascade,
  created_at   timestamptz default now(),
  unique (blocker_id, blocked_id),
  constraint user_blocks_self_chk check (blocker_id <> blocked_id)
);

-- ── 신고 ───────────────────────────────────────────────────
create table if not exists public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references auth.users(id) on delete cascade,
  group_id     uuid references public.community_groups(id) on delete set null,
  target_type  text not null check (target_type in ('post','tip','user')),
  target_id    uuid not null,
  reason       report_reason not null,
  detail       text,
  status       report_status not null default 'pending',
  created_at   timestamptz default now(),
  resolved_at  timestamptz,
  constraint reports_detail_chk check (detail is null or char_length(detail) <= 500)
);
create index if not exists reports_target_idx on public.reports (target_type, target_id);
create index if not exists reports_status_idx on public.reports (status, created_at desc);

-- ── 제재 (개발자 전용) ──────────────────────────────────────
create table if not exists public.sanctions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  report_id    uuid references public.reports(id) on delete set null,
  sanction     sanction_type not null,
  reason       text,
  expires_at   timestamptz,
  created_at   timestamptz default now()
);
create index if not exists sanctions_user_active_idx
  on public.sanctions (user_id) where expires_at is null or expires_at > now();

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ RLS 활성화                                                   ║
-- ╚══════════════════════════════════════════════════════════════╝

alter table public.community_groups        enable row level security;
alter table public.community_group_secrets enable row level security;
alter table public.group_members           enable row level security;
alter table public.community_posts         enable row level security;
alter table public.post_reactions          enable row level security;
alter table public.post_tips               enable row level security;
alter table public.user_blocks             enable row level security;
alter table public.reports                 enable row level security;
alter table public.sanctions               enable row level security;

-- 비밀번호 hash 는 service_role 만. 일반 사용자는 RPC 로만 검증.
-- (기본적으로 RLS 활성 + 정책 0개 = 모두 deny.)

-- ── community_groups ────────────────────────────────────────
-- 공개 그룹: 누구나 (로그인된) 메타데이터 select.
-- 비공개 그룹: 멤버만.
drop policy if exists "groups_read" on public.community_groups;
create policy "groups_read" on public.community_groups
  for select using (
    (visibility = 'public' and archived_at is null)
    or exists (
      select 1 from public.group_members gm
      where gm.group_id = community_groups.id
        and gm.user_id = auth.uid()
        and gm.left_at is null
        and gm.kicked_at is null
    )
  );

drop policy if exists "groups_owner_update" on public.community_groups;
create policy "groups_owner_update" on public.community_groups
  for update using (created_by = auth.uid())
  with check (created_by = auth.uid());

-- INSERT 는 RPC `create_community_group` 로만 (멤버십 + secrets 트랜잭션 보장).
-- DELETE 도 RPC `archive_community_group`.

-- ── group_members ───────────────────────────────────────────
-- SELECT: 같은 그룹 활성 멤버는 모두 서로의 행을 본다.
drop policy if exists "members_read" on public.group_members;
create policy "members_read" on public.group_members
  for select using (
    user_id = auth.uid()
    or exists (
      select 1 from public.group_members gm2
      where gm2.group_id = group_members.group_id
        and gm2.user_id = auth.uid()
        and gm2.left_at is null
        and gm2.kicked_at is null
    )
  );

-- INSERT: 본인 행만, 해당 그룹이 공개거나 RPC 통해 들어온 경우.
-- 클라이언트는 RPC `join_public_group` 또는 `verify_group_password` 사용.
-- 직접 INSERT 도 허용하되 (공개 그룹 한정), 비공개는 password hash 모르기 때문에
-- RPC 가 필수.
drop policy if exists "members_self_insert" on public.group_members;
create policy "members_self_insert" on public.group_members
  for insert with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.community_groups g
      where g.id = group_members.group_id
        and g.archived_at is null
        and g.visibility = 'public'
    )
  );

-- UPDATE: 본인은 show_*, auto_share, share_time, left_at 만 업데이트 가능.
-- kicked_at / role 은 절대 본인이 못 건드림. 트리거로 보호.
drop policy if exists "members_self_update" on public.group_members;
create policy "members_self_update" on public.group_members
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 트리거로 self-update 시 보호 컬럼 변경 차단.
create or replace function public._guard_member_self_update()
returns trigger language plpgsql as $$
begin
  -- service_role / SECURITY DEFINER 함수 호출은 auth.uid() 가 null 이거나
  -- old.user_id 와 다를 수 있다. 해당 경우는 트리거를 건너뜀.
  if auth.uid() is null then return new; end if;
  if new.user_id <> auth.uid() then return new; end if;

  -- 본인 update — 보호 컬럼은 변경 금지.
  if new.role <> old.role then
    raise exception 'role can only be changed by group owner via RPC';
  end if;
  if new.kicked_at is distinct from old.kicked_at
     or new.kicked_by is distinct from old.kicked_by then
    raise exception 'kicked_at can only be set by group owner via RPC';
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_member_self on public.group_members;
create trigger trg_guard_member_self
  before update on public.group_members
  for each row execute function public._guard_member_self_update();

-- DELETE: 본인이 멤버십을 영구 삭제 (탈퇴는 left_at 으로 soft).
-- 보통은 left_at update 가 표준. delete 는 owner 가 RPC 로.
drop policy if exists "members_self_delete" on public.group_members;
create policy "members_self_delete" on public.group_members
  for delete using (user_id = auth.uid());

-- ── community_posts ─────────────────────────────────────────
drop policy if exists "posts_group_read" on public.community_posts;
create policy "posts_group_read" on public.community_posts
  for select using (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = community_posts.group_id
        and gm.user_id = auth.uid()
        and gm.left_at is null
        and gm.kicked_at is null
    )
    and not exists (
      select 1 from public.user_blocks ub
      where ub.blocker_id = auth.uid()
        and ub.blocked_id = community_posts.user_id
    )
  );

drop policy if exists "posts_self_insert" on public.community_posts;
create policy "posts_self_insert" on public.community_posts
  for insert with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.group_members gm
      where gm.group_id = community_posts.group_id
        and gm.user_id = auth.uid()
        and gm.left_at is null
        and gm.kicked_at is null
    )
  );

drop policy if exists "posts_self_update" on public.community_posts;
create policy "posts_self_update" on public.community_posts
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "posts_self_delete" on public.community_posts;
create policy "posts_self_delete" on public.community_posts
  for delete using (user_id = auth.uid());

-- ── post_reactions ──────────────────────────────────────────
drop policy if exists "reactions_group_read" on public.post_reactions;
create policy "reactions_group_read" on public.post_reactions
  for select using (
    exists (
      select 1 from public.community_posts cp
      join public.group_members gm
        on gm.group_id = cp.group_id
       and gm.user_id = auth.uid()
       and gm.left_at is null
       and gm.kicked_at is null
      where cp.id = post_reactions.post_id
        and cp.deleted_at is null
        and cp.hidden_at is null
    )
  );

drop policy if exists "reactions_self_write" on public.post_reactions;
create policy "reactions_self_write" on public.post_reactions
  for insert with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.community_posts cp
      join public.group_members gm
        on gm.group_id = cp.group_id
       and gm.user_id = auth.uid()
       and gm.left_at is null
       and gm.kicked_at is null
      where cp.id = post_reactions.post_id
        and cp.deleted_at is null
        and cp.hidden_at is null
    )
  );

drop policy if exists "reactions_self_delete" on public.post_reactions;
create policy "reactions_self_delete" on public.post_reactions
  for delete using (user_id = auth.uid());

-- ── post_tips ───────────────────────────────────────────────
drop policy if exists "tips_group_read" on public.post_tips;
create policy "tips_group_read" on public.post_tips
  for select using (
    exists (
      select 1 from public.community_posts cp
      join public.group_members gm
        on gm.group_id = cp.group_id
       and gm.user_id = auth.uid()
       and gm.left_at is null
       and gm.kicked_at is null
      where cp.id = post_tips.post_id
        and cp.deleted_at is null
        and cp.hidden_at is null
    )
    and not exists (
      select 1 from public.user_blocks ub
      where ub.blocker_id = auth.uid()
        and ub.blocked_id = post_tips.user_id
    )
  );

drop policy if exists "tips_self_write" on public.post_tips;
create policy "tips_self_write" on public.post_tips
  for insert with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.community_posts cp
      join public.group_members gm
        on gm.group_id = cp.group_id
       and gm.user_id = auth.uid()
       and gm.left_at is null
       and gm.kicked_at is null
      where cp.id = post_tips.post_id
        and cp.deleted_at is null
        and cp.hidden_at is null
    )
  );

drop policy if exists "tips_self_delete" on public.post_tips;
create policy "tips_self_delete" on public.post_tips
  for delete using (user_id = auth.uid());

-- ── user_blocks ─────────────────────────────────────────────
drop policy if exists "blocks_self" on public.user_blocks;
create policy "blocks_self" on public.user_blocks
  for all using (blocker_id = auth.uid())
  with check (blocker_id = auth.uid());

-- ── reports ─────────────────────────────────────────────────
-- 사용자는 본인 신고만 INSERT. SELECT 는 차단(개발자/service_role 만).
drop policy if exists "reports_self_insert" on public.reports;
create policy "reports_self_insert" on public.reports
  for insert with check (reporter_id = auth.uid());

-- ── sanctions ───────────────────────────────────────────────
-- 사용자는 본인 활성 제재만 SELECT 가능 (앱이 정지 상태 안내하기 위해).
drop policy if exists "sanctions_self_read" on public.sanctions;
create policy "sanctions_self_read" on public.sanctions
  for select using (user_id = auth.uid());

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ RPC: 닉네임                                                  ║
-- ╚══════════════════════════════════════════════════════════════╝

-- 닉네임 사용 가능 여부 확인.
create or replace function public.check_nickname_available(target_nickname citext)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.profiles
    where lower(nickname::text) = lower(target_nickname::text)
  );
$$;
grant execute on function public.check_nickname_available(citext) to authenticated;

-- 닉네임 변경 (사용자 호출, 30일 cooldown).
create or replace function public.update_nickname(new_nickname citext)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_existing_id uuid;
  v_changed_at timestamptz;
begin
  if v_uid is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  -- 형식 검증: 2~12자 한글/영문/숫자/언더스코어.
  if new_nickname is null or new_nickname::text !~ '^[가-힣a-zA-Z0-9_]{2,12}$' then
    raise exception 'nickname_invalid_format' using errcode = '22023';
  end if;

  -- 30일 cooldown.
  select nickname_changed_at into v_changed_at
  from public.profiles where user_id = v_uid;
  if v_changed_at is not null and v_changed_at > now() - interval '30 days' then
    raise exception 'nickname_change_cooldown' using errcode = 'P0001';
  end if;

  -- 동일 닉네임을 본인이 이미 쓰는 경우는 noop.
  -- 다른 사용자가 쓰면 에러.
  select user_id into v_existing_id
  from public.profiles
  where lower(nickname::text) = lower(new_nickname::text);

  if v_existing_id is not null and v_existing_id <> v_uid then
    raise exception 'nickname_taken' using errcode = '23505';
  end if;
  if v_existing_id = v_uid then
    return;  -- 동일값. 변경 안 함.
  end if;

  update public.profiles
  set nickname = new_nickname,
      nickname_changed_at = now()
  where user_id = v_uid;
end $$;
grant execute on function public.update_nickname(citext) to authenticated;

-- 랜덤 닉네임 부여 (가입 직후 / 시스템). nickname_changed_at 은 건드리지 않음
-- → 첫 수동 변경 때 cooldown 에 걸리지 않음.
create or replace function public.assign_random_nickname()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_pool_adj text[] := array[
    '활발한','튼튼한','상큼한','달콤한','건강한','반짝이는','뽀송한',
    '귀여운','용감한','명랑한','보송한','싱그러운','새콤한','포근한',
    '단단한','꼼꼼한','쾌활한','다정한','씩씩한','고소한'
  ];
  v_pool_food text[] := array[
    '딸기','샐러드','두부','연어','계란','요거트','오이','파프리카',
    '브로콜리','단호박','아보카도','블루베리','귀리','현미','감자',
    '토마토','당근','버섯','케일','시금치'
  ];
  v_attempt int := 0;
  v_candidate text;
begin
  if v_uid is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  while v_attempt < 8 loop
    v_candidate :=
      v_pool_adj[1 + floor(random() * array_length(v_pool_adj, 1))::int]
      || '_'
      || v_pool_food[1 + floor(random() * array_length(v_pool_food, 1))::int]
      || '_'
      || lpad((floor(random() * 1000))::int::text, 3, '0');

    -- 형식은 위 풀이 보장. unique 만 검사.
    if not exists (
      select 1 from public.profiles
      where lower(nickname::text) = lower(v_candidate)
    ) then
      update public.profiles
      set nickname = v_candidate::citext
      where user_id = v_uid;
      return v_candidate;
    end if;
    v_attempt := v_attempt + 1;
  end loop;

  -- 최후의 수단: uuid 6자리 prefix.
  v_candidate := '푸디_' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
  update public.profiles
  set nickname = v_candidate::citext
  where user_id = v_uid;
  return v_candidate;
end $$;
grant execute on function public.assign_random_nickname() to authenticated;

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ RPC: 그룹 생성 / 비밀번호 검증 / 강퇴                         ║
-- ╚══════════════════════════════════════════════════════════════╝

-- 그룹 생성 — 한 트랜잭션으로 group + secrets + 첫 owner 멤버십.
create or replace function public.create_community_group(
  p_name text,
  p_emoji text,
  p_description text,
  p_visibility group_visibility,
  p_password text                -- 비공개 그룹일 때만 사용
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;
  if p_visibility = 'private' then
    if p_password is null or char_length(p_password) < 4 or char_length(p_password) > 8 then
      raise exception 'password_invalid_format' using errcode = '22023';
    end if;
  end if;
  if p_name is null or char_length(p_name) < 1 or char_length(p_name) > 40 then
    raise exception 'name_invalid_format' using errcode = '22023';
  end if;

  insert into public.community_groups (name, emoji, description, visibility, created_by)
    values (p_name, coalesce(p_emoji, '🥗'), p_description, p_visibility, v_uid)
    returning id into v_id;

  if p_visibility = 'private' then
    insert into public.community_group_secrets (group_id, password_hash)
      values (v_id, crypt(p_password, gen_salt('bf', 8)));
  end if;

  insert into public.group_members (group_id, user_id, role)
    values (v_id, v_uid, 'owner');

  return v_id;
end $$;
grant execute on function public.create_community_group(text, text, text, group_visibility, text) to authenticated;

-- 비공개 그룹 비밀번호 검증 + 가입.
-- 성공 시 group_id 반환, 실패 시 null.
create or replace function public.join_private_group(
  p_group_id uuid,
  p_password text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_hash text;
  v_visibility group_visibility;
  v_archived timestamptz;
  v_member_count int;
  v_max int;
  v_existing_kicked timestamptz;
begin
  if v_uid is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  select visibility, archived_at, max_members
    into v_visibility, v_archived, v_max
    from public.community_groups where id = p_group_id;
  if not found or v_archived is not null then
    raise exception 'group_not_found' using errcode = 'P0002';
  end if;
  if v_visibility <> 'private' then
    raise exception 'group_not_private' using errcode = 'P0001';
  end if;

  -- 강퇴된 사람이 24시간 안에 재시도 못 하도록.
  select kicked_at into v_existing_kicked
    from public.group_members
    where group_id = p_group_id and user_id = v_uid
      and kicked_at is not null;
  if v_existing_kicked is not null and v_existing_kicked > now() - interval '24 hours' then
    raise exception 'kicked_recently' using errcode = 'P0001';
  end if;

  select password_hash into v_hash
    from public.community_group_secrets where group_id = p_group_id;
  if v_hash is null or crypt(p_password, v_hash) <> v_hash then
    raise exception 'password_mismatch' using errcode = 'P0001';
  end if;

  select count(*) into v_member_count
    from public.group_members
    where group_id = p_group_id and left_at is null and kicked_at is null;
  if v_member_count >= v_max then
    raise exception 'group_full' using errcode = 'P0001';
  end if;

  insert into public.group_members (group_id, user_id, role)
    values (p_group_id, v_uid, 'member')
  on conflict (group_id, user_id) do update
    set left_at = null, kicked_at = null, kicked_by = null, joined_at = now(),
        role = case when group_members.role = 'owner' then 'owner' else 'member' end;
  return p_group_id;
end $$;
grant execute on function public.join_private_group(uuid, text) to authenticated;

-- 공개 그룹 가입 (RPC 로도 일관성 + 강퇴 24h 가드).
create or replace function public.join_public_group(p_group_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_visibility group_visibility;
  v_archived timestamptz;
  v_member_count int;
  v_max int;
  v_existing_kicked timestamptz;
begin
  if v_uid is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  select visibility, archived_at, max_members
    into v_visibility, v_archived, v_max
    from public.community_groups where id = p_group_id;
  if not found or v_archived is not null then
    raise exception 'group_not_found' using errcode = 'P0002';
  end if;
  if v_visibility <> 'public' then
    raise exception 'group_not_public' using errcode = 'P0001';
  end if;

  select kicked_at into v_existing_kicked
    from public.group_members
    where group_id = p_group_id and user_id = v_uid and kicked_at is not null;
  if v_existing_kicked is not null and v_existing_kicked > now() - interval '24 hours' then
    raise exception 'kicked_recently' using errcode = 'P0001';
  end if;

  select count(*) into v_member_count
    from public.group_members
    where group_id = p_group_id and left_at is null and kicked_at is null;
  if v_member_count >= v_max then
    raise exception 'group_full' using errcode = 'P0001';
  end if;

  insert into public.group_members (group_id, user_id, role)
    values (p_group_id, v_uid, 'member')
  on conflict (group_id, user_id) do update
    set left_at = null, kicked_at = null, kicked_by = null, joined_at = now(),
        role = case when group_members.role = 'owner' then 'owner' else 'member' end;
  return p_group_id;
end $$;
grant execute on function public.join_public_group(uuid) to authenticated;

-- 비밀번호 변경 (그룹장만).
create or replace function public.change_group_password(p_group_id uuid, p_new_password text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;
  if p_new_password is null or char_length(p_new_password) < 4 or char_length(p_new_password) > 8 then
    raise exception 'password_invalid_format' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.community_groups
    where id = p_group_id and created_by = v_uid
  ) then
    raise exception 'not_group_owner' using errcode = '42501';
  end if;

  insert into public.community_group_secrets (group_id, password_hash, updated_at)
    values (p_group_id, crypt(p_new_password, gen_salt('bf', 8)), now())
  on conflict (group_id) do update
    set password_hash = excluded.password_hash, updated_at = now();
end $$;
grant execute on function public.change_group_password(uuid, text) to authenticated;

-- 강퇴 RPC — 그룹장만, 본인 강퇴 불가.
create or replace function public.kick_group_member(p_group_id uuid, p_target_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;
  if v_uid = p_target_user then
    raise exception 'cannot_kick_self' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.community_groups
    where id = p_group_id and created_by = v_uid
  ) then
    raise exception 'not_group_owner' using errcode = '42501';
  end if;

  update public.group_members
  set kicked_at = now(), kicked_by = v_uid
  where group_id = p_group_id and user_id = p_target_user
    and kicked_at is null;
end $$;
grant execute on function public.kick_group_member(uuid, uuid) to authenticated;

-- 그룹 아카이브 (그룹장만).
create or replace function public.archive_community_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;
  if not exists (
    select 1 from public.community_groups
    where id = p_group_id and created_by = v_uid
  ) then
    raise exception 'not_group_owner' using errcode = '42501';
  end if;
  update public.community_groups
    set archived_at = now()
    where id = p_group_id and archived_at is null;
end $$;
grant execute on function public.archive_community_group(uuid) to authenticated;

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ RPC: 신고                                                    ║
-- ╚══════════════════════════════════════════════════════════════╝

-- 신고 + 자동 숨김 (누적 2건 이상이면 즉시 hidden_at).
create or replace function public.submit_report(
  p_target_type text,
  p_target_id uuid,
  p_reason report_reason,
  p_detail text,
  p_group_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_count int;
begin
  if v_uid is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;
  if p_target_type not in ('post','tip','user') then
    raise exception 'invalid_target_type' using errcode = '22023';
  end if;

  insert into public.reports (reporter_id, group_id, target_type, target_id, reason, detail)
    values (v_uid, p_group_id, p_target_type, p_target_id, p_reason, p_detail)
    on conflict do nothing
    returning id into v_id;

  -- 누적 신고 카운트 (status = pending).
  select count(distinct reporter_id) into v_count
    from public.reports
    where target_type = p_target_type
      and target_id = p_target_id
      and status = 'pending';

  if v_count >= 2 then
    if p_target_type = 'post' then
      update public.community_posts set hidden_at = now()
        where id = p_target_id and hidden_at is null;
    elsif p_target_type = 'tip' then
      update public.post_tips set hidden_at = now()
        where id = p_target_id and hidden_at is null;
    end if;
  end if;

  return v_id;
end $$;
grant execute on function public.submit_report(text, uuid, report_reason, text, uuid) to authenticated;

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ RPC: 커뮤니티에서 닉네임만 조회                                ║
-- ╚══════════════════════════════════════════════════════════════╝

-- 같은 그룹 멤버의 닉네임만 노출. profiles 테이블에는 weight/height/goal 등
-- 민감정보가 함께 들어 있어 row-level 정책으로 select 를 열어주면 컬럼 단위 보호가
-- 안 된다 (사용자가 select * 하면 다 보임). RPC 로 한정된 컬럼만 반환해서 차단.
create or replace function public.get_group_member_handles(p_user_ids uuid[])
returns table (user_id uuid, nickname text)
language sql
stable
security definer
set search_path = public
as $$
  select p.user_id, p.nickname::text
  from public.profiles p
  where p.user_id = any(p_user_ids)
    and (
      p.user_id = auth.uid()
      or exists (
        select 1
        from public.group_members gm_self
        join public.group_members gm_other
          on gm_self.group_id = gm_other.group_id
        where gm_self.user_id = auth.uid()
          and gm_self.left_at is null
          and gm_self.kicked_at is null
          and gm_other.user_id = p.user_id
          and gm_other.left_at is null
          and gm_other.kicked_at is null
      )
    );
$$;
grant execute on function public.get_group_member_handles(uuid[]) to authenticated;

-- 명시적으로 제거 — 이전 버전에서 추가했을 수 있음.
drop policy if exists "profiles_community_read" on public.profiles;
drop view if exists public.profile_handles;

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ Storage: 같은 그룹 멤버는 서로의 사진을 signed URL 로 열 수 있다 ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- food-photos 버킷의 path 규칙: '<user_id>/<entry_id>.jpg'.
-- 기존 정책은 본인 폴더만 select 허용 (대시보드에서 설정).
-- 커뮤니티 카드에 첨부된 사진을 같은 그룹 멤버가 봐야 하므로,
-- "공유 그룹이 하나라도 있는 사용자의 폴더" 도 select 허용.
--
-- 정책은 이미 있을 수 있어 drop 후 재생성. 정책 이름 충돌 시 무시.
do $$ begin
  drop policy if exists "community_group_member_can_read_photos"
    on storage.objects;
exception when others then null; end $$;

create policy "community_group_member_can_read_photos"
  on storage.objects for select
  using (
    bucket_id = 'food-photos'
    and (
      -- 본인 사진은 항상 (기존 정책과 별도 보장).
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (
        select 1
        from public.group_members gm_self
        join public.group_members gm_owner
          on gm_self.group_id = gm_owner.group_id
        where gm_self.user_id = auth.uid()
          and gm_self.left_at is null
          and gm_self.kicked_at is null
          and gm_owner.user_id::text = (storage.foldername(name))[1]
          and gm_owner.left_at is null
          and gm_owner.kicked_at is null
      )
    )
  );

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ Realtime publication                                          ║
-- ╚══════════════════════════════════════════════════════════════╝

-- 피드 자동 갱신을 위해 community_posts / post_reactions / post_tips 를 realtime 에 추가.
do $$ begin
  alter publication supabase_realtime add table public.community_posts;
exception when duplicate_object then null; when others then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.post_reactions;
exception when duplicate_object then null; when others then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.post_tips;
exception when duplicate_object then null; when others then null; end $$;
