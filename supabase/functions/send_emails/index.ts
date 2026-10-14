import { SupabaseGateway } from '../create_gym_owner/handler.ts';
import { createEmailHandler, type EmailJob } from './handler.ts';

class EmailGateway extends SupabaseGateway {
  async claim() {
    return await this.rpc('claim_email', {}) as EmailJob | null;
  }
  async finish(job: EmailJob, result: string, messageId?: string, errorCode?: string) {
    await this.rpc('finish_email', {
      p_id: job.id, p_lease: job.lease_token, p_result: result,
      p_message_id: messageId ?? null, p_error: errorCode ?? null,
    });
  }
  async logo(job: EmailJob) {
    if (job.kind === 'gym_welcome') return Deno.env.get('GYMDESK_LOGO_URL') || null;
    const path = job.payload.logo_path ?? job.payload.logo_url;
    if (typeof path !== 'string' || !path.startsWith(`${job.gym_id}/logos/`) || path.includes('..')) return null;
    const result = await this.request(`/storage/v1/object/sign/gym-assets/${path.split('/').map(encodeURIComponent).join('/')}`, {
      body: { expiresIn: 60 * 60 * 24 * 365 },
    }) as { signedURL?: string };
    if (!result.signedURL?.startsWith('/object/sign/gym-assets/')) throw new Error('logo_unavailable');
    return `${url}/storage/v1${result.signedURL}`;
  }
  async receipt(job: EmailJob) {
    const path = job.payload.receipt_path;
    if (typeof path !== 'string' || path === '') return null;
    if (!path.startsWith(`${job.gym_id}/receipts/`) || path.includes('..')) throw new Error('receipt_invalid');
    const result = await this.request(`/storage/v1/object/sign/receipts/${path.split('/').map(encodeURIComponent).join('/')}`, {
      body: { expiresIn: 60 * 60 * 24 * 365 },
    }) as { signedURL?: string };
    if (!result.signedURL?.startsWith('/object/sign/receipts/')) throw new Error('receipt_unavailable');
    return `${url}/storage/v1${result.signedURL}`;
  }
  async providerConfig() {
    try {
      return await this.rpc('email_worker_config', {}) as { api_key?: string; sender_email?: string; sender_name?: string } | null;
    } catch {
      return null;
    }
  }
}

const url = Deno.env.get('SUPABASE_URL')?.replace(/\/$/, '');
const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const workerToken = Deno.env.get('EMAIL_WORKER_TOKEN') ?? '';
if (!url || !key) {
  Deno.serve(() => Response.json({ error: 'server_configuration' }, { status: 503 }));
} else {
  const gateway = new EmailGateway(url, key, '');
  Deno.serve(async (req) => {
    if (!workerToken || req.headers.get('x-email-worker-token') !== workerToken) return Response.json({ error: 'unauthorized' }, { status: 401 });
    const stored = await gateway.providerConfig();
    return createEmailHandler(gateway, {
      workerToken,
      apiKey: stored?.api_key || Deno.env.get('BREVO_API_KEY') || '',
      senderEmail: stored?.sender_email || Deno.env.get('BREVO_SENDER_EMAIL') || '',
      senderName: stored?.sender_name || Deno.env.get('BREVO_SENDER_NAME') || 'GymDesk',
    })(req);
  });
}
