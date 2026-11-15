import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiet/features/checkin/checkin_share_card.dart';
import 'package:foodiet/features/checkin/weekly_checkin_page.dart';
import 'package:foodiet/providers/weekly_checkin_provider.dart';
import 'package:foodiet/widgets/primary_button.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ko'));

  group('weekStartFor', () {
    test('일 23:00 → 이번 주 월요일', () {
      // 2026-11-15 은 일요일.
      expect(weekStartFor(DateTime(2026, 11, 15, 23)), DateTime(2026, 11, 9));
    });
    test('월 09:00 → 지난 주 월요일', () {
      expect(weekStartFor(DateTime(2026, 11, 16, 9)), DateTime(2026, 11, 9));
    });
    test('일 16:59 → 지난 주 월요일', () {
      expect(
          weekStartFor(DateTime(2026, 11, 15, 16, 59)), DateTime(2026, 11, 2));
    });
    test('일 17:00 → 이번 주 월요일', () {
      expect(weekStartFor(DateTime(2026, 11, 15, 17)), DateTime(2026, 11, 9));
    });
    test('수 23:59 → 지난 주 월요일 (월 경계 넘어감)', () {
      // 2026-12-02 수 → 11-23 월
      expect(weekStartFor(DateTime(2026, 12, 2, 23, 59)), DateTime(2026, 11, 23));
    });
  });

  group('shouldShowCheckinPrompt', () {
    test('창 경계: 수 23:59 true, 목 00:00 false', () {
      expect(shouldShowCheckinPrompt(DateTime(2026, 11, 18, 23, 59), null),
          isTrue);
      expect(shouldShowCheckinPrompt(DateTime(2026, 11, 19), null), isFalse);
    });
    test('일 16:59 false, 일 17:00 true', () {
      expect(shouldShowCheckinPrompt(DateTime(2026, 11, 15, 16, 59), null),
          isFalse);
      expect(
          shouldShowCheckinPrompt(DateTime(2026, 11, 15, 17), null), isTrue);
    });
    test('완료했으면 false', () {
      final done = WeeklyCheckin(
        weekStart: DateTime(2026, 11, 9),
        completedAt: DateTime(2026, 11, 16, 10),
        chosenExperiment: '물 먼저',
      );
      expect(shouldShowCheckinPrompt(DateTime(2026, 11, 16, 12), done),
          isFalse);
    });
    test('생성만 되고 미완료면 true', () {
      final pending = WeeklyCheckin(weekStart: DateTime(2026, 11, 9));
      expect(shouldShowCheckinPrompt(DateTime(2026, 11, 16, 12), pending),
          isTrue);
    });
    test('지난 체크인 주의 완료 기록은 이번 창에 영향 없음', () {
      final old = WeeklyCheckin(
        weekStart: DateTime(2026, 11, 2),
        completedAt: DateTime(2026, 11, 9, 10),
      );
      expect(shouldShowCheckinPrompt(DateTime(2026, 11, 16, 12), old),
          isTrue);
    });
    test('기록 부족(insufficient)이면 false', () {
      final sparse =
          WeeklyCheckin(weekStart: DateTime(2026, 11, 9), insufficient: true);
      expect(shouldShowCheckinPrompt(DateTime(2026, 11, 16, 12), sparse),
          isFalse);
    });
  });

  group('WeeklyCheckin.fromJson', () {
    test('정상 응답', () {
      final c = WeeklyCheckin.fromJson({
        'week_start': '2026-11-09',
        'report': {
          'emoji': '🌱',
          'headline': '꾸준한 한 주',
          'wins': ['7일 기록', '단백질'],
          'pattern': '주말 저녁이 컸어.',
          'experiments': [
            {'if_then': 'A 하면 B 하기', 'why': '이유'},
            {'if_then': 'C', 'why': 'D'},
            {'if_then': 'E', 'why': 'F'},
          ],
          'note': '같이 가보자',
          'days_logged': 6,
        },
        'chosen_experiment': null,
        'completed_at': null,
      });
      expect(c.weekStart, DateTime(2026, 11, 9));
      expect(c.insufficient, isFalse);
      expect(c.report!.experiments.length, 3);
      expect(c.report!.experiments.first.ifThen, 'A 하면 B 하기');
      expect(c.report!.daysLogged, 6);
      expect(c.isCompleted, isFalse);
    });
    test('기록 부족 응답', () {
      final c = WeeklyCheckin.fromJson({
        'insufficient': true,
        'week_start': '2026-11-09',
        'days_logged': 1,
        'headline': '기록이 쌓이면 같이 돌아보자',
        'report': null,
      });
      expect(c.insufficient, isTrue);
      expect(c.report, isNull);
      expect(c.headline, '기록이 쌓이면 같이 돌아보자');
    });
    test('깨진 report 는 예외 없이 null', () {
      final c = WeeklyCheckin.fromJson({
        'week_start': '2026-11-09',
        'report': {'headline': 3, 'experiments': 'x'},
        'completed_at': '2026-11-16T01:00:00Z',
        'chosen_experiment': '물 먼저',
      });
      expect(c.report, isNull);
      expect(c.isCompleted, isTrue);
      expect(c.chosenExperiment, '물 먼저');
    });
    test('DB 행(report_json) 모양도 읽는다', () {
      final c = WeeklyCheckin.fromJson({
        'week_start': '2026-11-09',
        'report_json': {
          'emoji': '🌿',
          'headline': 'h',
          'wins': ['w'],
          'pattern': 'p',
          'experiments': [
            {'if_then': 'x', 'why': 'y'}
          ],
          'note': '',
        },
      });
      expect(c.report!.headline, 'h');
    });
  });

  group('WeeklyCheckinPage', () {
    final report = CheckinReport.fromJson({
      'emoji': '🌱',
      'headline': '꾸준한 한 주',
      'wins': ['7일 기록했어'],
      'pattern': '주말 저녁이 평일보다 컸어.',
      'experiments': [
        {'if_then': '국물은 반만 먹기', 'why': '나트륨'},
        {'if_then': '물 먼저 마시기', 'why': '허기 구분'},
        {'if_then': '단백질 반찬 하나 더', 'why': '포만감'},
      ],
      'note': '같이 가보자',
      'days_logged': 6,
    })!;

    Future<void> pump(WidgetTester t, WeeklyCheckin c) async {
      // 작은 폰 폭 + 긴 화면 — ListView 의 아래쪽 항목까지 빌드되게.
      t.view.physicalSize = const Size(360, 2000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [weeklyCheckinProvider.overrideWith((ref) async => c)],
        child: const MaterialApp(home: WeeklyCheckinPage()),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('리포트: 실험 고르기 전엔 버튼 비활성, 고르면 활성', (t) async {
      await pump(t, WeeklyCheckin(weekStart: DateTime(2026, 11, 9), report: report));
      expect(find.text('꾸준한 한 주'), findsOneWidget);
      expect(find.text('7일 중 6일 기록'), findsOneWidget);
      expect(find.text('11월 9일 ~ 11월 15일'), findsOneWidget);
      PrimaryButton submit() => t.widget<PrimaryButton>(find.ancestor(
          of: find.text('이번 주 이걸로 해볼게'),
          matching: find.byType(PrimaryButton)));
      expect(submit().onPressed, isNull);
      await t.tap(find.text('물 먼저 마시기'));
      await t.pump();
      expect(submit().onPressed, isNotNull);
      expect(t.takeException(), isNull);
    });

    testWidgets('완료된 주: 고른 실험 + 공유 버튼', (t) async {
      await pump(
          t,
          WeeklyCheckin(
            weekStart: DateTime(2026, 11, 9),
            report: report,
            chosenExperiment: '물 먼저 마시기',
            completedAt: DateTime(2026, 11, 16),
          ));
      expect(find.text('친구에게 공유하기'), findsOneWidget);
      expect(find.text('실험 바꾸기'), findsOneWidget);
    });

    testWidgets('기록 부족: 고정 문구만', (t) async {
      await pump(
          t,
          WeeklyCheckin(
            weekStart: DateTime(2026, 11, 9),
            insufficient: true,
            headline: '기록이 쌓이면 같이 돌아보자',
            daysLogged: 1,
          ));
      expect(find.text('기록이 쌓이면 같이 돌아보자'), findsOneWidget);
      expect(find.text('이번 주 이걸로 해볼게'), findsNothing);
    });

    testWidgets('공유 카드가 360 폭에서 넘치지 않음', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Center(
          child: CheckinShareCard(
            data: CheckinShareData(
              weekStart: DateTime(2026, 11, 9),
              nickname: '지훈',
              report: report,
              experiment: '저녁 먹고 출출하면 따뜻한 차 마시기',
            ),
          ),
        ),
      ));
      expect(t.takeException(), isNull);
    });
  });
}
