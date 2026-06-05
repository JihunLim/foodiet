/// 마이 — 목표/공유/알림/프라이버시/로그아웃.
///
/// 기획안 §6.
///
/// Phase F (MVP 완성도 개선):
///   - "목표·기한" → `/profile/edit` (편집 화면).
///   - "PT 공유" → 초대 문구를 클립보드에 복사 (간이 공유).
///   - "알림 설정" → 끼니 리마인더 (master + 아침/점심/저녁 별 ON·시각).
///       · `MealReminderService` 가 SharedPreferences 영속화 + OS 스케줄 동기화.
///   - "프라이버시 · 데이터" → 바텀시트
///       · 내 데이터 내보내기 (entries JSON 을 클립보드에 복사).
///       · 계정 삭제 (profiles + entries 하드 삭제 후 로그아웃).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/supabase_provider.dart';
import '../../services/daily_share_service.dart';
import '../../services/meal_reminder_service.dart';
import '../../supabase/client.dart';
import '../../theme/foodiet_tokens.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final inviteCount =
        ref.watch(myInvitesCountProvider).valueOrNull ?? 0;

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        title: Text('설정',
            style:
                FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FoodietShape.sp20),
          children: [
            _Header(
              nickname: profile?.nickname ?? '후니',
              targetKcal: profile?.dailyKcalTarget,
              goalWeightKg: profile?.goalWeightKg,
            ),
            const SizedBox(height: FoodietShape.sp24),

            // 계정 — 본인의 식별/목표 정보를 다루는 항목들.
            _MenuGroup(
              title: '계정',
              children: [
                _MenuItem(
                  icon: Icons.badge_outlined,
                  label: '닉네임 변경',
                  onTap: () => context.push('/profile/nickname'),
                ),
                _MenuItem(
                  icon: Icons.flag_outlined,
                  label: '프로필 · 목표 · 기한',
                  onTap: () => context.push('/profile/edit'),
                ),
              ],
            ),
            const SizedBox(height: FoodietShape.sp16),

            // 기록 — 즐겨찾기 등 빠른 기록 관리.
            _MenuGroup(
              title: '기록',
              children: [
                _MenuItem(
                  icon: Icons.star_outline_rounded,
                  label: '즐겨찾기 관리',
                  onTap: () => context.push('/favorites'),
                ),
              ],
            ),
            const SizedBox(height: FoodietShape.sp16),

            // 커뮤니티 — 그룹 관련 알림성 진입.
            _MenuGroup(
              title: '커뮤니티',
              children: [
                _MenuItem(
                  icon: Icons.mail_outline_rounded,
                  label: '그룹 초대장',
                  badgeCount: inviteCount,
                  onTap: () => context.push('/profile/invites'),
                ),
              ],
            ),
            const SizedBox(height: FoodietShape.sp16),

            // 알림 — 끼니 리마인더 등 푸시.
            _MenuGroup(
              title: '알림',
              children: [
                _MenuItem(
                  icon: Icons.notifications_none_rounded,
                  label: '알림 설정',
                  onTap: () => _openNotificationSheet(context),
                ),
              ],
            ),
            const SizedBox(height: FoodietShape.sp16),

            // 공유 — 외부로 나가는 액션.
            _MenuGroup(
              title: '공유',
              children: [
                _MenuItem(
                  icon: Icons.share_outlined,
                  label: 'PT · 친구에게 공유',
                  onTap: () => _sharePt(context, ref),
                ),
              ],
            ),
            const SizedBox(height: FoodietShape.sp16),

            // 데이터 / 개인정보.
            _MenuGroup(
              title: '데이터 · 개인정보',
              children: [
                _MenuItem(
                  icon: Icons.shield_outlined,
                  label: '프라이버시 · 데이터',
                  onTap: () => _openPrivacySheet(context, ref),
                ),
              ],
            ),
            const SizedBox(height: FoodietShape.sp24),

            // 로그아웃은 그룹 박스 밖 — 위험성 있는 액션.
            _MenuItem(
              icon: Icons.logout_rounded,
              label: '로그아웃',
              color: FoodietColors.danger,
              onTap: () async {
                final auth = ref.read(supabaseClientProvider).auth;
                if (auth.currentUser != null) {
                  await auth.signOut();
                }
                // 로컬 끼니 리마인더도 함께 정리.
                await MealReminderService.instance.cancelAll();
                if (context.mounted) context.go('/sign-in');
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── PT 공유 ─────────────────────────────────────────────────────
  // 홈 상단 공유 버튼과 같은 서비스 (오늘 카드 → 이미지 → 공유 시트) 를 재사용.
  Future<void> _sharePt(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(dailyShareServiceProvider).shareToday(context);
    } on DailyShareException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('공유 이미지를 만드는 데 실패했어요.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
        ),
      );
    }
  }

  // ── 알림 설정 시트 ──────────────────────────────────────────────
  Future<void> _openNotificationSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: FoodietColors.cream00,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FoodietShape.radiusLg),
        ),
      ),
      builder: (_) => const _NotificationSettingsSheet(),
    );
  }

  // ── 프라이버시 시트 ─────────────────────────────────────────────
  Future<void> _openPrivacySheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: FoodietColors.cream00,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FoodietShape.radiusLg),
        ),
      ),
      builder: (_) => const _PrivacyDataSheet(),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.nickname,
    this.targetKcal,
    this.goalWeightKg,
  });
  final String nickname;
  final int? targetKcal;
  final double? goalWeightKg;

  @override
  Widget build(BuildContext context) {
    final sub = <String>[];
    if (targetKcal != null) sub.add('일일 $targetKcal kcal');
    if (goalWeightKg != null) sub.add('목표 $goalWeightKg kg');
    final subLine = sub.isEmpty ? '오늘도 잘하고 있어 ✨' : sub.join(' · ');

    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: FoodietColors.coral100,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Text('🍓', style: TextStyle(fontSize: 28)),
        ),
        const SizedBox(width: FoodietShape.sp16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nickname,
                  style: FoodietText.h3
                      .copyWith(color: FoodietColors.warm900)),
              const SizedBox(height: 2),
              Text(subLine,
                  style: FoodietText.bodySm
                      .copyWith(color: FoodietColors.warm500)),
            ],
          ),
        ),
      ],
    );
  }
}

