import { renderEmail } from './templates.ts';

export interface EmailJob {
  id: string;
  gym_id: string;
  lease_token: string;
  kind: 'gym_welcome' | 'member_welcome' | 'member_renewal';
  recipient: string;
  payload: Record<string, unknown>;
}
export interface EmailGateway {
  claim(): Promise<EmailJob | null>;
  finish(job: EmailJob, result: string, messageId?: string, error?: string): Promise<void>;
  logo(job: EmailJob): Promise<string | null>;
}
interface Config {
  workerToken: string;
  apiKey: string;
  senderEmail: string;
  senderName: string;
}
const json = (value: unknown, status = 200) => Response.json(value, { status });

export function createEmailHandler(gateway: EmailGateway, config: Config, send: typeof fetch = fetch) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
    if (!config.workerToken || req.headers.get('x-email-worker-token') !== config.workerToken) return json({ error: 'unauthorized' }, 401);
    if (!config.apiKey || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(config.senderEmail)) return json({ error: 'email_not_configured' }, 503);
    let accepted = 0;
    const started = Date.now();
    try {
      for (let i = 0; i < 20 && Date.now() - started < 45000; i++) {
        const job = await gateway.claim();
        if (!job) break;
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(job.recipient)) {
          await gateway.finish(job, 'failed', undefined, 'invalid_recipient');
          continue;
        }
        let logo: string | null;
        try {
          logo = await gateway.logo(job);
        } catch {
          await gateway.finish(job, 'retry', undefined, 'logo_unavailable');
          continue;
        }
        const content = renderEmail(job, logo);
        let response: Response;
        try {
          response = await send('https://api.brevo.com/v3/smtp/email', {
            method: 'POST',
            headers: { 'api-key': config.apiKey, 'content-type': 'application/json', accept: 'application/json' },
            body: JSON.stringify({
              sender: { name: config.senderName, email: config.senderEmail },
              to: [{ email: job.recipient }], subject: content.subject, htmlContent: content.html,
              tags: ['gymdesk', job.kind], headers: { 'X-GymDesk-Event': job.id },
            }),
            signal: AbortSignal.timeout(15000),
          });
        } catch {
          await gateway.finish(job, 'uncertain', undefined, 'network_outcome_unknown');
          break;
        }
        const data = await response.json().catch(() => ({})) as Record<string, unknown>;
        if (response.ok) {
          if (typeof data.messageId !== 'string') {
            await gateway.finish(job, 'uncertain', undefined, 'missing_message_id');
            break;
          }
          await gateway.finish(job, 'sent', data.messageId);
          accepted++;
          continue;
        }
        const code = typeof data.code === 'string' && /^[a-z_]{1,80}$/.test(data.code) ? data.code : `http_${response.status}`;
        const outcome = code === 'not_enough_credits' ? 'quota'
          : response.status === 401 || response.status === 403 ? 'configuration'
          : response.status === 429 || response.status >= 500 ? 'retry' : 'failed';
        await gateway.finish(job, outcome, undefined, code);
        if (outcome !== 'failed') break;
      }
      return json({ accepted });
    } catch {
      return json({ error: 'email_worker_failed', accepted }, 503);
    }
  };
}
