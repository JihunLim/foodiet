import Flutter
import UIKit
import GoogleMobileAds
import google_mobile_ads
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // FirebaseAppDelegateProxyEnabled = false 인 상태에서 APNs 등록을 직접 트리거.
    // - UNUserNotificationCenter delegate 를 잡아 foreground/탭 콜백을 받게 한다
    //   (FlutterAppDelegate 가 UNUserNotificationCenterDelegate 를 채택하고 있으므로 self 를 그대로 사용).
    // - registerForRemoteNotifications 를 부르면 권한이 이미 부여된 경우 즉시
    //   APNs token 이 발급되어 didRegisterForRemoteNotificationsWithDeviceToken 콜백이
    //   호출되고, Messaging 에 apnsToken 이 주입돼 FCM token 이 발급된다.
    //   권한 미부여 상태면 아무 일도 일어나지 않으며, 추후 권한 부여 후 다음 launch
    //   에서 자동으로 발급된다.
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // FirebaseAppDelegateProxyEnabled = false 상태 (google_sign_in 호환).
  // 이 경우 APNs 토큰을 Firebase Messaging 에 수동 포워딩해야 FCM 토큰이 발급된다.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // 시뮬레이터·권한 미부여 등으로 등록 실패. log 만 찍고 silent fail.
    NSLog("[fcm] APNs registration failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  /// 앱이 foreground 인 동안 도착한 알림을 어떻게 표시할지 결정.
  ///
  /// 기본 iOS 동작은 foreground 면 banner 숨김 (사용자가 앱을 사용 중이라
  /// 가정). 우리 앱은 항상 banner + sound + badge + list 를 띄우고 싶으므로
  /// 명시적으로 모든 옵션을 컴플리션 핸들러에 전달.
  ///
  /// `FirebaseAppDelegateProxyEnabled=false` 인 상태이므로 Flutter 플러그인의
  /// `setForegroundNotificationPresentationOptions(alert:true)` 만으로는
  /// 동작하지 않음 — 이 메서드를 직접 구현해야 한다.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // AdMob 네이티브 고급형 광고 팩토리 등록 — Dart 의 factoryId 와 동일해야 함.
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      engineBridge.pluginRegistry,
      factoryId: "foodietNativeCard",
      nativeAdFactory: FoodietNativeAdFactory())
  }
}

// MARK: - FoodietNativeAdFactory
//
// AdMob 네이티브 고급형 광고의 iOS 렌더러.
// policy: "광고" 라벨 + headline + CTA 버튼. foodiet 디자인 토큰 유지.
// 별도 파일로 빼면 Xcode 프로젝트 등록이 필요해지므로 AppDelegate 에 동봉.
//
class FoodietNativeAdFactory: NSObject, FLTNativeAdFactory {

  func createNativeAd(_ nativeAd: GADNativeAd,
                      customOptions: [AnyHashable: Any]? = nil) -> GADNativeAdView? {
    let adView = GADNativeAdView(frame: .zero)
    // 루트 뷰는 Flutter platform-view 컨테이너가 frame 으로 크기를 지정하므로
    // 기본 autoresizing mask 를 유지해야 한다. `translatesAutoresizingMaskIntoConstraints = false`
    // 로 바꾸면 크기 제약이 없어 뷰가 intrinsic 컨텐츠 크기만큼 확장돼
    // 오른쪽이 화면 밖으로 튀어나간다.
    adView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    adView.clipsToBounds = true

    // design-system/colors_and_type.css 토큰 미러.
    let cream50  = UIColor(red: 0.984, green: 0.965, blue: 0.937, alpha: 1.0)
    let cream100 = UIColor(red: 0.957, green: 0.929, blue: 0.886, alpha: 1.0)
    let coral500 = UIColor(red: 1.000, green: 0.541, blue: 0.357, alpha: 1.0)
    let coral100 = UIColor(red: 1.000, green: 0.894, blue: 0.820, alpha: 1.0)
    let warm500  = UIColor(red: 0.420, green: 0.392, blue: 0.329, alpha: 1.0)
    let warm700  = UIColor(red: 0.243, green: 0.227, blue: 0.192, alpha: 1.0)
    let warm900  = UIColor(red: 0.133, green: 0.122, blue: 0.102, alpha: 1.0)

    adView.backgroundColor = cream50
    adView.layer.cornerRadius = 20
    adView.layer.borderWidth = 1
    adView.layer.borderColor = cream100.cgColor

    // "광고" 라벨 (policy 요구).
    let attributionLabel = UILabel()
    attributionLabel.text = "광고"
    attributionLabel.font = UIFont.systemFont(ofSize: 10, weight: .bold)
    attributionLabel.textColor = coral500
    attributionLabel.backgroundColor = coral100
    attributionLabel.textAlignment = .center
    attributionLabel.layer.cornerRadius = 4
    attributionLabel.clipsToBounds = true
    attributionLabel.translatesAutoresizingMaskIntoConstraints = false

    let headlineView = UILabel()
    headlineView.font = UIFont.systemFont(ofSize: 15, weight: .bold)
    headlineView.textColor = warm900
    headlineView.numberOfLines = 2
    headlineView.lineBreakMode = .byTruncatingTail
    headlineView.adjustsFontSizeToFitWidth = false
    headlineView.translatesAutoresizingMaskIntoConstraints = false
    // 긴 광고 텍스트가 trailing constraint 을 이기지 않도록 compression
    // resistance 를 낮춤 (기본 750).
    headlineView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    headlineView.setContentHuggingPriority(.defaultLow, for: .horizontal)
    adView.headlineView = headlineView

    let bodyView = UILabel()
    bodyView.font = UIFont.systemFont(ofSize: 12)
    bodyView.textColor = warm500
    bodyView.numberOfLines = 2
    bodyView.lineBreakMode = .byTruncatingTail
    bodyView.adjustsFontSizeToFitWidth = false
    bodyView.translatesAutoresizingMaskIntoConstraints = false
    bodyView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    bodyView.setContentHuggingPriority(.defaultLow, for: .horizontal)
    adView.bodyView = bodyView

    // AdMob policy: 앱 설치/브랜드 광고는 MediaView 로 메인 이미지·비디오를
    // 표시해야 한다. UIImageView 단독 사용은 정책 위반 및 일부 광고 렌더 실패.
    let mediaView = GADMediaView()
    mediaView.contentMode = .scaleAspectFill
    mediaView.clipsToBounds = true
    mediaView.layer.cornerRadius = 8
    mediaView.translatesAutoresizingMaskIntoConstraints = false
    adView.mediaView = mediaView

    // 아이콘은 여전히 headline 옆의 작은 썸네일로 유지 (선택사항, nil 허용).
    let iconView = UIImageView()
    iconView.contentMode = .scaleAspectFill
    iconView.clipsToBounds = true
    iconView.layer.cornerRadius = 6
    iconView.translatesAutoresizingMaskIntoConstraints = false
    adView.iconView = iconView

    let advertiserView = UILabel()
    advertiserView.font = UIFont.systemFont(ofSize: 11)
    advertiserView.textColor = warm700
    advertiserView.lineBreakMode = .byTruncatingTail
    advertiserView.translatesAutoresizingMaskIntoConstraints = false
    advertiserView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    advertiserView.setContentHuggingPriority(.defaultLow, for: .horizontal)
    adView.advertiserView = advertiserView

    let callToActionView = UIButton(type: .system)
    callToActionView.backgroundColor = coral500
    callToActionView.setTitleColor(.white, for: .normal)
    callToActionView.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .bold)
    callToActionView.layer.cornerRadius = 10
    callToActionView.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
    // GADNativeAdView 가 클릭을 가로채도록 view 자체 인터랙션은 off.
    callToActionView.isUserInteractionEnabled = false
    callToActionView.translatesAutoresizingMaskIntoConstraints = false
    callToActionView.setContentCompressionResistancePriority(.required, for: .horizontal)
    callToActionView.setContentHuggingPriority(.required, for: .horizontal)
    adView.callToActionView = callToActionView

