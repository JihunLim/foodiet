/// 사진 없는 기록(식단·추천 1탭 기록)의 썸네일 자리 — 끼니 이모지 타일.
library;

import 'package:flutter/material.dart';

import '../theme/foodiet_tokens.dart';

class NoPhotoTile extends StatelessWidget {
  const NoPhotoTile({
    super.key,
    this.size,
    this.mealSlot,
    this.radius,
  });

  /// null 이면 부모 크기를 채운다.
  final double? size;
  final String? mealSlot;
  final BorderRadius? radius;

  static String emojiFor(String? slot) => switch (slot) {
        'breakfast' => '🍳',
        'lunch' => '🍱',
        'dinner' => '🍽️',
        'late_night' => '🌙',
        _ => '🍽️',
      };

  @override
  Widget build(BuildContext context) {
    final s = size;
    return ClipRRect(
      borderRadius: radius ?? BorderRadius.zero,
      child: Container(
        width: s,
        height: s,
        color: FoodietColors.cream100,
        alignment: Alignment.center,
        child: Text(
          emojiFor(mealSlot),
          style: TextStyle(fontSize: s == null ? 48 : s * 0.45),
        ),
      ),
    );
  }
}
