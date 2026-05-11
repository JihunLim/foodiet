# foodiet 커뮤니티 기획서 (§19)

> **한 줄 요약** — 같이 먹고, 같이 응원하고, 같이 달성하는 식단 커뮤니티. 하루 식단 요약을 친구들에게 공유하고, "응원"과 "조언"으로 서로의 목표 달성을 돕는다.

- 작성일: 2026-05-05
- 상위 문서: `foodiet_기획안.md` v1.2
- 위치: 로드맵 v1.2+ (§15.3 "챌린지/그룹" 확장)
- 우선순위: v1.2 핵심 기능

---

## 1. 배경 & 목적

### 1.1 왜 커뮤니티인가

현재 foodiet의 리텐션 루프는 **개인(기록→분석→코칭)**과 **1:1(PT 공유)**로 구성되어 있다. 그러나 다이어트의 가장 큰 적은 "혼자라는 느낌"이다.

- 기록 습관의 최대 적: 3주 후 동기 저하 → D30 리텐션 18% 목표(§14.2)를 돌파하려면 **사회적 동기**가 필요
- PT를 받지 않는 사용자(전체의 ~75%)에게는 현재 공유 대상이 없음
- 경쟁 앱(MyFitnessPal, 다이어트신)의 커뮤니티 기능은 "게시판형" — 식단 맥락 없이 범용적이라 참여도 낮음

### 1.2 핵심 가설

> **"하루 식단 달성 여부를 친한 사람 3~7명과 공유하면, 주간 기록 지속률(W1R)이 1.5배 이상 상승한다."**

### 1.3 디자인 원칙 (커뮤니티 특화)

1. **비교하지 않는다** — 칼로리/체중 랭킹, 순위, 비교 그래프 일절 없음. 각자의 목표 대비 달성률만 표시.
2. **가볍게 시작** — 가입 첫날부터 포스팅 부담 없이, "오늘 식단 공유" 한 탭이면 끝.
3. **따뜻한 반응만** — "응원"과 "조언" 두 가지 반응 채널. 비난·부정적 댓글은 구조적으로 억제.
4. **내가 정하는 공개범위** — 사진·칼로리·영양소(탄단지) 등 공유 항목을 사용자가 직접 설정. 디폴트는 모두 공개, 원하면 항목별 OFF.

---

## 2. 핵심 개념 정의

### 2.1 "커뮤니티 그룹" (Group)

구성원들이 식단을 공유하고 소통하는 단위. **공개 그룹**과 **비공개 그룹** 두 유형 제공.

- 최대 **32명**
- 하나의 계정으로 최대 10개 그룹 참여 가능
- 그룹 내에서만 피드 열람 + 커뮤니케이션 가능

#### 공개 그룹 (Public)
- 커뮤니티 탭의 "그룹 탐색" 에서 검색/리스트 노출
- 누구나 바로 참여 가능 (비밀번호 없음)
- 그룹 소개글(한 줄)로 취지 표현 — 예: "직장인 점심 인증", "30대 간헐적 단식 모임"

#### 비공개 그룹 (Private)
- 검색/탐색에 노출되지 않음
- **비밀번호**(4~8자리, 그룹장 설정)를 아는 사람만 입장
- 비밀번호는 카톡/문자 등으로 전달
- 예: 친한 친구, 직장 동료, PT 멤버

#### 그룹장 (Owner) 권한
- 그룹 이름/이모지/소개글 수정
- 공개↔비공개 전환, 비밀번호 변경
- **구성원 강제 퇴장 (강퇴)** — 강퇴된 사용자에게 푸시 알림 + 재가입 24h 제한
- 그룹 삭제(아카이브)
- 그룹장 위임 (다른 멤버에게 owner 이전)

### 2.2 "오늘 식단 카드" (Daily Card)

기존 `DailyShareCard`를 확장 — 그룹 피드에 자동/수동으로 게시되는 하루 요약 단위.

**카드에 포함되는 정보 (사용자 설정에 따라):**
- 닉네임 + 프로필 이모지(아바타 대체) — 항상 표시
- 날짜 — 항상 표시
- 끼니별 대표 사진 (최대 4장 — 아침/점심/저녁/간식 각 1장) — show_photos
- 오늘 총 섭취 kcal / 목표 kcal — show_kcal
- 영양소: 탄수화물 · 단백질 · 지방 (g 단위) — show_macros
- 달성률(%) + 링 차트 — 항상 표시
- 달성 상태 배지: 🎯 "목표 달성!" / 💪 "거의 다 왔어" / 🌱 "내일 다시!" — 항상 표시

**사용자 설정 가능 공유 항목 (디폴트 = 모두 공개):**
- 🔘 음식 사진 — ON/OFF (기본 ON)
- 🔘 칼로리 수치(kcal) — ON/OFF (기본 ON)
- 🔘 영양소(탄수화물·단백질·지방) — ON/OFF (기본 ON)
- 🔘 달성률(%) — 항상 공개 (핵심 지표이므로 OFF 불가)
- 🔘 달성 상태 배지 — 항상 공개

**절대 공개되지 않는 항목:**
- ❌ 체중 / 목표 체중
- ❌ 코치 메시지 내용
- ❌ 보정 이력
- ❌ 활동량 / 운동 기록

### 2.3 반응 시스템: "응원" & "조언"

일반적인 댓글/좋아요 대신, 목적에 맞는 **두 가지 반응 채널**로 분리.

#### 응원 (Cheer) 🎉
- 원탭 반응 — 이모지 3종 중 택 1: 🔥(불타올라!) / 👏(잘했어!) / 💚(응원해!)
- 작성 부담 없음, 누구나 하루에 여러 번 가능
- 알림: "{닉네임}이 🔥로 응원했어!"

#### 조언 (Tip) 💡
- 짧은 텍스트 메시지 (최대 100자)
- 조언은 **목표 미달성 카드에만** 달 수 있음 (달성 카드에는 응원만)
- 톤 가이드: 긍정적 제안만 허용. 시스템이 부정어 감지 시 게시 전 안내
- 예시: "내일 점심 샐러드 어때? 근처에 맛있는 데 있어!", "단백질 간식 추천! 그릭요거트 짱이야"

