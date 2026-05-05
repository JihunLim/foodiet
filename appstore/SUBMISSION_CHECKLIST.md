# foodiet — App Store Connect 제출 체크리스트

이 문서는 **제출 직전** 에 보면서 체크할 것. 순서대로 하면 리젝션 0 을 목표.

---

## 0. 기기 / 계정 준비 (선행)

- [ ] Apple Developer Program 멤버십 활성 (연 $99)
- [ ] App Store Connect 에서 `foodiet` 앱 레코드 생성
  - Bundle ID: `com.jihun.foodiet` (이미 Xcode 프로젝트에 박혀있음)
  - Primary language: Korean
  - Bundle ID 동일한 iPad/iPhone 지원 앱으로 등록
- [ ] Xcode → Signing & Capabilities → Team: Jihun Lim (74L4LBXJTK)
  - 자동 provisioning 켜둠

---

## 1. 코드 / 구성 최종 점검

모두 끝났으면 ✅.

- [x] **버전 1.0.0+1** (`app/pubspec.yaml`, `app/lib/main.dart`)
- [x] **iOS deployment target 14.0** (`ios/Podfile`, `Runner.xcodeproj`)
- [x] **NSUserTrackingUsageDescription** (`ios/Runner/Info.plist`)
- [x] **PrivacyInfo.xcprivacy** (`ios/Runner/PrivacyInfo.xcprivacy` + 프로젝트 Resources 등록)
- [x] **ATT 상태에 따른 NPA 광고 fallback** (`lib/services/ads_service.dart`)
- [x] **온보딩 intro 4장** (`lib/features/onboarding/onboarding_value_page.dart`)
- [x] **온보딩 권한 카드** (`lib/features/onboarding/onboarding_permissions_page.dart`)
- [x] **기록 상세 — 풀사진 + 탭 zoom** (`lib/features/entry/entry_detail_page.dart`)
- [x] **iPad 레이아웃 레터박스** (`lib/main.dart` MaterialApp.builder)
- [x] **체중 추적 + 예측 탭** (`lib/features/insight/weight_insight_page.dart`,
       `lib/providers/weight_provider.dart`, `lib/services/kcal_calc.dart::computeTdee`)
- [x] **푸시 알림 인프라** (서버 push):
       - Edge Functions: `send-push`, `daily-reminder` (deployed)
       - pg_cron `foodiet_daily_reminder` 매일 KST 20:00 실행 (catch-all)
       - Supabase Secrets: `FCM_PROJECT_ID` / `INTERNAL_PUSH_TOKEN` /
         `FCM_SERVICE_ACCOUNT_JSON`
       - Firebase: APNs Auth Key 개발 슬롯 등록됨
         (Key ID `879Q9AZ5UJ`, Team ID `74L4LBXJTK`, Sandbox 전용)
       - AppDelegate: `userNotificationCenter:willPresent:` 구현 — foreground
         일 때도 banner+sound+badge 표시 (`FirebaseAppDelegateProxyEnabled=false`
         상태에서 필수). `setForegroundNotificationPresentationOptions` 만으로는
         iOS 가 무시한다.
       - foreground / 잠금화면 / background 모두 도착 검증됨 ✅
       - **App Store archive 전 추가 작업 필요**: 현재 키는 Sandbox 전용이라
         production APNs 로 전송 불가. archive 직전에:
         1. Apple Developer 의 사용 안 하는 키 (Expo Push 등) 1개 revoke
         2. 새 키 발급 시 Environment = "Sandbox & Production" 으로 생성
         3. Firebase 프로덕션 슬롯에도 같은 .p8 업로드
         또는 단순히 "Sandbox & Production" 1개 키로 두 슬롯 모두 채우기 (1개로 양쪽 작동)
- [x] **끼니 리마인더 (로컬 알림)**:
       - `flutter_local_notifications` 21.x + `timezone` 0.11
       - `lib/services/meal_reminder_service.dart` — 부팅 시 prefs 로드 + OS 스케줄 동기화
       - 마이 > 알림 설정 시트:
         · master 토글 "식사 리마인더"
         · master ON 시 아침/점심/저녁 각 ON/OFF + 시각 (TimePicker)
         · 주간 리포트 / 스트릭 응원 항목 제거 — 스트릭은 항상 ON 으로 동작
       - SharedPreferences 키: `mealReminder.master`,
         `mealReminder.{breakfast|lunch|dinner}.{enabled|hour|minute}`
       - 권한은 FCM 흐름이 받은 UNUserNotificationCenter 권한을 그대로 사용 — 별도 다이얼로그 없음
       - 시간대: `Asia/Seoul` 고정 (foodiet 한국 시장 우선)
       - v1 의 의도된 단순화: 끼니를 이미 기록했어도 그 시간엔 발화 (문구를 부드럽게).
         "이미 기록했으면 오늘 알림 취소" 는 v1.1 에 추가
