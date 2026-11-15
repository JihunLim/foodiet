/// 투약 관리 화면·시트가 함께 쓰는 작은 위젯/포맷 헬퍼.
library;

import 'package:flutter/material.dart';

import '../../services/medication_schedule.dart';
import '../../theme/foodiet_tokens.dart';

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// '11월 17일 (화)'
String medDateLabel(DateTime d) =>
    '${d.month}월 ${d.day}일 (${_weekdays[d.weekday - 1]})';

/// '11월 17일 (화) 23:30'
String medDateTimeLabel(DateTime d) =>
    '${medDateLabel(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// 9 → '오전 9시', 13 → '오후 1시', 0 → '오전 12시'.
String medHourLabel(int h) {
  final am = h < 12;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '${am ? '오전' : '오후'} $h12시';
}

class MedSheetHandle extends StatelessWidget {
  const MedSheetHandle({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: FoodietShape.sp12),
        decoration: BoxDecoration(
          color: FoodietColors.cream100,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class MedSectionLabel extends StatelessWidget {
  const MedSectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FoodietShape.sp8),
      child: Text(text,
          style: FoodietText.bodySm.copyWith(
            color: FoodietColors.warm700,
            fontWeight: FontWeight.w700,
          )),
    );
  }
}

/// 선택형 알약 칩.
class MedPill extends StatelessWidget {
  const MedPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? FoodietColors.coral500 : FoodietColors.cream50,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? FoodietColors.coral500 : FoodietColors.cream100,
          ),
        ),
        child: Text(label,
            style: FoodietText.bodySm.copyWith(
              color: selected ? Colors.white : FoodietColors.warm700,
              fontWeight: FontWeight.w700,
            )),
      ),
    );
  }
}

/// 탭하면 피커가 뜨는 값 표시 행.
class MedValueRow extends StatelessWidget {
  const MedValueRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: FoodietColors.cream50,
          borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
          border: Border.all(color: FoodietColors.cream100),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: FoodietColors.warm700),
            const SizedBox(width: 10),
            Text(label,
                style:
                    FoodietText.body.copyWith(color: FoodietColors.warm900)),
            const Spacer(),
            Text(value,
                style: FoodietText.body.copyWith(
                  color: onTap == null
                      ? FoodietColors.warm500
                      : FoodietColors.coral700,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
    );
  }
}

InputDecoration medInputDecoration(String hint, {String? suffix}) =>
    InputDecoration(
      hintText: hint,
      suffixText: suffix,
      isDense: true,
      filled: true,
      fillColor: FoodietColors.cream50,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        borderSide: const BorderSide(color: FoodietColors.cream100),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        borderSide: const BorderSide(color: FoodietColors.cream100),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        borderSide: const BorderSide(color: FoodietColors.coral300),
      ),
    );

/// 고정 고지 문구 박스.
class MedDisclaimer extends StatelessWidget {
  const MedDisclaimer({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: FoodietColors.cream50,
        borderRadius: BorderRadius.circular(FoodietShape.radiusMd),
        border: Border.all(color: FoodietColors.cream100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded,
                size: 16, color: FoodietColors.warm500),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(kMedicationDisclaimer,
                style: FoodietText.caption.copyWith(
                  color: FoodietColors.warm700,
                  fontWeight: FontWeight.w500,
                )),
          ),
        ],
      ),
    );
  }
}

void showMedSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? FoodietColors.danger : FoodietColors.warm700,
    ),
  );
}
