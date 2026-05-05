/// Onboarding — 시스템 권한 요청.
///
/// 가치 카드(4장) 다음 단계. 각 카드의 "허용하기" 버튼이 실제 iOS 시스템
/// 다이얼로그를 띄운다. 이미 영구 거부된 권한은 "설정에서 허용하기" 로
/// 바뀌며 [openAppSettings] 로 설정 앱 해당 섹션으로 딥링크.
///
/// - 카메라 / 사진 / 알림 / (iOS) 광고 추적 4종.
/// - 모든 권한은 "선택" 이다. 사용자가 계속하기를 누르면 바로 sign-in 으로.
///   앱의 정책: 거부한 권한은 해당 기능 사용 시점에 재요청 + 설정 안내.
///
/// 라이프사이클:
/// - [didChangeAppLifecycleState] 로 resume 감지 → 설정 앱에서 돌아왔을 때
///   현재 상태를 다시 읽어 UI 갱신.
library;

import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/ads_service.dart';
import '../../services/first_launch_flags.dart';
import '../../services/meal_reminder_service.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/primary_button.dart';

/// 권한 상태의 간단한 3-way 추상화.
/// permission_handler 와 AppTrackingTransparency 가 서로 다른 enum 을
/// 쓰기 때문에 UI 에서는 이걸로 통일.
enum _PermUi { notDetermined, granted, denied, permanentlyDenied }

_PermUi _fromStatus(PermissionStatus s) {
  if (s.isGranted || s.isLimited) return _PermUi.granted;
  if (s.isPermanentlyDenied || s.isRestricted) {
    return _PermUi.permanentlyDenied;
  }
  if (s.isDenied) {
    // iOS permission_handler 는 "아직 안 물어봄(notDetermined)" 을
    // PermissionStatus.denied 로 매핑한다 (사용자가 실제 거부한 상태는
    // permanentlyDenied 로 별도 매핑됨). 그대로 denied 로 처리하면
    // 첫 실행부터 모든 카드가 "다시 시도" 로 나와버려 혼란스러우므로
    // iOS 에선 denied == notDetermined 로 간주해 "허용하기" 를 노출.
    // Android 는 denied == 사용자가 거부(재요청 가능) 의미라 그대로 둔다.
    return Platform.isIOS ? _PermUi.notDetermined : _PermUi.denied;
  }
  return _PermUi.notDetermined;
}

_PermUi _fromAtt(TrackingStatus s) {
  switch (s) {
    case TrackingStatus.authorized:
      return _PermUi.granted;
    case TrackingStatus.denied:
      return _PermUi.denied;
    case TrackingStatus.restricted:
      return _PermUi.permanentlyDenied;
    case TrackingStatus.notDetermined:
      return _PermUi.notDetermined;
    case TrackingStatus.notSupported:
      return _PermUi.granted; // 비iOS 에선 해당 카드 자체를 숨김.
  }
}

class OnboardingPermissionsPage extends ConsumerStatefulWidget {
  const OnboardingPermissionsPage({super.key});

  @override
  ConsumerState<OnboardingPermissionsPage> createState() =>
      _OnboardingPermissionsPageState();
}

/// 권한 키 — `_everGranted` 추적용. 문자열 상수 오타 위험 제거.
class _K {
  static const camera = 'camera';
  static const photos = 'photos';
  static const notif = 'notif';
  static const att = 'att';
}

