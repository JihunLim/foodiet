-- foodiet 즐겨찾기 + 1탭 재기록 (업그레이드 로드맵 [Q2]).
--
-- 자주 먹는 음식을 "즐겨찾기"로 고정해두면, 다음에 같은 걸 먹을 때
-- 사진/분석 없이 홈 화면 칩 한 번 탭으로 entry 를 즉시 생성한다.
--   - favorites 행은 음식명 + 매크로 스냅샷 + 대표 사진 경로를 들고 있다 (denormalized).
--     원본 entry 가 삭제돼도 즐겨찾기는 살아남도록 FK 가 아니라 스냅샷으로 보관한다.
--   - 재기록 시 favorites.image_path 를 새 entry 경로로 storage.copy 한다
--     (entry 삭제가 storage 파일을 지우므로 경로를 공유하면 안 됨 — entry_detail 삭제 흐름 참고).
--   - 재기록 entry 는 source='favorite' 로 분리해 인사이트 통계 왜곡을 막는다.

-- ── 즐겨찾기 ───────────────────────────────────────────────
create table public.favorites (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  name            text not null,                 -- 칩 라벨 / 재기록 entry 의 title
  image_path      text,                          -- food-photos 버킷 내 스냅샷 ({user_id}/favorites/{id}.jpg)
  kcal_total      int,
  macros          jsonb,                         -- {carb_g, protein_g, fat_g}
  meal_slot       meal_slot,                     -- 재기록 시 현재 시각으로 재추론하므로 참고용
  eating_type     eating_type,
  source_entry_id uuid references public.entries(id) on delete set null, -- 출처(선택, 삭제돼도 NULL 로 유지)
  pinned_at       timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  unique (user_id, name)                         -- 같은 음식명은 사용자당 하나
);
create index favorites_user_pinned_idx on public.favorites (user_id, pinned_at desc);

-- ── RLS ────────────────────────────────────────────────────
alter table public.favorites enable row level security;
create policy "own_favorites" on public.favorites
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── entries.source 에 'favorite' 추가 ──────────────────────
-- 주의: 'entries_source_check' 는 0001_init.sql 의 인라인 CHECK 에 대해 Postgres 가
-- 자동 생성하는 이름이다. 적용 전 `\d public.entries` 로 실제 제약 이름을 확인할 것.
alter table public.entries drop constraint if exists entries_source_check;
alter table public.entries add constraint entries_source_check
  check (source in ('camera', 'gallery', 'favorite'));
