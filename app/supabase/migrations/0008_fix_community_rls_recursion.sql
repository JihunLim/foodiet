-- 0007 의 group_members.members_read 정책이 같은 테이블을 EXISTS 로 다시
-- 참조해서 PostgreSQL 의 정책 재귀 detection 에 걸린다:
--   "infinite recursion detected in policy for relation \"group_members\""
--
-- 해결: SECURITY DEFINER helper 안에서 멤버십을 평가해 RLS 평가 사이클을
-- 끊는다. 함수 본문은 BYPASSRLS 권한으로 실행되므로 group_members 의
-- 내부 SELECT 가 다시 RLS 평가를 트리거하지 않는다.
--
-- 보안 노트:
--   · helper 는 auth.uid() 를 함수 본문에서 호출 (파라미터 X) →
--     SECURITY DEFINER 라도 호출자 컨텍스트를 그대로 사용.
--   · 반환은 boolean 1개. 멤버 행/PII 노출 없음.
--   · search_path 는 public 으로 고정 → search_path 우회 공격 차단.
--   · public 에서 EXECUTE 회수 후 authenticated 에만 부여 →
--     anon 이 직접 RPC 로 호출하지 못함 (RLS 평가 컨텍스트에서는 어차피
--     auth.uid() 가 null 이라 false 반환).
--   · 정책 술어 (left_at is null, kicked_at is null) 는 그대로 유지 →
--     접근 범위 변경 없음.

create or replace function public.is_member_of_group(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.group_members
    where group_id = p_group_id
      and user_id = auth.uid()
      and left_at is null
      and kicked_at is null
  );
$$;
revoke all on function public.is_member_of_group(uuid) from public;
grant execute on function public.is_member_of_group(uuid) to authenticated;

-- group_members.members_read — 자기참조 제거.
drop policy if exists "members_read" on public.group_members;
create policy "members_read" on public.group_members
  for select using (
    user_id = auth.uid()
    or public.is_member_of_group(group_id)
  );

-- community_groups.groups_read — 일관성 위해 같은 helper 사용.
-- (재귀 발생 지점은 아니지만 정책을 단순화하면 추후 변경 시 같은 실수를
--  반복하지 않게 됨.)
drop policy if exists "groups_read" on public.community_groups;
create policy "groups_read" on public.community_groups
  for select using (
    (visibility = 'public' and archived_at is null)
    or public.is_member_of_group(community_groups.id)
  );