**왜 분리하는가?**
- 달성한 사람에게 조언은 불필요하고 기분 상할 수 있음
- 미달성 시에도 "응원"이 기본 — 조언은 선택적으로 원하는 사람만 받음
- 부정적 댓글의 구조적 억제: 텍스트 입력 자체가 "조언" 맥락에서만 열림

### 2.4 닉네임 시스템

커뮤니티에서 사용자를 식별하는 고유 닉네임. **중복 불가**를 철저히 보장.

#### 닉네임 규칙
- 2~12자 (한글/영문/숫자/언더스코어)
- **전체 서비스 내 유일** (unique, case-insensitive)
- 특수문자·공백·이모지 불가
- 금지어(욕설/비하어) 포함 시 설정 불가

#### 초기 닉네임 (랜덤 자동 부여)
- 회원가입 완료 시 랜덤 닉네임 자동 생성
- 형식: `{형용사}_{음식}_{숫자3자리}` — 예: "활발한_딸기_042", "건강한_샐러드_817"
- 생성 시 DB uniqueness 검증 후 확정 (충돌 시 재생성, 최대 5회 시도)

#### 닉네임 변경 (마이 설정)
- 홈 AppBar → 👤 프로필 → "닉네임 변경"
- 입력 즉시 **실시간 중복 확인** (debounce 300ms → Supabase RPC 호출)
- UI 상태:
  - ✅ "사용 가능한 닉네임이에요!"
  - ❌ "이미 사용 중인 닉네임이에요."
  - ⚠️ "2~12자 한글/영문/숫자만 가능해요."
- "저장" 버튼은 중복확인 통과 + 규칙 통과 시에만 활성화
- 저장 시 서버에서 한번 더 unique 검증 (race condition 방지)
- 변경 횟수 제한: 30일 1회 (남용 방지)

#### 기술 구현
- `profiles.nickname` 컬럼: `citext not null unique`
- DB 레벨 unique constraint → 어떤 경로에서든 중복 불가 보장
- RPC `check_nickname_available(nickname citext)`: returns boolean
- RPC `update_nickname(new_nickname citext)`: 검증 + 업데이트 atomic
- 닉네임 변경 이력: `profiles.nickname_changed_at` 으로 30일 제한 체크

---

## 3. 사용자 플로우

### 3.1 그룹 만들기

1. 커뮤니티 탭 → "그룹 만들기" 또는 상단 "+" 버튼
2. 그룹 이름 입력 (예: "헬창 모임", "직장인 점심 인증")
3. 그룹 이모지 선택 (대표 아이콘)
4. 공개/비공개 선택
   - 공개 → 소개글 입력 (선택)
   - 비공개 → 비밀번호 설정 (4~8자리)
5. 그룹 생성 완료 → 피드 진입

### 3.2 그룹 참여

**공개 그룹:**
1. 커뮤니티 탭 → "그룹 탐색" → 검색 또는 리스트 브라우징
2. 그룹 카드 확인 (이름/이모지/소개글/현재 인원)
3. "참여하기" 탭 → 즉시 입장

**비공개 그룹:**
1. 비밀번호를 카톡/문자 등으로 수신
2. 커뮤니티 탭 → "비밀번호로 참여"
3. 비밀번호 입력 → 그룹 확인 → "참여하기"
4. 참여 즉시 피드 열람 가능

### 3.3 식단 공유 (매일)

**수동 공유 (기본):**
- 커뮤니티 탭 → FAB "오늘 공유하기" → 그룹 선택 → 즉시 게시
- 과거 날짜도 공유 가능 (캘린더에서 선택)

**자동 공유 모드 (기본 OFF, 옵트인):**
- 그룹 설정에서 "자동 공유 켜기" → 시각 설정 (기본 21:00)
- 매일 설정 시각에 오늘 식단 카드가 자동으로 그룹 피드에 게시
- 기록이 없는 날은 게시되지 않음
- 게시 전 푸시 알림: "오늘 식단이 그룹에 공유됩니다. [확인/건너뛰기]"
- 왜 기본 OFF? → App Store 프라이버시 가이드라인 준수 + 사용자 통제감 우선

### 3.4 피드 열람 & 반응

1. 커뮤니티 탭 진입 → 그룹 피드(시간순, 최신 상단)
2. 구성원의 식단 카드 확인
3. 달성 카드 → 🔥/👏/💚 응원 탭
4. 미달성 카드 → 응원 OR "조언 남기기" 탭 → 텍스트 입력(100자)
5. 조언 수신자에게 푸시: "{닉네임}의 조언: '내일은 아침을 꼭 먹어보자!'"

### 3.5 그룹장 관리

1. 그룹 설정 → "구성원 관리"
2. 구성원 목록에서 특정 사용자 → "강퇴"
3. 확인 다이얼로그: "{닉네임}님을 그룹에서 내보낼까요?"
4. 강퇴 시: 해당 사용자의 게시물은 유지, 열람/작성 권한만 제거
5. 강퇴된 사용자에게 푸시: "{그룹이름}에서 퇴장되었습니다."
6. 재가입 제한: 24시간 후 재참여 가능

### 3.6 신고

1. 카드/조언의 ⋮ 메뉴 → "신고"
2. 신고 사유 선택 (부적절/스팸/괴롭힘/기타) + 상세 입력(선택)
3. 신고 접수 즉시 → **개발자(그룹장 아님)에게 FCM 푸시 알림**
4. 개발자 관리 화면에서: 신고 대상 게시물/사진 확인 → 제재 결정
   - 경고 발송
   - 해당 콘텐츠 삭제
   - 계정 정지 (7일/30일/영구)
5. 자동 조치: 신고 누적 2건 → 콘텐츠 자동 숨김 (개발자 확인 전까지)

### 3.7 알림 흐름