    [attributionLabel, mediaView, iconView, headlineView, bodyView, advertiserView, callToActionView]
      .forEach { adView.addSubview($0) }

    NSLayoutConstraint.activate([
      attributionLabel.topAnchor.constraint(equalTo: adView.topAnchor, constant: 10),
      attributionLabel.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 14),
      attributionLabel.widthAnchor.constraint(equalToConstant: 32),
      attributionLabel.heightAnchor.constraint(equalToConstant: 16),

      // MediaView — 좌측 56×56. AdMob native advanced 는 MediaView 필수.
      mediaView.topAnchor.constraint(equalTo: attributionLabel.bottomAnchor, constant: 10),
      mediaView.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 14),
      mediaView.widthAnchor.constraint(equalToConstant: 56),
      mediaView.heightAnchor.constraint(equalToConstant: 56),

      // iconView 는 숨김이지만 SDK 가 기대하므로 0 크기 placeholder 로 유지.
      iconView.topAnchor.constraint(equalTo: adView.topAnchor),
      iconView.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 0),
      iconView.heightAnchor.constraint(equalToConstant: 0),

      headlineView.topAnchor.constraint(equalTo: attributionLabel.bottomAnchor, constant: 6),
      headlineView.leadingAnchor.constraint(equalTo: mediaView.trailingAnchor, constant: 10),
      headlineView.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -14),

      bodyView.topAnchor.constraint(equalTo: headlineView.bottomAnchor, constant: 2),
      bodyView.leadingAnchor.constraint(equalTo: headlineView.leadingAnchor),
      bodyView.trailingAnchor.constraint(equalTo: headlineView.trailingAnchor),

      advertiserView.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 10),
      advertiserView.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 14),
      // CTA 버튼과 가로로 나란히 앉으므로 trailing 을 CTA 의 leading 에 묶음.
      advertiserView.trailingAnchor.constraint(
        lessThanOrEqualTo: callToActionView.leadingAnchor, constant: -8),

      callToActionView.centerYAnchor.constraint(equalTo: advertiserView.centerYAnchor),
      callToActionView.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -14),
      callToActionView.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor, constant: -10),
      // CTA 는 수축되지 않도록 compression resistance 높게.

    ])

    (adView.headlineView as? UILabel)?.text = nativeAd.headline
    (adView.bodyView as? UILabel)?.text = nativeAd.body
    (adView.bodyView as? UILabel)?.isHidden = (nativeAd.body == nil)
    (adView.advertiserView as? UILabel)?.text = nativeAd.advertiser
    (adView.advertiserView as? UILabel)?.isHidden = (nativeAd.advertiser == nil)
    (adView.callToActionView as? UIButton)?
      .setTitle(nativeAd.callToAction, for: .normal)
    // iconView 는 hidden placeholder. MediaContent 는 mediaView 가 자동 렌더.
    (adView.mediaView as? GADMediaView)?.mediaContent = nativeAd.mediaContent

    adView.nativeAd = nativeAd
    return adView
  }
}
