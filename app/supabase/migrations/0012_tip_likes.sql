-- 댓글(조언) 좋아요 테이블 + RLS.
create table if not exists public.tip_likes (
  tip_id     uuid not null references public.post_tips(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (tip_id, user_id)
);
create index if not exists tip_likes_tip_idx on public.tip_likes(tip_id);

alter table public.tip_likes enable row level security;

drop policy if exists "tip_likes_auth_read" on public.tip_likes;
create policy "tip_likes_auth_read" on public.tip_likes
  for select using (auth.uid() is not null);

drop policy if exists "tip_likes_self_insert" on public.tip_likes;
create policy "tip_likes_self_insert" on public.tip_likes
  for insert with check (user_id = auth.uid());

drop policy if exists "tip_likes_self_delete" on public.tip_likes;
create policy "tip_likes_self_delete" on public.tip_likes
  for delete using (user_id = auth.uid());

do $$ begin
  alter publication supabase_realtime add table public.tip_likes;
exception when duplicate_object then null; when others then null; end $$;
