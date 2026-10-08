import { ApiError, createHandler, type PlatformGateway, validateCreate } from './handler.ts';

type Json = Record<string, unknown>;
const actorId = '10000000-0000-4000-8000-000000000001';
const ownerId = '10000000-0000-4000-8000-000000000002';
const body = {
  action: 'create', request_id: '20000000-0000-4000-8000-000000000001',
  gym_id: '30000000-0000-4000-8000-000000000001', staff_id: '40000000-0000-4000-8000-000000000001',
  gym: { name: 'Test Gym', code: 'TST', accent_color: '#1F6F4A', timezone: 'America/Port-au-Prince', currency: 'HTG' },
  owner_name: 'Test Owner', owner_email: 'owner@example.invalid', owner_password: 'Test-only-password-42',
};

function assert(value: unknown, message = 'Assertion failed'): asserts value {
  if (!value) throw new Error(message);
}

class TestGateway implements PlatformGateway {
  authorized = true;
  actorCalls = 0;
  creates = 0;
  finishes = 0;
  resetCalls = 0;
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
    if (name === 'provision_gym_begin') {
      this.capturedPayload = params.p_payload as Json;
      return Promise.resolve({ owner_user_id: this.user });
    }
    if (name === 'provision_gym_auth_user') return Promise.resolve(this.user);
    if (name === 'provision_gym_finish') {
      if (this.failFinishOnce) { this.failFinishOnce = false; return Promise.reject(new ApiError('provision_failed', 502)); }
      this.finishes++;
      return Promise.resolve({ id: body.gym_id, code: body.gym.code });
    }
    return Promise.reject(new Error('Unexpected RPC'));
  }

  createUser(_email: string, _password: string, requestId: string): Promise<string> {
    assert(requestId === body.request_id);
    this.creates++;
    this.user = ownerId;
    if (this.loseAuthResponse) return Promise.reject(new ApiError('network', 503));
    return Promise.resolve(ownerId);
  }

  resetOwner(gymId: string, actor: string): Promise<void> {
    assert(gymId === body.gym_id && actor === actorId);
    this.resetCalls++;
    return Promise.resolve();
  }
}

function request(value: unknown = body, headers: Record<string, string> = { Authorization: 'Bearer test-token' }) {
  return new Request('https://edge.example.invalid/create_gym_owner', { method: 'POST', headers, body: JSON.stringify(value) });
}

Deno.test('rejects missing bearer token before provisioning', async () => {
  const gateway = new TestGateway();
  const result = await createHandler(gateway, new Set())(request(body, {}));
  assert(result.status === 401 && gateway.actorCalls === 0 && gateway.creates === 0);
});

Deno.test('rejects non-platform staff', async () => {
  const gateway = new TestGateway(); gateway.authorized = false;
  const result = await createHandler(gateway, new Set())(request());
  assert(result.status === 403 && gateway.creates === 0);
});

Deno.test('rejects unapproved browser origin', async () => {
  const gateway = new TestGateway();
  const result = await createHandler(gateway, new Set())(request(body, { Authorization: 'Bearer test-token', Origin: 'https://untrusted.example.invalid' }));
  assert(result.status === 403 && gateway.actorCalls === 0);
});

Deno.test('never includes password in database provisioning payload', async () => {
  const gateway = new TestGateway();
  const result = await createHandler(gateway, new Set())(request());
  assert(result.status === 200 && gateway.creates === 1);
  assert(!JSON.stringify(gateway.capturedPayload).includes(body.owner_password));
  assert(!JSON.stringify(await result.json()).includes(body.owner_password));
});

Deno.test('retry after SQL failure reuses the already-created account', async () => {
  const gateway = new TestGateway(); gateway.failFinishOnce = true;
  const handler = createHandler(gateway, new Set());
  assert((await handler(request())).status === 502);
  assert((await handler(request())).status === 200);
  assert(gateway.creates === 1 && gateway.finishes === 1);
});

Deno.test('lost Auth response is recovered through immutable request metadata', async () => {
  const gateway = new TestGateway(); gateway.loseAuthResponse = true;
  const result = await createHandler(gateway, new Set())(request());
  assert(result.status === 200 && gateway.creates === 1 && gateway.finishes === 1);
});

Deno.test('rejects weak passwords and invalid tenant codes', () => {
  for (const value of [{ ...body, owner_password: 'short' }, { ...body, gym: { ...body.gym, code: 'BAD-CODE' } }]) {
    let rejected = false;
    try { validateCreate(value); } catch (error) { rejected = error instanceof ApiError; }
    assert(rejected);
  }
});

Deno.test('limits request size', async () => {
  const gateway = new TestGateway();
  const result = await createHandler(gateway, new Set())(request({ ...body, padding: 'x'.repeat(40000) }));
  assert(result.status === 413 && gateway.creates === 0);
});

Deno.test('owner reset uses verified actor and never creates accounts', async () => {
  const gateway = new TestGateway();
  const result = await createHandler(gateway, new Set())(request({ action: 'reset_owner', gym_id: body.gym_id }));
  assert(result.status === 200 && gateway.resetCalls === 1 && gateway.creates === 0);
});
