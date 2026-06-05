/// 홈 "빠른 기록" 칩 행 (업그레이드 로드맵 [Q2]).
///
/// 즐겨찾기한 음식을 가로 스크롤 칩으로 보여주고, 한 번 탭하면 사진/분석 없이
/// 바로 기록한다. 실수 방지는 confirm 다이얼로그 대신 "실행취소" 스낵바로 처리해
/// 마찰을 최소화한다. 즐겨찾기가 없으면(또는 0016 미적용 시) 아무것도 그리지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/entries_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/signed_network_image.dart';

class QuickRecordChips extends ConsumerWidget {
  const QuickRecordChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider).valueOrNull ?? const [];
    if (favorites.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bolt_rounded,
                size: 16, color: FoodietColors.coral500),
            const SizedBox(width: 4),
            Text('빠른 기록',
                style: FoodietText.title
                    .copyWith(color: FoodietColors.warm700)),
          ],
        ),
        const SizedBox(height: FoodietShape.sp12),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: favorites.length,
            separatorBuilder: (_, __) => const SizedBox(width: FoodietShape.sp8),
            itemBuilder: (_, i) => _FavoriteChip(
              favorite: favorites[i],
              onTap: () => _record(context, ref, favorites[i]),
              onLongPress: () => _confirmRemove(context, ref, favorites[i]),
            ),
          ),
        ),
        const SizedBox(height: FoodietShape.sp24),
      ],
    );
  }

  Future<void> _record(
      BuildContext context, WidgetRef ref, Favorite fav) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(favoritesServiceProvider);
    try {
      final recorded = await service.recordFromFavorite(fav);
      ref.invalidate(todayEntriesProvider);
      ref.invalidate(recentEntriesProvider);

      final kcal = fav.kcalTotal;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(kcal != null
                ? '기록했어 · ${fav.name} $kcal kcal'
                : '기록했어 · ${fav.name}'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: '실행취소',
              onPressed: () async {
                await service.deleteEntry(recorded.entryId, recorded.imagePath);
                ref.invalidate(todayEntriesProvider);
                ref.invalidate(recentEntriesProvider);
              },
            ),
          ),
        );
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('기록 못 했어: $e')));
    }
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, Favorite fav) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FoodietColors.cream00,
        title: const Text('즐겨찾기 해제'),
        content: Text("'${fav.name}'을(를) 빠른 기록에서 뺄까?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소',
                style: TextStyle(color: FoodietColors.warm500)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('해제',
                style: TextStyle(color: FoodietColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(favoritesServiceProvider)
        .removeById(fav.id, imagePath: fav.imagePath);
    ref.invalidate(favoritesProvider);
  }
}

class _FavoriteChip extends StatelessWidget {
  const _FavoriteChip({
    required this.favorite,
    required this.onTap,
    required this.onLongPress,
  });
  final Favorite favorite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final kcal = favorite.kcalTotal;
    return Material(
      color: FoodietColors.coral50,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 14, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: favorite.imagePath != null
                      ? SignedNetworkImage(
                          path: favorite.imagePath!,
                          cacheWidth: 96,
                          cacheHeight: 96,
                          errorBuilder: (_) => _placeholder(),
                        )
                      : _placeholder(),
                ),
              ),
              const SizedBox(width: FoodietShape.sp8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  favorite.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoodietText.bodySm.copyWith(
                    color: FoodietColors.warm900,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (kcal != null) ...[
                const SizedBox(width: 6),
                Text('$kcal',
                    style: FoodietText.caption
                        .copyWith(color: FoodietColors.coral500)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: FoodietColors.cream100,
        alignment: Alignment.center,
        child: const Text('🍽️', style: TextStyle(fontSize: 14)),
      );
}
