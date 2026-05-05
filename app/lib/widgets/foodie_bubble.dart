/// 푸디의 한마디 — AI 코칭 메시지 컴포넌트.
///
/// 기획안 §4.4 / §7.5 / §10.2 — 모든 AI 출력은 이 버블로만 렌더된다.
/// `coach_messages.body_json.persona == "foodie"` 인 경우에만 사용.
library;

import 'package:flutter/material.dart';
import '../theme/foodiet_tokens.dart';

class FoodieBubble extends StatelessWidget {
  const FoodieBubble({
    super.key,
    required this.headline,
    this.why,
    this.suggestedAction,
    this.onTapMore,
  });

  /// §10.2 body_json.headline — 20자 내외 반말.
  final String headline;

  /// §10.2 body_json.why — 한 문장 근거.
  final String? why;

  /// §10.2 body_json.suggested_next_action — 1개 액션만.
  final String? suggestedAction;

  final VoidCallback? onTapMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: FoodietColors.coral50,
        border: Border.all(color: FoodietColors.coral100, width: 1),
        borderRadius: BorderRadius.circular(FoodietShape.radiusLg),
        boxShadow: FoodietShape.shadowCard,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 푸디 마스코트 — 실제 SVG는 assets/illust/mascot-foodie.svg 사용.
          // MVP 초기엔 원형 플레이스홀더로, 이후 flutter_svg 로 교체.
          Container(
            width: 36, height: 36,
            margin: const EdgeInsets.only(right: 12, top: 2),
            decoration: const BoxDecoration(
              color: FoodietColors.coral500,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text('🍓', style: TextStyle(fontSize: 18)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Label(),
                const SizedBox(height: 4),
                Text(headline, style: FoodietText.title.copyWith(
                  color: FoodietColors.warm900,
                  fontWeight: FontWeight.w700,
                )),
                if (why != null && why!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(why!, style: FoodietText.bodySm.copyWith(
                    color: FoodietColors.warm500,
                  )),
                ],
                if (suggestedAction != null && suggestedAction!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onTapMore,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: FoodietColors.coral500,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(suggestedAction!,
                          style: FoodietText.bodySm.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label();
  @override
  Widget build(BuildContext context) {
    return Text(
      '푸디의 한마디',
      style: FoodietText.caption.copyWith(
        color: FoodietColors.coral600,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }
}
