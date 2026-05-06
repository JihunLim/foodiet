/// Edge Function 안에서 service-role 권한으로 Supabase REST 를 부르는 헬퍼.
///
/// `SUPABASE_URL` 과 `SUPABASE_SERVICE_ROLE_KEY` 는 모든 Edge Function 런타임에
/// 자동 주입돼 있어 (대시보드에서 별도 secret 설정 불필요).

const _url = Deno.env.get('SUPABASE_URL') ?? '';
const _key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const _headers = {
  Authorization: `Bearer ${_key}`,
  apikey: _key,
  'Content-Type': 'application/json',
};

export async function srSelect(
  table: string,
  query: string,
): Promise<unknown[]> {
  const r = await fetch(`${_url}/rest/v1/${table}?${query}`, {
    headers: _headers,
  });
  if (!r.ok) {
    throw new Error(`select ${table} failed ${r.status}: ${await r.text()}`);
  }
  return await r.json();
}

export async function srInsert(
  table: string,
  rows: Record<string, unknown> | Record<string, unknown>[],
): Promise<unknown> {
  const r = await fetch(`${_url}/rest/v1/${table}`, {
    method: 'POST',
    headers: { ..._headers, Prefer: 'return=minimal' },
    body: JSON.stringify(rows),
  });
  if (!r.ok) {
    throw new Error(`insert ${table} failed ${r.status}: ${await r.text()}`);
  }
  return null;
}

export async function srDelete(table: string, query: string): Promise<void> {
  const r = await fetch(`${_url}/rest/v1/${table}?${query}`, {
    method: 'DELETE',
    headers: _headers,
  });
  if (!r.ok) {
    throw new Error(`delete ${table} failed ${r.status}: ${await r.text()}`);
  }
}
