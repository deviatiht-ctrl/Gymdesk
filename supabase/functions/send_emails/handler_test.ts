import { createEmailHandler, type EmailGateway, type EmailJob } from './handler.ts';
import { renderEmail } from './templates.ts';

function assert(value: unknown): asserts value {
  if (!value) throw new Error('Assertion failed');
}
const job: EmailJob = {
  id: '00000000-0000-4000-8000-000000000001', gym_id: 'gym-1', lease_token: 'lease',
  kind: 'member_welcome', recipient: 'member@example.invalid',
  payload: { name: 'Marie <script>alert(1)</script>', gym_name: 'Gym & Co', plan_name: 'Mensuel', price: 800, currency: 'HTG', start_date: '2026-10-01', end_date: '2026-10-31', status: 'active' },
};
class Gateway implements EmailGateway {
  claims = 0;
  results: string[] = [];
  claim(): Promise<EmailJob | null> { return Promise.resolve(this.claims++ === 0 ? job : null); }
  finish(_job: EmailJob, result: string): Promise<void> { this.results.push(result); return Promise.resolve(); }
  logo(): Promise<string | null> { return Promise.resolve(null); }
}
const config = { workerToken: 'test-worker-token', apiKey: 'test-api-key', senderEmail: 'noreply@example.invalid', senderName: 'GymDesk' };
const request = (token = config.workerToken) => new Request('https://example.invalid/send_emails', { method: 'POST', headers: { 'x-email-worker-token': token } });

Deno.test('unauthorized caller cannot claim or send emails', async () => {
  const gateway = new Gateway();
  const response = await createEmailHandler(gateway, config, () => { throw new Error('Must not send'); })(request('invalid'));
  assert(response.status === 401 && gateway.claims === 0);
});
Deno.test('successful Brevo acceptance is recorded, not called delivered', async () => {
  const gateway = new Gateway();
  const response = await createEmailHandler(gateway, config, (_url, init) => {
    const body = JSON.parse(String(init?.body));
    assert(body.to.length === 1 && body.to[0].email === job.recipient);
    assert(body.htmlContent.includes('800') && !body.htmlContent.includes('<script>'));
    return Promise.resolve(new Response(JSON.stringify({ messageId: '<message-1>' }), { status: 201 }));
  })(request());
  assert(response.status === 200 && gateway.results.join() === 'sent');
});
for (const [status, code, expected] of [
  [400, 'not_enough_credits', 'quota'], [429, 'rate_limit', 'retry'],
  [503, 'unavailable', 'retry'], [401, 'unauthorized', 'configuration'],
  [400, 'invalid_parameter', 'failed'], [403, 'account_under_validation', 'configuration'],
] as const) {
  Deno.test(`Brevo ${code} becomes ${expected}`, async () => {
    const gateway = new Gateway();
    await createEmailHandler(gateway, config, () => Promise.resolve(new Response(JSON.stringify({ code }), { status })))(request());
    assert(gateway.results.join() === expected);
  });
}
Deno.test('ambiguous network outcome is retained for review instead of blindly duplicating', async () => {
  const gateway = new Gateway();
  await createEmailHandler(gateway, config, () => Promise.reject(new Error('connection lost')))(request());
  assert(gateway.results.join() === 'uncertain');
});
Deno.test('missing Brevo configuration does not consume a queue reservation', async () => {
  const gateway = new Gateway();
  const response = await createEmailHandler(gateway, { ...config, apiKey: '' })(request());
  assert(response.status === 503 && gateway.claims === 0);
});
Deno.test('templates escape content and reject unsafe logo URLs and colors', () => {
  const rendered = renderEmail(job, 'javascript:alert(1)');
  assert(rendered.html.includes('&lt;script&gt;') && rendered.html.includes('Gym &amp; Co'));
  assert(!rendered.html.includes('javascript:') && !rendered.html.includes('<img'));
  const imported = renderEmail({ ...job, payload: { ...job.payload, imported: true } }, 'https://example.invalid/logo.png');
  assert(imported.html.includes('<img') && imported.text.includes('déjà réglée'));
  const renewal = renderEmail({ ...job, kind: 'member_renewal' }, null);
  assert(renewal.subject.includes('Renouvellement'));
  const welcome = renderEmail({ ...job, kind: 'gym_welcome', payload: { ...job.payload, status: 'trial', badge_quota: 100 } }, null);
  assert(welcome.text.includes('100') && welcome.text.includes('essai') && welcome.subject.includes('GymDesk'));
});
