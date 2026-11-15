/// LLM 출력 공통 안전 필터 — analyze-entry / home-coach / meal-suggest / weekly-checkin.
///
/// 프롬프트 규칙만으로는 새어 나올 수 있는 표현을 화면에 내보내기 전에 거른다.
///   * 금지 어휘 (부정·도덕적 평가)
///   * 효과 보장 ("3kg 빠져", "살이 쭉 빠져", "효과 보장")
///   * 굶기·끼니 거르기 권유 — 단 "굶지 말고", "거르지 않기" 같은 부정형은 통과
///   * 투약·약 이름 (GLP-1 용량·투약 조언 금지)
/// 걸리면 호출부가 문장을 버리고 고정 문구로 대체한다. 이 파일은 import 가 없는
/// 순수 모듈이라 테스트에서 바로 불러 쓸 수 있다.

export const BANNED = ['실패', '어겼다', '망쳤다', '해주세요', '나쁜 음식'];

const EFFICACY_RE = /\d+(?:\.\d+)?\s*(?:kg|킬로|키로)\s*(?:감량|빠|뺄|뺀)/i;
const EFFICACY_WORDS_RE =
  /살\s*(?:이\s*)?(?:쭉\s*|잘\s*|확\s*)?빠(?:지|져|진|짐|질)|(?:효과|감량)\s*보장/;

// 뒤에 "(먹)지 않/말/마" 가 오면 부정형(= 굶지 말라는 말)이라 통과.
const NOT_NEGATED = '(?![가-힣]{0,2}\\s*지\\s*(?:않|말|마))';
const FAST_RE = new RegExp(`(?:굶|단식)${NOT_NEGATED}`);
const MEAL_RE = /아침|점심|저녁|끼니|식사|한\s*끼/g;
const SKIP_RE = new RegExp(
  `(?:거르|거른|걸러|건너\\s*뛰|생략|빼먹|안\\s*먹)${NOT_NEGATED}`,
  'g',
);
// 끼니어와 동사 사이에 이런 말이 끼면 끼니가 아니라 그걸 거르는 얘기 —
// "저녁 먹고 야식 건너뛰기", "저녁 국물은 생략" 은 정상 실험이다.
const NON_MEAL_BETWEEN =
  /야식|간식|술|음료|디저트|커피|과자|밥|국물|소스|양념|반찬|튀김|면|설탕|[.,!?\n]/;
const SKIP_WINDOW = 12;
const MEDICATION_RE = /투약|주사|용량|위고비|마운자로|오젬픽|삭센다|젭바운드/;

export function hasBannedWord(s: string): boolean {
  return BANNED.some((b) => s.includes(b));
}

export function hasEfficacyClaim(s: string): boolean {
  return EFFICACY_RE.test(s) || EFFICACY_WORDS_RE.test(s);
}

export function hasStarveAdvice(s: string): boolean {
  if (FAST_RE.test(s)) return true;
  for (const meal of s.matchAll(MEAL_RE)) {
    const from = (meal.index ?? 0) + meal[0].length;
    const window = s.slice(from, from + SKIP_WINDOW + 6);
    SKIP_RE.lastIndex = 0;
    for (const verb of window.matchAll(SKIP_RE)) {
      const gap = window.slice(0, verb.index ?? 0);
      if ((verb.index ?? 0) <= SKIP_WINDOW && !NON_MEAL_BETWEEN.test(gap)) {
        return true;
      }
    }
  }
  return false;
}

export function hasMedicationTalk(s: string): boolean {
  return MEDICATION_RE.test(s);
}

/// 화면에 그대로 내보내면 안 되는 문장인가.
export function unsafeText(s: unknown): boolean {
  if (typeof s !== 'string') return false;
  return hasBannedWord(s) || hasEfficacyClaim(s) || hasStarveAdvice(s) ||
    hasMedicationTalk(s);
}
