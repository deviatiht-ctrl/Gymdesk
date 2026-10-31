import { ApiError } from '../create_gym_owner/handler.ts';
import { createMemberAccountHandler, type MemberAccountGateway } from './handler.ts';

type Json = Record<string, unknown>;
const actorId = '10000000-0000-4000-8000-000000000010';
const gymId = '20000000-0000-4000-8000-000000000010';
const memberId = '30000000-0000-4000-8000-000000000010';
const memberUser = '40000000-0000-4000-8000-000000000010';
const sharedUser = '40000000-0000-4000-8000-000000000099';
const base = { action: 'set_password', gym_id: gymId, member_id: memberId, password: 'Motdepasse-membre-1' };

function assert(value: unknown, message = 'Assertion failed'): asserts value {
  if (!value) throw new Error(message);
}

class TestGateway implements MemberAccountGateway {
  authorized = true;
  isStaff = true;
  memberRow: Json | null = { id: memberId, email: 'membre@example.invalid' };
  linkedUser: string | null = null;
  byEmail: string | null = null;
  shared = false;
  passwords: string[] = [];
  created = 0;
  deleted = 0;
  linked = 0;
  unlinked = 0;
  memberEmails: string[] = [];
  emailResult: boolean | Error = true;
  sentEmails: { email: string; password: string }[] = [];

  actor(_token: string): Promise<string> {
    if (!this.authorized) return Promise.reject(new ApiError('access_denied', 403));
    return Promise.resolve(actorId);
  }
  staffOf(): Promise<boolean> { return Promise.resolve(this.isStaff); }
  member(): Promise<Json | null> { return Promise.resolve(this.memberRow); }
  accountUser(): Promise<string | null> { return Promise.resolve(this.linkedUser); }
  authUserByEmail(): Promise<string | null> { return Promise.resolve(this.byEmail); }
  userShared(): Promise<boolean> { return Promise.resolve(this.shared); }
  setPassword(_u: string, password: string): Promise<void> { this.passwords.push(password); return Promise.resolve(); }
  createUser(): Promise<string> { this.created++; return Promise.resolve(memberUser); }
  deleteUser(): Promise<void> { this.deleted++; return Promise.resolve(); }
  linkAccount(): Promise<void> { this.linked++; return Promise.resolve(); }
  unlinkAccount(): Promise<void> { this.unlinked++; return Promise.resolve(); }
  setMemberEmail(_g: string, _m: string, email: string): Promise<void> { this.memberEmails.push(email); return Promise.resolve(); }
  sendAccessEmail(_g: string, _m: string, email: string, password: string): Promise<boolean> {
    this.sentEmails.push({ email, password });
    return this.emailResult instanceof Error ? Promise.reject(this.emailResult) : Promise.resolve(this.emailResult);
  }
}

function request(body: unknown = base) {
  return new Request('https://edge.example.invalid/manage_member_account', {
    method: 'POST', headers: { Authorization: 'Bearer test-token' }, body: JSON.stringify(body),
  });
}

async function call(gateway: TestGateway, req = request()) {
  const res = await createMemberAccountHandler(gateway, new Set())(req);
  return { status: res.status, body: await res.json() as Json };
}

Deno.test('rejects missing bearer token', async () => {
  const g = new TestGateway();
  const res = await createMemberAccountHandler(g, new Set())(
    new Request('https://edge.example.invalid/manage_member_account', { method: 'POST', body: '{}' }),
  );
  assert(res.status === 401);
});

Deno.test('rejects non-staff actor and unknown member', async () => {
  const g = new TestGateway();
  g.isStaff = false;
  assert((await call(g)).status === 403);
  g.isStaff = true;
  g.memberRow = null;
  assert((await call(g)).status === 404);
});

Deno.test('validates password strength and email', async () => {
  const g = new TestGateway();
  assert((await call(g, request({ ...base, password: 'court' }))).body.error === 'weak_password');
  g.memberRow = { id: memberId, email: null };
  assert((await call(g)).body.error === 'email_required');
});

Deno.test('creates a new auth user, links it and fills member email', async () => {
  const g = new TestGateway();
  g.memberRow = { id: memberId, email: null };
  const res = await call(g, request({ ...base, email: 'Nouveau@Example.invalid' }));
  assert(res.status === 200, JSON.stringify(res.body));
  assert(res.body.email === 'nouveau@example.invalid');
  assert(g.created === 1 && g.linked === 1 && g.passwords.length === 0);
  assert(g.memberEmails[0] === 'nouveau@example.invalid');
});

Deno.test('reuses an existing auth user when it is safe', async () => {
  const g = new TestGateway();
  g.byEmail = sharedUser;
  const res = await call(g);
  assert(res.status === 200);
  assert(g.created === 0 && g.passwords.length === 1 && g.linked === 1);
});

Deno.test('refuses a shared account', async () => {
  const g = new TestGateway();
  g.byEmail = sharedUser;
  g.shared = true;
  const res = await call(g);
  assert(res.status === 409 && res.body.error === 'shared_account');
  assert(g.passwords.length === 0 && g.created === 0);
});

Deno.test('resets the password of an already linked account without relinking', async () => {
  const g = new TestGateway();
  g.linkedUser = memberUser;
  const res = await call(g);
  assert(res.status === 200);
  assert(g.passwords.length === 1 && g.created === 0 && g.linked === 0);
});

Deno.test('emails the credentials to the member automatically', async () => {
  const g = new TestGateway();
  const res = await call(g);
  assert(res.status === 200 && res.body.email_sent === true);
  assert(g.sentEmails.length === 1);
  assert(g.sentEmails[0].email === 'membre@example.invalid' && g.sentEmails[0].password === base.password);
});

Deno.test('account stays created when the email cannot be sent', async () => {
  const g = new TestGateway();
  g.emailResult = new Error('brevo down');
  const res = await call(g);
  assert(res.status === 200 && res.body.email_sent === false);
  g.emailResult = false;
  assert((await call(g)).body.email_sent === false);
});

Deno.test('send_email false skips the email', async () => {
  const g = new TestGateway();
  const res = await call(g, request({ ...base, send_email: false }));
  assert(res.status === 200 && res.body.email_sent === false && g.sentEmails.length === 0);
});

Deno.test('no email on revoke or failed validation', async () => {
  const g = new TestGateway();
  g.linkedUser = memberUser;
  await call(g, request({ action: 'revoke', gym_id: gymId, member_id: memberId }));
  await call(g, request({ ...base, password: 'court' }));
  assert(g.sentEmails.length === 0);
});

Deno.test('revoke unlinks and removes orphan auth user', async () => {
  const g = new TestGateway();
  g.linkedUser = memberUser;
  const res = await call(g, request({ action: 'revoke', gym_id: gymId, member_id: memberId }));
  assert(res.status === 200);
  assert(g.unlinked === 1 && g.deleted === 1);
});

Deno.test('revoke keeps the auth user when shared', async () => {
  const g = new TestGateway();
  g.linkedUser = memberUser;
  g.shared = true;
  await call(g, request({ action: 'revoke', gym_id: gymId, member_id: memberId }));
  assert(g.unlinked === 1 && g.deleted === 0);
});
