import { ApiError } from '../create_gym_owner/handler.ts';
import { createStaffHandler, type StaffGateway } from './handler.ts';

type Json = Record<string, unknown>;
const actorId = '10000000-0000-4000-8000-000000000010';
const staffUser = '10000000-0000-4000-8000-000000000011';
const body = {
  action: 'create_staff', request_id: '20000000-0000-4000-8000-000000000010',
  staff_id: '30000000-0000-4000-8000-000000000010', email: 'staff@example.invalid',
  full_name: 'Test Reception', phone: '+50937000000', role: 'reception', password: 'Test-only-password-42',
};

function assert(value: unknown, message = 'Assertion failed'): asserts value {
  if (!value) throw new Error(message);
}

class TestStaffGateway implements StaffGateway {
  authorized = true;
  actorCalls = 0;
  creates = 0;
  finishes = 0;
  user: string | null = null;
  failFinishOnce = false;
  loseAuthResponse = false;
  capturedPayload: Json | null = null;

  actor(_token: string): Promise<string> {
    this.actorCalls++;
    if (!this.authorized) return Promise.reject(new ApiError('access_denied', 403));
    return Promise.resolve(actorId);
  }

  rpc(name: string, params: Json): Promise<unknown> {
    if (name === 'staff_provision_begin') {
      this.capturedPayload = params.p_payload as Json;
      return Promise.resolve({ user_id: this.user });
    }
    if (name === 'staff_provision_auth_user') return Promise.resolve(this.user);
    if (name === 'staff_provision_finish') {
      if (this.failFinishOnce) { this.failFinishOnce = false; return Promise.reject(new ApiError('provision_failed', 502)); }
      this.finishes++;
      return Promise.resolve({ id: body.staff_id, role: body.role });
    }
    return Promise.reject(new Error('Unexpected RPC'));
  }

  createUser(_email: string, _password: string, request: string): Promise<string> {
    assert(request === body.request_id);
    this.creates++;
    this.user = staffUser;
    if (this.loseAuthResponse) return Promise.reject(new ApiError('network', 503));
    return Promise.resolve(staffUser);
  }
}

function request(value: unknown = body, headers: Record<string, string> = { Authorization: 'Bearer test-token' }) {
  return new Request('https://edge.example.invalid/manage_staff', { method: 'POST', headers, body: JSON.stringify(value) });
}

Deno.test('rejects missing bearer token before staff provisioning', async () => {
  const gateway = new TestStaffGateway();
  const result = await createStaffHandler(gateway, new Set())(request(body, {}));
  assert(result.status === 401 && gateway.actorCalls === 0 && gateway.creates === 0);
});

Deno.test('rejects non-owner before staff creation', async () => {
  const gateway = new TestStaffGateway(); gateway.authorized = false;
  const result = await createStaffHandler(gateway, new Set())(request());
  assert(result.status === 403 && gateway.creates === 0);
});

Deno.test('never stores staff password in the provisioning payload', async () => {
  const gateway = new TestStaffGateway();
  const result = await createStaffHandler(gateway, new Set())(request());
  assert(result.status === 200 && gateway.creates === 1);
  assert(!JSON.stringify(gateway.capturedPayload).includes(body.password));
  assert(!JSON.stringify(await result.json()).includes(body.password));
});

Deno.test('retry after SQL failure reuses the already-created staff account', async () => {
  const gateway = new TestStaffGateway(); gateway.failFinishOnce = true;
  const handler = createStaffHandler(gateway, new Set());
  assert((await handler(request())).status === 502);
  assert((await handler(request())).status === 200);
  assert(gateway.creates === 1 && gateway.finishes === 1);
});

Deno.test('lost Auth response is recovered through request metadata', async () => {
  const gateway = new TestStaffGateway(); gateway.loseAuthResponse = true;
  const result = await createStaffHandler(gateway, new Set())(request());
  assert(result.status === 200 && gateway.creates === 1 && gateway.finishes === 1);
});

Deno.test('rejects owner roles, weak passwords and invalid records', async () => {
  const gateway = new TestStaffGateway();
  const handler = createStaffHandler(gateway, new Set());
  for (const value of [
    { ...body, role: 'owner' }, { ...body, role: 'super_admin' }, { ...body, password: 'short' }, { ...body, action: 'unknown' },
  ]) {
    const result = await handler(request(value));
    assert([400, 403, 409].includes(result.status));
  }
  assert(gateway.creates === 0);
});