| 이벤트 | 알림 | 빈도 제한 |
|---|---|---|
| 내 카드에 응원 반응 | "{닉네임}이 🔥 응원!" | 동일인 1일 1회 |
| 내 카드에 조언 | "💡 {닉네임}: {조언 미리보기}" | 즉시, 건당 |
| 구성원 목표 달성 | "🎯 {닉네임}이 오늘 목표 달성!" | 그룹당 1일 3건 상한 |
| 구성원 3일 연속 달성 | "🔥 {닉네임} 3일 연속 달성 중!" | 해당 이벤트 시에만 |
| 내가 3일 무기록 | "그룹 친구들이 기다리고 있어!" | 1회만 |
| 강퇴됨 | "{그룹이름}에서 퇴장되었습니다." | 해당 이벤트 시 |
| 🔔 신고 접수 (→ 개발자) | "신고 접수: {그룹이름} / {닉네임}" | 즉시, 건당 |

---

## 4. 정보 구조 (IA) 확장

### 4.1 탭 바 변경

```
[기존 Tab Bar]
 🏠 홈  |  📅 기록  |  ➕ 촬영  |  📊 인사이트  |  👤 마이

[변경 Tab Bar]
 🏠 홈  |  📅 기록  |  ➕ 촬영  |  📊 인사이트  |  👥 커뮤니티
```

- 👤 마이(프로필)는 홈 화면 AppBar 우측 아이콘으로 이동 (기존 공유 아이콘 자리)
- 홈 화면의 공유 아이콘은 제거 (공유는 커뮤니티 탭에서 수행)
- 기존 마이 탭 위치(5번째)에 👥 커뮤니티 배치
- 📅 기록(캘린더) 탭은 그대로 유지

### 4.2 커뮤니티 탭 구조

```
👥 커뮤니티
├─ 상단 탭: [내 그룹] [그룹 탐색]
│
├─ [내 그룹] 화면:
│  ├─ 그룹 셀렉터 (가로 스크롤 칩 — 참여 중인 그룹 목록)
│  ├─ 피드 (선택된 그룹의 세로 스크롤)
│  │  ├─ [Daily Card] 닉네임 · 날짜 · 사진 · 달성률 · 반응
│  │  └─ ...
│  ├─ 빈 상태: "아직 참여 중인 그룹이 없어요! 만들거나 찾아보자"
│  └─ FAB: 내 오늘 카드 즉시 공유
│
└─ [그룹 탐색] 화면:
   ├─ 검색 바 (그룹 이름 검색)
   ├─ 공개 그룹 카드 리스트 (이름/이모지/소개글/인원수)
   └─ "비밀번호로 참여" 버튼
```

### 4.3 서브 화면

```
[커뮤니티 서브]
├─ 그룹 만들기 (공개/비공개 선택 + 비밀번호 설정)
├─ 비밀번호 입력 (비공개 그룹 참여)
├─ 그룹 설정 (이름/이모지/소개글/공개↔비공개/비밀번호 변경/나가기)
├─ 공유 범위 설정 (사진/칼로리/영양소 토글 — 그룹별)
├─ 구성원 관리 (그룹장: 강퇴 가능 / 일반: 목록만)
├─ 카드 상세 (사진 크게 + 반응 목록 + 조언 스레드)
├─ 신고 시트
└─ 차단 시트

[홈 AppBar]
└─ 👤 프로필 아이콘 (기존 마이 탭 내용으로 이동)
```

---

## 5. 프라이버시 & 안전

### 5.1 공개 범위 정책 (커뮤니티 카드)

사용자가 **그룹별로** 공유 항목을 ON/OFF 설정한다. 디폴트는 모두 공개.

| 항목 | 기본값 | 설정 | 비고 |
|---|---|---|---|
| 닉네임 | ✅ 항상 공개 | 변경 불가 | |
| 프로필 이모지 | ✅ 항상 공개 | 변경 불가 | |
| 음식 사진 (끼니별 대표 1장) | ✅ ON | 사용자 OFF 가능 | |
| 총 섭취 kcal | ✅ ON | 사용자 OFF 가능 | |
| 영양소(탄수화물·단백질·지방) | ✅ ON | 사용자 OFF 가능 | |
| 목표 대비 달성률(%) | ✅ 항상 공개 | 변경 불가 | 핵심 지표 |
| 달성 상태 배지 | ✅ 항상 공개 | 변경 불가 | |
| 체중 / 목표 체중 | ❌ | 설정 불가 | 절대 비공개 |
| 코치 메시지 | ❌ | 설정 불가 | 절대 비공개 |
| 보정 이력 | ❌ | 설정 불가 | 절대 비공개 |
| 활동량 / 운동 기록 | ❌ | 설정 불가 | 절대 비공개 |

### 5.2 Apple App Store 1.2 (UGC) 준수

커뮤니티 = 사용자 생성 콘텐츠(UGC) 앱. **MVP에 반드시 포함해야 할 사항:**

1. **신고 기능** — 모든 조언 텍스트·카드에 "신고" 메뉴 (⋮ → "부적절한 내용 신고")
2. **차단 기능** — 특정 사용자를 차단하면 해당 사용자의 콘텐츠 비노출 + 내 카드 비노출
3. **자동 숨김** — 신고 2건 누적 시 자동 soft delete (개발자 확인 전까지)
4. **개발자 즉시 알림** — 신고 접수 시 개발자 FCM 푸시 + 관리 화면에서 게시물/사진 열람 → 계정 제재
5. **그룹장 강퇴 권한** — 그룹장이 구성원을 즉시 퇴장시킬 수 있음
6. **이용약관** — 커뮤니티 가이드라인 (욕설/비하/비난/광고 금지) 명시
7. **콘텐츠 필터** — 조언 텍스트 게시 전 금지어 필터 (욕설, 비하어, 부정어)

### 5.2.1 개발자 관리 도구 (Admin)

신고 접수 시 개발자가 즉각 대응할 수 있는 경로:

