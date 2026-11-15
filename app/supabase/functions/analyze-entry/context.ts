// analyze-entry 사용자 컨텍스트 — 순수 함수만 (테스트가 권한 없이 import).
//
// 피드백 개인화에 쓰는 값: 일일 목표 kcal, 이 끼니 전 오늘 섭취 kcal(1인분 환산),
// 실효 목표 모드, GLP-1 사용 여부(medication_plans.active && coach_context).
// 투약 기록·용량은 LLM 에 보내지 않는다.

export type GoalMode = 'lose' | 'maintain' | 'gain';

/// profiles.goal_mode 는 기본 'lose'. 'lose' 인데 목표 체중이 현재보다 무거우면
/// 실효 모드는 'gain' (spec 결정 사항). 모르는 값은 'lose' 로 본다.
export function effectiveGoalMode(
  mode: unknown,
  goalWeightKg: number | null | undefined,
  currentWeightKg: number | null | undefined,
): GoalMode {
  const m: GoalMode = mode === 'maintain' || mode === 'gain' ? mode : 'lose';
  if (
    m === 'lose' &&
    typeof goalWeightKg === 'number' && Number.isFinite(goalWeightKg) &&
    typeof currentWeightKg === 'number' && Number.isFinite(currentWeightKg) &&
    goalWeightKg > currentWeightKg
  ) {
    return 'gain';
  }
  return m;
}

/// `iso` 시각이 속한 로컬 날짜(오프셋 tzOffsetMin)의 00:00 을 UTC ISO 로.
export function localDayStartUtc(iso: string, tzOffsetMin: number): string {
  const shifted = new Date(new Date(iso).getTime() + tzOffsetMin * 60_000);
  const midnightLocalAsUtc = Date.UTC(
    shifted.getUTCFullYear(),
    shifted.getUTCMonth(),
    shifted.getUTCDate(),
  );
  return new Date(midnightLocalAsUtc - tzOffsetMin * 60_000).toISOString();
}

export type UserContext = {
  dailyKcalTarget: number | null;
  /// 이 끼니 전 오늘 섭취(1인분 환산). 조회 실패면 null.
  priorKcalToday: number | null;
  mode: GoalMode;
  glp1: boolean;
  sex: string | null;
  /// 이 사진의 식사를 몇 명이 나눠 먹었는지 (1 = 혼자).
  sharedWithCount: number;
};

const MODE_LABEL: Record<GoalMode, string> = {
  lose: '감량',
  maintain: '유지',
  gain: '증량',
};

/// user 프롬프트에 붙는 한 줄. 예:
/// `[사용자] 목표 1800 kcal · 이 끼니 전 오늘 640 kcal · 모드 감량 · 여성 · GLP-1 사용 중`
export function buildUserContextLine(c: UserContext): string {
  const parts: string[] = [];
  parts.push(
    c.dailyKcalTarget && c.dailyKcalTarget > 0
      ? `목표 ${Math.round(c.dailyKcalTarget)} kcal`
      : '목표 미설정',
  );
  if (c.priorKcalToday != null) {
    parts.push(`이 끼니 전 오늘 ${Math.round(c.priorKcalToday)} kcal`);
  }
  parts.push(`모드 ${MODE_LABEL[c.mode]}`);
  if (c.sex === 'male') parts.push('남성 (하한 1500 kcal)');
  else if (c.sex === 'female') parts.push('여성 (하한 1200 kcal)');
  else parts.push('성별 미입력 (하한 1200 kcal)');
  parts.push(c.glp1 ? 'GLP-1 사용 중' : 'GLP-1 미사용');
  if (c.sharedWithCount > 1) {
    parts.push(`이 식사는 ${c.sharedWithCount}명이 나눠 먹음 (사진 전체 기준으로 분석, 피드백은 1인분 관점)`);
  }
  return `[사용자] ${parts.join(' · ')}`;
}
