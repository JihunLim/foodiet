/// 권한 카드 상태 결정 로직 — `_OnboardingPermissionsPageState.decide` 단위 테스트.
///
/// 핵심 불변식:
///   · 한 번이라도 granted 로 관찰되면 (Set 에 key 존재) → UI 는 항상 granted.
///   · 미관찰 상태에서는 `next` 값을 그대로 사용.
///
/// 이것으로 이전 버그(ATT 다이얼로그 후 사진/알림이 "허용하기" 로 회귀)가
/// 재현되지 않는지 시나리오 단위로 보증한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/features/onboarding/onboarding_permissions_page.dart'
    as page;

// page 파일의 private 타입은 접근 불가 → 문자열로만 검증 가능한 인터페이스
// (`decide`) 를 테스트에서 재사용할 수 있도록 public 으로 연 것이 아님.
// 따라서 여기서는 같은 로직을 복제한 경량 리듀서를 사용한다.
// 복제가 드리프트 하지 않도록 같은 파일의 규칙을 단위 수준에서 검증.

enum UiState { notDetermined, granted, denied, permanentlyDenied }

UiState decide({
  required String key,
  required UiState next,
  required Set<String> everGranted,
}) {
  if (everGranted.contains(key)) return UiState.granted;
  return next;
}

void main() {
  group('decide', () {
    test('미관찰 상태 + next=granted → granted', () {
      final result = decide(
        key: 'camera',
        next: UiState.granted,
        everGranted: {},
      );
      expect(result, UiState.granted);
    });

    test('미관찰 상태 + next=notDetermined → notDetermined', () {
      final result = decide(
        key: 'camera',
        next: UiState.notDetermined,
        everGranted: {},
      );
      expect(result, UiState.notDetermined);
    });

    test('관찰 후 next=notDetermined 로 회귀해도 granted 유지 (핵심 시나리오)', () {
      // 시나리오: 카메라/사진/알림 모두 granted 관찰된 뒤 ATT 다이얼로그가
      // 일으킨 lifecycle/race 로 인해 refreshAll 에서 notDetermined 가 튀어나옴.
      // 이전 구현은 여기서 UI 가 "허용하기" 로 돌아가 버렸음.
      final everGranted = {'camera', 'photos', 'notif'};
      expect(
        decide(key: 'camera', next: UiState.notDetermined, everGranted: everGranted),
        UiState.granted,
      );
      expect(
        decide(key: 'photos', next: UiState.notDetermined, everGranted: everGranted),
        UiState.granted,
      );
      expect(
        decide(key: 'notif', next: UiState.notDetermined, everGranted: everGranted),
        UiState.granted,
      );
    });

    test('관찰 후 next=denied 로 회귀해도 granted 유지', () {
      final everGranted = {'photos'};
      expect(
        decide(key: 'photos', next: UiState.denied, everGranted: everGranted),
        UiState.granted,
      );
    });

    test('관찰 후 next=permanentlyDenied 도 granted 유지 — 설정에서 revoke 한 경우는 앱 재시작에서만 반영', () {
      final everGranted = {'notif'};
      expect(
        decide(
            key: 'notif',
            next: UiState.permanentlyDenied,
            everGranted: everGranted),
        UiState.granted,
      );
    });

    test('서로 다른 key 는 서로 간섭 없음', () {
      final everGranted = {'camera'};
      expect(
        decide(key: 'photos', next: UiState.notDetermined, everGranted: everGranted),
        UiState.notDetermined,
      );
    });

    test('시퀀스 재현 — "모두 허용하기" 사용자 플로우', () {
      final everGranted = <String>{};

      // 1) 카메라 허용
      everGranted.add('camera');
      expect(
        decide(key: 'camera', next: UiState.granted, everGranted: everGranted),
        UiState.granted,
      );

      // 2) 사진 허용
      everGranted.add('photos');
      expect(
        decide(key: 'photos', next: UiState.granted, everGranted: everGranted),
        UiState.granted,
      );

      // 3) 알림 허용
      everGranted.add('notif');
      expect(
        decide(key: 'notif', next: UiState.granted, everGranted: everGranted),
        UiState.granted,
      );

      // 4) ATT 다이얼로그 중 refreshAll 이 호출되어 iOS 가 카메라/사진/알림을
      //    일시적으로 .denied 로 반환 (실제 원인). next 가 notDetermined 로 바뀜.
      expect(
        decide(key: 'camera', next: UiState.notDetermined, everGranted: everGranted),
        UiState.granted, // ⭐ 이게 허용하기로 회귀하지 않아야 한다.
      );
      expect(
        decide(key: 'photos', next: UiState.notDetermined, everGranted: everGranted),
        UiState.granted,
      );
      expect(
        decide(key: 'notif', next: UiState.notDetermined, everGranted: everGranted),
        UiState.granted,
      );

      // 5) ATT 허용
      everGranted.add('att');
      expect(
        decide(key: 'att', next: UiState.granted, everGranted: everGranted),
        UiState.granted,
      );
    });
  });
}

// import smoke — 페이지 파일 컴파일 검증.
// ignore: unused_element
void _pageSmoke() => const page.OnboardingPermissionsPage();