- **FCM 푸시**: "🚨 신고 접수: {그룹이름} / {닉네임} / {사유}" → 탭하면 관리 화면
- **관리 화면** (웹 또는 앱 내 숨겨진 admin 경로):
  - 신고 대상 게시물 전문 + 사진 원본 열람
  - 신고 이력 (해당 사용자 과거 신고 건수)
  - 제재 액션: 경고 / 콘텐츠 삭제 / 7일 정지 / 30일 정지 / 영구 정지
  - 제재 시 해당 사용자에게 자동 푸시: "커뮤니티 가이드라인 위반으로 {제재내용}."
- **자동 에스컬레이션**: 신고 2건 누적 → 콘텐츠 즉시 숨김, 개발자 확인 후 복원 또는 삭제 확정

### 5.3 건강 데이터 민감성 가드

- **비교 UI 금지**: 구성원 간 칼로리·달성률 비교 차트/랭킹 없음
- **연속 달성 스트릭**: 본인만 볼 수 있음. 그룹에는 3일 이상 달성 시 축하 알림만
- **섭식장애 트리거 방지**: 극단적 저칼로리(<800kcal) 달성을 축하하지 않음. 대신 푸디가 부드럽게 안내
- **미성년자 제한**: 14세 미만은 커뮤니티 접근 불가 (가입 시 생년월일 기반)

---

## 6. 데이터 모델 (신규 테이블)

### 6.1 Enum 추가

```sql
create type group_visibility as enum ('public','private');
create type reaction_type as enum ('fire','clap','heart');
create type report_reason as enum ('inappropriate','spam','harassment','other');
create type report_status as enum ('pending','resolved','dismissed');
create type sanction_type as enum ('warning','content_delete','suspend_7d','suspend_30d','permanent_ban');
```

### 6.2 기존 테이블 변경 (profiles)

```sql
-- 닉네임을 unique + citext 로 강제 (기존 profiles 테이블에 ALTER)
alter table public.profiles
  alter column nickname set not null,
  alter column nickname type citext using nickname::citext;

-- 닉네임 고유성 보장 (이미 unique index가 없는 경우)
create unique index if not exists profiles_nickname_unique
  on public.profiles (nickname);

-- 닉네임 변경일 추적
alter table public.profiles
  add column if not exists nickname_changed_at timestamptz;

-- 닉네임 중복 확인 RPC
create or replace function public.check_nickname_available(target_nickname citext)
returns boolean
language sql stable security definer
as $$
  select not exists (
    select 1 from public.profiles where nickname = target_nickname
  );
$$;

-- 닉네임 변경 RPC (30일 제한 + 중복 검증 포함)
create or replace function public.update_nickname(new_nickname citext)
returns void
language plpgsql security definer
as $$
begin
  -- 30일 제한 체크
  if exists (
    select 1 from public.profiles
    where id = auth.uid()
    and nickname_changed_at > now() - interval '30 days'
  ) then
    raise exception 'nickname_change_cooldown';
  end if;

  -- 규칙 검증 (2~12자, 한글/영문/숫자/언더스코어)
  if new_nickname !~ '^[가-힣a-zA-Z0-9_]{2,12}$' then
    raise exception 'nickname_invalid_format';
  end if;

  -- 업데이트 (unique constraint가 중복 방지)
  update public.profiles
  set nickname = new_nickname, nickname_changed_at = now()
  where id = auth.uid();
end;
$$;
```

### 6.3 핵심 테이블

```sql
-- 커뮤니티 그룹
create extension if not exists citext;
create table public.community_groups (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  emoji        text not null default '🥗',
  description  text,                          -- 그룹 소개글 (공개 그룹에서 노출)
  visibility   group_visibility not null default 'private',
  password     text,                          -- 비공개 그룹 비밀번호 (bcrypt hash)
  created_by   uuid not null references auth.users(id) on delete cascade,
  max_members  int not null default 32,
  created_at   timestamptz default now(),
  archived_at  timestamptz
);
create index community_groups_visibility_idx on public.community_groups (visibility)
  where archived_at is null;

-- 그룹 멤버십
create table public.group_members (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.community_groups(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  role         text not null default 'member' check (role in ('owner','member')),
  show_photos  boolean not null default true,  -- 사진 공개 여부
  show_kcal    boolean not null default true,  -- 칼로리 수치 공개 여부
  show_macros  boolean not null default true,  -- 영양소(탄단지) 공개 여부
  auto_share   boolean not null default false, -- 자동 공유 (기본 OFF, 옵트인)
  share_time   time not null default '21:00',  -- 자동 공유 시각
  joined_at    timestamptz default now(),
  left_at      timestamptz,
  kicked_at    timestamptz,                    -- 강퇴 시각 (non-null이면 강퇴됨)
  kicked_by    uuid references auth.users(id),
  unique (group_id, user_id)
);

-- 커뮤니티 공유 카드 (하루 요약)
create table public.community_posts (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.community_groups(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  post_date    date not null,              -- 어떤 날짜의 식단인지
  total_kcal   int,                        -- 해당 일 총 섭취 (null = 비공개)
  target_kcal  int,                        -- 해당 일 목표
  macros       jsonb,                      -- {carb_g, protein_g, fat_g} (null = 비공개)
  achievement  numeric(4,1),               -- 달성률 (%) = total/target*100
  status_badge text not null check (status_badge in ('achieved','almost','retry')),
  photo_paths  text[] default '{}',        -- Storage 경로 (최대 4장)
  show_photos  boolean not null default true,
  show_kcal    boolean not null default true,
  show_macros  boolean not null default true,
  created_at   timestamptz default now(),
  deleted_at   timestamptz,
  unique (group_id, user_id, post_date)    -- 같은 날 같은 그룹에 중복 게시 방지
);

-- 응원 반응
create table public.post_reactions (
  id           uuid primary key default gen_random_uuid(),
  post_id      uuid not null references public.community_posts(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  reaction     reaction_type not null,
  created_at   timestamptz default now(),
  unique (post_id, user_id, reaction)      -- 같은 반응 중복 방지
);

-- 조언 메시지
create table public.post_tips (
  id           uuid primary key default gen_random_uuid(),
  post_id      uuid not null references public.community_posts(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  body         text not null check (char_length(body) <= 100),
  created_at   timestamptz default now(),
  deleted_at   timestamptz
);

-- 차단
create table public.user_blocks (
  id           uuid primary key default gen_random_uuid(),
  blocker_id   uuid not null references auth.users(id) on delete cascade,
  blocked_id   uuid not null references auth.users(id) on delete cascade,
  created_at   timestamptz default now(),
  unique (blocker_id, blocked_id)
);

-- 신고
create table public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references auth.users(id) on delete cascade,
  group_id     uuid references public.community_groups(id) on delete cascade,
  target_type  text not null check (target_type in ('post','tip','user')),
  target_id    uuid not null,
  reason       report_reason not null,
  detail       text,
  status       report_status not null default 'pending',
  created_at   timestamptz default now(),
  resolved_at  timestamptz
);

-- 제재 이력 (개발자가 내린 조치 기록)
create table public.sanctions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  report_id    uuid references public.reports(id),
  sanction     sanction_type not null,
  reason       text,
  expires_at   timestamptz,           -- null이면 영구
  created_at   timestamptz default now()
);
```

