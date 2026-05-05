-- 프로필: 생년월일·성별 컬럼.
--
-- 온보딩에서 이미 수집하지만 저장 안 했던 값을 이제 저장한다.
-- 목적: 프로필 편집 화면에서 일일 권장 칼로리를 자동 재계산하려면
--       나이·성별(BMR 공식의 입력)이 필요하다.
--
-- 둘 다 nullable — 기존 유저는 프로필 편집 화면에서 채워 넣을 수 있다.

alter table public.profiles
  add column if not exists birth_date date,
  add column if not exists sex text check (sex in ('female', 'male'));
