/// go_router 설정 + 인증 가드.
///
/// 기획안 §5 / 부록 A — 19개 MVP 화면을 커버하도록 확장 가능한 트리.
/// 지금 단계에선 splash → onboarding → sign-in → survey → home(5탭) 스켈레톤.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/sign_in_page.dart';
import '../features/calendar/calendar_page.dart';
import '../features/camera/camera_page.dart';
import '../features/community/community_group_create_page.dart';
import '../features/community/community_group_detail_page.dart';
import '../features/community/community_group_invite_page.dart';
import '../features/community/community_group_join_page.dart';
import '../features/community/community_group_members_page.dart';
import '../features/community/community_my_invites_page.dart';
import '../features/community/community_group_settings_page.dart';
import '../features/community/community_page.dart';
import '../features/community/community_post_detail_page.dart';
import '../features/community/community_share_today_page.dart';
import '../features/entry/entry_detail_page.dart';
import '../features/home/home_shell.dart';
import '../features/home/home_today_page.dart';
import '../features/insight/insight_page.dart';
import '../features/onboarding/onboarding_permissions_page.dart';
import '../features/onboarding/onboarding_survey_page.dart';
import '../features/onboarding/onboarding_value_page.dart';
import '../features/profile/nickname_edit_page.dart';
import '../features/profile/profile_page.dart';
import '../features/profile/profile_edit_page.dart';
import '../features/splash/splash_page.dart';
import 'auth_provider.dart';
import 'profile_provider.dart';

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(profileProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthListenable(ref);
  ref.onDispose(listenable.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: listenable,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      final user = ref.read(currentUserProvider);
      final authed = user != null;
      final loc = state.matchedLocation;

      // Splash 는 자체적으로 분기. redirect 가 끼어들지 않는다.
      if (loc == '/') return null;

      const publicOnboarding = [
        '/onboarding/value',
        '/onboarding/permissions',
        '/sign-in',
      ];

      if (!authed) {
        if (publicOnboarding.contains(loc)) return null;
        return '/sign-in';
      }

      // 로그인됐지만 profiles row 가 없으면 → 온보딩 설문으로.
      final profileAsync = ref.read(profileProvider);
      final needsSurvey =
          profileAsync.hasValue && profileAsync.value == null;
      if (needsSurvey && loc != '/onboarding/survey') {
        return '/onboarding/survey';
      }

      // authed 상태에서 onboarding/sign-in 에 머물면 홈으로.
      if (publicOnboarding.contains(loc)) return '/home';

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashPage()),
      GoRoute(
        path: '/onboarding/value',
        builder: (_, __) => const OnboardingValuePage(),
      ),
      GoRoute(
        path: '/onboarding/permissions',
        builder: (_, __) => const OnboardingPermissionsPage(),
      ),
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInPage()),
      GoRoute(
        path: '/onboarding/survey',
        builder: (_, __) => const OnboardingSurveyPage(),
      ),
      GoRoute(path: '/camera', builder: (_, __) => const CameraPage()),
      GoRoute(
        path: '/entry/:id',
        builder: (_, state) =>
            EntryDetailPage(entryId: state.pathParameters['id']!),
      ),

      // 마이(프로필)는 홈 AppBar 아이콘에서 진입 — top-level 라우트로 분리.
      GoRoute(
        path: '/profile',
        builder: (_, __) => const ProfilePage(),
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (_, __) => const ProfileEditPage(),
      ),
      GoRoute(
        path: '/profile/nickname',
        builder: (_, __) => const NicknameEditPage(),
      ),

      // 커뮤니티 서브 화면들 (모두 top-level — 탭 전환과 무관하게 push).
      GoRoute(
        path: '/community/new',
        builder: (_, __) => const CommunityGroupCreatePage(),
      ),
      GoRoute(
        path: '/community/join',
        builder: (_, __) => const CommunityGroupJoinPage(),
      ),
      GoRoute(
        path: '/community/share-today',
        builder: (_, __) => const CommunityShareTodayPage(),
      ),
      GoRoute(
        path: '/community/group/:id',
        builder: (_, state) =>
            CommunityGroupDetailPage(groupId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/community/group/:id/settings',
        builder: (_, state) =>
            CommunityGroupSettingsPage(groupId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/community/group/:id/members',
        builder: (_, state) =>
            CommunityGroupMembersPage(groupId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/community/group/:id/invite',
        builder: (_, state) =>
            CommunityGroupInvitePage(groupId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/profile/invites',
        builder: (_, __) => const CommunityMyInvitesPage(),
      ),
      GoRoute(
        path: '/community/group/:gid/post/:pid',
        builder: (_, state) => CommunityPostDetailPage(
          groupId: state.pathParameters['gid']!,
          postId: state.pathParameters['pid']!,
        ),
      ),

      // 5-탭 Shell (홈 / 기록 / 인사이트 / 커뮤니티 — FAB=카메라는 별도)
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (_, __) => const HomeTodayPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/calendar', builder: (_, __) => const CalendarPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/insight', builder: (_, __) => const InsightPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/community',
              builder: (_, __) => const CommunityPage(),
            ),
          ]),
        ],
      ),
    ],
  );
});
