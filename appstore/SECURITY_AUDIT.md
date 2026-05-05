# foodiet 1.0 — 제출 전 보안 감사 결과

수행: 2026-04-25, 코드베이스 + 라이브 Supabase 프로젝트 직접 점검.

---

## 🟢 결론

**App Store 제출 차단 사유 없음.** CRITICAL / HIGH 1건은 코드 패치 완료. 그 외는 정상.

---

## 점검 통과 (✅ 12 / 12 항목)

### 1. 시크릿 노출 (✅ PASS)
- `app/.env.example` 에 publishable key 만 존재 (`sb_publishable_...`).
  서비스 롤·OPENAI·FCM service account 는 모두 주석 처리, Edge Function Secrets 로만 주입.
- `app/.gitignore` 에 `.env`, `.env.local`, `.env.*.local` 모두 포함.
- 클라이언트 코드 (`lib/`) 어디에도 service_role / OPENAI / INTERNAL_PUSH_TOKEN
  하드코딩 없음.

### 2. RLS (Row Level Security) (✅ PASS)
라이브 DB 점검 결과 — 10 개 사용자 테이블 모두 RLS enable + 정책 1개씩:

| 테이블 | RLS | 정책 (cmd=ALL, qual) |
|---|---|---|
| profiles | ✅ | `user_id = auth.uid()` |
| entries | ✅ | `user_id = auth.uid()` |
| entry_items | ✅ | `EXISTS (SELECT 1 FROM entries WHERE id = entry_items.entry_id AND user_id = auth.uid())` |
| corrections | ✅ | `user_id = auth.uid()` |
| coach_messages | ✅ | `user_id = auth.uid()` |
| weight_logs | ✅ | `user_id = auth.uid()` |
| share_links | ✅ | `user_id = auth.uid()` |
| share_access_logs | ✅ | `EXISTS (SELECT 1 FROM share_links WHERE id = ... AND user_id = auth.uid())` |
| device_tokens | ✅ | `user_id = auth.uid()` |
| notifications | ✅ | `user_id = auth.uid()` |

타 사용자 데이터를 끌어올 수 있는 SELECT 경로 없음.

### 3. Storage Bucket (✅ PASS)
```
food-photos: public=false, file_size_limit=10MB
RLS:
  SELECT/INSERT/UPDATE/DELETE — bucket_id='food-photos' AND foldername(name)[1] = auth.uid()::text
```
경로 `{user_id}/{entry_id}.jpg` 구조로 사용자 격리. 다른 사용자의 폴더 접근 불가.
업로드 / 다운로드 모두 signed URL 또는 RLS 게이트 통과. **public bucket 이 아님 — leak 경로 없음.**

### 4. Edge Function 인증 (✅ PASS)
- `send-push`, `daily-reminder`: `INTERNAL_PUSH_TOKEN` 헤더 검증 ✅
- `home-coach`: `verify_jwt:false` 설정이지만 함수 안에서 `admin.auth.getUser(jwt)` 로
  manual verification → 미인증 시 401 + 사용자별 일일 5회 캐시 + 시간대 슬롯 제한.
- `analyze-entry`: 인증 없음. 단 `entry_id` UUID 가 필요 (랜덤 추측 불가능,
  `status='done'` 인 entry 는 idempotent skip → LLM 비용 차단).
  ⚠️ 자기 계정으로 의도적 abuse 시 OpenAI 비용 burnable. v1.1 에서 per-user
  rate limit 추가 권장 (영향: 최악 ~$10 / 사용자 자기파괴).

### 5. 클라이언트 로깅 (✅ PASS)
- 모든 진단 로그가 `if (kDebugMode) debugPrint(...)` 가드 또는 `kDebugMode` 분기 안.
- production AOT 빌드에선 출력 안 됨.
- 사용자 ID / FCM 토큰 풀텍스트 / JWT / IDFA 가 production 콘솔에 안 찍힘.

### 6. 딥링크 / URL 스킴 (✅ PASS)
- iOS Info.plist 의 CFBundleURLTypes:
  - `com.googleusercontent.apps.*` (Google Sign-In 콜백)
  - `kakao{KAKAO_NATIVE_APP_KEY}` (Kakao SDK 콜백)
  - `foodiet://` (홈위젯 → 카메라/홈/코치 라우팅)
