import { phoneKey, phoneLogin, type PhoneLoginGateway } from './handler.ts';

const gym = '20000000-0000-4000-8000-000000000010';
const memberId = '30000000-0000-4000-8000-000000000010';
const user = '40000000-0000-4000-8000-000000000010';

function assert(value: unknown, message = 'Assertion failed'): asserts value {
  if (!value) throw new Error(message);
}

class Fake implements PhoneLoginGateway {
  allowed = true;
  memberRow: { id: string; email: string | null; firstName: string } | null = { id: memberId, email: null, firstName: 'Ana' };
  linked: string | null = null;
  byEmail = new Map<string, string>();
  shared = false;
  created: string[] = [];
  links: string[] = [];
  phones: string[] = [];
  attempt() { return Promise.resolve(this.allowed); }
  member(_g: string, phone: string) { this.phones.push(phone); return Promise.resolve(this.memberRow); }
  accountUser() { return Promise.resolve(this.linked); }
  authUserByEmail(email: string) { return Promise.resolve(this.byEmail.get(email) ?? null); }
  userShared() { return Promise.resolve(this.shared); }
  createUser(email: string) { this.created.push(email); this.byEmail.set(email, user); return Promise.resolve(user); }
  linkAccount(_u: string, _g: string, _m: string, email: string) { this.links.push(email); return Promise.resolve(); }
  userEmail() { return Promise.resolve([...this.byEmail.keys()][0] ?? 'linked@example.invalid'); }
  magicToken(email: string) { return Promise.resolve(`hash-${email}`); }
}

Deno.test('phoneKey keeps the last 8 digits', () => {
  assert(phoneKey('+509 3106-5559') === '31065559');
  assert(phoneKey('3106555') === '');
  assert(phoneKey(42) === '');
});

Deno.test('member without email gets a synthetic account and a token', async () => {
  const g = new Fake();
  const res = await phoneLogin(g, { gym_id: gym, phone: '+509 31 06 55 59' });
  assert(res.status === 'ok' && res.token_hash === `hash-m.${memberId}@membres.securgym.com`);
  assert(g.phones[0] === '31065559');
  assert(g.created.length === 1 && g.links.length === 1);
});

Deno.test('already linked account is reused without creating anything', async () => {
  const g = new Fake();
  g.linked = user;
  const res = await phoneLogin(g, { gym_id: gym, phone: '31065559' });
  assert(res.status === 'ok' && g.created.length === 0 && g.links.length === 0);
});

Deno.test('staff or shared email is never reused', async () => {
  const g = new Fake();
  g.memberRow = { id: memberId, email: 'owner@example.invalid', firstName: 'Ana' };
  g.byEmail.set('owner@example.invalid', '50000000-0000-4000-8000-000000000010');
  g.shared = true;
  const res = await phoneLogin(g, { gym_id: gym, phone: '31065559' });
  assert(res.status === 'ok');
  assert(g.created[0] === `m.${memberId}@membres.securgym.com`);
});

Deno.test('unknown phone, bad phone and rate limit', async () => {
  const g = new Fake();
  g.memberRow = null;
  assert((await phoneLogin(g, { gym_id: gym, phone: '31065559' })).status === 'not_found');
  assert((await phoneLogin(g, { gym_id: gym, phone: '123' })).status === 'invalid_phone');
  g.allowed = false;
  assert((await phoneLogin(g, { gym_id: gym, phone: '31065559' })).status === 'too_many_attempts');
});
