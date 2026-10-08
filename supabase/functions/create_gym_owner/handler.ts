type Json = Record<string, unknown>;

export class ApiError extends Error {
  constructor(public code: string, public status = 400) { super(code); }
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function object(value: unknown): Json {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new ApiError('invalid_record');
  return value as Json;
}

export function text(value: unknown, min: number, max: number): string {
  if (typeof value !== 'string' || value.trim().length < min || value.length > max) throw new ApiError('invalid_record');
  return value.trim();
}

export function uuid(value: unknown): string {
  if (typeof value !== 'string' || !uuidPattern.test(value)) throw new ApiError('invalid_record');
  return value;
}

export function validateCreate(input: Json) {
  const gym = object(input.gym);
  const name = text(gym.name, 2, 120);
  const code = text(gym.code, 3, 4).toUpperCase();
  const accent = text(gym.accent_color, 7, 7);
  const currency = text(gym.currency, 3, 3);
  const timezone = text(gym.timezone, 3, 80);
  const email = text(input.owner_email, 3, 254).toLowerCase();
  const ownerName = text(input.owner_name, 2, 120);
  const password = input.owner_password;
  if (!/^[A-Z]{3,4}$/.test(code) || !/^#[0-9a-f]{6}$/i.test(accent) || !['HTG', 'USD'].includes(currency) || !emailPattern.test(email)) throw new ApiError('invalid_record');
  if (typeof password !== 'string' || password.length < 12 || password.length > 128) throw new ApiError('weak_password');
  try { new Intl.DateTimeFormat('en', { timeZone: timezone }); } catch { throw new ApiError('invalid_record'); }
  const gymEmail = text(gym.email ?? '', 0, 254);
  if (gymEmail && !emailPattern.test(gymEmail)) throw new ApiError('invalid_record');
  return {
    requestId: uuid(input.request_id), gymId: uuid(input.gym_id), staffId: uuid(input.staff_id), password,
    payload: {
      gym: { name, code, accent_color: accent, timezone, currency, address: text(gym.address ?? '', 0, 500), phone: text(gym.phone ?? '', 0, 32), email: gymEmail },
      owner_email: email, owner_name: ownerName,
    },
  };
}

export interface PlatformGateway {
  actor(token: string): Promise<string>;
  rpc(name: string, params: Json): Promise<unknown>;
  createUser(email: string, password: string, requestId: string): Promise<string>;
  resetOwner(gymId: string, actorId: string): Promise<void>;
}

export class SupabaseGateway implements PlatformGateway {
  constructor(private url: string, private serviceKey: string, private resetRedirect: string) {}

  protected async request(path: string, { token, body, method = 'POST' }: { token?: string; body?: Json; method?: string } = {}): Promise<unknown> {
    const response = await fetch(`${this.url}${path}`, {
      method, headers: { apikey: this.serviceKey, Authorization: `Bearer ${token ?? this.serviceKey}`, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20_000),
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      const details = result && typeof result === 'object' && !Array.isArray(result) ? result as Json : {};
      const code = typeof details.code === 'string' ? details.code : null;
      const message = typeof details.message === 'string' ? details.message : typeof details.msg === 'string' ? details.msg : null;
      const authCode = typeof details.error_code === 'string' ? details.error_code : null;
      if (code === '42501' || response.status === 401 || response.status === 403) throw new ApiError('access_denied', 403);
      if (authCode === 'email_exists' || authCode === 'user_already_exists' || code === 'user_already_exists') throw new ApiError('owner_exists', 409);
      if (message === 'duplicate_code') throw new ApiError('duplicate_code', 409);
      if (message === 'owner_exists') throw new ApiError('owner_exists', 409);
      if (message === 'owner_missing') throw new ApiError('owner_missing', 404);
      if (message === 'request_mismatch') throw new ApiError('request_mismatch', 409);
      if (message === 'rate_limited') throw new ApiError('rate_limited', 429);
      if (code === '23505') throw new ApiError('duplicate', 409);
      if (code === '40001') throw new ApiError('conflict', 409);
      if (code === '22023') throw new ApiError('invalid_record');
      if (response.status === 429) throw new ApiError('rate_limited', 429);
      throw new ApiError('provision_failed', 502);
    }
    return result;
  }

  protected async authenticatedUser(token: string): Promise<string> {
    return uuid(object(await this.request('/auth/v1/user', { method: 'GET', token })).id);
  }

  async actor(token: string): Promise<string> {
    const userId = await this.authenticatedUser(token);
    const rows = await this.request(`/rest/v1/staff?user_id=eq.${userId}&role=eq.super_admin&active=eq.true&deleted_at=is.null&select=id`, { method: 'GET' });
    if (!Array.isArray(rows) || rows.length !== 1) throw new ApiError('access_denied', 403);
    return userId;
  }

  rpc(name: string, params: Json): Promise<unknown> {
    return this.request(`/rest/v1/rpc/${name}`, { body: params });
  }

  async createUser(email: string, password: string, requestId: string): Promise<string> {
    const user = object(await this.request('/auth/v1/admin/users', { body: {
      email, password, email_confirm: true, app_metadata: { gymdesk_provision_request: requestId },
    } }));
    return uuid(user.id);
  }

  async resetOwner(gymId: string, actorId: string): Promise<void> {
    let redirect: URL;
    try { redirect = new URL(this.resetRedirect); } catch { throw new ApiError('reset_not_configured', 503); }
    if (redirect.protocol !== 'https:' || redirect.username || redirect.password || redirect.hash) throw new ApiError('reset_not_configured', 503);
    const email = text(await this.rpc('platform_request_owner_reset', { p_actor: actorId, p_gym: gymId }), 3, 254);
    await this.request(`/auth/v1/recover?redirect_to=${encodeURIComponent(this.resetRedirect)}`, { body: { email } });
  }
}

async function readJson(request: Request): Promise<Json> {
  const reader = request.body?.getReader();
  if (!reader) throw new ApiError('invalid_record');
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > 32768) { await reader.cancel(); throw new ApiError('invalid_record', 413); }
    chunks.push(value);
  }
  const data = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.length; }
  try { return object(JSON.parse(new TextDecoder().decode(data))); } catch { throw new ApiError('invalid_record'); }
}

