-- 좋아요 RLS 를 그룹 멤버 범위로 좁힘.
-- 0012 의 auth.uid() is not null read 정책은 비공개 그룹 멤버십을 간접
-- 누출시킬 수 있어 같은 그룹 활성 멤버만 read/write 하도록 변경.

drop policy if exists "tip_likes_auth_read" on public.tip_likes;
drop policy if exists "tip_likes_group_read" on public.tip_likes;
create policy "tip_likes_group_read" on public.tip_likes
  for select using (
    exists (
      select 1
      from public.post_tips pt
      join public.community_posts cp on cp.id = pt.post_id
      where pt.id = tip_likes.tip_id
        and public.is_member_of_group(cp.group_id)
    )
  );

drop policy if exists "tip_likes_self_insert" on public.tip_likes;
create policy "tip_likes_self_insert" on public.tip_likes
  for insert with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.post_tips pt
      join public.community_posts cp on cp.id = pt.post_id
      where pt.id = tip_likes.tip_id
        and public.is_member_of_group(cp.group_id)
    )
  );
