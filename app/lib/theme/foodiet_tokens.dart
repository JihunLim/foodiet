/// Foodiet 디자인 토큰 (Dart 포트).
///
/// 원본: `design-system/colors_and_type.css`
/// 기획안 §7 — **이 파일은 CSS 토큰의 1:1 거울**이다. 하드코딩 금지.
/// CSS 변수값이 바뀌면 여기도 반드시 동기화할 것.
library;

import 'package:flutter/material.dart';

/// 컬러 토큰
class FoodietColors {
  FoodietColors._();

  // ── 브랜드 ────────────────────────────────────────────────
  static const coral50  = Color(0xFFFFF2EA);
  static const coral100 = Color(0xFFFFE4D1);
  static const coral300 = Color(0xFFFFB48E);
  static const coral500 = Color(0xFFFF8A5B); // primary
  static const coral600 = Color(0xFFEE7042); // hover
  static const coral700 = Color(0xFFCC5A31); // pressed

  static const leaf100 = Color(0xFFDFF0DD);
  static const leaf300 = Color(0xFFAED1AB);
  static const leaf500 = Color(0xFF7FB77E); // secondary / success
  static const leaf700 = Color(0xFF5C9A5B);

  // ── 뉴트럴 (웜톤) ────────────────────────────────────────
  static const cream00  = Color(0xFFFFFDFA); // 바닥
  static const cream50  = Color(0xFFFBF6EF); // 카드
  static const cream100 = Color(0xFFF4EDE2); // 헤어라인
  static const warm200  = Color(0xFFE8E0D1);
  static const warm500  = Color(0xFF6B6454); // body
  static const warm700  = Color(0xFF3E3A31); // heading
  static const warm900  = Color(0xFF221F1A); // ink

  // ── Meal slot (시간대 축) ─────────────────────────────────
  static const mealBreakfast = Color(0xFFF7D36A); // --meal-breakfast
  static const mealLunch     = coral500;          // --meal-lunch
  static const mealDinner    = Color(0xFF8B6FB3); // --meal-dinner
  // 야식(late_night) = mealDinner + overlay (rgba(26,17,8,0.12))

  // ── Eating type (식사 종류 축) ────────────────────────────
  static const mealSnack    = leaf500;            // --meal-snack
  static const mealBeverage = Color(0xFF9BC6E3);  // --sky-500 (음료 칩)

  // ── 시맨틱 ───────────────────────────────────────────────
  static const success = leaf500;
  static const warning = Color(0xFFF2A93B);
  static const danger  = Color(0xFFE5574E); // 분석/네트워크 실패에만 (§7.2)
  static const info    = Color(0xFF9BC6E3);

  // ── 섀도 틴트 (웜톤만) ────────────────────────────────────
  static const shadowTint = Color(0x143A2614); // rgba(58,38,20,0.08)
}

/// 라운드·스페이싱·섀도
class FoodietShape {
  FoodietShape._();

  // Radius (§7.6)
  static const radiusXs  = 6.0;
  static const radiusSm  = 10.0;
  static const radiusMd  = 14.0; // 기본 카드·버튼 최소
  static const radiusLg  = 20.0;
  static const radiusXl  = 28.0;

  // Spacing (§7.6)
  static const sp4  = 4.0;
  static const sp8  = 8.0;
  static const sp12 = 12.0;
  static const sp16 = 16.0;
  static const sp20 = 20.0;
  static const sp24 = 24.0;
  static const sp32 = 32.0;
  static const sp40 = 40.0;

  static const shadowCard = [
    BoxShadow(
      color: FoodietColors.shadowTint,
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];
}

/// 타이포그래피 — Gmarket Sans (§7.4)
class FoodietText {
  FoodietText._();

  static const _family = 'GmarketSans';
  static const _fallback = <String>[
    'Pretendard',
    'Apple SD Gothic Neo',
    'Noto Sans KR',
  ];