export function authorizedHandler(gateway: Pick<PlatformGateway, 'actor'>, allowedOrigins: ReadonlySet<string>, handle: (input: Json, actor: string) => Promise<Json>) {
  return async (request: Request): Promise<Response> => {
    const origin = request.headers.get('Origin');
    const headers: Record<string, string> = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', Vary: 'Origin' };
    if (origin && allowedOrigins.has(origin)) {
      headers['Access-Control-Allow-Origin'] = origin;
      headers['Access-Control-Allow-Headers'] = 'authorization, apikey, content-type, x-client-info';
      headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS';
    }
    const reply = (body: Json, status = 200) => new Response(JSON.stringify(body), { status, headers });
    try {
      if (origin && !allowedOrigins.has(origin)) throw new ApiError('origin_denied', 403);
      if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
      if (request.method !== 'POST') throw new ApiError('method_not_allowed', 405);
      const bearer = request.headers.get('Authorization');
      if (!bearer?.startsWith('Bearer ') || bearer.length > 8192) throw new ApiError('access_denied', 401);
      const actor = await gateway.actor(bearer.substring(7));
      const input = await readJson(request);
      return reply(await handle(input, actor));
    } catch (error) {
      return error instanceof ApiError ? reply({ error: error.code }, error.status) : reply({ error: 'network' }, 503);
    }
  };
}

export function createHandler(gateway: PlatformGateway, allowedOrigins: ReadonlySet<string>) {
  return authorizedHandler(gateway, allowedOrigins, async (input, actor) => {
    if (input.action === 'reset_owner') {
      await gateway.resetOwner(uuid(input.gym_id), actor);
      return { ok: true };
    }
    if (input.action !== 'create') throw new ApiError('invalid_record');
    const command = validateCreate(input);
    const record = object(await gateway.rpc('provision_gym_begin', {
      p_request: command.requestId, p_actor: actor, p_gym: command.gymId, p_staff: command.staffId, p_payload: command.payload,
    }));
    let owner = record.owner_user_id ?? await gateway.rpc('provision_gym_auth_user', { p_request: command.requestId, p_actor: actor });
    if (!owner) {
      try { owner = await gateway.createUser(command.payload.owner_email, command.password, command.requestId); } catch (error) {
        owner = await gateway.rpc('provision_gym_auth_user', { p_request: command.requestId, p_actor: actor });
        if (!owner) throw error;
      }
    }
    return { gym: await gateway.rpc('provision_gym_finish', { p_request: command.requestId, p_actor: actor, p_owner_user: uuid(owner) }) };
  });
}
