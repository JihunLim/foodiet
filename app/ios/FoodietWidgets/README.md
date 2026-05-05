# FoodietWidgets — iOS 홈스크린 위젯 Extension

기획안 §4.1 / §4.4 / §4.5 를 구현하는 WidgetKit extension 입니다.

## 포함 위젯
- **FoodietQuickLogWidget** (systemSmall) — 탭 → `foodiet://widget/camera`
- **FoodietRemainingWidget** (systemMedium) — 남은 칼로리 + 탄·단·지
- **FoodietCoachTipWidget** (systemMedium) — 푸디의 한마디

## Xcode 최초 설정 (한 번만)

CocoaPods 만으로는 extension target 이 생성되지 않으므로 Xcode GUI 에서 아래 단계를 수행해야 합니다.

### 1. Widget Extension 타겟 추가

1. `ios/Runner.xcworkspace` 를 Xcode 로 연다.
2. 프로젝트 네비게이터에서 최상단 **Runner** → `+` 버튼 → **Widget Extension** → Next.
3. Product Name: `FoodietWidgets`, Team/Bundle ID 는 `com.jihun.foodiet.FoodietWidgets`, **Include Configuration Intent 체크 해제**, Language: Swift.
4. Activate Scheme 다이얼로그에서 **Cancel** (Runner scheme 을 유지).
5. Xcode 가 자동 생성한 `FoodietWidgets/FoodietWidgets.swift`, `FoodietWidgets.intentdefinition`, `Assets.xcassets` 은 **제거**하고, 이 폴더에 이미 존재하는 파일들만 남긴다:
   - `FoodietWidgets.swift` (이 리포지토리에 있는 파일)
   - `Info.plist`
   - `FoodietWidgets.entitlements`
6. 파일 인스펙터에서 세 파일 모두 **Target Membership = FoodietWidgets** 만 체크.

### 2. App Group capability

1. **Runner** 타겟 → **Signing & Capabilities** → `+ Capability` → **App Groups** → `group.com.jihun.foodiet.widget` 추가.
2. **FoodietWidgets** 타겟도 동일하게 같은 App Group 을 추가.
3. Build Settings 에서 두 타겟 모두 Code Signing Entitlements 경로가 다음과 같이 설정됐는지 확인:
   - Runner: `Runner/Runner.entitlements`
   - FoodietWidgets: `FoodietWidgets/FoodietWidgets.entitlements`

### 3. Deployment target

- **FoodietWidgets** 타겟의 `IPHONEOS_DEPLOYMENT_TARGET` 을 최소 **iOS 16.0** 으로 설정 (containerBackground 는 17.0+ 에서만 활성화).

### 4. (선택) Color Assets

이 코드는 inline color 로 디자인 토큰을 박았기 때문에 별도 Asset Catalog 는 필요 없습니다. 톤이 바뀌면 `FD` enum 만 업데이트 하세요.

## 동작 원리

1. Flutter 앱의 `FoodietWidgetService.sync(...)` 가 App Group UserDefaults 에 값을 기록한다.
2. `home_widget` 플러그인이 `WidgetCenter.shared.reloadTimelines(ofKind:)` 를 호출한다.
3. `FoodietProvider.getTimeline` 이 다시 호출되어 `FoodietSnapshot.load()` 로 최신값을 읽는다.
4. 사용자가 위젯을 탭하면 `widgetURL` 이 앱을 열고, `home_widget` 플러그인이 `widgetClicked` 스트림으로 URI 를 전달 → `main.dart` 에서 go_router 라우팅.
