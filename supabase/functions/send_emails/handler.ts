import { renderEmail } from './templates.ts';

export interface EmailJob {
  id: string;
  gym_id: string;
  lease_token: string;
  kind: 'gym_welcome' | 'member_welcome' | 'member_renewal' | 'renewal_reminder' | 'campaign' | 'payment_receipt' | 'daily_report';
  recipient: string;
  payload: Record<string, unknown>;
}
export interface EmailGateway {
  claim(): Promise<EmailJob | null>;
  finish(job: EmailJob, result: string, messageId?: string, error?: string): Promise<void>;
  logo(job: EmailJob): Promise<string | null>;
  receipt(job: EmailJob): Promise<string | null>;
}
interface Config {
  workerToken: string;
  apiKey: string;
  senderEmail: string;
  senderName: string;
}
const json = (value: unknown, status = 200) => Response.json(value, { status });
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const displayName = (value: unknown, fallback: string) =>
  String(value ?? '').replace(/[\r\n"<>]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 70) || fallback;

export function brevoPayload(job: EmailJob, config: Pick<Config, 'senderEmail' | 'senderName'>, content: ReturnType<typeof renderEmail>) {
  const replyTo = typeof job.payload.reply_to === 'string' && emailPattern.test(job.payload.reply_to) ? job.payload.reply_to : null;
  const name = job.kind === 'gym_welcome' ? config.senderName : displayName(job.payload.gym_name, config.senderName);
  const isMarketing = job.kind === 'campaign';
  const headers: Record<string, string> = {
    'X-GymDesk-Event': job.id,
    'X-Entity-Ref-ID': job.id,
  };
  if (isMarketing) {
    headers['Feedback-ID'] = `${job.kind}:gymdesk`;
    if (replyTo) headers['List-Unsubscribe'] = `<mailto:${replyTo}?subject=STOP>`;
    headers['Precedence'] = 'bulk';
  } else {
    headers['X-Auto-Response-Suppress'] = 'OOF, AutoReply';
    headers['X-Priority'] = '3';
    headers['Importance'] = 'Normal';
  }
  return {
    sender: { name, email: config.senderEmail },
    ...(replyTo ? { replyTo: { email: replyTo, name } } : {}),
    to: [{ email: job.recipient, ...(typeof job.payload.name === 'string' ? { name: displayName(job.payload.name, '') } : {}) }],
    subject: content.subject, htmlContent: content.html, textContent: content.text,
    tags: isMarketing ? ['gymdesk-marketing', 'campaign'] : ['gymdesk-transactional', job.kind],
    headers,
  };
}

export function createEmailHandler(gateway: EmailGateway, config: Config, send: typeof fetch = fetch) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
    if (!config.workerToken || req.headers.get('x-email-worker-token') !== config.workerToken) return json({ error: 'unauthorized' }, 401);
    if (!config.apiKey || !emailPattern.test(config.senderEmail)) return json({ error: 'email_not_configured' }, 503);
    let accepted = 0;
    const started = Date.now();
    try {
      for (let i = 0; i < 20 && Date.now() - started < 45000; i++) {
        const job = await gateway.claim();
        if (!job) break;
        if (!emailPattern.test(job.recipient)) {
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
        let receipt: string | null = null;
        if (typeof job.payload.receipt_path === 'string' && job.payload.receipt_path !== '') {
          try {
            receipt = await gateway.receipt(job);
          } catch {
            await gateway.finish(job, 'retry', undefined, 'receipt_unavailable');
            continue;
          }
        }
        const content = renderEmail(job, logo, receipt);
        let response: Response;
        try {
          response = await send('https://api.brevo.com/v3/smtp/email', {
            method: 'POST',
            headers: { 'api-key': config.apiKey, 'content-type': 'application/json', accept: 'application/json' },
            body: JSON.stringify(brevoPayload(job, config, content)),
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
