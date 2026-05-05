# foodiet 1.0 — 지금 바로 제출하기

순서대로 따라가면 30~60분 안에 App Store 제출 완료.

크롬에 이미 띄워둔 탭:
1. **App Store Connect login** (`tab 792841384`) — 메인 작업 페이지
2. **Apple Developer Auth Keys** (`tab 792841387`) — APNs 키 교체용
3. **Firebase Cloud Messaging** (`tab 792841330`) — 새 키 업로드용

---

## ① APNs Production 키 교체 (10분)

현재 Firebase 에 등록된 키 `879Q9AZ5UJ` 는 Sandbox 전용 → Production APNs 로 푸시가
안 옴. 출시 전 반드시 교체.

**Apple Developer (tab 792841387)**
1. 로그인 (Apple ID + 2FA)
2. Keys 목록에서 `879Q9AZ5UJ` 또는 다른 안 쓰는 키 1개 선택 → "Revoke"
   (키 limit 2개라 1개 비워야 새로 만들 수 있음)
3. 우상단 "+" 버튼 → New Key
4. Key Name: `foodiet APNs (sandbox+prod)`
5. **Apple Push Notifications service (APNs)** 체크
   - Configure → Environment = **"Sandbox & Production"** ⚠️ 이게 핵심
6. Continue → Register → **Download** (.p8 파일은 한 번만 다운로드 가능)
7. 다운받은 Key ID 와 Team ID `74L4LBXJTK` 메모

**Firebase Console (tab 792841330)**
1. Cloud Messaging 페이지에서 Apple App Store config 섹션 스크롤
2. APNs Authentication Key → 기존 키 옆 휴지통 → 삭제
3. Upload → 방금 다운받은 .p8 + Key ID + Team ID 입력 → Upload

---

## ② IPA 업로드 (10분)

빌드 산출물: `app/build/ios/ipa/foodiet.ipa`

가장 쉬운 방법: **Transporter.app** (App Store 에서 무료)
1. Mac App Store 에서 "Transporter" 설치
2. Transporter 열고 Apple ID 로그인
3. `foodiet.ipa` drag & drop
4. "DELIVER" 클릭 → 5~15분 후 ASC 에서 처리됨

또는 Xcode:
1. `open /Users/JihunLim/Documents/dev/foodiet/app/ios/Runner.xcworkspace`
2. Window → Organizer → 최근 archive 선택
3. Distribute App → App Store Connect → Upload

업로드 후 ASC > TestFlight 에 "Processing" 으로 뜨면 성공. 10~30분 후
"Ready to Submit" 상태가 됨.

---

## ③ App 레코드 생성 (5분)

**App Store Connect (tab 792841384)** 로그인 후

1. My Apps → "+" → New App
2. 입력값:
   - **Platforms**: iOS
   - **Name**: `foodiet`
   - **Primary Language**: Korean
   - **Bundle ID**: `com.jihun.foodiet` (드롭다운에서 선택 — Apple Developer 에서 자동 등록됨)
   - **SKU**: `foodiet-ios-1` (내부 식별자, 임의)
   - **User Access**: Full Access
3. Create

---

## ④ 메타데이터 입력 (10분)

**App Information**:
- Subtitle: `한 장으로 끝내는 AI 식단 코치`
- Category Primary: **Health & Fitness**
- Category Secondary: **Food & Drink**
- Content Rights: "Does not contain..." 체크
- Age Rating: 4+ (질문지 모두 None — `appstore/listing/ko.md` §Age Rating 참고)

**Pricing and Availability**:
- Price: KRW 0 (무료)
- Availability: All Countries (또는 Korea, US 만 선택)

**App Privacy** (좌측 메뉴):
| 데이터 | 수집? | 목적 | 연결? | 추적? |
|---|---|---|---|---|
| Email Address | Yes | App Functionality | Linked | No |
| User ID | Yes | App Functionality | Linked | No |
| Photos | Yes | App Functionality | Linked | No |
| Device ID (IDFA) | Yes | Third-Party Advertising | Linked | **Yes** |
| Product Interaction | Yes | Analytics | Linked | No |
| Crash Data | Yes | App Functionality | Not Linked | No |
| Performance Data | Yes | App Functionality | Not Linked | No |

(상세는 `appstore/listing/ko.md` §App Privacy 참고)

---

## ⑤ 1.0 버전 페이지 입력 (15분)

좌측 메뉴 "iOS App > 1.0 Prepare for Submission":

**Version Information** (한국어):
- Promotional Text: `appstore/listing/ko.md` §Promotional Text
- Description: `appstore/listing/ko.md` §Description (전체)
- Keywords: `식단기록,다이어트,AI식단,칼로리계산,푸디,PT식단,탄단지,사진식단,끼니,식단관리,영양분석,헬스식단,체중관리`
- Support URL: `https://JihunLim.github.io/foodiet/support`
- Marketing URL: `https://JihunLim.github.io/foodiet/`
- Privacy Policy URL: `https://JihunLim.github.io/foodiet/privacy`

**Localizations 추가 → English (U.S.)**:
- 동일 항목을 `appstore/listing/en.md` 에서 복사

**Screenshots**:
- iPhone 6.9" Display: `appstore/screenshots/iphone_6_9/01.png ~ 08.png` 8장 drag & drop
- iPad 13" Display: `appstore/screenshots/ipad_13/01.png ~ 08.png` 8장
- (6.5" / 12.9" 슬롯은 자동 fallback — 비워둬도 됨)

**What's New in This Version**: `appstore/listing/ko.md` §What's New 박스 내용

**Build**: ② 단계에서 업로드한 빌드 선택 (Processing 끝난 후 노출)

**App Review Information**:
- Sign-in required: **Yes**
  - Username: `apple-reviewer@foodiet.app` (테스트 계정 만들고 입력)
  - Password: 임시 비번
- Contact Information: `jihunlim204@gmail.com`, 010-XXXX-XXXX
- Notes:
  ```
  1. App logs meals via photo + AI analysis.
  2. Account creation supports Apple / Google / Kakao SSO only.
  3. Test account: apple-reviewer@foodiet.app / [password]
  4. AdMob native ads appear in the Insight tab.
  5. ATT dialog appears during onboarding permission step.
  6. Meal reminders are local notifications scheduled at user-configured times.
  ```

**Version Release**: "Manually release this version" 권장 (승인 후 직접 출시 시점 선택)

---

## ⑥ 제출 (1분)

1. 우상단 **"Add for Review"**
2. 다음 페이지에서 권리 / 광고 식별자 / 법적 동의 체크박스 모두 ✓
3. **"Submit to App Review"**

리뷰 평균 24~48시간. 승인되면 "Pending Developer Release" 상태에서 출시 버튼 누르면 끝.

---

## ⑦ 제출 후 (선택)

- **TestFlight 내부 테스트**: 본인 Apple ID 로 1회 설치해서 production 빌드 동작 확인
  (특히 푸시가 production APNs 로 들어오는지)
- **Firebase Crashlytics 알림 설정**: 크래시 발생 시 이메일/Slack
- **AdMob 대시보드**: 일일 활성 광고 수익 모니터링
