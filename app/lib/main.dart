/// foodiet 앱 엔트리포인트.
///
/// 기획안 §8 — Flutter + Supabase + Firebase + Riverpod + go_router.
library;

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_common/kakao_flutter_sdk_common.dart';

import 'config/env.dart';
import 'providers/fcm_provider.dart';
import 'providers/router_provider.dart';
import 'services/ads_service.dart';
import 'services/fcm_service.dart';
import 'services/home_widget_service.dart';
import 'services/meal_reminder_service.dart';
import 'supabase/client.dart';
import 'theme/foodiet_tokens.dart';

/// FCM 백그라운드 핸들러는 반드시 top-level · @pragma 로 선언해야 한다.
/// 별도 isolate 에서 실행되므로 앱 상태에 의존할 수 없다.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {/* 이미 초기화됐으면 무시 */}
  if (kDebugMode) {
    debugPrint('[fcm:bg] ${message.messageId} ${message.data}');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Env.load();
  await FoodietSupabase.init();

  // Kakao SDK — Native 키가 있을 때만 초기화. 없으면 Kakao 버튼은 숨김.
  final kakaoNative = Env.kakaoNativeAppKey;
  if (kakaoNative != null) {
    KakaoSdk.init(
      nativeAppKey: kakaoNative,
      javaScriptAppKey: Env.kakaoJsAppKey,
    );
  }

  // Firebase 는 플랫폼 config 파일(GoogleService-Info.plist / google-services.json)
  // 에서 자동 로드. Android 파일이 아직 없을 수 있으니 try/catch 로 감싼다.
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (e) {
    debugPrint('[foodiet] Firebase init skipped: $e');
  }

  // FCM 백그라운드 핸들러는 Firebase 초기화 뒤에 딱 한 번 등록.
  if (firebaseReady) {
    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
  }

  // AdMob — 네이티브 팩토리는 AppDelegate / MainActivity 에서 등록.
  await initAdMob();

  // 홈스크린 위젯용 App Group 을 부팅 시 먼저 set 해서, 이후 어디서
  // `HomeWidget.*` 가 호출돼도 native 채널이 ready 상태이도록 보장.
  // 이 호출이 없으면 iOS 에서 `widgetClicked` / `initiallyLaunchedFromHomeWidget`
  // 가 `PlatformException(-7, AppGroupId not set)` 을 던져 unhandled async
  // exception → 일부 케이스에서 후속 native crash (EXC_BAD_ACCESS) 까지 유발.
  await FoodietWidgetService.instance.ensureInit();

  // 끼니 리마인더 — flutter_local_notifications + tz 셋업.
  // 권한은 FCM 흐름이 이미 받아둠. 부팅 시 prefs 를 읽어 OS 스케줄과 동기화.
  await MealReminderService.instance.ensureInit();
  unawaited(MealReminderService.instance
      .loadPrefs()
      .then((p) => MealReminderService.instance.apply(p)));

  // FCM 서비스 — ProviderScope override 로 주입.
  final fcm = FcmService(
    FoodietSupabase.client,
    packageVersion: '1.0.0', // pubspec.yaml version 과 동기화.
  );

  runApp(
    ProviderScope(
      overrides: [
        fcmServiceProvider.overrideWithValue(fcm),
      ],
      child: FoodietApp(fcm: fcm),
    ),
  );
}

class FoodietApp extends ConsumerStatefulWidget {
  const FoodietApp({super.key, required this.fcm});
  final FcmService fcm;

  @override
  ConsumerState<FoodietApp> createState() => _FoodietAppState();
}

class _FoodietAppState extends ConsumerState<FoodietApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _fcmInited = false;

  @override
  void initState() {
    super.initState();
    // 홈스크린 위젯 탭 → 앱 내 라우팅. URI 스킴: foodiet://widget/<target>.
    FoodietWidgetService.instance.registerLaunchHandler((uri) {
      final router = ref.read(routerProvider);
      final target = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      switch (target) {
        case 'camera':
          router.go('/camera');
          break;
        case 'coach':
        case 'home':
          router.go('/home');
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // FCM 초기화 — 라우터가 생성된 이후 1회. auth 변화는 fcmLifecycleProvider 가 본다.
    if (!_fcmInited) {
      _fcmInited = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.fcm.init(router: router, messengerKey: _messengerKey);
        ref.read(fcmLifecycleProvider);
      });
    }

    return MaterialApp.router(
      title: 'foodiet',
      debugShowCheckedModeBanner: false,
      theme: buildFoodietTheme(),
      scaffoldMessengerKey: _messengerKey,
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      // iPad / 큰 화면 대응 — 핸드폰 폼팩터에 맞춰 만든 레이아웃이라
      // 넓은 화면에선 좌우가 너무 길어지는 문제가 있다. 화면 전체에
      // 레터박스를 씌워 최대 폭 540 으로 제한하고, 양쪽은 크림 배경.
      builder: (context, child) {
        // 글로벌 키보드 dismiss — 입력란 외부의 빈 영역을 탭하면 키보드가
        // 자동으로 내려간다. translucent 라서 자식(TextField 등)이 hit 인
        // 곳은 자식이 그대로 처리, 빈 곳만 이 탭 콜백이 잡는다.
        Widget wrapped = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child ?? const SizedBox(),
        );

        final width = MediaQuery.sizeOf(context).width;
        if (width <= 600 || child == null) return wrapped;
        return ColoredBox(
          color: FoodietColors.cream00,
          child: Center(
            child: SizedBox(
              width: 540,
              child: wrapped,
            ),
          ),
        );
      },
    );
  }
}
