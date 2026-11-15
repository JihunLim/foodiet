import assert from 'node:assert/strict';
import { hasStarveAdvice, unsafeText } from '../_shared/safety.ts';

Deno.test('굶기·끼니 거르기 권유는 잡는다 (조사 변형 포함)', () => {
  for (const s of [
    '저녁은 거르기',
    '아침도 건너뛰기',
    '저녁 한 끼 건너뛰기',
    '점심은 안 먹기',
    '오늘 저녁은 가볍게 건너뛰어도 돼',
    '식사를 빼먹기',
    '하루 굶어보자',
    '16시간 단식 해보자',
    '다음 날 아침은 거르고 점심부터',
  ]) assert.equal(hasStarveAdvice(s), true, s);
});

Deno.test('부정형(굶지 말고·거르지 않기)은 통과', () => {
  for (const s of [
    '아침을 거르지 않기',
    '배고프면 굶지 말고 단백질 간식 먹기',
    '끼니 거르지 말고 가볍게라도 먹기',
    '식사를 빼먹지 않기',
    '저녁은 채소부터 먹기',
    '저녁 먹고 야식 건너뛰기',
    '야식은 생략하고 물 한 잔',
    '간식 건너뛰기',
    '저녁에 밥 반 공기 빼기',
    '점심 국물은 생략하기',
  ]) assert.equal(hasStarveAdvice(s), false, s);
});

Deno.test('효과 보장·투약·금지어', () => {
  assert.equal(unsafeText('이대로면 한 달에 3kg 빠져'), true);
  assert.equal(unsafeText('살이 쭉 빠질 거야'), true);
  assert.equal(unsafeText('주사 맞은 날이라 적게 먹은 거 잘했어'), true);
  assert.equal(unsafeText('위고비 용량 올려봐'), true);
  assert.equal(unsafeText('오늘은 망쳤다'), true);
  assert.equal(unsafeText('단백질이 든든하게 들어갔네!'), false);
  assert.equal(unsafeText(42), false);
});
