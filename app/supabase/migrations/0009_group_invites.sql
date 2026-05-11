-- 그룹 초대 (group invites).
--
-- 기획: 그룹 멤버가 같은 앱 사용자(닉네임 기반)를 초대 → 마이 탭의
-- "그룹 초대장"에서 수락하면 그룹 가입.
--
-- 보안 노트:
--   · 초대 INSERT/UPDATE 모두 RPC 만. 직접 INSERT 차단.
--   · SELECT 는 발신자/수신자 본인만 (그룹 멤버 전체에는 미공개 — 누가
--     초대됐는지는 본인과 보낸 사람만 안다).
--   · 사용자 디렉토리 RPC 는 nickname/user_id 만 반환 — profiles 의
--     weight/height/birth_date/sex 같은 PII 누출 차단.
--   · 강퇴 24h 가드, max_members, 차단(blocks) 모두 join 와 같은 규칙.
--   · accept 의 max_members 검사는 insert → count → 초과 시 raise 로
--     race 차단 (count → insert 순서면 동시 수락에서 +1 가능).

-- ── 테이블 ─────────────────────────────────────────────────────────
create table if not exists public.group_invites (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.community_groups(id) on delete cascade,
  inviter_id   uuid not null references auth.users(id) on delete cascade,
  invitee_id   uuid not null references auth.users(id) on delete cascade,
  status       text not null default 'pending'
                 check (status in ('pending','accepted','declined','expired')),
  created_at   timestamptz default now(),
  responded_at timestamptz,
  expires_at   timestamptz default (now() + interval '14 days'),
  constraint group_invites_self_chk check (inviter_id <> invitee_id)
);

-- 같은 (group, invitee) 에 동시 pending 하나만 허용 — 중복 초대 차단.
-- accepted/declined 는 히스토리로 남으니 unique 에서 제외.
create unique index if not exists group_invites_pending_unique
  on public.group_invites (group_id, invitee_id) where status = 'pending';
create index if not exists group_invites_invitee_pending_idx
  on public.group_invites (invitee_id, created_at desc) where status = 'pending';
create index if not exists group_invites_group_idx
  on public.group_invites (group_id);

-- ── RLS ────────────────────────────────────────────────────────────
alter table public.group_invites enable row level security;

-- SELECT: 본인이 보낸 / 받은 초대만. 그룹 다른 멤버에는 미공개.
drop policy if exists "invites_self_read" on public.group_invites;
create policy "invites_self_read" on public.group_invites
  for select using (
    invitee_id = auth.uid() or inviter_id = auth.uid()
  );

