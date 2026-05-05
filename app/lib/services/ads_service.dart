/// AdMob 초기화 + 광고 단위 상수.
///
/// - 앱 ID 는 네이티브 Info.plist / AndroidManifest 에만 박는다 (SDK 요구사항).
/// - 광고 단위 ID 는 `FoodietAdUnits` 에 플랫폼별로 정리.
/// - 네이티브 고급형 광고 (native advanced) 는 `factoryId = "foodietNativeCard"`
///   로 iOS/Android 양쪽에서 같은 이름의 팩토리가 등록돼 있어야 한다.
/// - iOS 14.5+ ATT 상태에 맞춰 개인화 광고 설정을 자동 조정한다
///   ([applyAdMobPrivacyConfig]). 거부 / 미정 상태에서는 non-personalized
///   광고만 요청해 AdMob 정책과 App Store 리뷰 기준을 만족.
library;

import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class FoodietAdUnits {
  FoodietAdUnits._();

  /// 인사이트 탭 콘텐츠 사이에 삽입되는 네이티브 고급형 광고 단위.
  /// AdMob policy 준수를 위해 "광고" 라벨 + 명확한 타겟 + 광고주명 표기 필수.
  static String get insightNative {
    // 디버그 빌드에서는 Google 테스트 광고 단위를 사용 (실수로 실광고 호출 방지).
    if (kDebugMode) {
      if (Platform.isIOS) return 'ca-app-pub-3940256099942544/3986624511';
      return 'ca-app-pub-3940256099942544/2247696110';
    }
    // 프로덕션 — 동일한 단위를 iOS/Android 양쪽에서 사용.
    return 'ca-app-pub-6523753930426193/4600657381';
  }

  /// iOS/Android 네이티브 팩토리 등록에 쓰는 공통 ID.
  static const String nativeFactoryId = 'foodietNativeCard';
}

/// 앱 부팅 시 한 번 호출. 실패해도 앱 실행에는 영향 없도록 try/catch.
Future<void> initAdMob() async {
  try {
    await MobileAds.instance.initialize();
    // 디버그 빌드에서는 모든 기기를 테스트 기기로 취급 — "테스트 광고" 라벨이 뜨도록.
    if (kDebugMode) {
      MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: <String>[]),
      );
    }
    // ATT 상태 반영 — 앱 재실행마다 현재 상태를 다시 읽어 RequestConfiguration 갱신.
    await applyAdMobPrivacyConfig();
  } catch (e) {
    debugPrint('[ads] init failed: $e');
  }
}

/// ATT (iOS) 현재 상태에 맞춰 AdMob 의 개인화 광고 설정을 적용한다.
///
/// - iOS 14.5+ 에서 `authorized` 가 아니면 `nonPersonalizedAds = true`.
/// - iOS 14 미만 / Android 는 ATT 개념이 없어 non-personalized 로 유지하지 않는다
///   (Android 의 광고 개인화는 UMP/consent 로 별도 관리).
///
/// 온보딩 권한 화면에서 ATT 를 방금 요청 받은 직후에도 이 함수를 한번 더
/// 호출해서 새 상태를 즉시 반영한다.
Future<void> applyAdMobPrivacyConfig() async {
  try {
    if (!Platform.isIOS) return;
    final status =
        await AppTrackingTransparency.trackingAuthorizationStatus;
    final isAuthorized = status == TrackingStatus.authorized;
    // google_mobile_ads 5.x 는 RequestConfiguration 에 nonPersonalizedAds
    // 플래그가 없어서 `extras("npa","1")` 를 AdRequest 에 싣는 방식으로
    // 처리한다 (아래 [buildAdRequest] 참조).
    // 전역 config 갱신은 의도적으로 생략 — updateRequestConfiguration 을
    // 빈 인자로 호출하면 initAdMob 에서 설정한 testDeviceIds 가 지워진다.
    _npaFlag = !isAuthorized;
    debugPrint('[ads] ATT=$status → NPA=${_npaFlag ? "on" : "off"}');
  } catch (e) {
    debugPrint('[ads] applyAdMobPrivacyConfig failed: $e');
  }
}

/// ATT 거부 / 미정 / 비iOS 플랫폼에서 true — non-personalized 광고만 요청.
bool _npaFlag = true;

/// 모든 AdMob 광고 요청은 이 함수로 만들면 ATT 상태가 자동 반영돼.
AdRequest buildAdRequest() {
  return AdRequest(
    extras: _npaFlag ? const <String, String>{'npa': '1'} : null,
  );
}

/// 테스트 / 디버그 UI 에서 현재 플래그 확인용.
bool get isNonPersonalizedOnly => _npaFlag;