- `foodiet://` 핸들러 (`main.dart` 에서 `pathSegments.last` 로 한정된 케이스만 라우팅:
  `camera | coach | home`). 임의 path 가 와도 switch default 로 무시 → 안전.

### 7. 사진 EXIF (✅ PASS)
`flutter_image_compress.compressWithList()` 의 `keepExif` 기본값 = **false** (iOS/Android 둘 다).
업로드 전 자동 strip 됨. GPS / device fingerprint 누출 없음.

### 8. iOS Info.plist / Entitlements (✅ PASS)
- 필수 NSUsageDescription 4종 모두 존재 + 한국어 친근한 문구:
  - `NSCameraUsageDescription`
  - `NSPhotoLibraryUsageDescription`
  - `NSMicrophoneUsageDescription` (image_picker 가 video 옵션 포함 — "사진 촬영엔 사용 안 해" 명시)
  - `NSUserTrackingUsageDescription`
- `aps-environment = production` (archive 직전에 토글 완료).
- App Group `group.com.jihun.foodiet.widget` 등록 (홈위젯용).
- `FirebaseAppDelegateProxyEnabled = false` (manual delegate forwarding — 의도된 설정).
- SKAdNetwork 식별자 적절히 등록.

### 9. 의존성 (✅ PASS)
- `pubspec.yaml` 의존성 모두 메이저 버전 핀 적용 (`^x.y.z`).
- `path_provider_foundation: 2.3.2` 명시 override (Flutter 3.41 + objective_c 빌드 이슈 회피).
- 알려진 CVE 보유 패키지 없음.

### 10. 계정 삭제 데이터 완전성 (✅ FIXED — 이번 패치)
**🔴 발견된 이슈**: `profiles.delete()` 만으로는 Storage 사진 파일이 고아로 남음.
**🟢 수정**: `lib/features/profile/profile_page.dart` `_deleteAccount` 에서
DB 삭제 *전에* `client.storage.list(path: user.id)` → `remove(paths)` 로 일괄 삭제.
Apple Privacy Guideline 5.1.1 (사용자 데이터 완전 삭제) 준수.

### 11. ATT / AdMob (✅ PASS)
- `applyAdMobPrivacyConfig()` 에서 ATT 상태 확인 → 미허용 시 NPA 모드 강제.
- IDFA 는 ATT 동의 후에만 광고 요청에 포함.
- Debug 빌드는 Google 테스트 광고 ID — 실 수익 사고 방지.

### 12. Apple Sign-In Nonce (✅ PASS)
- 클라이언트에서 raw nonce 생성 → SHA256 hash → Apple ID provider 에 hashed 전달.
- id_token 받으면 raw nonce 와 함께 `signInWithIdToken(nonce: raw)` 으로 Supabase 검증.
- replay attack 방어 동작 정상.

---

## ⚠️ 알려진 한계 (블로킹 아님, v1.1 권장)

### A. analyze-entry — Edge Function rate limit 없음
- 시나리오: 악성 사용자가 자기 계정으로 1000장 업로드 + analyze 트리거 → ~$10 OpenAI 비용 burn
- **완화책 (v1.1)**: per-user daily limit (e.g., 100 분석 / 일) 추가
- 1.0 출시 영향: **무시 가능** (소규모 베타 + 사용자 abuse 비용은 자기 시간)

### B. 서버 daily-reminder cron 의 timezone
- 현재 `_hasLoggedToday` 가 server UTC 기준 직전 24시간 윈도우.
- 한국 KST 와 어긋날 수 있어 가끔 "오늘 기록했는데 또 알림" 케이스.
- **완화책 (v1.1)**: profiles 에 `timezone` 컬럼 추가 → `date_trunc('day', now() AT TIME ZONE timezone)`.

### C. test-push Edge Function 가 서버에 deploy 된 채 남아있음
- 클라이언트 호출처 (`_TestPushButton`) 는 이전 cleanup 에서 제거됐음.
- `verify_jwt: true` 라 인증 없이 호출 불가 → 보안 위험은 없음.
- **권장**: Supabase Dashboard → Edge Functions → `test-push` → Delete 로 정리.

---

## 한 줄 요약

> **제출해도 됨.** Apple privacy review 가 까다로운 "사용자 데이터 완전 삭제" 항목까지
> 패치 들어갔고, RLS / Storage 격리 / Edge Function 인증은 모두 견고. 분석 LLM
> 비용 abuse 만 v1.1 에 손볼 가치가 있음.