-- INSERT/UPDATE 정책 없음 = 직접 못 함. 모든 쓰기는 SECURITY DEFINER RPC.

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ RPC: 초대 보내기                                              ║
-- ╚══════════════════════════════════════════════════════════════╝
create or replace function public.send_group_invite(
  p_group_id uuid,
  p_invitee_id uuid
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_archived timestamptz;
  v_max int;
  v_member_count int;
  v_existing_kicked timestamptz;
  v_already_pending uuid;
begin
  if v_uid is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;
  if v_uid = p_invitee_id then
    raise exception 'cannot_invite_self' using errcode = 'P0001';
  end if;

  -- 그룹 존재/활성 + max 정원.
  select archived_at, max_members
    into v_archived, v_max
    from public.community_groups where id = p_group_id;
  if not found or v_archived is not null then
    raise exception 'group_not_found' using errcode = 'P0002';
  end if;

  -- 호출자가 활성 멤버여야 초대 가능 (0008 helper 재사용).
  if not public.is_member_of_group(p_group_id) then
    raise exception 'not_group_member' using errcode = '42501';
  end if;

  -- 양방향 차단 확인 — 누가 누구를 차단했든 초대 차단.
  if exists (
    select 1 from public.user_blocks
    where (blocker_id = v_uid and blocked_id = p_invitee_id)
       or (blocker_id = p_invitee_id and blocked_id = v_uid)
  ) then
    raise exception 'blocked' using errcode = 'P0001';
  end if;

  -- 이미 활성 멤버면 초대 의미 없음.
  if exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = p_invitee_id
      and left_at is null and kicked_at is null
  ) then
    raise exception 'already_member' using errcode = 'P0001';
  end if;

  -- 강퇴 24h 안엔 초대 거부 — join_*_group 와 같은 정책.
  select kicked_at into v_existing_kicked
    from public.group_members
    where group_id = p_group_id and user_id = p_invitee_id
      and kicked_at is not null;
  if v_existing_kicked is not null and v_existing_kicked > now() - interval '24 hours' then
    raise exception 'kicked_recently' using errcode = 'P0001';
  end if;

  -- 정원 — 이미 꽉 차 있으면 초대 무의미.
  select count(*) into v_member_count
    from public.group_members
    where group_id = p_group_id and left_at is null and kicked_at is null;
  if v_member_count >= v_max then
    raise exception 'group_full' using errcode = 'P0001';
  end if;

  -- 이미 동일 (group, invitee) 에 pending 이 있으면 그 id 반환 (idempotent).
  select id into v_already_pending
    from public.group_invites
    where group_id = p_group_id and invitee_id = p_invitee_id
      and status = 'pending';
  if v_already_pending is not null then
    return v_already_pending;
  end if;

  insert into public.group_invites (group_id, inviter_id, invitee_id)
    values (p_group_id, v_uid, p_invitee_id)
    returning id into v_id;
  return v_id;
