import { createHandler, SupabaseGateway } from './handler.ts';

const url = Deno.env.get('SUPABASE_URL');
const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const origins = new Set((Deno.env.get('GYMDESK_ALLOWED_ORIGINS') ?? '').split(',').map((v) => v.trim()).filter(Boolean));
const resetRedirect = Deno.env.get('GYMDESK_PASSWORD_RESET_REDIRECT') ?? '';

if (!url || !key) {
  Deno.serve(() => new Response(JSON.stringify({ error: 'server_configuration' }), { status: 503, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } }));
} else {
  Deno.serve(createHandler(new SupabaseGateway(url.replace(/\/$/, ''), key, resetRedirect), origins));
}
