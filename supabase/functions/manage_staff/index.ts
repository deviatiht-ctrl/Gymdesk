import { createStaffHandler, SupabaseStaffGateway } from './handler.ts';

const url = Deno.env.get('SUPABASE_URL');
const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const origins = new Set((Deno.env.get('GYMDESK_ALLOWED_ORIGINS') ?? '').split(',').map((s) => s.trim()).filter(Boolean));
if (!url || !key) {
  Deno.serve(() => new Response(JSON.stringify({ error: 'server_configuration' }), { status: 503, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } }));
} else {
  Deno.serve(createStaffHandler(new SupabaseStaffGateway(url.replace(/\/$/, ''), key, ''), origins));
}