class _OnboardingPermissionsPageState
    extends ConsumerState<OnboardingPermissionsPage>
    with WidgetsBindingObserver {
  _PermUi _cameraUi = _PermUi.notDetermined;
  _PermUi _photosUi = _PermUi.notDetermined;
  _PermUi _notifUi = _PermUi.notDetermined;
  _PermUi _attUi = _PermUi.notDetermined;

  /// "이 세션에서 한 번이라도 granted 로 관찰된" 권한들의 key.
  /// 현재 _PermUi 상태와 무관하게 UI 는 이 Set 을 믿는다. 어떤 async 레이스로
  /// state 가 잠시 오염되어도 뒤집히지 않도록 하는 핵심 방어선.
  final Set<String> _everGranted = <String>{};

  /// 설정 앱으로 보낸 상태인지. `didChangeAppLifecycleState(resumed)` 에서
  /// 이 값이 true 일 때만 `_refreshAll()` 을 호출해 상태를 재동기화한다.
  /// ATT 다이얼로그나 시스템 권한 다이얼로그로 인한 inactive/resumed 에는
  /// 리프레시하지 않아 UI 가 오염되지 않는다.
  bool _settingsRequested = false;

  bool get _isIOS => Platform.isIOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // ❗ 자동 리프레시 금지. ATT/권한 다이얼로그가 resumed 이벤트를 트리거하고,
    // 그 타이밍에 iOS permission_handler 가 일시적 .denied 를 돌려주는 경우
    // 이미 granted 된 카드가 "허용하기" 로 회귀 보이는 버그의 주원인.
    // 설정 앱으로 보낸 케이스 (`_settingsRequested`) 에서만 예외적으로 리프레시.
    if (state == AppLifecycleState.resumed && _settingsRequested) {
      _settingsRequested = false;
      _refreshAll();
    }
  }

  /// 순수 리듀서 — "한 번이라도 granted 였으면 granted, 아니면 next".
  /// static 하고 부작용 없어 unit test 에서 그대로 검증 가능.
  static _PermUi decide({
    required String key,
    required _PermUi next,
    required Set<String> everGranted,
  }) {
    if (everGranted.contains(key)) return _PermUi.granted;
    return next;
  }

  /// PermissionStatus 가 granted 카운트인지 판별.
  static bool _statusGranted(PermissionStatus s) => s.isGranted || s.isLimited;

  Future<void> _refreshAll() async {
    final cam = await Permission.camera.status;
    final photos = await Permission.photos.status;
    final notif = await Permission.notification.status;
    TrackingStatus att = TrackingStatus.notSupported;
    if (_isIOS) {
      att = await AppTrackingTransparency.trackingAuthorizationStatus;
    }
    if (!mounted) return;
    // 관찰된 granted 는 영구 기록.
    if (_statusGranted(cam)) _everGranted.add(_K.camera);
    if (_statusGranted(photos)) _everGranted.add(_K.photos);
    if (_statusGranted(notif)) _everGranted.add(_K.notif);
    if (att == TrackingStatus.authorized) _everGranted.add(_K.att);
    setState(() {
      _cameraUi = decide(
          key: _K.camera, next: _fromStatus(cam), everGranted: _everGranted);
      _photosUi = decide(
          key: _K.photos, next: _fromStatus(photos), everGranted: _everGranted);
      _notifUi = decide(
          key: _K.notif, next: _fromStatus(notif), everGranted: _everGranted);
      _attUi = decide(
          key: _K.att, next: _fromAtt(att), everGranted: _everGranted);
    });
  }

  Future<void> _requestCamera() async {
    final s = await Permission.camera.request();
    if (!mounted) return;
    if (_statusGranted(s)) _everGranted.add(_K.camera);
    setState(() => _cameraUi = decide(
        key: _K.camera, next: _fromStatus(s), everGranted: _everGranted));
  }

  Future<void> _requestPhotos() async {
    final s = await Permission.photos.request();
    if (!mounted) return;
    if (_statusGranted(s)) _everGranted.add(_K.photos);
    setState(() => _photosUi = decide(
        key: _K.photos, next: _fromStatus(s), everGranted: _everGranted));
  }

  Future<void> _requestNotif() async {
    final s = await Permission.notification.request();
    if (!mounted) return;
    if (_statusGranted(s)) {
      _everGranted.add(_K.notif);
      // 권한이 막 떨어진 직후 끼니 리마인더 스케줄을 한 번 갱신해서, 부팅 시
      // 권한 없이 등록됐던 스케줄이 곧바로 활성화되도록 재적용.
      // ignore: discarded_futures
      MealReminderService.instance
          .loadPrefs()
          .then((p) => MealReminderService.instance.apply(p));
    }
    setState(() => _notifUi = decide(
        key: _K.notif, next: _fromStatus(s), everGranted: _everGranted));
  }

  Future<void> _requestAtt() async {
    if (!_isIOS) return;
    final s = await AppTrackingTransparency.requestTrackingAuthorization();
    // ATT 결과를 즉시 AdMob 개인화 설정에 반영.
    await applyAdMobPrivacyConfig();
    if (!mounted) return;
    if (s == TrackingStatus.authorized) _everGranted.add(_K.att);
    setState(() => _attUi = decide(
        key: _K.att, next: _fromAtt(s), everGranted: _everGranted));
  }

  /// 화면 상단 "모두 허용" — granted 가 아닌 카드들을 순차 요청.
  /// iOS 는 각 권한 다이얼로그가 차례로 뜨며, 사용자가 하나라도 거부해도
  /// 다음으로 계속 진행한다.
  bool _allowingAll = false;

  /// 직전 시스템 다이얼로그가 dismiss 된 직후엔 앱이 잠시 inactive 상태에 머문다.
  /// 그 사이에 다음 권한을 요청하면:
  ///   - 일반 권한(permission_handler): 보통 큐잉되어 잘 뜨지만 가끔 무시됨.
  ///   - ATT(`requestTrackingAuthorization`): inactive 면 다이얼로그가 silent
  ///     drop 되고 즉시 `notDetermined` 를 돌려준다 — 사용자가 본 그 증상.
  /// resumed 가 될 때까지 짧게 polling 한 뒤 안전 마진까지 더해 다음 요청을 던진다.
  Future<void> _waitForActive() async {
    for (int i = 0; i < 30; i++) {
      if (WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    // ATT 는 lifecycleState 가 resumed 이어도 곧바로 호출하면 무시되는 경우가
    // 있어 추가 buffer.
    await Future.delayed(const Duration(milliseconds: 400));
  }

  Future<void> _requestAll() async {
    if (_allowingAll) return;
    setState(() => _allowingAll = true);
    try {
      if (_cameraUi != _PermUi.granted) {
        await _requestCamera();
        await _waitForActive();
      }
      if (_photosUi != _PermUi.granted) {
        await _requestPhotos();
        await _waitForActive();
      }
      if (_notifUi != _PermUi.granted) {
        await _requestNotif();
        await _waitForActive();
      }
      if (_isIOS && _attUi != _PermUi.granted) {
        await _requestAtt();
      }
    } finally {
      if (mounted) setState(() => _allowingAll = false);
    }
  }

  bool get _allGranted =>
      _everGranted.contains(_K.camera) &&
      _everGranted.contains(_K.photos) &&
      _everGranted.contains(_K.notif) &&
      (!_isIOS || _everGranted.contains(_K.att));

  /// 설정 앱으로 딥링크. resume 시 `_refreshAll` 이 실행되도록 플래그를 세운다.
  Future<void> _openSettings() async {
    _settingsRequested = true;
    await openAppSettings();
  }

  Future<void> _onContinue() async {
    final flags = await ref.read(firstLaunchFlagsProvider.future);
    await flags.markPermissionsCompleted();
    if (!mounted) return;
    context.go('/sign-in');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: FoodietShape.sp20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: FoodietShape.sp16),
                  Text(
                    '앱 사용 전에,\n몇 가지만 허용해줄래?',
                    style: FoodietText.h1.copyWith(
                      color: FoodietColors.warm900,
                    ),
                  ),
                  const SizedBox(height: FoodietShape.sp8),
                  Text(
                    '각 항목의 "허용하기" 를 누르면 시스템 창이 떠. '
                    '거부해도 앱은 쓸 수 있고, 나중에 설정에서 언제든 바꿀 수 있어.',
                    style: FoodietText.bodySm.copyWith(
                      color: FoodietColors.warm500,
                    ),
                  ),
                  const SizedBox(height: FoodietShape.sp24),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _PermCard(
                          emoji: '📷',
                          tint: FoodietColors.coral50,
                          accent: FoodietColors.coral500,
                          title: '카메라',
                          desc: '식사 사진을 찍어 AI 가 칼로리·영양을 분석해.',
                          state: _cameraUi,
                          onRequest: _requestCamera,
                          onOpenSettings: _openSettings,
                          required: true,
                        ),
                        const SizedBox(height: FoodietShape.sp12),
                        _PermCard(
                          emoji: '🖼️',
                          tint: FoodietColors.leaf100,
                          accent: FoodietColors.leaf700,
                          title: '사진',
                          desc: '갤러리의 기존 사진으로도 기록할 수 있어.',
                          state: _photosUi,
                          onRequest: _requestPhotos,
                          onOpenSettings: _openSettings,
                          required: true,
                        ),
                        const SizedBox(height: FoodietShape.sp12),
                        _PermCard(
                          emoji: '🔔',
                          tint: FoodietColors.cream50,
                          accent: FoodietColors.mealDinner,
                          title: '알림',
                          desc: '분석 완료, 목표 리마인더, 코치 피드백을 보내줄게.',
                          state: _notifUi,
                          onRequest: _requestNotif,
                          onOpenSettings: _openSettings,
                          required: false,
                        ),
                        if (_isIOS) ...[
                          const SizedBox(height: FoodietShape.sp12),
                          _PermCard(
                            emoji: '🎯',
                            tint: FoodietColors.coral100,
                            accent: FoodietColors.coral700,
                            title: '광고 개인화 (선택)',
                            desc: '너에게 맞는 광고를 보여주기 위해 필요해. '
                                '거부해도 앱 기능은 그대로 다 써.',
                            state: _attUi,
                            onRequest: _requestAtt,
                            onOpenSettings: _openSettings,
                            required: false,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: FoodietShape.sp16),
                  // 전체 권한 한 번에 요청 — iOS 시스템 다이얼로그가 순차로 뜸.
                  // "계속하기" 바로 위에 ghost(outline) 스타일로 배치해 CTA 와 구분.
                  _AllowAllButton(
                    allGranted: _allGranted,
                    busy: _allowingAll,
                    onTap: _requestAll,
                  ),
                  const SizedBox(height: FoodietShape.sp8),
                  PrimaryButton(
                    label: '계속하기',
                    onPressed: _onContinue,
                  ),
                  const SizedBox(height: FoodietShape.sp24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermCard extends StatelessWidget {
  const _PermCard({
    required this.emoji,
    required this.tint,
    required this.accent,
    required this.title,
    required this.desc,
    required this.state,
    required this.onRequest,
    required this.onOpenSettings,
    required this.required,
  });

  final String emoji;
  final Color tint;
  final Color accent;
  final String title;
  final String desc;
  final _PermUi state;
  final Future<void> Function() onRequest;
  final Future<void> Function() onOpenSettings;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final granted = state == _PermUi.granted;
    final permanentlyDenied = state == _PermUi.permanentlyDenied;
    final denied = state == _PermUi.denied;

    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp16),
      decoration: BoxDecoration(
        color: FoodietColors.cream00,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(
          color: granted ? accent.withValues(alpha: 0.3) : FoodietColors.cream100,
          width: granted ? 1.5 : 1,
        ),
        boxShadow: FoodietShape.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint,
                  shape: BoxShape.circle,
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: FoodietShape.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: FoodietText.title.copyWith(
                              color: FoodietColors.warm900,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (required) ...[
                          const SizedBox(width: 6),
                          Text(
                            '필수',
                            style: FoodietText.caption.copyWith(
                              color: FoodietColors.coral500,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      style: FoodietText.bodySm.copyWith(
                        color: FoodietColors.warm500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FoodietShape.sp8),
              if (granted)
                const Icon(
                  Icons.check_circle_rounded,
                  color: FoodietColors.leaf700,
                  size: 26,
                ),
            ],
          ),
          const SizedBox(height: FoodietShape.sp12),
          _ActionButton(
            granted: granted,
            denied: denied,
            permanentlyDenied: permanentlyDenied,
            accent: accent,
            onRequest: onRequest,
            onOpenSettings: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.granted,
    required this.denied,
    required this.permanentlyDenied,
    required this.accent,
    required this.onRequest,
    required this.onOpenSettings,
  });

  final bool granted;
  final bool denied;
  final bool permanentlyDenied;
  final Color accent;
  final Future<void> Function() onRequest;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (granted) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: FoodietColors.leaf100,
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        ),
        child: Text(
          '✓ 허용됨',
          style: FoodietText.bodySm.copyWith(
            color: FoodietColors.leaf700,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    if (permanentlyDenied) {
      return InkWell(
        onTap: () async {
          await onOpenSettings();
        },
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: FoodietColors.cream50,
            borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
            border: Border.all(color: FoodietColors.cream100),
          ),
          child: Text(
            '설정에서 허용하기 →',
            style: FoodietText.bodySm.copyWith(
              color: FoodietColors.warm700,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    final label = denied ? '다시 시도' : '허용하기';
    return InkWell(
      onTap: () async {
        await onRequest();
      },
      borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        ),
        child: Text(
          label,
          style: FoodietText.bodySm.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// 상단 "모두 허용" 버튼. 이미 전부 granted 면 "✓ 모두 허용됨" 표시로 변함.
class _AllowAllButton extends StatelessWidget {
  const _AllowAllButton({
    required this.allGranted,
    required this.busy,
    required this.onTap,
  });

  final bool allGranted;
  final bool busy;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    if (allGranted) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: FoodietColors.leaf100,
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
          border: Border.all(color: FoodietColors.leaf500.withValues(alpha: 0.3)),
        ),
        child: Text(
          '✓ 모두 허용됨',
          style: FoodietText.body.copyWith(
            color: FoodietColors.leaf700,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    // Ghost(outline) 스타일 — 아래 "계속하기" (coral CTA) 와 시각 구분.
    return InkWell(
      onTap: busy ? null : () async {
        await onTap();
      },
      borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: FoodietColors.cream50,
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
          border: Border.all(color: FoodietColors.leaf500, width: 1.5),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: FoodietColors.leaf700,
                ),
              )
            : Text(
                '한 번에 모두 허용하기',
                style: FoodietText.body.copyWith(
                  color: FoodietColors.leaf700,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
