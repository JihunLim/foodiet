/// Supabase Storage signed URL 을 그리는 `Image.network` 래퍼.
///
/// 왜 별도 위젯이 필요한가:
///   - `Image.network` 는 한 번 실패하면 같은 URL 을 재시도하지 않는다.
///     [ImageCache] 가 "실패" 상태로 남기 때문에 위젯이 리마운트 될 때까지
///     영원히 fallback 만 보인다. → "앱 껐다 키면 다시 나온다" 증상.
///   - Supabase Storage 의 CDN 은 404/403 을 edge 에서 negative-cache 한다.
///     업로드 직후 아직 propagate 안 된 타이밍에 URL 을 때리면 이 음성 캐시가
///     남아서 같은 URL 로는 계속 실패한다. 또 업로드 자체가 성공해도 CDN
///     쪽에서 일시적 전파 지연이 있을 수 있다.
///   - 해결: 실패 시 [signedUrlProvider] 를 invalidate 해 새 `?token=` 이
///     달린 URL 을 가져온다. 쿼리스트링이 다르면 CDN 캐시 키가 달라지므로
///     negative cache 우회가 가능하다.
///
/// 설계:
///   · Timer 로 지연 후 재시도 (errorBuilder 는 build 단계에서 실행되므로
///     setState/invalidate 를 동기로 호출하면 안 된다).
///   · 최대 3회, 400ms × 2^n backoff (400 / 800 / 1600ms).
///   · cacheWidth/cacheHeight 로 디코드 메모리 압력 감소 — 썸네일 크기는
///     물리 픽셀 단위 (pt × DPR) 로 지정.
///   · kDebugMode 에서만 debugPrint 로 재시도 흔적을 남김 — 릴리즈 빌드
///     로그에는 찍히지 않음.
library;

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/entries_provider.dart';
import '../theme/foodiet_tokens.dart';

typedef SignedImageBuilder = Widget Function(BuildContext context);

class SignedNetworkImage extends ConsumerStatefulWidget {
  const SignedNetworkImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
    this.loadingBuilder,
    this.errorBuilder,
    this.maxRetries = 3,
  });

  /// Storage object path (예: `users/abc/2026-04-21/foo.jpg`).
  /// `signedUrlProvider(path)` 의 key 로 그대로 사용된다.
  final String path;
  final BoxFit fit;

  /// 디코드 시 리사이즈 타겟 (물리 픽셀). pt × DPR 으로 계산해서 전달.
  /// 필수는 아니지만 썸네일 크기가 정해져 있으면 크게 도움됨.
  final int? cacheWidth;
  final int? cacheHeight;

  /// 로딩/실패 시 보여줄 위젯. 지정 안 하면 cream100 배경 + 🍽️ fallback.
  final SignedImageBuilder? loadingBuilder;
  final SignedImageBuilder? errorBuilder;

  /// 실패 시 최대 재시도 횟수. 0 이면 재시도 안 함.
  final int maxRetries;

  @override
  ConsumerState<SignedNetworkImage> createState() =>
      _SignedNetworkImageState();
}

class _SignedNetworkImageState extends ConsumerState<SignedNetworkImage> {
  int _retryCount = 0;
  Timer? _retryTimer;

  @override
  void didUpdateWidget(covariant SignedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // path 가 바뀌면 재시도 카운터 리셋.
    if (oldWidget.path != widget.path) {
      _retryCount = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  /// 에러 발생 시 다음 프레임에 URL 을 invalidate.
  ///
  /// errorBuilder / AsyncValue.error 는 build 단계에서 호출되므로
  /// 여기서 setState/invalidate 를 동기로 부르면 안 된다. Timer 로 뒤로 미룸.
  void _scheduleRetry(String reason) {
    if (_retryCount >= widget.maxRetries) {
      if (kDebugMode) {
        debugPrint(
          '[SignedNetworkImage] give up after $_retryCount retries '
          '(${widget.path}) — $reason',
        );
      }
      return;
    }
    if (_retryTimer?.isActive == true) return; // 이미 예약됨.

    final next = _retryCount + 1;
    final delay = Duration(milliseconds: 400 * (1 << _retryCount));
    if (kDebugMode) {
      debugPrint(
        '[SignedNetworkImage] retry $next/${widget.maxRetries} in '
        '${delay.inMilliseconds}ms (${widget.path}) — $reason',
      );
    }
    _retryTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {
        _retryCount = next;
      });
      // 새 signed URL 을 강제로 가져온다. 다른 `?token=` 이 붙어
      // CDN negative cache / Flutter ImageCache 둘 다 우회.
      ref.invalidate(signedUrlProvider(widget.path));
    });
  }

  Widget _defaultFallback() => Container(
        color: FoodietColors.cream100,
        alignment: Alignment.center,
        child: const Text('🍽️', style: TextStyle(fontSize: 24)),
      );

  Widget _defaultLoading() => Container(color: FoodietColors.cream100);

  @override
  Widget build(BuildContext context) {
    final urlAsync = ref.watch(signedUrlProvider(widget.path));

    return urlAsync.when(
      loading: () => widget.loadingBuilder?.call(context) ?? _defaultLoading(),
      error: (e, _) {
        // signed URL 자체를 못 받은 경우도 재시도 대상.
        _scheduleRetry('signedUrlProvider error: $e');
        return widget.errorBuilder?.call(context) ?? _defaultFallback();
      },
      // CachedNetworkImage — 디스크 캐시로 재방문/스크롤 시 즉시 표시.
      // cacheKey 를 path 로 고정해서, signed URL 의 token 이 새로 발급돼도
      // 같은 사진은 동일 캐시 엔트리를 사용 (token 만 다른 캐시 미스 방지).
      data: (url) => CachedNetworkImage(
        imageUrl: url,
        cacheKey: widget.path,
        fit: widget.fit,
        memCacheWidth: widget.cacheWidth,
        memCacheHeight: widget.cacheHeight,
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (context, _) =>
            widget.loadingBuilder?.call(context) ?? _defaultLoading(),
        errorWidget: (_, __, error) {
          _scheduleRetry('CachedNetworkImage error: $error');
          return widget.errorBuilder?.call(context) ?? _defaultFallback();
        },
      ),
    );
  }
}
