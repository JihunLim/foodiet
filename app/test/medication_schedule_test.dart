import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/features/medication/medication_page.dart';
import 'package:foodiet/features/medication/medication_widgets.dart';
import 'package:foodiet/providers/medication_provider.dart';
import 'package:foodiet/services/medication_schedule.dart';

Widget _page({MedicationPlan? plan, List<MedicationLog> logs = const []}) =>
    ProviderScope(
      overrides: [
        medicationPlanProvider.overrideWith((ref) async => plan),
        medicationLogsProvider.overrideWith((ref) async => logs),
      ],
      child: const MaterialApp(home: MedicationPage()),
    );

void main() {
  group('nextDueDate', () {
    test('자정 직전 투약도 로컬 날짜 기준 + 간격', () {
      final due = nextDueDate(
        lastTakenLocal: DateTime(2026, 11, 10, 23, 30),
        intervalDays: 7,
      );
      expect(due, DateTime(2026, 11, 17));
    });

    test('자정 직후 투약은 그날 기준', () {
      final due = nextDueDate(
        lastTakenLocal: DateTime(2026, 11, 11, 0, 10),
        intervalDays: 7,
      );
      expect(due, DateTime(2026, 11, 18));
    });

    test('기록 없음 + 시작일 → 시작일(시각 버림)', () {
      final due = nextDueDate(
        intervalDays: 7,
        startDateLocal: DateTime(2026, 11, 20, 15, 0),
      );
      expect(due, DateTime(2026, 11, 20));
    });

    test('둘 다 없음 → null', () {
      expect(nextDueDate(intervalDays: 7), isNull);
    });

    test('예정 시작일보다 일찍 맞아도 기록 기준', () {
      final due = nextDueDate(
        lastTakenLocal: DateTime(2026, 11, 19, 21),
        intervalDays: 7,
        startDateLocal: DateTime(2026, 11, 20),
      );
      expect(due, DateTime(2026, 11, 26));
    });

    test('기록이 있으면 시작일보다 기록 기준', () {
      final due = nextDueDate(
        lastTakenLocal: DateTime(2026, 11, 10, 9),
        intervalDays: 14,
        startDateLocal: DateTime(2026, 11, 3),
      );
      expect(due, DateTime(2026, 11, 24));
    });

    test('쉬었다가 새 시작일을 정하면 옛 기록보다 시작일', () {
      final due = nextDueDate(
        lastTakenLocal: DateTime(2026, 8, 1, 9),
        intervalDays: 7,
        startDateLocal: DateTime(2026, 11, 20),
      );
      expect(due, DateTime(2026, 11, 20));
    });
  });

  group('dueInDays / dueLabel', () {
    test('남은 날·지난 날', () {
      final today = DateTime(2026, 11, 16, 22, 0);
      expect(dueInDays(DateTime(2026, 11, 18), today), 2);
      expect(dueInDays(DateTime(2026, 11, 16), today), 0);
      expect(dueInDays(DateTime(2026, 11, 14), today), -2);
      expect(dueInDays(null, today), isNull);
    });

    test('월 경계도 날짜 단위로', () {
      expect(dueInDays(DateTime(2026, 12, 1), DateTime(2026, 11, 30, 23, 59)),
          1);
    });

    test('라벨', () {
      expect(dueLabel(0), '오늘');
      expect(dueLabel(-2), '2일 지남');
      expect(dueLabel(3), 'D-3');
      expect(dueLabel(null), '-');
    });
  });

  group('상수·라벨', () {
    test('약 이름', () {
      expect(drugLabel('wegovy'), '위고비');
      expect(drugLabel('mounjaro'), '마운자로');
      expect(drugLabel('other', custom: '삭센다'), '삭센다');
      expect(drugLabel('other'), '기타');
    });

    test('용량 프리셋', () {
      expect(kWegovyDoses, [0.25, 0.5, 1.0, 1.7, 2.4]);
      expect(kMounjaroDoses, [2.5, 5.0, 7.5, 10.0, 12.5, 15.0]);
      expect(dosePresets('other'), isEmpty);
    });

    test('용량 표기', () {
      expect(formatDose(2.5), '2.5mg');
      expect(formatDose(10.0), '10mg');
      expect(formatDose(0.25), '0.25mg');
    });

    test('용량 입력 파싱', () {
      expect(parseDose('2.5'), 2.5);
      expect(parseDose(' 0,25 '), 0.25);
      expect(parseDose('0'), isNull);
      expect(parseDose('-1'), isNull);
      expect(parseDose('abc'), isNull);
      expect(parseDose('1000'), isNull);
      expect(doseInputText(10.0), '10');
    });

    test('알림 시각', () {
      expect(reminderAt(DateTime(2026, 11, 17), 9), DateTime(2026, 11, 17, 9));
      expect(reminderAt(null, 9), isNull);
    });

    test('고지 문구', () {
      expect(kMedicationDisclaimer,
          '기록·알림 도구야. 용량 변경이나 투약을 놓쳤을 때는 처방한 의료진의 안내를 따라줘.');
    });
  });

  group('계획 모델', () {
    test('fromJson — numeric 문자열·start_date', () {
      final p = MedicationPlan.fromJson({
        'drug': 'mounjaro',
        'current_dose_mg': '7.500',
        'interval_days': 7,
        'start_date': '2026-11-20',
        'reminder_hour': 21,
      });
      expect(p.currentDoseMg, 7.5);
      expect(p.startDate, DateTime(2026, 11, 20));
      expect(p.reminderHour, 21);
      expect(p.coachContext, isTrue);
      expect(p.displayName, '마운자로');
    });

    test('computeMedicationDue — 기록 기준 D-day', () {
      const plan = MedicationPlan(drug: 'wegovy', currentDoseMg: 1.0);
      final due = computeMedicationDue(
          plan, DateTime(2026, 11, 10, 23, 30), DateTime(2026, 11, 16, 8));
      expect(due.due, DateTime(2026, 11, 17));
      expect(due.label, 'D-1');
    });

    test('toRow — other 이름·start_date 문자열', () {
      final row = MedicationPlan(
        drug: 'other',
        drugLabel: ' 삭센다 ',
        currentDoseMg: 1.2,
        startDate: DateTime(2026, 1, 5),
      ).toRow('u1');
      expect(row['drug_label'], '삭센다');
      expect(row['start_date'], '2026-01-05');
      expect(row['user_id'], 'u1');
    });
  });

  group('MedicationPage', () {
    testWidgets('미설정이면 소개 + 시작하기 + 고지', (tester) async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();
      expect(find.text('시작하기'), findsOneWidget);
      expect(find.text(kMedicationDisclaimer), findsOneWidget);
    });

    testWidgets('켜져 있으면 D-day·기록·고지', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(_page(
        plan: const MedicationPlan(drug: 'wegovy', currentDoseMg: 1.7),
        logs: [
          MedicationLog(
            id: 'l1',
            drug: 'wegovy',
            doseMg: 1.7,
            takenAt: DateTime(now.year, now.month, now.day - 9, 9),
            site: 'abdomen',
          ),
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.text('2일 지남'), findsOneWidget);
      expect(find.text('오늘 맞았어'), findsOneWidget);
      expect(find.textContaining('복부'), findsOneWidget);
      expect(find.text(kMedicationDisclaimer), findsOneWidget);
    });

    testWidgets('기록 조회 실패면 시작일로 D-day 를 계산하지 않고 재시도', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          medicationPlanProvider.overrideWith((ref) async => MedicationPlan(
                drug: 'wegovy',
                currentDoseMg: 1.0,
                startDate: DateTime(now.year, now.month, now.day - 30),
              )),
          medicationLogsProvider.overrideWith(
              (ref) => Future<List<MedicationLog>>.error(Exception('offline'))),
        ],
        child: const MaterialApp(home: MedicationPage()),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('일 지남'), findsNothing);
      expect(find.text('다시 불러오기'), findsOneWidget);
      expect(find.text(kMedicationDisclaimer), findsOneWidget);
    });

    testWidgets('계획 조회 실패면 시작하기 대신 재시도', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          medicationPlanProvider.overrideWith(
              (ref) => Future<MedicationPlan?>.error(Exception('offline'))),
          medicationLogsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: MedicationPage()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('시작하기'), findsNothing);
      expect(find.text('다시 불러오기'), findsOneWidget);
    });

    testWidgets('꺼둔 계획 다시 켜기 → 시작일 기본값은 오늘', (tester) async {
      await tester.pumpWidget(_page(
        plan: MedicationPlan(
          drug: 'wegovy',
          currentDoseMg: 1.0,
          startDate: DateTime(2026, 1, 5),
          active: false,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다시 켜기'));
      await tester.pumpAndSettle();
      expect(find.text(medDateLabel(DateTime.now())), findsOneWidget);
    });

    testWidgets('시작하기 → 설정 시트 (프리셋 탭 시 저장 활성)', (tester) async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();
      await tester.tap(find.text('시작하기'));
      await tester.pumpAndSettle();
      expect(find.text('투약 관리 시작하기'), findsOneWidget);
      expect(find.text('0.25mg'), findsOneWidget);
      await tester.tap(find.text('마운자로'));
      await tester.pumpAndSettle();
      expect(find.text('2.5mg'), findsOneWidget);
      expect(find.text('푸디 조언에 GLP-1 사용 여부만 반영'), findsOneWidget);
    });

    testWidgets('오늘 맞았어 → 기록 시트 기본 용량', (tester) async {
      await tester.pumpWidget(_page(
        plan: const MedicationPlan(drug: 'mounjaro', currentDoseMg: 7.5),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('오늘 맞았어'));
      await tester.pumpAndSettle();
      expect(find.text('투약 기록'), findsWidgets);
      expect(find.widgetWithText(TextField, '7.5'), findsOneWidget);
      expect(find.text('허벅지'), findsOneWidget);
    });
  });
}