### 6.4 RLS 정책

```sql
alter table public.community_groups  enable row level security;
alter table public.group_members    enable row level security;
alter table public.community_posts  enable row level security;
alter table public.post_reactions   enable row level security;
alter table public.post_tips        enable row level security;
alter table public.user_blocks      enable row level security;
alter table public.reports          enable row level security;
alter table public.sanctions        enable row level security;

-- 그룹: 공개 그룹은 누구나 열람, 비공개 그룹은 멤버만
create policy "group_public_read" on public.community_groups
  for select using (
    visibility = 'public' and archived_at is null
    or exists (select 1 from public.group_members gm
               where gm.group_id = id and gm.user_id = auth.uid()
               and gm.left_at is null and gm.kicked_at is null)
  );
create policy "group_owner_write" on public.community_groups
  for all using (created_by = auth.uid()) with check (created_by = auth.uid());

-- 멤버십: 본인 행 관리 + 같은 그룹 멤버 열람 + 그룹장 강퇴(update)
create policy "own_membership" on public.group_members
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "group_members_read" on public.group_members
  for select using (
    exists (select 1 from public.group_members gm2
            where gm2.group_id = group_id and gm2.user_id = auth.uid()
            and gm2.left_at is null and gm2.kicked_at is null)
  );
create policy "owner_can_kick" on public.group_members
  for update using (
    exists (select 1 from public.group_members gm_owner
            where gm_owner.group_id = group_id and gm_owner.user_id = auth.uid()
            and gm_owner.role = 'owner' and gm_owner.left_at is null)
  );

-- 포스트: 같은 그룹 활성 멤버만 열람, 본인만 작성
create policy "post_group_read" on public.community_posts
  for select using (
    exists (select 1 from public.group_members gm
            where gm.group_id = group_id and gm.user_id = auth.uid()
            and gm.left_at is null and gm.kicked_at is null)
    and not exists (select 1 from public.user_blocks ub
                    where ub.blocker_id = auth.uid() and ub.blocked_id = user_id)
  );
create policy "post_own_write" on public.community_posts
  for insert with check (user_id = auth.uid());
create policy "post_own_delete" on public.community_posts
  for update using (user_id = auth.uid());

-- 반응: 그룹 멤버만
create policy "reaction_group" on public.post_reactions
  for all using (
    exists (select 1 from public.community_posts cp
            join public.group_members gm on gm.group_id = cp.group_id
            where cp.id = post_id and gm.user_id = auth.uid()
            and gm.left_at is null and gm.kicked_at is null)
  );

-- 조언: 그룹 멤버만, 본인만 삭제
create policy "tip_group_read" on public.post_tips
  for select using (
    exists (select 1 from public.community_posts cp
            join public.group_members gm on gm.group_id = cp.group_id
            where cp.id = post_id and gm.user_id = auth.uid()
            and gm.left_at is null and gm.kicked_at is null)
  );
create policy "tip_write" on public.post_tips
  for insert with check (user_id = auth.uid());
create policy "tip_own_delete" on public.post_tips
  for update using (user_id = auth.uid());

-- 차단: 본인만
create policy "own_blocks" on public.user_blocks
  for all using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

-- 신고: 본인만 작성, 조회 불가(개발자는 service_role)
create policy "own_reports_insert" on public.reports
  for insert with check (reporter_id = auth.uid());

-- 제재: service_role만 (개발자 전용)
-- sanctions 테이블은 클라이언트에서 직접 접근 불가
```

---

## 7. API / Edge Functions

### 7.1 `community-auto-share` (Cron Edge Function)

- 스케줄: **5분 간격** 실행 (비용 최적화)
- 로직: `group_members.auto_share = true`이고 `share_time`이 현재 시각 기준 ±2.5분 이내인 멤버의 오늘 `entries`를 조회 → `community_posts` INSERT
- `entries`가 0건이면 skip (무기록 날은 공유 안 함)
- 게시 후 해당 그룹 멤버에게 FCM 알림 (그룹당 1일 1회 제한)
- 중복 방지: `community_posts`의 `unique (group_id, user_id, post_date)` 제약으로 idempotent

### 7.2 `community-report` (Edge Function)

- 신고 INSERT 시 Database Webhook으로 호출
- **처리 흐름:**
  1. `reports` INSERT 감지
  2. 해당 target의 기존 신고 건수 조회
  3. 누적 2건 이상 → 콘텐츠 자동 숨김 (`deleted_at` 세팅)
  4. **개발자에게 FCM 푸시**: "🚨 신고 접수: {그룹이름} / {닉네임} / {사유}"
  5. 푸시 payload에 report_id 포함 → 탭하면 관리 화면으로 딥링크

### 7.3 `community-sanction` (Edge Function)