- [ ] USB 연결 아이폰에서 위 항목 전부 실제 확인 ← **제출 전 최종 관문**
  - 인사이트 탭 → 체중 / 영양 두 탭 전환 확인
  - 체중 탭 빈 상태(목표 미설정) 안내 동작
  - "기록" 버튼 → bottom sheet → 저장 → 차트에 점이 찍히는지
  - TDEE / 평균 섭취 / 적자 메트릭 값이 합리적인지
  - 9가지 verdict (🎯/⚠️/🔴/...) 중 하나가 정상적으로 노출
  - 권한 다이얼로그 4개 (카메라/사진/알림/ATT) 순차 노출 + 실제 시스템 다이얼로그 발화
  - 마이 > 알림 설정 → master 토글, 끼니별 토글, 시각 변경 → 1~2분 뒤로 시각 맞추고
    잠금화면에서 발화 확인 (3 끼니 모두)

---

## 2. 스크린샷

사용자가 찍은 원본은 `appstore/screenshots/raw/` 에 넣음.
각 원본을 Claude 가 광고 카피 + 배경 스타일로 꾸며 해당 사이즈 폴더에 내보냄.

### 필수 사이즈 (App Store Connect 업로드 기준)

| 디바이스 | 해상도 | 필요 장수 | 폴더 |
|---|---|---|---|
| iPhone 6.9" (iPhone 16 Pro Max) | 1290×2796 | 3~10장 (권장 5~6장) | `iphone_6_9/` |
| iPhone 6.5" (iPhone 11 Pro Max) | 1242×2688 | iPhone 6.9 와 공유 가능 | `iphone_6_5/` |
| iPad 13" (M4) | 2064×2752 | 3~10장 (권장 5장) | `ipad_13/` |
| iPad 12.9" (Pro 2/3/4/5/6 gen) | 2048×2732 | iPad 13 과 공유 가능 | `ipad_12_9/` |

> 팁: iPhone 은 6.9 만 찍어서 업로드하면 됨. iPad 도 13 한 사이즈.

### 추천 6장 구성

1. **"사진 한 장으로 끝"** — 카메라에서 막 찍은 사진 + AI 분석 결과 카드
2. **"칼로리·탄단지 자동 분석"** — 기록 상세의 매크로 차트
3. **"체중, 이대로 가면 도달할까?"** — 인사이트 > 체중 탭의 예측 차트 + 🎯 verdict 카드 ← **메인 임팩트**
4. **"목표 대비 남은 kcal"** — 홈의 링 프로그레스
5. **"푸디의 따뜻한 코치"** — 피드백 카드
6. **"홈 위젯 + 일일 공유 카드"** — 위젯 + 공유 카드 한 장에 합치기

---

## 3. 메타데이터 입력

App Store Connect > My Apps > foodiet > App Information / Version Information

- 한국어: `appstore/listing/ko.md` 내용 그대로 복사
- 영어: `appstore/listing/en.md` 내용 그대로 복사
- Category: Primary = **Health & Fitness**, Secondary = **Food & Drink**
- Age rating: **4+**
- Support URL: `https://JihunLim.github.io/foodiet/support/`
- Privacy Policy URL: `https://JihunLim.github.io/foodiet/privacy/`
- Marketing URL (선택): `https://JihunLim.github.io/foodiet/`

### App Privacy (데이터 수집 설문)

PrivacyInfo.xcprivacy 와 일치하게 답변. 아래대로.

- **Email Address** — Linked, Used for App Functionality
- **User ID** — Linked, Used for App Functionality
- **Photos** — Linked, Used for App Functionality
- **Health & Fitness** — Linked, Used for App Functionality
- **Product Interaction** — Not Linked, Analytics + App Functionality
- **Crash Data** — Not Linked, App Functionality
- **Performance Data** — Not Linked, App Functionality
- **Device ID** — Linked, **Used for Tracking**, Third-Party Advertising

