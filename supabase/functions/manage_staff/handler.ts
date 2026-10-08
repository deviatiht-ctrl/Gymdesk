import { ApiError, authorizedHandler, object, SupabaseGateway, text, uuid } from '../create_gym_owner/handler.ts';

type Json = Record<string, unknown>;
export interface StaffGateway {
  actor(token: string): Promise<string>;
  rpc(name: string, params: Json): Promise<unknown>;
  createUser(email: string, password: string, request: string): Promise<string>;
}

export class SupabaseStaffGateway extends SupabaseGateway {
  override async actor(token: string): Promise<string> {
    const actor = await this.authenticatedUser(token);
    await this.rpc('staff_owner_gym', { p_actor: actor });
    return actor;
  }

  override async createUser(email: string, password: string, request: string): Promise<string> {
    const result = object(await this.request('/auth/v1/admin/users', { body: {
      email, password, email_confirm: true, app_metadata: { gymdesk_staff_request: request },
    } }));
    return uuid(result.id);
  }
}

export function createStaffHandler(gateway: StaffGateway, origins: ReadonlySet<string>) {
  return authorizedHandler(gateway, origins, async (input, actor) => {
    if (input.action !== 'create_staff') throw new ApiError('invalid_record');
    const request = uuid(input.request_id);
    const staff = uuid(input.staff_id);
    const email = text(input.email, 3, 254).toLowerCase();
    const fullName = text(input.full_name, 2, 120);
    const phone = text(input.phone ?? '', 0, 32);
    const role = text(input.role, 1, 16);
    if (!['manager','reception'].includes(role) || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new ApiError('invalid_record');
    const password = input.password;
    if (typeof password !== 'string' || password.length < 12 || password.length > 128) throw new ApiError('weak_password');
    const record = object(await gateway.rpc('staff_provision_begin', {
      p_request: request, p_actor: actor, p_staff: staff, p_payload: { email, full_name: fullName, phone, role },
    }));
    let user = record.user_id ?? await gateway.rpc('staff_provision_auth_user', { p_request: request, p_actor: actor });
    if (!user) {
      try { user = await gateway.createUser(email, password, request); } catch (error) {
        user = await gateway.rpc('staff_provision_auth_user', { p_request: request, p_actor: actor });
        if (!user) throw error;
      }
    }
    return { staff: await gateway.rpc('staff_provision_finish', { p_request: request, p_actor: actor, p_user: uuid(user) }) };
  });
}