/// 그룹 라벨 + 한 묶음 메뉴 항목들. 시각적으로 카드 박스로 묶어
/// 카테고리를 즉시 인지할 수 있게 한다.
class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 6),
          child: Text(title,
              style: FoodietText.caption.copyWith(
                  color: FoodietColors.warm500,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4)),
        ),
        Container(
          decoration: BoxDecoration(
            color: FoodietColors.cream50,
            borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
            border: Border.all(color: FoodietColors.cream100),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: 4, vertical: 2),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.badgeCount = 0,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color ?? FoodietColors.warm700, size: 22),
            const SizedBox(width: 14),
            Text(label,
                style: FoodietText.body
                    .copyWith(color: color ?? FoodietColors.warm900)),
            const Spacer(),
            if (badgeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: FoodietColors.coral500,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: FoodietText.bodySm.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11),
                ),
              ),
            if (badgeCount > 0) const SizedBox(width: 8),
            if (color == null)
              const Icon(Icons.chevron_right,
                  color: FoodietColors.warm500, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── 알림 설정 시트 ──────────────────────────────────────────────────
//
// 끼니 리마인더 한 가지만 노출.
//   - master 토글: ON 이어야 아래 끼니별 알림이 발화.
//   - 끼니별 (아침/점심/저녁): 각각 ON/OFF + 시각.
//   - 시각 탭하면 시스템 TimePicker 가 떠서 분 단위로 조정.
// 모든 변경은 즉시 [MealReminderService] 로 저장 + OS 스케줄과 동기화.
//
// 스트릭 응원: 항상 ON 으로 동작 (백엔드 미구현 — 추후 도입 시 자동 적용).
//   사용자가 따로 끄거나 켤 항목이 아님이라 UI 에서 빼둠.
class _NotificationSettingsSheet extends StatefulWidget {
  const _NotificationSettingsSheet();

  @override
  State<_NotificationSettingsSheet> createState() =>
      _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState
    extends State<_NotificationSettingsSheet> {
  bool _loading = true;
  late MealReminderPrefs _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await MealReminderService.instance.loadPrefs();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      _loading = false;
    });
  }

  Future<void> _save(MealReminderPrefs next) async {
    setState(() => _prefs = next);
    await MealReminderService.instance.savePrefs(next);
  }

  Future<void> _pickTime(MealSlot slot) async {
    final current = _prefs.forSlot(slot);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox(),
      ),
    );
    if (picked == null) return;
    final next = _prefs.withSlot(
      slot,
      current.copyWith(hour: picked.hour, minute: picked.minute),
    );
    await _save(next);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Padding(
          // 하단 패딩 80 — HomeShell 의 플로팅 카메라 FAB 가 바텀시트 위로
          // 돌출되어 컨텐츠를 가리기 때문에 마지막 텍스트가 겹치지 않도록 확보.
          padding: const EdgeInsets.fromLTRB(FoodietShape.sp20,
              FoodietShape.sp8, FoodietShape.sp20, 80),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: FoodietShape.sp12),
                  decoration: BoxDecoration(
                    color: FoodietColors.cream100,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('알림 설정',
                  style: FoodietText.h3
                      .copyWith(color: FoodietColors.warm900)),
              const SizedBox(height: 4),
              Text('끼니 시간에 기록 안 했을 때 부드럽게 알려줄게.',
                  style: FoodietText.bodySm
                      .copyWith(color: FoodietColors.warm500)),
              const SizedBox(height: FoodietShape.sp16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: FoodietColors.coral500,
                    ),
                  ),
                )
              else ...[
                _ToggleRow(
                  title: '식사 리마인더',
                  subtitle: '아침·점심·저녁 별로 시각을 정해줘',
                  value: _prefs.masterEnabled,
                  onChanged: (v) =>
                      _save(_prefs.copyWith(masterEnabled: v)),
                ),
                if (_prefs.masterEnabled) ...[
                  const SizedBox(height: FoodietShape.sp12),
                  for (final slot in MealSlot.values) ...[
                    _MealSlotRow(
                      slot: slot,
                      pref: _prefs.forSlot(slot),
                      onToggle: (v) => _save(
                        _prefs.withSlot(
                          slot,
                          _prefs.forSlot(slot).copyWith(enabled: v),
                        ),
                      ),
                      onTimeTap: () => _pickTime(slot),
                    ),
                    if (slot != MealSlot.values.last)
                      const SizedBox(height: FoodietShape.sp8),
                  ],
                ],
                const SizedBox(height: FoodietShape.sp16),
                Text(
                  '* 알림은 기기에서 직접 발화돼. 비행기 모드여도 시간이 되면 떠.\n'
                  '* iOS 설정 > 알림 > foodiet 에서 시스템 차원 차단 가능.',
                  style: FoodietText.caption.copyWith(
                      color: FoodietColors.warm500, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 아침/점심/저녁 한 줄 — 좌측 라벨 + 시각 chip + 우측 토글.
class _MealSlotRow extends StatelessWidget {
  const _MealSlotRow({
    required this.slot,
    required this.pref,
    required this.onToggle,
    required this.onTimeTap,
  });
  final MealSlot slot;
  final MealSlotPref pref;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTimeTap;

  @override
  Widget build(BuildContext context) {
    final disabled = !pref.enabled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              slot.label,
              style: FoodietText.body.copyWith(
                color: FoodietColors.warm900,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: pref.enabled ? onTimeTap : null,
                borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: disabled
                        ? FoodietColors.cream100
                        : FoodietColors.coral50,
                    borderRadius:
                        BorderRadius.circular(FoodietShape.radiusSm),
                  ),
                  child: Text(
                    pref.hhmm,
                    style: FoodietText.body.copyWith(
                      color: disabled
                          ? FoodietColors.warm500
                          : FoodietColors.coral700,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Switch(
            value: pref.enabled,
            onChanged: onToggle,
            activeThumbColor: FoodietColors.coral500,
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: FoodietText.body.copyWith(
                      color: FoodietColors.warm900,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: FoodietText.caption
                        .copyWith(color: FoodietColors.warm500)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: FoodietColors.coral500,
          ),
        ],
      ),
    );
  }
}

// ── 프라이버시 · 데이터 시트 ────────────────────────────────────────
class _PrivacyDataSheet extends ConsumerStatefulWidget {
  const _PrivacyDataSheet();

  @override
  ConsumerState<_PrivacyDataSheet> createState() =>
      _PrivacyDataSheetState();
}

class _PrivacyDataSheetState extends ConsumerState<_PrivacyDataSheet> {
  bool _exporting = false;
  bool _deleting = false;

  Future<void> _exportData() async {
    if (_exporting) return;
    final user = ref.read(currentUserProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('로그인이 필요해.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
        ),
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      final client = ref.read(supabaseClientProvider);
      final profileRow = await client
          .from('profiles')
          .select(
            'nickname, locale, unit_energy, unit_mass, height_cm, '
            'weight_kg, goal_weight_kg, goal_deadline, activity_level, '
            'diet_restrictions, daily_kcal_target',
          )
          .eq('user_id', user.id)
          .maybeSingle();

      final entries = await client
          .from('entries')
          .select(
            'id, captured_at, image_path, status, shared_with_count, '
            'title, note, meal_slot, eating_type, kcal_total, macros, '
            'confidence',
          )
          .eq('user_id', user.id)
          .order('captured_at', ascending: false)
          .limit(1000);

      final payload = {
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'user_id': user.id,
        'profile': profileRow,
        'entries': entries,
      };
      final json = const JsonEncoder.withIndent('  ').convert(payload);
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      final count = (entries as List).length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count 개 기록 + 프로필을 JSON 으로 복사했어 📋'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('내보내기 실패: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _deleteAccount() async {
    if (_deleting) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: FoodietColors.cream00,
        title: const Text('정말 계정을 삭제할까?'),
        content: const Text(
          '모든 식사 기록과 프로필이 삭제돼.\n이 작업은 되돌릴 수 없어.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: FoodietColors.danger,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _deleting = true);
    try {
      final client = ref.read(supabaseClientProvider);

      // 순서:
      //   1) Storage 사진 파일 일괄 삭제 — DB row 가 사라지면 image_path 를
      //      못 따라가 고아 파일이 영구히 남는다. 사용자 데이터 완전 삭제
      //      (Apple Privacy Guideline 5.1.1) 를 위해 DB 삭제 *전에* 처리.
      //   2) entries 삭제 (entry_items 는 ON DELETE CASCADE).
      //   3) profiles 삭제 (다른 user-scoped 테이블들은 user_id FK CASCADE).
      try {
        final files = await client.storage
            .from(FoodietSupabase.foodPhotosBucket)
            .list(path: user.id);
        final paths = files
            .where((f) => f.name.isNotEmpty)
            .map((f) => '${user.id}/${f.name}')
            .toList();
        if (paths.isNotEmpty) {
          await client.storage
              .from(FoodietSupabase.foodPhotosBucket)
              .remove(paths);
        }
      } catch (_) {
        // best-effort. 파일 삭제 실패해도 계정 삭제는 계속 진행.
        // (Storage RLS 가 본인 폴더만 허용하기 때문에 일부 실패해도 보안상 안전.)
      }

      await client.from('entries').delete().eq('user_id', user.id);
      await client.from('profiles').delete().eq('user_id', user.id);
      await client.auth.signOut();
      await MealReminderService.instance.cancelAll();

      if (!mounted) return;
      // 시트 닫고 sign-in 으로.
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('계정이 삭제됐어. 언제든 다시 돌아와줘 🌸'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.warm700,
        ),
      );
      context.go('/sign-in');
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('삭제 실패: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FoodietColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        // 하단 80 — HomeShell 의 플로팅 카메라 FAB 가 바텀시트 위에 돌출되어
        // 컨텐츠를 가리지 않도록 확보.
        padding: const EdgeInsets.fromLTRB(
            FoodietShape.sp20, FoodietShape.sp8, FoodietShape.sp20, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: FoodietShape.sp12),
                decoration: BoxDecoration(
                  color: FoodietColors.cream100,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('프라이버시 · 데이터',
                style: FoodietText.h3
                    .copyWith(color: FoodietColors.warm900)),
            const SizedBox(height: 4),
            Text('내 기록을 내보내거나 계정을 삭제할 수 있어.',
                style: FoodietText.bodySm
                    .copyWith(color: FoodietColors.warm500)),
            const SizedBox(height: FoodietShape.sp16),
            _ActionCard(
              icon: Icons.file_download_outlined,
              title: '내 데이터 내보내기',
              subtitle: '프로필 + 최근 1000 개 기록을 JSON 으로 복사',
              trailing: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: FoodietColors.coral500,
                      ),
                    )
                  : const Icon(Icons.chevron_right,
                      color: FoodietColors.warm500, size: 20),
              onTap: _exportData,
            ),
            const SizedBox(height: FoodietShape.sp12),
            _ActionCard(
              icon: Icons.delete_outline,
              iconColor: FoodietColors.danger,
              title: '계정 삭제',
              titleColor: FoodietColors.danger,
              subtitle: '프로필과 모든 식사 기록을 영구 삭제',
              trailing: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: FoodietColors.danger,
                      ),
                    )
                  : const Icon(Icons.chevron_right,
                      color: FoodietColors.warm500, size: 20),
              onTap: _deleteAccount,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
    this.titleColor,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? titleColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FoodietColors.cream50,
      borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
            border: Border.all(color: FoodietColors.cream100),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: iconColor ?? FoodietColors.warm700, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: FoodietText.body.copyWith(
                          color: titleColor ?? FoodietColors.warm900,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: FoodietText.caption
                            .copyWith(color: FoodietColors.warm500)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
