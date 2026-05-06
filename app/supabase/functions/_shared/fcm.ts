/// FCM HTTP v1 헬퍼 — Service Account JSON 으로 OAuth2 access token 을 발급해
/// `https://fcm.googleapis.com/v1/projects/{PID}/messages:send` 로 푸시.
///
/// **중요**: payload 는 `notification` + (optional) `data` 만 포함. `android`
/// 또는 `apns` custom block 을 추가하지 않는다.
///
/// - `apns.payload.aps.mutable-content: 1` 같은 옵션을 NotificationServiceExtension
///   없이 추가하면 iOS 가 silent drop.
/// - `android` 블록을 iOS 토큰 메시지에 같이 보내면 (FCM 도큐상 무시되어야 하지만)
///   실측 결과 APNs 단에서 silent drop. FCM 은 sent:1 로 200 응답 — 한참 디버깅
///   해야 잡히는 류의 문제. 확실히 드롭됨.
/// - 위 둘 다 안 넣고 `notification` + `data` 만 보내면 iOS, Android 양쪽 모두
///   FCM 이 자동으로 platform-specific 로 변환해 정상 발송. 가장 안전.
///
/// 환경 변수:
///   - `FCM_SERVICE_ACCOUNT_JSON` : Firebase Console → Project Settings →
///     Service accounts → "Generate new private key" 의 JSON 전체.
///   - `FCM_PROJECT_ID` : Firebase 프로젝트 ID (예: `foodiet-4f861`).

interface ServiceAccount {
  client_email: string;
  private_key: string;
  private_key_id: string;
  project_id: string;
}

interface FcmMessage {
  token: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}

let cachedToken: { value: string; expiresAt: number } | null = null;

function _b64url(bytes: Uint8Array): string {
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/=+$/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function _b64urlString(s: string): string {
  return _b64url(new TextEncoder().encode(s));
}

async function _importPrivateKey(pem: string): Promise<CryptoKey> {
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(cleaned), c => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

function _readServiceAccount(): ServiceAccount {
  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
  if (!raw) {
    throw new Error('FCM_SERVICE_ACCOUNT_JSON not set');
  }
  return JSON.parse(raw) as ServiceAccount;
}

export async function getFcmAccessToken(): Promise<string> {
  const now = Date.now();
  if (cachedToken && cachedToken.expiresAt > now + 60_000) {
    return cachedToken.value;
  }
  const sa = _readServiceAccount();

  const iat = Math.floor(now / 1000);
  const exp = iat + 3600;
  const header = { alg: 'RS256', typ: 'JWT', kid: sa.private_key_id };
  const claims = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat,
    exp,
  };
  const unsigned = `${_b64urlString(JSON.stringify(header))}.${_b64urlString(JSON.stringify(claims))}`;
  const key = await _importPrivateKey(sa.private_key);
  const sig = await crypto.subtle.sign(
    { name: 'RSASSA-PKCS1-v1_5' },
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${_b64url(new Uint8Array(sig))}`;

  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!r.ok) {
    const errBody = await r.text();
    throw new Error(`OAuth2 token exchange failed: ${r.status} ${errBody}`);
  }
  const j = (await r.json()) as { access_token: string; expires_in: number };
  cachedToken = {
    value: j.access_token,
    expiresAt: now + (j.expires_in - 60) * 1000,
  };
  return cachedToken.value;
}

export interface SendResult {
  ok: boolean;
  status: number;
  errorCode?: string;
  errorBody?: string;
}

export async function sendOne(msg: FcmMessage): Promise<SendResult> {
  const projectId = Deno.env.get('FCM_PROJECT_ID');
  if (!projectId) {
    return {
      ok: false,
      status: 500,
      errorCode: 'NO_PROJECT_ID',
      errorBody: 'FCM_PROJECT_ID env var not set',
    };
  }

  const token = await getFcmAccessToken();
  const message: Record<string, unknown> = {
    token: msg.token,
    notification: { title: msg.title, body: msg.body },
  };
  if (msg.data && Object.keys(msg.data).length > 0) {
    message.data = msg.data;
  }

  const r = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ message }),
    },
  );
  if (r.ok) return { ok: true, status: r.status };

  const errBody = await r.text();
  let errorCode: string | undefined;
  try {
    const parsed = JSON.parse(errBody);
    errorCode = parsed?.error?.status ?? parsed?.error?.message;
  } catch {/* not json */}
  return { ok: false, status: r.status, errorCode, errorBody: errBody };
}

export const STALE_TOKEN_CODES = new Set([
  'UNREGISTERED',
  'NOT_FOUND',
  'INVALID_ARGUMENT',
  'SENDER_ID_MISMATCH',
]);
