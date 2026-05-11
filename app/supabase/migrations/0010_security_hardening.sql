-- Supabase 보안 advisor 가 잡은 항목들 정리.
--
-- (1) function_search_path_mutable
--     트리거 / SECURITY DEFINER 함수에 search_path 가 명시 안 되면
--     호출자가 search_path 를 바꿔서 다른 schema 의 동명 함수를 끼워넣는
--     공격이 가능. 모두 public 고정.
--
-- (2) anon_security_definer_function_executable
--     PostgreSQL 의 PUBLIC pseudo-role 에서 revoke 해도 Supabase 가
--     생성 시 anon/authenticated 에 명시적으로 grant 한 상태일 수 있다.
--     anon 에서 명시적으로 revoke 해서 PostgREST 익명 호출을 차단.
--     authenticated 만 접근 — 함수 본문의 auth.uid() 체크가 의미 갖는다.
--
-- 무시 항목 (의도적):
--   · community_group_secrets RLS no policy → service_role 전용 lockdown.
--   · pg_net / citext extension in public → 이미 사용 중. 이동 비용 큼.
--   · authenticated_security_definer_function_executable → 의도된 동작
--     (사용자가 호출하는 RPC). 0029 advisor 는 false positive.

-- ── (1) search_path 보강 ───────────────────────────────────────────
alter function public._guard_member_self_update() set search_path = public;
do $$ begin
  -- enforce_share_scope 는 일부 환경에서만 존재 (system installed).
  -- 없으면 조용히 skip.
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'enforce_share_scope'
  ) then
    execute 'alter function public.enforce_share_scope() set search_path = public';
  end if;
end $$;

-- ── (2) anon revoke — 0007 / 0008 / 0009 의 모든 SECURITY DEFINER ──
revoke all on function public.assign_random_nickname() from anon;
revoke all on function public.update_nickname(citext) from anon;
revoke all on function public.check_nickname_available(citext) from anon;
revoke all on function public.create_community_group(text, text, text, group_visibility, text) from anon;
revoke all on function public.join_public_group(uuid) from anon;
revoke all on function public.join_private_group(uuid, text) from anon;
revoke all on function public.archive_community_group(uuid) from anon;
revoke all on function public.kick_group_member(uuid, uuid) from anon;
revoke all on function public.change_group_password(uuid, text) from anon;
revoke all on function public.submit_report(text, uuid, report_reason, text, uuid) from anon;
revoke all on function public.get_group_member_handles(uuid[]) from anon;
revoke all on function public.is_member_of_group(uuid) from anon;
revoke all on function public.send_group_invite(uuid, uuid) from anon;
revoke all on function public.accept_group_invite(uuid) from anon;
revoke all on function public.decline_group_invite(uuid) from anon;
revoke all on function public.list_users_by_nickname(text, uuid, int, int) from anon;
revoke all on function public.get_invite_inviter_handles() from anon;

-- ── (3) PUBLIC pseudo-role 에서 0007 함수들 회수 ─────────────────────
-- 0007 RPC 들은 정의 시 grant execute to authenticated 만 했고 PUBLIC
-- 에서 회수 안 함 → anon 이 PUBLIC 멤버 자격으로 호출 가능했다.
-- PUBLIC 에서 회수 + authenticated 안전망 grant 로 차단.
revoke all on function public.assign_random_nickname() from public;
revoke all on function public.update_nickname(citext) from public;
revoke all on function public.check_nickname_available(citext) from public;
revoke all on function public.create_community_group(text, text, text, group_visibility, text) from public;
revoke all on function public.join_public_group(uuid) from public;
revoke all on function public.join_private_group(uuid, text) from public;
revoke all on function public.archive_community_group(uuid) from public;
revoke all on function public.kick_group_member(uuid, uuid) from public;
revoke all on function public.change_group_password(uuid, text) from public;
revoke all on function public.submit_report(text, uuid, report_reason, text, uuid) from public;
revoke all on function public.get_group_member_handles(uuid[]) from public;

grant execute on function public.assign_random_nickname() to authenticated;
grant execute on function public.update_nickname(citext) to authenticated;
grant execute on function public.check_nickname_available(citext) to authenticated;
grant execute on function public.create_community_group(text, text, text, group_visibility, text) to authenticated;
grant execute on function public.join_public_group(uuid) to authenticated;
grant execute on function public.join_private_group(uuid, text) to authenticated;
grant execute on function public.archive_community_group(uuid) to authenticated;
grant execute on function public.kick_group_member(uuid, uuid) to authenticated;
grant execute on function public.change_group_password(uuid, text) to authenticated;
grant execute on function public.submit_report(text, uuid, report_reason, text, uuid) to authenticated;
grant execute on function public.get_group_member_handles(uuid[]) to authenticated;
