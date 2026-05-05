-- Phase C — entries 테이블을 supabase_realtime publication 에 추가.
-- 이러면 클라이언트가 Postgres Change Data Capture 로 UPDATE 이벤트를 받을 수 있다.
-- 분석 완료(status: pending→done) 시 홈/기록 탭이 자동 새로고침.
alter publication supabase_realtime add table public.entries;
