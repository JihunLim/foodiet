/// GLP-1 투약 일정 — 순수 함수와 상수.
///
/// 기록·알림 도구일 뿐이다. 용량 증감·놓친 투약 처리 같은 의료 조언은 하지 않는다
/// (화면에는 항상 [kMedicationDisclaimer] 를 고정 노출).
///
/// 날짜 계산은 모두 **로컬 날짜(시각 버림)** 기준이다. 자정 직전/직후 투약이
/// 다른 날로 밀리지 않게 taken_at 은 호출 쪽에서 `toLocal()` 해서 넘긴다.
library;

/// 화면 하단 고정 고지 문구.
const String kMedicationDisclaimer =
    '기록·알림 도구야. 용량 변경이나 투약을 놓쳤을 때는 처방한 의료진의 안내를 따라줘.';

/// 위고비(세마글루타이드) 펜 용량 프리셋 (mg).
const List<double> kWegovyDoses = [0.25, 0.5, 1.0, 1.7, 2.4];

/// 마운자로(터제파타이드) 펜 용량 프리셋 (mg).
const List<double> kMounjaroDoses = [2.5, 5.0, 7.5, 10.0, 12.5, 15.0];

/// medication_plans.drug 허용 값.
const List<String> kMedicationDrugs = ['wegovy', 'mounjaro', 'other'];

/// medication_logs.site 허용 값 → 표시 이름.
const Map<String, String> kInjectionSites = {
  'abdomen': '복부',
  'thigh': '허벅지',
  'arm': '팔',
};

String drugLabel(String drug, {String? custom}) {
  switch (drug) {
    case 'wegovy':
      return '위고비';
    case 'mounjaro':
      return '마운자로';
    default:
      final c = custom?.trim();
      return (c == null || c.isEmpty) ? '기타' : c;
  }
}

List<double> dosePresets(String drug) {
  switch (drug) {
    case 'wegovy':
      return kWegovyDoses;
    case 'mounjaro':
      return kMounjaroDoses;
    default:
      return const [];
  }
}

/// 2.5 → '2.5mg', 10.0 → '10mg', 0.25 → '0.25mg'.
String formatDose(double mg) {
  var s = mg.toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  return '${s}mg';
}

/// 2.5 → '2.5' (입력 필드 기본값용, 단위 없이).
String doseInputText(double mg) => formatDose(mg).replaceAll('mg', '');

/// 사용자 입력 용량 파싱. 0 < x < 1000 (DB numeric(6,3)) 만, 소수 셋째 자리까지.
double? parseDose(String raw) {
  final v = double.tryParse(raw.trim().replaceAll(',', '.'));
  if (v == null || !v.isFinite || v <= 0 || v >= 1000) return null;
  return double.parse(v.toStringAsFixed(3));
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 다음 투약 예정일(로컬 날짜, 00:00).
///
/// - 마지막 투약 기록이 있으면 그 로컬 날짜 + [intervalDays] (예정보다 하루 일찍
///   맞아도 실제 기록 기준으로 이어간다).
/// - 단, 시작일이 그보다 뒤면 시작일 — 쉬었다가 다시 켜며 새 시작일을 정한 경우
///   옛 기록 때문에 '지남'으로 남고 알림이 영영 안 걸리는 것을 막는다.
/// - 기록이 없으면 시작일, 둘 다 없으면 null.
DateTime? nextDueDate({
  DateTime? lastTakenLocal,
  required int intervalDays,
  DateTime? startDateLocal,
}) {
  final start = startDateLocal == null ? null : _dateOnly(startDateLocal);
  if (lastTakenLocal == null) return start;
  final last = _dateOnly(lastTakenLocal);
  // DateTime 생성자로 일 단위 더하기 — Duration 덧셈은 DST 지역에서 시각이 어긋난다.
  final fromLog = DateTime(last.year, last.month, last.day + intervalDays);
  if (start != null && start.isAfter(fromLog)) return start;
  return fromLog;
}

/// 예정일까지 남은 날 수 (0 = 오늘, 음수 = 지남). due 가 없으면 null.
int? dueInDays(DateTime? due, DateTime todayLocal) {
  if (due == null) return null;
  final a = DateTime.utc(due.year, due.month, due.day);
  final b = DateTime.utc(todayLocal.year, todayLocal.month, todayLocal.day);
  return a.difference(b).inDays;
}

/// 'D-2' / '오늘' / '2일 지남' / '-'. 지난 경우에도 조언 문구는 붙이지 않는다.
String dueLabel(int? d) {
  if (d == null) return '-';
  if (d == 0) return '오늘';
  if (d > 0) return 'D-$d';
  return '${-d}일 지남';
}

/// 예정일의 알림 시각(로컬).
DateTime? reminderAt(DateTime? due, int hour) {
  if (due == null) return null;
  return DateTime(due.year, due.month, due.day, hour);
}