---

## 4. 빌드 업로드 (Release IPA)

### 4.1 사전 확인

```bash
cd /Users/JihunLim/Documents/dev/foodiet/app
flutter doctor -v        # 모두 ✓ 확인
flutter analyze          # 0 issues
flutter pub outdated     # 치명적 dep 버전 이슈 없는지
```

### 4.2 IPA 빌드

> ⚠️ **Push 알림용 entitlement 토글 필수**:
> `ios/Runner/Runner.entitlements` 의 `aps-environment` 값을
> `development` → `production` 으로 변경 후 archive.
> (TestFlight / App Store 는 production APNs 환경. development 로 archive
>  하면 푸시가 안 옴.) 빌드 후 다시 development 로 되돌리면 USB 디버그
> 빌드 푸시 테스트도 계속 가능.

```bash
cd /Users/JihunLim/Documents/dev/foodiet/app
flutter clean
flutter pub get
cd ios && LANG=en_US.UTF-8 pod install && cd ..
flutter build ipa --release
```

산출물: `build/ios/ipa/foodiet.ipa`

빌드 넘버(`+1`) 는 **매번 올려야** App Store Connect 가 새 빌드로 인식한다.
이미 `1.0.0+1` 이면 다음 업로드 전 `1.0.0+2` 로 bump.

### 4.3 업로드

1. Xcode 열기: `open ios/Runner.xcworkspace`
2. Product > Destination > Any iOS Device (arm64)
3. Product > Archive
4. Organizer > Distribute App > App Store Connect > Upload
5. 10–30분 후 ASC > My Apps > TestFlight 에 빌드가 "Processing" 으로 뜸

또는 CLI 로:
```bash
xcrun altool --upload-app \
  -f build/ios/ipa/foodiet.ipa \
  -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_UUID>
```

---

## 5. TestFlight 내부 테스트 (필수는 아니지만 권장)

- 최소 본인 Apple ID 로 1회 설치 → 실제 백엔드(Supabase)와 연동되는지 확인
- 광고가 뜨는지 (debug 빌드는 테스트 광고, release 는 실광고)
- 결제 없음 — 별도 설정 불필요
- ATT 다이얼로그가 첫 실행에 뜨는지
- 계정 삭제 흐름 동작하는지

---

## 6. 리뷰 제출

App Store Connect > Version > "Submit for Review"

- **로그인 정보**: 리뷰어가 시험해볼 수 있도록 테스트 계정을 준비
  - 예: `apple-reviewer@foodiet.app` / 임시 비번
  - Notes 에 Apple 로그인 지원 안내 (sandbox Apple ID)
- **리뷰 노트 (Notes)**:
  ```
  1. This app logs meals via photo + AI analysis.
  2. Account creation supports Apple / Google / Kakao SSO only.
  3. Test account: <email> / <password>
  4. AdMob native ads appear in the Insight tab.
  5. ATT dialog appears during onboarding permission step.
  ```
- **Demo account 필요 여부**: 예 (로그인 필수 앱)
- **Contact info**: jihunlim204@gmail.com

**평균 리뷰 시간 현재 24–48시간 (2026-04 기준)**.

---

## 7. 리젝션 빈발 포인트 (예방)

- 🚨 **Guideline 5.1.1 Data Collection & Storage** — 계정 삭제 기능 필수 → 앱 내 "설정 > 계정 삭제" 구현 확인.
- 🚨 **Guideline 4.2 Minimum Functionality** — 온보딩 가치 카드 4장이 너무 단순해 보일 수 있음 → 첫 로그인 후 실제 분석까지 경험하도록 샘플 사진 가이드를 추가하면 안전.
- 🚨 **Guideline 5.1.2 Data Minimization** — 광고 개인화 거부시 앱이 잠그지 않는지 리뷰어가 확인. NPA fallback 이미 구현.
- 🚨 **ITMS-91053** — PrivacyInfo.xcprivacy 누락 경고. 이번에 추가함.

---

## 8. 출시 후

- App Analytics (Impressions, Sales) → 주 1회
- TestFlight 피드백 > Respond
- AdMob 대시보드 → 일일 활성 광고 수익
- Firebase Crashlytics → 크래시 발생 시 Slack / 이메일 알림 (원하면 설정)
- 1.0.1 로 버그픽스 빠르게 → 첫 주에 1 라운드 예상
