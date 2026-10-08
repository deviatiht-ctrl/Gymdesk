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
    const path = job.payload.logo_path;
    if (typeof path !== 'string' || !path.startsWith(`${job.gym_id}/logos/`) || path.includes('..')) return null;
    const result = await this.request(`/storage/v1/object/sign/gym-assets/${path.split('/').map(encodeURIComponent).join('/')}`, {
      body: { expiresIn: 60 * 60 * 24 * 30 },
    }) as { signedURL?: string };
    if (!result.signedURL?.startsWith('/object/sign/gym-assets/')) throw new Error('logo_unavailable');
    return `${url}/storage/v1${result.signedURL}`;
  }
}

const url = Deno.env.get('SUPABASE_URL')?.replace(/\/$/, '');
const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
if (!url || !key) {
  Deno.serve(() => Response.json({ error: 'server_configuration' }, { status: 503 }));
} else {
  Deno.serve(createEmailHandler(new EmailGateway(url, key, ''), {
    workerToken: Deno.env.get('EMAIL_WORKER_TOKEN') ?? '',
    apiKey: Deno.env.get('BREVO_API_KEY') ?? '',
    senderEmail: Deno.env.get('BREVO_SENDER_EMAIL') ?? '',
    senderName: Deno.env.get('BREVO_SENDER_NAME') ?? 'GymDesk',
  }));
}