- 개발자가 관리 화면에서 제재 액션 실행 시 호출 (service_role)
- `sanctions` INSERT → 해당 사용자에게 FCM 푸시: "커뮤니티 가이드라인 위반 알림"
- 정지(suspend) 시: `sanctions.expires_at` 체크하여 해당 기간 동안 게시/반응 차단
- 영구 정지: 해당 사용자의 모든 그룹에서 탈퇴 처리 + 재가입 차단

### 7.4 텍스트 필터 (조언 게시 전)

- 금지어 목록: 욕설, 비하어, "실패", "어겼다", "망쳤다", 체중 관련 비하
- 해당 단어 포함 시 게시 차단 + 안내: "따뜻한 조언으로 바꿔볼까? 푸디가 도와줄게!"
- 필터 통과 후에만 `post_tips` INSERT

### 7.5 `group-password-verify` (Edge Function)

- 비공개 그룹 참여 시 비밀번호 검증
- 클라이언트에서 평문 전송 → Edge Function에서 bcrypt 비교 → 성공 시 `group_members` INSERT
- 비밀번호는 DB에 bcrypt hash로만 저장 (평문 저장 금지)

---

## 8. UI 디자인 방향

### 8.1 커뮤니티 탭 피드

```
┌─────────────────────────────────────────┐
│ 👥 커뮤니티    [내 그룹 ▾] [그룹 탐색]   │  ← 상단 탭
│               [그룹A] [그룹B] [그룹C]   │  ← 그룹 칩 (내 그룹 선택 시)
├─────────────────────────────────────────┤
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ 🍓 수민  ·  5월 5일             │    │
│  │                                 │    │
│  │ [아침📷] [점심📷] [저녁📷]      │    │  ← 사진 가로 스크롤
│  │                                 │    │
│  │  🎯 목표 달성!  92%             │    │  ← 달성 배지 + 링 차트
│  │  1,650 / 1,800 kcal            │    │  ← show_kcal=true 일 때만
│  │  탄 180g · 단 95g · 지 45g     │    │  ← show_macros=true 일 때만
│  │                                 │    │
│  │  🔥 3  👏 2  💚 1               │    │  ← 응원 반응 요약
│  │  [🔥 응원하기]                  │    │  ← 내가 아직 반응 안 했을 때
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ 🏋️ 재호  ·  5월 5일             │    │
│  │                                 │    │
│  │ [점심📷] [저녁📷]               │    │
│  │                                 │    │
│  │  🌱 내일 다시!  115%            │    │  ← 초과
│  │                                 │    │
│  │  🔥 1                           │    │
│  │  [🔥 응원하기] [💡 조언 남기기] │    │  ← 미달성이라 조언 가능
│  └─────────────────────────────────┘    │
│                                         │
└─────────────────────────────────────────┘
```

### 8.2 디자인 토큰 (기존 시스템 확장)

| 요소 | 토큰 | 값 |
|---|---|---|
| 커뮤니티 배경 | `--cream-00` | #FFFDFA (기존) |
| 카드 배경 | `--cream-50` | #FBF6EF (기존) |
| 달성 배지 (achieved) | `--leaf-500` | #7FB77E |
| 달성 배지 (almost) | `--coral-500` | #FF8A5B |
| 달성 배지 (retry) | `--warm-500` | #6B6454 |
| 응원 반응 영역 | `--coral-50` | #FFF5F0 |
| 조언 입력 배경 | `--sky-50` | (신규) #F0F7FC |
| 그룹 칩 선택 | `--coral-100` | #FFE4D1 |

### 8.3 모션

- 응원 탭 시: 이모지 바운스 + 파티클(작은 불꽃/하트/박수) 0.4s
- 달성 배지: 링 차트 fill 애니메이션 0.6s ease
- 카드 등장: fade-in + translateY(8px) 0.2s

---

## 9. 알림 & 리텐션 확장

### 9.1 커뮤니티 전용 푸시

| 알림 | 트리거 | 하루 상한 |
|---|---|---|
| "🔥 {닉네임}이 응원했어!" | 내 카드에 반응 | 통합 3건 (묶음) |
| "💡 {닉네임}: {미리보기}" | 내 카드에 조언 | 즉시, 건당 |
| "🎯 {닉네임} 목표 달성!" | 구성원 달성 | 그룹당 1일 2건 |
| "오늘 식단 기록하고 친구들에게 공유해볼까?" | 15시 무기록 + 그룹 참여 중 | 1일 1회 |
| "그룹 친구 {N}명이 오늘 기록했어!" | 구성원 과반 기록 시 | 1일 1회 |

### 9.2 리텐션 메커니즘

- **사회적 압력**: 그룹 구성원이 기록하면 나도 기록하게 되는 선순환
- **연속 달성 축하**: 3/7/14/30일 연속 달성 시 그룹에 자동 축하 카드 (시스템 생성)
- **주간 그룹 리포트**: 일요일 저녁, 그룹 전체의 이번 주 평균 달성률 요약 (개인 비교 없이, 그룹 전체 수치만)

---

## 10. 기술 구현 방향

### 10.1 기존 자산 재활용

| 기존 자산 | 커뮤니티 활용 |
|---|---|
| `DailyShareCard` + `DailyShareService` | 커뮤니티 카드 렌더링 기반 |
| `share_links.scope_json` 패턴 | 그룹별 공개 범위 제어 패턴 참고 |
| Supabase Realtime | 그룹 피드 실시간 갱신 |
| FCM + `notifications` 테이블 | 커뮤니티 알림 통합 |
| `entries` + `todayEntriesProvider` | 자동 공유 데이터 소스 |
| `profiles.daily_kcal_target` | 달성률 계산 기준 |

### 10.2 Flutter 구조 확장