end $$;
revoke all on function public.send_group_invite(uuid, uuid) from public;
grant execute on function public.send_group_invite(uuid, uuid) to authenticated;

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ RPC: 초대 수락                                                ║
-- ╚══════════════════════════════════════════════════════════════╝
create or replace function public.accept_group_invite(p_invite_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_invite record;
  v_archived timestamptz;
  v_max int;
  v_count int;
begin
  if v_uid is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  select * into v_invite from public.group_invites where id = p_invite_id for update;
  if not found then
    raise exception 'invite_not_found' using errcode = 'P0002';
  end if;
  if v_invite.invitee_id <> v_uid then
    raise exception 'not_invitee' using errcode = '42501';
  end if;
  if v_invite.status <> 'pending' then
    raise exception 'invite_not_pending' using errcode = 'P0001';
  end if;
  if v_invite.expires_at <= now() then
    update public.group_invites set status = 'expired' where id = p_invite_id;
    raise exception 'invite_expired' using errcode = 'P0001';
  end if;

  -- 그룹 활성 확인.
  select archived_at, max_members
    into v_archived, v_max
    from public.community_groups where id = v_invite.group_id;
  if not found or v_archived is not null then
    raise exception 'group_not_found' using errcode = 'P0002';
  end if;

  -- 강퇴 24h 가드.
  if exists (
    select 1 from public.group_members
    where group_id = v_invite.group_id and user_id = v_uid
      and kicked_at is not null and kicked_at > now() - interval '24 hours'
  ) then
    raise exception 'kicked_recently' using errcode = 'P0001';
  end if;

  -- INSERT 먼저, 그 다음 정원 검사 — 동시 수락 race 차단.
  insert into public.group_members (group_id, user_id, role)
    values (v_invite.group_id, v_uid, 'member')
  on conflict (group_id, user_id) do update
    set left_at = null, kicked_at = null, kicked_by = null, joined_at = now(),
        role = case when group_members.role = 'owner' then 'owner' else 'member' end;

  select count(*) into v_count
    from public.group_members
    where group_id = v_invite.group_id and left_at is null and kicked_at is null;
  if v_count > v_max then
    -- 정원 초과 → insert 롤백시킴.
    raise exception 'group_full' using errcode = 'P0001';
  end if;

  update public.group_invites
    set status = 'accepted', responded_at = now()
    where id = p_invite_id;
  return v_invite.group_id;
end $$;
revoke all on function public.accept_group_invite(uuid) from public;
grant execute on function public.accept_group_invite(uuid) to authenticated;

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ RPC: 초대 거절                                                ║
-- ╚══════════════════════════════════════════════════════════════╝
create or replace function public.decline_group_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_invitee uuid;
  v_status text;
begin
  if v_uid is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  select invitee_id, status into v_invitee, v_status
    from public.group_invites where id = p_invite_id;
  if not found then
    raise exception 'invite_not_found' using errcode = 'P0002';
  end if;
  if v_invitee <> v_uid then
    raise exception 'not_invitee' using errcode = '42501';
  end if;
  if v_status <> 'pending' then
    raise exception 'invite_not_pending' using errcode = 'P0001';
  end if;

  update public.group_invites
    set status = 'declined', responded_at = now()
    where id = p_invite_id;
end $$;
revoke all on function public.decline_group_invite(uuid) from public;
grant execute on function public.decline_group_invite(uuid) to authenticated;

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ RPC: 사용자 디렉토리 (닉네임순)                               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- 보안:
--   · 반환 컬럼 명시적으로 (user_id, nickname) 만 — profiles select * 절대 X.
--   · profiles 의 weight/height/birth_date/sex 같은 PII 노출 차단.
--   · authenticated 만 호출 가능. anon 은 차단.
--   · p_exclude_group_id 가 주어지면 해당 그룹의 활성 멤버는 결과에서 제외
--     (이미 멤버인 사람을 다시 초대하지 못하게 — 클라이언트 필터보다 안전).
--   · 본인은 항상 결과에서 제외.
--   · 차단(blocks) 양방향 사용자 제외.
create or replace function public.list_users_by_nickname(
  p_query text default '',
  p_exclude_group_id uuid default null,
  p_limit int default 50,
  p_offset int default 0
) returns table (user_id uuid, nickname text)
language sql
stable
security definer
set search_path = public
as $$
  select p.user_id, p.nickname::text
  from public.profiles p
  where
    p.user_id <> auth.uid()
    and p.nickname is not null
    and (p_query = '' or lower(p.nickname::text) like lower(p_query) || '%')
    and not exists (
      select 1 from public.user_blocks ub
      where (ub.blocker_id = auth.uid() and ub.blocked_id = p.user_id)
         or (ub.blocker_id = p.user_id and ub.blocked_id = auth.uid())
    )
    and (
      p_exclude_group_id is null
      or not exists (
        select 1 from public.group_members gm
        where gm.group_id = p_exclude_group_id
          and gm.user_id = p.user_id
          and gm.left_at is null
          and gm.kicked_at is null
      )
    )
  order by lower(p.nickname::text)
  limit greatest(1, least(p_limit, 200))
  offset greatest(0, p_offset);
$$;
revoke all on function public.list_users_by_nickname(text, uuid, int, int) from public;
grant execute on function public.list_users_by_nickname(text, uuid, int, int) to authenticated;

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ Realtime publication                                          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- 마이 탭에서 새 초대 즉시 반영되도록.
do $$ begin
  alter publication supabase_realtime add table public.group_invites;
exception when duplicate_object then null; when others then null; end $$;

-- ╔══════════════════════════════════════════════════════════════╗
-- ║ RPC: 내가 받은 pending 초대의 inviter 닉네임 (배치 조회)       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- get_group_member_handles 는 "같은 그룹 활성 멤버끼리"만 노출하므로,
-- 아직 그룹에 가입하지 않은 invitee 가 inviter 닉네임을 볼 수 없다.
-- 본인이 받은 pending 초대에 한해 inviter 닉네임만 반환.
create or replace function public.get_invite_inviter_handles()
returns table (inviter_id uuid, nickname text)
language sql
stable
security definer
set search_path = public
as $$
  select distinct gi.inviter_id, p.nickname::text
  from public.group_invites gi
  join public.profiles p on p.user_id = gi.inviter_id
  where gi.invitee_id = auth.uid()
    and gi.status = 'pending';
$$;
revoke all on function public.get_invite_inviter_handles() from public;
grant execute on function public.get_invite_inviter_handles() to authenticated;
