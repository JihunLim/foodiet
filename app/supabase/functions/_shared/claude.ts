/// Claude(Anthropic Messages API) 호출 헬퍼 — analyze-entry / home-coach /
/// generate-meal-plan 공용. 응답은 structured outputs 로 JSON 스키마에 강제한다.
///
/// 환경 변수 (Edge Function Secrets):
///   - `ANTHROPIC_API_KEY` : Anthropic API 키.
///   - `ANTHROPIC_MODEL`   : 모델 ID (기본 'claude-opus-5-5'). 재배포 없이 바꾸려면
///     secret 으로 덮어쓴다 (예: 'claude-sonnet-5-5', 'claude-haiku-5-5').
///
/// 주의:
///   - structured outputs 는 `minimum`/`maximum`/`minItems`/`maxItems`/`minLength`
///     등을 지원하지 않는다(400). 스키마엔 넣지 말고 description + 호출부 후처리로.
///   - Opus 5.5 는 thinking 을 끌 수 없고 effort 기본값이 'medium' 이다. 지연을
///     줄이려고 effort='low' 를 명시한다 (gpt-5.5 때 reasoning_effort='low' 와 같은 의도).
///   - 안전 분류기 오탐으로 거절되면 서버측 fallback('default')이 권장 모델로 한 번
///     더 돌린다. 그래도 거절이면 에러로 던진다.

import Anthropic from 'npm:@anthropic-ai/sdk@1.3.0';

export const CLAUDE_MODEL = Deno.env.get('ANTHROPIC_MODEL') ?? 'claude-opus-5-5';

const client = new Anthropic({
  apiKey: Deno.env.get('ANTHROPIC_API_KEY'),
  // Edge Function wall-clock(150s) 안에서 끝나야 한다. SDK 기본값(10분·재시도 2회)
  // 이면 429 한 번에 함수가 먼저 죽으므로 짧게.
  timeout: 120_000,
  maxRetries: 1,
});

export type ClaudeContent = Anthropic.Beta.Messages.BetaMessageContentParam;

/// 한 턴 호출 → JSON 스키마에 맞춘 응답을 파싱해 돌려준다. 실패는 모두 throw.
/// SDK 에러(Anthropic.APIError)는 `status` 를 그대로 들고 있다.
export async function claudeJson<T>(opts: {
  tag: string;
  system: string;
  content: ClaudeContent;
  schema: Record<string, unknown>;
  maxTokens?: number;
}): Promise<T> {
  const startedAt = Date.now();
  const msg = await client.beta.messages.create({
    model: CLAUDE_MODEL,
    max_tokens: opts.maxTokens ?? 16000,
    system: opts.system,
    messages: [{ role: 'user', content: opts.content }],
    output_config: {
      effort: 'low',
      format: { type: 'json_schema', schema: opts.schema },
    },
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
  });
  console.log(`claude[${opts.tag}] ` + JSON.stringify({
    model: msg.model,
    ms: Date.now() - startedAt,
    stop: msg.stop_reason,
    input: msg.usage.input_tokens,
    output: msg.usage.output_tokens,
  }));

  if (msg.stop_reason === 'refusal') {
    throw new Error(`Claude refusal: ${msg.stop_details?.category ?? 'unknown'}`);
  }
  if (msg.stop_reason === 'max_tokens') {
    throw new Error('Claude: max_tokens — JSON 이 잘렸다');
  }
  // thinking 블록이 앞에 올 수 있으므로 text 블록만 모은다.
  const text = msg.content
    .map((b) => (b.type === 'text' ? b.text : ''))
    .join('');
  if (!text) throw new Error('Claude: empty content');
  try {
    return JSON.parse(text) as T;
  } catch (e) {
    throw new Error(`Claude: invalid JSON: ${(e as Error).message}`);
  }
}