```
lib/features/community/
├─ community_page.dart          # 메인 탭 (내 그룹 / 그룹 탐색)
├─ community_card.dart          # Daily Card 위젯
├─ group_create_page.dart       # 그룹 만들기 (공개/비공개)
├─ group_join_page.dart         # 비밀번호 입력 참여
├─ group_explore_page.dart      # 공개 그룹 탐색/검색
├─ group_settings_page.dart     # 그룹 설정 (그룹장 전용 포함)
├─ group_members_page.dart      # 구성원 관리 (그룹장: 강퇴)
├─ post_detail_page.dart        # 카드 상세 + 반응 + 조언
├─ tip_input_sheet.dart         # 조언 입력 바텀시트
├─ report_sheet.dart            # 신고 바텀시트
└─ admin/
   └─ admin_reports_page.dart   # 개발자 관리 화면 (신고 처리)

lib/providers/
├─ community_provider.dart      # 그룹 목록, 피드 데이터
├─ group_members_provider.dart  # 멤버십 상태
├─ reactions_provider.dart      # 반응/조언 CRUD
└─ reports_provider.dart        # 신고/제재 (admin)
```

### 10.3 성능 고려

- 피드 페이지네이션: 10건 단위, infinite scroll
- 이미지: signed URL + 캐시 (기존 `SignedNetworkImage` 재활용)
- Realtime 구독: 그룹별 `community_posts` 변경 감지 → 피드 자동 갱신
- 오프라인: 캐시된 피드는 표시, 반응/조언은 온라인 시에만

---

## 11. KPI (커뮤니티)

### 11.1 핵심 지표

| 지표 | 목표 (론칭 3개월) |
|---|---|
| 그룹 참여 사용자 비율 (MAU 중) | ≥ 30% |
| 그룹 참여자의 W1R (주 3일+ 기록) | ≥ 60% (비참여자 대비 1.5x) |
| 일일 피드 열람률 (그룹 참여자 중) | ≥ 50% |
| 응원 반응률 (카드 당 평균) | ≥ 2.0건 |
| 조언 작성률 (미달성 카드 중) | ≥ 15% |

### 11.2 건강성 지표

| 지표 | 경고 기준 |
|---|---|
| 신고 비율 (조언 텍스트 중) | > 2% → 필터 강화 |
| 그룹 이탈률 (월간) | > 20% → 원인 분석 |
| 자동 공유 OFF 전환률 | > 30% → 알림 과다 의심 |
| 강퇴율 (월간, 공개 그룹) | > 10% → 가이드라인 강화 검토 |

---

## 12. 페이즈 구분

### Phase 1 — MVP (4주)

- 그룹 CRUD (공개/비공개 생성, 참여, 나가기)
- 공개 그룹 탐색/검색
- 비공개 그룹 비밀번호 참여
- 그룹장 강퇴 기능
- 수동 공유 (커뮤니티 탭 → "오늘 공유하기")
- 피드 열람
- 응원 반응 (🔥/👏/💚)
- 신고 → 개발자 FCM 알림 + 관리 화면
- 차단 기능
- 커뮤니티 가이드라인 약관
- 개인정보처리방침 / 이용약관 업데이트

### Phase 2 — 자동화 & 조언 (2주)

- 자동 공유 (시각 설정 + Cron Edge Function)
- 조언 텍스트 기능 + 금지어 필터
- 커뮤니티 알림 (응원/조언/달성 축하)
- 연속 달성 축하 카드 (시스템 생성)
- 제재 시스템 고도화 (정지 기간 자동 만료)

### Phase 3 — 인게이지먼트 강화 (2주)

- 주간 그룹 리포트
- 그룹 목표 챌린지 (예: "이번 주 전원 5일 달성!")
- 프로필 이모지/배지 커스터마이징
- 카드 꾸미기 (배경 테마)

---

## 13. 리스크 & 완화

| 리스크 | 영향 | 완화 |
|---|---|---|
| App Store UGC 리젝 | 높음 | Phase 1에 신고/차단/가이드라인 필수 포함 |
| 섭식장애 트리거 (칼로리 비교) | 높음 | 랭킹 없음, kcal 숨기기 옵션, 극단 칼로리 축하 차단 |
| 부정적 조언으로 이탈 | 중간 | 금지어 필터 + 달성 카드엔 조언 불가 구조 |
| 공개 그룹에서 스팸/부적절 콘텐츠 | 중간 | 신고 → 개발자 즉시 알림 + 자동 숨김 + 그룹장 강퇴 |
| 그룹 활성도 저하 | 중간 | 자동 공유 + 달성 축하 알림으로 최소 인터랙션 보장 |
| 비밀번호 유출 (비공개 그룹) | 낮음 | 32명 상한 + 그룹장이 비밀번호 변경 가능 + 강퇴 |
| 신고 폭주 시 개발자 과부하 | 낮음 | 자동 숨김(2건)으로 즉시 대응, 수동 확인은 비동기 |

---

## 14. 오픈 이슈 (결정 필요)

### 14.1 확정된 결정

| # | 이슈 | 결정 | 근거 |
|---|---|---|---|
| 1 | 탭 바 구성 | 5탭 유지. 마이→홈 AppBar 아이콘, 마이 자리에 커뮤니티 | 사용자 결정 |
| 2 | 공유 범위 | 사용자 설정 가능 (사진/kcal/영양소) 디폴트 ALL ON | 사용자 결정 |
| 3 | 자동 공유 기본값 | OFF (옵트인) | App Store 프라이버시 + 사용자 결정 |
| 4 | 그룹 구조 | 공개 그룹(검색 가능) + 비공개 그룹(비밀번호) | 사용자 결정 |
| 5 | 그룹 상한 인원 | 32명 | 사용자 결정 |
| 6 | 그룹장 권한 | 구성원 강퇴 가능 | 사용자 결정 |
| 7 | 신고 처리 | 개발자에게 FCM 즉시 알림 → 관리 화면에서 제재 | 사용자 결정 |

### 14.2 미결 이슈

| # | 이슈 | 옵션 A | 옵션 B | 추천 |
|---|---|---|---|---|
| 8 | 사진 공유 시 원본 vs 리사이즈 | 원본 signed URL | 480px 리사이즈 썸네일 전용 | B (트래픽 절약 + 프라이버시) |
| 9 | 조언 길이 | 100자 | 200자 | A (짧을수록 부담 적음) |
| 10 | 달성률 계산 시 초과 표현 | 115% 그대로 | 100% 캡 | A (초과도 데이터) |
| 11 | 프로필 아바타 | 이모지만 | 사진 업로드 가능 | A (MVP는 이모지, 사진은 Phase 3) |

