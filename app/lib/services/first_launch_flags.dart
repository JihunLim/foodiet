/// 첫 실행 온보딩 상태 플래그.
///
/// 인증 상태(Supabase session)와 별개로, 디바이스에 남기는 "이 앱을 예전에
/// 열어봤는가" 표식. 로그아웃 후 재로그인 때는 인트로/권한을 다시 돌리지
/// 않도록 하기 위한 가드.
///
/// - [introCompleted]  — /onboarding/value 4장 카드 완료
/// - [permissionsCompleted] — /onboarding/permissions 단계 완료 (전부 허용일
///                            필요는 없음. "이 스크린을 지났다" 만 기록.)
///
/// 두 플래그는 독립적으로 기록되므로, 중간에 앱이 꺼져도 마지막 단계부터
/// 복귀한다. 필요 시 [reset] 로 테스트에서 초기화할 수 있다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirstLaunchFlags {
  FirstLaunchFlags._(this._prefs);

  static const _kIntro = 'onboarding_intro_v1';
  static const _kPermissions = 'onboarding_permissions_v1';

  final SharedPreferences _prefs;

  static Future<FirstLaunchFlags> load() async {
    final prefs = await SharedPreferences.getInstance();
    return FirstLaunchFlags._(prefs);
  }

  bool get introCompleted => _prefs.getBool(_kIntro) ?? false;
  bool get permissionsCompleted => _prefs.getBool(_kPermissions) ?? false;

  Future<void> markIntroCompleted() => _prefs.setBool(_kIntro, true);
  Future<void> markPermissionsCompleted() =>
      _prefs.setBool(_kPermissions, true);

  Future<void> reset() async {
    await _prefs.remove(_kIntro);
    await _prefs.remove(_kPermissions);
  }
}

/// 앱 부팅 시점에 한 번 로드해 두고 전역에서 읽는다.
/// `FutureProvider` 로 두면 splash 에서 `when` 으로 lock 해 쓸 수 있다.
final firstLaunchFlagsProvider = FutureProvider<FirstLaunchFlags>((ref) async {
  return FirstLaunchFlags.load();
});
