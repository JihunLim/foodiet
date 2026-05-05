/// 카메라 — image_picker + 리사이즈/q80 + Storage 업로드 파이프라인.
///
/// 기획안 §4.1 / §8.2 / §18.1 #13.
///
/// UX (MVP 완성도 개선):
///   - 진입 시 **소스 선택 캡슐** 두 개 노출.
///       왼쪽 = 카메라, 오른쪽 = 앨범. 탭 또는 좌우 드래그로 바로 선택.
///   - 카메라/앨범에서 취소하면 홈으로 돌아오지 않고 선택 화면에 머묾.
///   - 프리뷰 상태에선 "다시 찍기" / "기록하기" + 하단에 "앨범" 진입 재노출.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/entries_provider.dart';
import '../../services/photo_upload_service.dart';
import '../../theme/foodiet_tokens.dart';

class CameraPage extends ConsumerStatefulWidget {
  const CameraPage({super.key});

  @override
  ConsumerState<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends ConsumerState<CameraPage> {
  XFile? _picked;
  PhotoSource _source = PhotoSource.camera;
  bool _busy = false;
  String? _error;

  Future<void> _pick(PhotoSource source) async {
    if (_busy) return;
    final svc = ref.read(photoUploadServiceProvider);
    setState(() => _error = null);
    HapticFeedback.selectionClick();
    try {
      final file = await svc.pick(source: source);
      if (!mounted) return;
      if (file == null) {
        // 사용자가 picker 에서 취소. 선택 화면 유지.
        return;
      }
      setState(() {
        _picked = file;
        _source = source;
        _error = null;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'camera_access_denied' =>
          '카메라 권한이 거부됐어. 설정 > 푸디엣 에서 카메라를 허용해줘.',
        'photo_access_denied' =>
          '사진 접근 권한이 거부됐어. 설정 > 푸디엣 에서 사진을 허용해줘.',
        'invalid_source' =>
          '이 기기에서는 카메라를 사용할 수 없어. 앨범에서 골라줘.',
        _ => '사진을 가져오지 못했어: ${e.message ?? e.code}',
      };
      setState(() => _error = msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '사진을 가져오지 못했어: $e');
    }
  }

  Future<void> _submit() async {
    final file = _picked;
    if (file == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final svc = ref.read(photoUploadServiceProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();

    try {
      await svc.upload(file: file, source: _source, locale: locale);
      ref.invalidate(todayEntriesProvider);
      ref.invalidate(recentEntriesProvider);
      if (!mounted) return;
      context.pop(true);
    } on PhotoUploadFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '업로드 실패: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _picked;
    return Scaffold(
      backgroundColor: FoodietColors.warm900,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          onPressed: _busy ? null : () => context.pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: SafeArea(
        child: file == null ? _buildChooser() : _buildPreview(file),
      ),
    );
  }

  Widget _buildChooser() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FoodietShape.sp20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: FoodietShape.sp24),
          Text(
            '어떻게 기록할까?',
            style: FoodietText.h2.copyWith(color: Colors.white),
          ),
          const SizedBox(height: FoodietShape.sp4),
          Text(
            '탭하거나 좌우로 드래그해서 선택해.',
            style: FoodietText.body.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: FoodietShape.sp24),

          // 소스 선택 캡슐 — 좌우 드래그 또는 탭.
          _SourceChooser(
            onCamera: () => _pick(PhotoSource.camera),
            onGallery: () => _pick(PhotoSource.gallery),
          ),

          const SizedBox(height: FoodietShape.sp16),

          // 에러 메시지는 캡슐 아래.
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(FoodietShape.sp12),
              decoration: BoxDecoration(
                color: FoodietColors.danger.withValues(alpha: 0.16),
                borderRadius:
                    BorderRadius.circular(FoodietShape.radiusMd),
                border: Border.all(
                  color: FoodietColors.danger.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                _error!,
                style: FoodietText.bodySm.copyWith(color: Colors.white),
              ),
            ),

          const Spacer(),

          // 힌트.
          Padding(
            padding:
                const EdgeInsets.only(bottom: FoodietShape.sp24, top: 8),
            child: Row(
              children: [
                const Icon(Icons.swipe_rounded,
                    color: Colors.white38, size: 16),
                const SizedBox(width: 6),
                Text(
                  '왼쪽으로 드래그하면 카메라, 오른쪽은 앨범',
                  style: FoodietText.caption
                      .copyWith(color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(XFile file) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(FoodietShape.sp16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
              child: kIsWeb
                  ? Image.network(file.path, fit: BoxFit.cover)
                  : Image.file(File(file.path), fit: BoxFit.cover),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FoodietShape.sp20,
              vertical: FoodietShape.sp8,
            ),
            child: Text(
              _error!,
              style: FoodietText.bodySm.copyWith(color: FoodietColors.danger),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FoodietShape.sp20,
            FoodietShape.sp8,
            FoodietShape.sp20,
            FoodietShape.sp8,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _pick(PhotoSource.camera),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(FoodietShape.radiusMd),
                    ),
                  ),
                  child: const Text('다시 찍기'),
                ),
              ),
              const SizedBox(width: FoodietShape.sp12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: FoodietColors.coral500,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(FoodietShape.radiusMd),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          '기록하기',
                          style: FoodietText.body.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: FoodietShape.sp16),
          child: TextButton.icon(
            onPressed: _busy ? null : () => _pick(PhotoSource.gallery),
            icon: const Icon(Icons.photo_library_outlined,
                size: 18, color: Colors.white70),
            label: Text(
              '앨범에서 다시 고르기',
              style: FoodietText.bodySm.copyWith(color: Colors.white70),
            ),
          ),
        ),
      ],
    );
  }
}

/// 두 캡슐(카메라/앨범) + 좌우 드래그 인식.
///
/// - 탭: 해당 소스 픽커 즉시 실행.
/// - 좌우 드래그: primaryVelocity 또는 이동 거리로 방향 판정.
///     · left (velocity < 0 또는 누적 dx < -임계) → 카메라
///     · right (velocity > 0 또는 누적 dx > +임계) → 앨범
/// - 드래그 중엔 해당 방향 캡슐을 살짝 강조(hover 효과).
class _SourceChooser extends StatefulWidget {
  const _SourceChooser({required this.onCamera, required this.onGallery});
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  State<_SourceChooser> createState() => _SourceChooserState();
}

class _SourceChooserState extends State<_SourceChooser> {
  /// 드래그 중 강조되는 쪽. null = 강조 없음.
  PhotoSource? _hover;