  static const displayLarge = TextStyle(
    fontFamily: _family, fontFamilyFallback: _fallback,
    fontSize: 42, fontWeight: FontWeight.w700,
    letterSpacing: -0.84, height: 1.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const h1 = TextStyle(
    fontFamily: _family, fontFamilyFallback: _fallback,
    fontSize: 34, fontWeight: FontWeight.w700,
    letterSpacing: -0.68, height: 1.2,
  );
  static const h2 = TextStyle(
    fontFamily: _family, fontFamilyFallback: _fallback,
    fontSize: 28, fontWeight: FontWeight.w700,
    letterSpacing: -0.56, height: 1.25,
  );
  static const h3 = TextStyle(
    fontFamily: _family, fontFamilyFallback: _fallback,
    fontSize: 24, fontWeight: FontWeight.w500,
    letterSpacing: -0.48, height: 1.3,
  );
  static const title = TextStyle(
    fontFamily: _family, fontFamilyFallback: _fallback,
    fontSize: 18, fontWeight: FontWeight.w500, height: 1.4,
  );
  static const body = TextStyle(
    fontFamily: _family, fontFamilyFallback: _fallback,
    fontSize: 16, fontWeight: FontWeight.w500, height: 1.5,
  );
  static const bodySm = TextStyle(
    fontFamily: _family, fontFamilyFallback: _fallback,
    fontSize: 13, fontWeight: FontWeight.w500, height: 1.5,
  );
  static const caption = TextStyle(
    fontFamily: _family, fontFamilyFallback: _fallback,
    fontSize: 12, fontWeight: FontWeight.w300, height: 1.4,
  );

  /// 숫자 강조 — 남은 칼로리, 일별 합계 등 (§7.4)
  static const numberLarge = TextStyle(
    fontFamily: _family, fontFamilyFallback: _fallback,
    fontSize: 42, fontWeight: FontWeight.w700,
    letterSpacing: -0.5, height: 1.0,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// 축별 색 헬퍼 — enum 혼동 방지 (§7.3, §13.5)
///
/// `meal_slot` (시간대)과 `eating_type` (식사/간식/음료)은 서로 다른 축이다.
/// UI에서는 상단 배지=meal_slot 색, 우측 칩=eating_type 색으로 분리한다.
class FoodietSemantic {
  FoodietSemantic._();

  static Color mealSlotColor(String slot) {
    switch (slot) {
      case 'breakfast':  return FoodietColors.mealBreakfast;
      case 'lunch':      return FoodietColors.mealLunch;
      case 'dinner':     return FoodietColors.mealDinner;
      case 'late_night': return FoodietColors.mealDinner; // + overlay
      default:           return FoodietColors.warm500;
    }
  }

  static Color eatingTypeColor(String type) {
    switch (type) {
      case 'meal':     return FoodietColors.coral500;
      case 'snack':    return FoodietColors.mealSnack;
      case 'beverage': return FoodietColors.mealBeverage;
      default:         return FoodietColors.warm500;
    }
  }
}

/// MaterialApp.theme 에 바로 꽂아 쓰는 진입점.
ThemeData buildFoodietTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: FoodietColors.cream00,
    colorScheme: const ColorScheme.light(
      primary: FoodietColors.coral500,
      onPrimary: Colors.white,
      secondary: FoodietColors.leaf500,
      onSecondary: Colors.white,
      error: FoodietColors.danger,
      surface: FoodietColors.cream50,
      onSurface: FoodietColors.warm900,
    ),
    textTheme: base.textTheme.copyWith(
      displayLarge: FoodietText.displayLarge.copyWith(color: FoodietColors.warm900),
      headlineLarge: FoodietText.h1.copyWith(color: FoodietColors.warm900),
      headlineMedium: FoodietText.h2.copyWith(color: FoodietColors.warm900),
      titleLarge: FoodietText.h3.copyWith(color: FoodietColors.warm700),
      titleMedium: FoodietText.title.copyWith(color: FoodietColors.warm700),
      bodyLarge: FoodietText.body.copyWith(color: FoodietColors.warm700),
      bodyMedium: FoodietText.bodySm.copyWith(color: FoodietColors.warm500),
      labelSmall: FoodietText.caption.copyWith(color: FoodietColors.warm500),
    ),
    splashFactory: NoSplash.splashFactory, // 따뜻한 톤 유지
  );
}
