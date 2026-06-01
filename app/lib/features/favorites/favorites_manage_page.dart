/// 즐겨찾기 관리 — 설정에서 진입. 즐겨찾기 목록을 보고 빠르게 삭제한다.
///
/// 삭제는 행의 휴지통 버튼 한 번으로 즉시 처리하되, "실행취소" 스낵바로 안전망을
/// 둔다. 취소하지 않으면 스냅샷 사진까지 정리한다(고아 파일 방지).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/favorites_provider.dart';
import '../../theme/foodiet_tokens.dart';
import '../../widgets/signed_network_image.dart';

class FavoritesManagePage extends ConsumerStatefulWidget {
  const FavoritesManagePage({super.key});

  @override
  ConsumerState<FavoritesManagePage> createState() =>
      _FavoritesManagePageState();
}

class _FavoritesManagePageState extends ConsumerState<FavoritesManagePage> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(favoritesProvider);

    return Scaffold(
      backgroundColor: FoodietColors.cream00,
      appBar: AppBar(
        backgroundColor: FoodietColors.cream00,
        elevation: 0,
        title: Text('즐겨찾기 관리',
            style: FoodietText.h3.copyWith(color: FoodietColors.warm900)),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: FoodietColors.coral500),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(FoodietShape.sp20),
              child: Text('목록을 불러오지 못했어: $e',
                  textAlign: TextAlign.center,
                  style: FoodietText.body
                      .copyWith(color: FoodietColors.warm700)),
            ),
          ),
          data: (favorites) {
            if (favorites.isEmpty) return const _EmptyFavorites();
            return ListView.separated(
              padding: const EdgeInsets.all(FoodietShape.sp20),
              itemCount: favorites.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: FoodietShape.sp12),
              itemBuilder: (_, i) => _FavoriteRow(
                favorite: favorites[i],
                onDelete: () => _delete(favorites[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 행 삭제 + 실행취소 스낵바. 취소하지 않으면 스냅샷 사진까지 정리.
  Future<void> _delete(Favorite fav) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(favoritesServiceProvider);

    await service.deleteRow(fav.id);
    if (mounted) ref.invalidate(favoritesProvider);

    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text("'${fav.name}' 삭제됨"),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '실행취소',
          onPressed: () async {
            await service.restore(fav);
            if (mounted) ref.invalidate(favoritesProvider);
          },
        ),
      ),
    );

    // 스낵바가 실행취소 없이 닫히면 스냅샷 사진을 정리(고아 방지).
    final reason = await controller.closed;
    if (reason != SnackBarClosedReason.action) {
      await service.deleteImage(fav.imagePath);
    }
  }
}

class _FavoriteRow extends StatelessWidget {
  const _FavoriteRow({required this.favorite, required this.onDelete});
  final Favorite favorite;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final kcal = favorite.kcalTotal;
    return Container(
      padding: const EdgeInsets.all(FoodietShape.sp12),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(FoodietShape.radiusSm),
            child: SizedBox(
              width: 48,
              height: 48,
              child: favorite.imagePath != null
                  ? SignedNetworkImage(
                      path: favorite.imagePath!,
                      cacheWidth: 144,
                      cacheHeight: 144,
                      errorBuilder: (_) => _thumb(),
                    )
                  : _thumb(),
            ),
          ),
          const SizedBox(width: FoodietShape.sp12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(favorite.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoodietText.body.copyWith(
                      color: FoodietColors.warm900,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text(kcal != null ? '$kcal kcal' : '칼로리 미정',
                    style: FoodietText.bodySm
                        .copyWith(color: FoodietColors.warm500)),
              ],
            ),
          ),
          IconButton(
            tooltip: '삭제',
            icon: const Icon(Icons.delete_outline_rounded,
                color: FoodietColors.danger),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  Widget _thumb() => Container(
        color: FoodietColors.cream100,
        alignment: Alignment.center,
        child: const Text('🍽️', style: TextStyle(fontSize: 18)),
      );
}

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FoodietShape.sp24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⭐', style: TextStyle(fontSize: 44)),
            const SizedBox(height: FoodietShape.sp12),
            Text('아직 즐겨찾기가 없어',
                style: FoodietText.title
                    .copyWith(color: FoodietColors.warm700)),
            const SizedBox(height: 4),
            Text('기록 상세에서 ⭐ 를 눌러 자주 먹는 음식을 추가해봐.',
                textAlign: TextAlign.center,
                style: FoodietText.bodySm
                    .copyWith(color: FoodietColors.warm500)),
          ],
        ),
      ),
    );
  }
}
