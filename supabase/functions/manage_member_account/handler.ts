import { ApiError, authorizedHandler, object, SupabaseGateway, uuid } from '../create_gym_owner/handler.ts';

type Json = Record<string, unknown>;
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export interface MemberAccountGateway {
  actor(token: string): Promise<string>;
  staffOf(user: string, gym: string): Promise<boolean>;
  member(gym: string, memberId: string): Promise<Json | null>;
  accountUser(gym: string, memberId: string): Promise<string | null>;
  authUserByEmail(email: string): Promise<string | null>;
  userShared(user: string, gym: string, memberId: string): Promise<boolean>;
  setPassword(user: string, password: string): Promise<void>;
  createUser(email: string, password: string): Promise<string>;
  deleteUser(user: string): Promise<void>;
  linkAccount(user: string, gym: string, memberId: string, email: string): Promise<void>;
  unlinkAccount(gym: string, memberId: string): Promise<void>;
  setMemberEmail(gym: string, memberId: string, email: string): Promise<void>;
}

export class SupabaseMemberGateway extends SupabaseGateway implements MemberAccountGateway {
  override async actor(token: string): Promise<string> {
    return this.authenticatedUser(token);
  }

  private async get(path: string): Promise<unknown> {
    return this.request(path, { method: 'GET' });
  }

  private async first(path: string): Promise<Json | null> {
    const rows = await this.get(path);
    return Array.isArray(rows) && rows.length > 0 ? rows[0] as Json : null;
  }

  async staffOf(user: string, gym: string): Promise<boolean> {
    return await this.first(
      `/rest/v1/staff?user_id=eq.${user}&gym_id=eq.${gym}&active=eq.true&deleted_at=is.null&select=id&limit=1`,
    ) !== null;
  }

  member(gym: string, memberId: string): Promise<Json | null> {
    return this.first(
      `/rest/v1/members?id=eq.${memberId}&gym_id=eq.${gym}&deleted_at=is.null&select=id,email&limit=1`,
    );
  }

  accountUser(gym: string, memberId: string): Promise<string | null> {
    return this.first(
      `/rest/v1/member_accounts?gym_id=eq.${gym}&member_id=eq.${memberId}&select=user_id&limit=1`,
    ).then((row) => (row ? uuid(row.user_id) : null));
  }

  async authUserByEmail(email: string): Promise<string | null> {
    const result = object(await this.get(`/auth/v1/admin/users?filter=${encodeURIComponent(email)}&per_page=50`));
    const users = Array.isArray(result.users) ? result.users : [];
    const match = users.find((u) => typeof (u as Json).id === 'string'
      && String((u as Json).email).toLowerCase() === email);
    return match ? uuid((match as Json).id) : null;
  }

  async userShared(user: string, gym: string, memberId: string): Promise<boolean> {
    if (await this.first(`/rest/v1/staff?user_id=eq.${user}&select=id&limit=1`) !== null) return true;
    const links = await this.get(`/rest/v1/member_accounts?user_id=eq.${user}&select=gym_id,member_id`);
    return Array.isArray(links) && links.some((row) => {
      const link = row as Json;
      return link.gym_id !== gym || link.member_id !== memberId;
    });
  }

  async setPassword(user: string, password: string): Promise<void> {
    await this.request(`/auth/v1/admin/users/${user}`, { method: 'PUT', body: { password } });
  }

  override async createUser(email: string, password: string): Promise<string> {
    const user = object(await this.request('/auth/v1/admin/users', { body: {
      email, password, email_confirm: true, user_metadata: { securgym_member: true },
    } }));
    return uuid(user.id);
  }

  async deleteUser(user: string): Promise<void> {
    await this.request(`/auth/v1/admin/users/${user}`, { method: 'DELETE' });
  }

  async linkAccount(user: string, gym: string, memberId: string, email: string): Promise<void> {
    await this.request('/rest/v1/member_accounts', { body: {
      user_id: user, gym_id: gym, member_id: memberId, email,
    } });
  }

  async unlinkAccount(gym: string, memberId: string): Promise<void> {
    await this.request(`/rest/v1/member_accounts?gym_id=eq.${gym}&member_id=eq.${memberId}`, { method: 'DELETE' });
  }

  async setMemberEmail(gym: string, memberId: string, email: string): Promise<void> {
    await this.request(`/rest/v1/members?id=eq.${memberId}&gym_id=eq.${gym}`, {
      method: 'PATCH', body: { email, updated_at: new Date().toISOString() },
    });
  }
}

export function createMemberAccountHandler(gateway: MemberAccountGateway, origins: ReadonlySet<string>) {
  return authorizedHandler(gateway, origins, async (input, actor) => {
    const gym = uuid(input.gym_id);
    const memberId = uuid(input.member_id);
    if (!await gateway.staffOf(actor, gym)) throw new ApiError('access_denied', 403);
    const member = await gateway.member(gym, memberId);
    if (!member) throw new ApiError('invalid_record', 404);

    if (input.action === 'revoke') {
      const linked = await gateway.accountUser(gym, memberId);
      if (!linked) return { status: 'ok' };
      await gateway.unlinkAccount(gym, memberId);
      // Compte Auth inutilisé ailleurs : on le supprime pour ne pas laisser d'orphelin.
      if (!await gateway.userShared(linked, gym, memberId)) {
        try { await gateway.deleteUser(linked); } catch { /* compte conservé */ }
      }
      return { status: 'ok' };
    }

    if (input.action !== 'set_password') throw new ApiError('invalid_record');
    const password = input.password;
    if (typeof password !== 'string' || password.length < 8 || password.length > 128) {
      throw new ApiError('weak_password');
    }
    const memberEmail = typeof member.email === 'string' ? member.email : '';
    const rawEmail = typeof input.email === 'string' && input.email.trim() !== '' ? input.email : memberEmail;
    const email = rawEmail.trim().toLowerCase();
    if (email.length > 254 || !emailPattern.test(email)) throw new ApiError('email_required');

    const linked = await gateway.accountUser(gym, memberId);
    let user = linked;
    if (!user) {
      const existing = await gateway.authUserByEmail(email);
      if (existing) {
        // Jamais sur le compte d'un collègue ni sur un compte utilisé ailleurs.
        if (await gateway.userShared(existing, gym, memberId)) throw new ApiError('shared_account', 409);
        user = existing;
      }
    }
    if (user) await gateway.setPassword(user, password);
    else user = await gateway.createUser(email, password);
    if (!linked) await gateway.linkAccount(user, gym, memberId, email);
    if (!memberEmail) await gateway.setMemberEmail(gym, memberId, email);
    return { status: 'ok', email };
  });
}
