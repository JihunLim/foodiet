-- 0014_community_post_multi_share.sql
-- 같은 그룹/날짜에 여러 번 공유 가능하게 하고, 각 포스트가 어떤 entries를
-- 포함하는지 트래킹한다.
--
-- 변경:
--   1) (group_id, user_id, post_date) UNIQUE 제약 제거.
--   2) community_posts.entry_ids uuid[] 컬럼 추가 (어떤 식단 항목 합산인지).
--   3) already_shared_entry_ids(group_id, post_date) RPC — 클라가 default
--      selection 을 정할 때 사용.

-- 1) 컬럼명 기반으로 unique constraint를 동적으로 찾아 drop (autogen 이름
--    가정 없이 안전하게).
do $$
declare
  cname text;
begin
  select c.conname into cname
  from pg_constraint c
  where c.conrelid = 'public.community_posts'::regclass
    and c.contype = 'u'
    and (
      select array_agg(a.attname order by a.attnum)
      from pg_attribute a
      where a.attrelid = c.conrelid
        and a.attnum = any(c.conkey)
    ) = array['group_id', 'user_id', 'post_date']::name[];

  if cname is not null then
    execute format('alter table public.community_posts drop constraint %I', cname);
  end if;
end$$;

-- 2) 카드가 어떤 entries를 합산했는지 기록.
--    기존 행들은 빈 배열로 시작 (마이그레이션 이전 카드들은 식단 항목 단위
--    트래킹이 없으므로 always_shared 검사에서 무시됨).
alter table public.community_posts
  add column if not exists entry_ids uuid[] not null default '{}';

-- 3) 같은 그룹/날짜에 내가 이미 공유한 entry id들을 반환.
--    RLS 상 본인 post 는 항상 select 가능하므로 security invoker 로 충분.
create or replace function public.already_shared_entry_ids(
  p_group_id uuid,
  p_post_date date
) returns setof uuid
language sql
security invoker
set search_path = public
as $$
  select distinct unnest(entry_ids)
  from public.community_posts
  where group_id = p_group_id
    and user_id  = auth.uid()
    and post_date = p_post_date
    and deleted_at is null;
$$;

revoke all on function public.already_shared_entry_ids(uuid, date) from public;
grant execute on function public.already_shared_entry_ids(uuid, date) to authenticated;