  /// 누적 드래그 거리.
  double _dragDx = 0;

  static const double _distanceThreshold = 48; // px
  static const double _velocityThreshold = 300; // px/s

  void _onDragStart(DragStartDetails _) {
    _dragDx = 0;
    HapticFeedback.selectionClick();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _dragDx += d.delta.dx;
    PhotoSource? h;
    if (_dragDx < -16) {
      h = PhotoSource.camera;
    } else if (_dragDx > 16) {
      h = PhotoSource.gallery;
    }
    if (h != _hover) setState(() => _hover = h);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    PhotoSource? pick;
    if (v <= -_velocityThreshold || _dragDx <= -_distanceThreshold) {
      pick = PhotoSource.camera;
    } else if (v >= _velocityThreshold || _dragDx >= _distanceThreshold) {
      pick = PhotoSource.gallery;
    }
    setState(() {
      _hover = null;
      _dragDx = 0;
    });
    if (pick == PhotoSource.camera) {
      widget.onCamera();
    } else if (pick == PhotoSource.gallery) {
      widget.onGallery();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Row(
        children: [
          Expanded(
            child: _ChooserTile(
              icon: Icons.photo_camera_rounded,
              label: '카메라',
              subtitle: '지금 바로 찍기',
              active: _hover == PhotoSource.camera,
              onTap: widget.onCamera,
            ),
          ),
          const SizedBox(width: FoodietShape.sp12),
          Expanded(
            child: _ChooserTile(
              icon: Icons.photo_library_rounded,
              label: '앨범',
              subtitle: '사진에서 고르기',
              active: _hover == PhotoSource.gallery,
              onTap: widget.onGallery,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChooserTile extends StatelessWidget {
  const _ChooserTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        height: 168,
        decoration: BoxDecoration(
          color: active
              ? FoodietColors.coral500
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
          border: Border.all(
            color: active
                ? FoodietColors.coral500
                : Colors.white.withValues(alpha: 0.18),
            width: 1.5,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: FoodietColors.coral500.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(FoodietShape.sp16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 40),
            const SizedBox(height: FoodietShape.sp12),
            Text(
              label,
              style: FoodietText.title.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: FoodietText.caption.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
