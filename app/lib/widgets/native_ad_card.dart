/// 인사이트 등 컨텐츠 리스트 사이에 끼워 넣는 AdMob 네이티브 고급형 광고.
///
/// - 같은 단위를 여러 카드에서 동시에 로드할 수 있음 (`key` 로 구분).
/// - 로딩 실패하면 위젯 자체가 사라져서 자리만 차지하는 걸 피함.
/// - policy: 광고 영역임을 명시하는 라벨과 CTA 를 `FoodietNativeAdFactory`
///   (iOS Swift / Android Kotlin) 가 렌더한다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ads_service.dart';

class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key, this.height = 128});

  /// 네이티브 팩토리가 그리는 고정 높이. 레이아웃 점프 방지용.
  final double height;

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    if (kDebugMode) {
      debugPrint('[ad] loading native unit=${FoodietAdUnits.insightNative} '
          'factory=${FoodietAdUnits.nativeFactoryId}');
    }
    final ad = NativeAd(
      adUnitId: FoodietAdUnits.insightNative,
      factoryId: FoodietAdUnits.nativeFactoryId,
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (kDebugMode) debugPrint('[ad] ✅ loaded');
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          if (kDebugMode) {
            debugPrint('[ad] ❌ failed code=${error.code} '
                'domain=${error.domain} msg=${error.message}');
          }
          ad.dispose();
          if (mounted) setState(() => _failed = true);
        },
        onAdImpression: (_) {
          if (kDebugMode) debugPrint('[ad] impression');
        },
        onAdClicked: (_) {
          if (kDebugMode) debugPrint('[ad] click');
        },
      ),
      // ATT 상태에 맞춰 자동으로 personalized / non-personalized 로 요청.
      request: buildAdRequest(),
    );
    ad.load();
    _ad = ad;
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      // 릴리스 빌드 — 자리 없이 깔끔 제거.
      if (!kDebugMode) return const SizedBox.shrink();
      // 디버그 빌드 — 원인 확인용 가시 자리.
      return Container(
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFFE4D1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFF8A5B)),
        ),
        child: const Text('[debug] 광고 로드 실패 (콘솔 확인)',
            style: TextStyle(color: Color(0xFFCC5A31))),
      );
    }
    if (!_loaded || _ad == null) {
      // 스켈레톤 — 레이아웃 점프 방지.
      return SizedBox(height: widget.height);
    }
    // 네이티브 광고 뷰(iOS UIView / Android View) 는 자체 intrinsic width 가
    // 없어서 부모가 명시해 주지 않으면 화면 밖으로 넘어간다.
    // LayoutBuilder 로 부모 폭을 계산해 SizedBox 에 명시.
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return SizedBox(
          width: w,
          height: widget.height,
          child: AdWidget(ad: _ad!),
        );
      },
    );
  }
}
