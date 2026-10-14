import { brevoPayload, createEmailHandler, type EmailGateway, type EmailJob } from './handler.ts';
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
  receipt(): Promise<string | null> { return Promise.resolve(null); }
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
Deno.test('member emails are sent under the gym name with the gym as Reply-To and a text part', () => {
  const branded = { ...job, payload: { ...job.payload, reply_to: 'contact@gym.example', gym_name: 'Gym "Elite"\nPAP' } };
  const body = brevoPayload(branded, config, renderEmail(branded, null));
  assert(body.sender.name === 'Gym Elite PAP' && body.sender.email === config.senderEmail);
  assert(body.replyTo?.email === 'contact@gym.example' && body.textContent.includes('Répondez'));
  assert(!('List-Unsubscribe' in body.headers));
  const campaign = { ...branded, kind: 'campaign' as const, payload: { ...branded.payload, subject: 'Promo', body_text: 'Bonjour Marie,\nSalut' } };
  const sent = brevoPayload(campaign, config, renderEmail(campaign, null));
  assert(sent.subject === 'Promo' && sent.headers['List-Unsubscribe'] === '<mailto:contact@gym.example?subject=STOP>');
  assert(!sent.htmlContent.includes('&lt;script&gt;') && sent.textContent.includes('STOP'));
  const noReply = brevoPayload({ ...job, payload: { ...job.payload, reply_to: 'not-an-email' } }, config, renderEmail(job, null));
  assert(!('replyTo' in noReply));
  const platform = brevoPayload({ ...job, kind: 'gym_welcome' }, config, renderEmail({ ...job, kind: 'gym_welcome' }, null));
  assert(platform.sender.name === 'GymDesk');
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
Deno.test('renewal reminders follow the gym member language; other emails stay French', () => {
  const reminder = (language: string, days: number) => renderEmail({
    ...job, kind: 'renewal_reminder',
    payload: { ...job.payload, language, days_left: days, renewal_price: 1500, end_date: '2026-10-31' },
  }, null);
  const ht = reminder('ht', 2);
  assert(ht.subject.includes('2 jou') && ht.html.includes('lang="ht"') && ht.text.startsWith('Bonjou') && ht.text.includes('Pa bliye peye'));
  const en = reminder('en', 0);
  assert(en.subject.includes('ends today') && en.text.includes('Best regards'));
  const fr = reminder('xx', 7);
  assert(fr.subject.includes('7 jours') && fr.html.includes('lang="fr"'));
  const welcome = renderEmail({ ...job, payload: { ...job.payload, language: 'ht' } }, null);
  assert(welcome.html.includes('lang="fr"') && welcome.text.includes('Cordialement'));
});
Deno.test('payment receipt is localized and carries the PDF download button', () => {
  const receipt = (language: string) => renderEmail({
    ...job, kind: 'payment_receipt',
    payload: {
      ...job.payload, language, receipt_no: 'AB12CD34', amount: 80,
      received_amount: 100, credit_amount: 20, credit_balance: 20,
      method: 'cash', paid_at: '2026-10-14',
    },
  }, null, 'https://example.invalid/receipt.pdf');
  const ht = receipt('ht');
  assert(ht.subject.includes('Resi peman') && ht.html.includes('lang="ht"'));
  assert(ht.html.includes('Telechaje resi a (PDF)') && ht.html.includes('https://example.invalid/receipt.pdf'));
  assert(ht.text.includes('https://example.invalid/receipt.pdf'));
  const en = receipt('en');
  assert(en.subject.includes('receipt #AB12CD34') && en.html.includes('Download receipt (PDF)'));
  const fr = receipt('fr');
  assert(fr.subject.includes('Reçu de paiement') && fr.html.includes('Télécharger le reçu'));
  const noLink = renderEmail({ ...job, kind: 'payment_receipt', payload: { ...job.payload, language: 'en', method: 'cash', paid_at: '2026-10-14' } }, null, null);
  assert(!noLink.html.includes('Download receipt'));
});