### 14.3 계정 삭제 시 데이터 처리

사용자가 계정을 삭제(`auth.users` CASCADE)하면:
- `community_posts` → CASCADE 삭제 (본인 카드 제거)
- `post_reactions` / `post_tips` → CASCADE 삭제 (본인이 남긴 응원/조언 제거)
- `group_members` → CASCADE 삭제 (그룹 탈퇴 처리)
- `community_groups.created_by` → 그룹장 삭제 시, 남은 멤버 중 가장 오래된 멤버에게 owner 이전 (Edge Function `on_user_delete` 트리거)
- 남은 멤버가 없으면 그룹 archived 처리

---

## 부록 A. 커뮤니티 화면 리스트

1. 커뮤니티 탭 — 내 그룹 (그룹 셀렉터 + 카드 리스트)
2. 커뮤니티 탭 — 그룹 탐색 (공개 그룹 검색/리스트)
3. 그룹 만들기 (공개/비공개 선택 + 비밀번호)
4. 비밀번호 입력 (비공개 그룹 참여)
5. 그룹 설정 (이름/이모지/소개글/공개↔비공개/비밀번호/자동 공유/나가기)
6. 공유 범위 설정 (사진/칼로리/영양소 토글)
7. 구성원 관리 (목록 + 그룹장: 강퇴)
8. 카드 상세 (사진 확대 + 응원 목록 + 조언 스레드)
9. 조언 입력 바텀시트
10. 신고 바텀시트
11. 닉네임 변경 (프로필 → 닉네임 변경 / 실시간 중복확인)
12. 차단 관리 (홈 → 프로필 아이콘 → 설정)
13. 빈 상태 (그룹 없음 / 오늘 기록 없음)
14. [개발자] 신고 관리 화면 (신고 목록 + 게시물 열람 + 제재 액션)

## 부록 B. 용어집 (커뮤니티 추가)

- **닉네임 (Nickname)**: 서비스 전체에서 고유한 사용자 식별명. 중복 불가, 30일 1회 변경
- **커뮤니티 그룹 (Group)**: 최대 32명이 식단을 공유하는 단위. 공개/비공개 선택
- **공개 그룹 (Public Group)**: 누구나 검색/브라우징으로 참여 가능
- **비공개 그룹 (Private Group)**: 비밀번호를 아는 사람만 참여 가능
- **그룹장 (Owner)**: 그룹 생성자. 설정 변경, 구성원 강퇴, 그룹장 위임 권한
- **식단 카드 (Daily Card)**: 하루 식단 요약 + 달성률을 담은 공유 단위
- **응원 (Cheer)**: 원탭 이모지 반응 (🔥/👏/💚)
- **조언 (Tip)**: 미달성 카드에 남기는 짧은 격려/제안 텍스트 (100자 이내)
- **달성 배지 (Status Badge)**: 🎯 달성 / 💪 거의 / 🌱 내일
- **자동 공유 (Auto Share)**: 설정 시각에 오늘 식단을 그룹에 자동 게시
- **강퇴 (Kick)**: 그룹장이 구성원을 퇴장시키는 것. 24h 재가입 제한
- **제재 (Sanction)**: 개발자가 신고 기반으로 내리는 계정 조치 (경고/정지/영구 차단)

---

## 부록 C. 법적 문서 / 외부 페이지 업데이트 필요사항

커뮤니티 기능 출시 시 아래 문서/페이지에 관련 내용을 추가·수정해야 함:

### C.1 개인정보처리방침 (Privacy Policy)

추가할 항목:
- **수집 항목**: 닉네임, 프로필 이모지, 식단 사진, 칼로리/영양소 데이터 (커뮤니티 공유 시)
- **수집 목적**: 커뮤니티 그룹 내 식단 공유, 구성원 간 소통 기능 제공
- **보유 기간**: 그룹 탈퇴 또는 계정 삭제 시 즉시 삭제 (공유 카드 포함)
- **제3자 제공**: 같은 그룹 구성원에게만 공개 (사용자 설정 범위 내)
- **신고 데이터**: 신고 사유/상세, 대상 콘텐츠를 운영자(개발자)가 확인할 수 있음
- **제재 이력**: 가이드라인 위반 시 제재 기록 보관 (서비스 안전 목적)

### C.2 이용약관 / 커뮤니티 가이드라인

추가할 항목:
- 커뮤니티 내 금지 행위 (욕설, 비하, 괴롭힘, 스팸, 광고)
- 신고 절차 및 처리 기준
- 제재 단계 (경고 → 7일 정지 → 30일 정지 → 영구 차단)
- 그룹장 권한 범위 (강퇴 사유 불필요, 재가입 24h 제한)
- 자동 숨김 기준 (신고 2건 누적 시)
- 이의 제기 절차 (개발자 이메일로 문의)

### C.3 개발자 URL / 고객지원 페이지 (App Store 등록용)

- **Support URL**: 커뮤니티 관련 문의/이의제기 안내 추가
- **Privacy URL**: 위 개인정보처리방침 링크
- **App Store 설명**: 커뮤니티 기능 소개 문구
- **마케팅 페이지**: 커뮤니티 기능 스크린샷/소개 (선택)

### C.4 GitHub Pages (docs/) 업데이트

기존 `docs/` 에 있는 support, privacy, home 페이지에 커뮤니티 관련 내용 반영:
- `docs/privacy.md` (또는 .html): 커뮤니티 데이터 수집/처리 내용 추가
- `docs/support.md`: 신고/제재 관련 FAQ + 이의제기 경로 추가
- `docs/index.html`: 커뮤니티 기능 소개 섹션 (선택)

---

*본 기획서는 `foodiet_기획안.md` §15.3의 "챌린지/그룹" 확장으로, 커뮤니티 MVP 합의용 초안입니다. §14.2 미결 이슈를 확정한 뒤 와이어프레임 → 구현으로 진행합니다.*
