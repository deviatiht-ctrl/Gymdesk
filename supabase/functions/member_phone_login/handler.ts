import { ApiError, object, originAllowed, SupabaseGateway, uuid } from '../create_gym_owner/handler.ts';

type Json = Record<string, unknown>;
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export interface PhoneLoginGateway {
  attempt(key: string): Promise<boolean>;
  member(gym: string, phone: string): Promise<{ id: string; email: string | null; firstName: string } | null>;
  accountUser(gym: string, memberId: string): Promise<string | null>;
  authUserByEmail(email: string): Promise<string | null>;
  userShared(user: string, gym: string, memberId: string): Promise<boolean>;
  createUser(email: string): Promise<string>;
  linkAccount(user: string, gym: string, memberId: string, email: string): Promise<void>;
  userEmail(user: string): Promise<string>;
  /** Jeton magiclink (hashed_token) sans envoi d'email. */
  magicToken(email: string): Promise<string>;
}

export class SupabasePhoneLoginGateway extends SupabaseGateway implements PhoneLoginGateway {
  constructor(url: string, serviceKey: string) {
    super(url, serviceKey, '');
  }

  private get(path: string): Promise<unknown> {
    return this.request(path, { method: 'GET' });
  }

  async attempt(key: string): Promise<boolean> {
    return await this.rpc('mp_phone_attempt', { p_key: key }) === true;
  }

  async member(gym: string, phone: string) {
    const rows = await this.rpc('mp_phone_member', { p_gym: gym, p_phone: phone });
    if (!Array.isArray(rows) || rows.length === 0) return null;
    const row = rows[0] as Json;
    return {
      id: uuid(row.member_id),
      email: typeof row.email === 'string' && emailPattern.test(row.email) ? row.email : null,
      firstName: typeof row.first_name === 'string' ? row.first_name : '',
    };
  }

  async accountUser(gym: string, memberId: string): Promise<string | null> {
    const rows = await this.get(`/rest/v1/member_accounts?gym_id=eq.${gym}&member_id=eq.${memberId}&select=user_id&limit=1`);
    return Array.isArray(rows) && rows.length > 0 ? uuid((rows[0] as Json).user_id) : null;
  }

  async authUserByEmail(email: string): Promise<string | null> {
    const result = object(await this.get(`/auth/v1/admin/users?filter=${encodeURIComponent(email)}&per_page=50`));
    const users = Array.isArray(result.users) ? result.users : [];
    const match = users.find((u) => String((u as Json).email).toLowerCase() === email);
    return match ? uuid((match as Json).id) : null;
  }

  async userShared(user: string, gym: string, memberId: string): Promise<boolean> {
    const staff = await this.get(`/rest/v1/staff?user_id=eq.${user}&select=id&limit=1`);
    if (Array.isArray(staff) && staff.length > 0) return true;
    const links = await this.get(`/rest/v1/member_accounts?user_id=eq.${user}&select=gym_id,member_id`);
    return Array.isArray(links) && links.some((row) => (row as Json).gym_id !== gym || (row as Json).member_id !== memberId);
  }

  override async createUser(email: string): Promise<string> {
    const password = crypto.randomUUID() + crypto.randomUUID();
    const user = object(await this.request('/auth/v1/admin/users', { body: {
      email, password, email_confirm: true, user_metadata: { securgym_member: true, phone_login: true },
    } }));
    return uuid(user.id);
  }

  async linkAccount(user: string, gym: string, memberId: string, email: string): Promise<void> {
    await this.request('/rest/v1/member_accounts', { body: { user_id: user, gym_id: gym, member_id: memberId, email } });
  }

  async userEmail(user: string): Promise<string> {
    const row = object(await this.get(`/auth/v1/admin/users/${user}`));
    if (typeof row.email !== 'string' || !emailPattern.test(row.email)) throw new ApiError('invalid_record', 500);
    return row.email.toLowerCase();
  }

  async magicToken(email: string): Promise<string> {
    const res = object(await this.request('/auth/v1/admin/generate_link', { body: { type: 'magiclink', email } }));
    const props = res.properties && typeof res.properties === 'object' ? res.properties as Json : {};
    const token = typeof res.hashed_token === 'string' ? res.hashed_token : props.hashed_token;
    if (typeof token !== 'string' || token.length < 10) throw new ApiError('provision_failed', 502);
    return token;
  }
}

export function phoneKey(phone: unknown): string {
  const digits = typeof phone === 'string' ? phone.replace(/\D/g, '') : '';
  return digits.length >= 8 && digits.length <= 15 ? digits.slice(-8) : '';
}

/** Compte Auth du membre (créé au besoin) puis jeton de connexion à usage unique. */
export async function phoneLogin(gateway: PhoneLoginGateway, input: Json): Promise<Json> {
  const gym = uuid(input.gym_id);
  const key = phoneKey(input.phone);
  if (!key) return { status: 'invalid_phone' };
  if (!await gateway.attempt(`phone:${gym}:${key}`)) return { status: 'too_many_attempts' };
  const member = await gateway.member(gym, key);
  if (!member) return { status: 'not_found' };

  let user = await gateway.accountUser(gym, member.id);
  if (!user) {
    let email: string | null = member.email;
    if (email) {
      const existing = await gateway.authUserByEmail(email);
      if (existing && !await gateway.userShared(existing, gym, member.id)) user = existing;
      else if (existing) email = null;
    }
    const linkEmail = email ?? `m.${member.id}@membres.securgym.com`;
    if (!user) user = await gateway.authUserByEmail(linkEmail) ?? await gateway.createUser(linkEmail);
    await gateway.linkAccount(user, gym, member.id, linkEmail);
  }
  const tokenHash = await gateway.magicToken(await gateway.userEmail(user));
  return { status: 'ok', token_hash: tokenHash, first_name: member.firstName };
}

export function createPhoneLoginHandler(gateway: PhoneLoginGateway, origins: ReadonlySet<string>) {
  return async (request: Request): Promise<Response> => {
    const origin = request.headers.get('Origin');
    const headers: Record<string, string> = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', Vary: 'Origin' };
    if (origin && originAllowed(origin, origins)) {
      headers['Access-Control-Allow-Origin'] = origin;
      headers['Access-Control-Allow-Headers'] = 'authorization, apikey, content-type, x-client-info';
      headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS';
    }
    const reply = (body: Json, status = 200) => new Response(JSON.stringify(body), { status, headers });
    try {
      if (!originAllowed(origin, origins)) throw new ApiError('origin_denied', 403);
      if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
      if (request.method !== 'POST') throw new ApiError('method_not_allowed', 405);
      const raw = await request.text();
      if (raw.length > 4096) throw new ApiError('invalid_record');
      let input: Json;
      try { input = object(JSON.parse(raw)); } catch { throw new ApiError('invalid_record'); }
      return reply(await phoneLogin(gateway, input));
    } catch (error) {
      return error instanceof ApiError ? reply({ error: error.code }, error.status) : reply({ error: 'network' }, 503);
    }
  };
}
