-- 본인이 쓴 조언을 수정할 수 있도록 update 정책 추가.
-- 0007 은 insert / delete 만 허용했어서 update 가 막혀있었다.
drop policy if exists "tips_self_update" on public.post_tips;
create policy "tips_self_update" on public.post_tips
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());
