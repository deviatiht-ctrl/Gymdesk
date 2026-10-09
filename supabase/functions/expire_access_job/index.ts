import { createClient } from 'jsr:@supabase/supabase-js@2';

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('Origin') ?? '*';
  const corsHeaders = {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
    'Content-Type': 'application/json',
  };

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey, {
      auth: { persistSession: false },
    });

    console.log('[EXPIRE_JOB] Starting daily midnight access expiration sweep...');

    const { data, error } = await supabase.rpc('process_daily_expirations');

    if (error) {
      console.error('[EXPIRE_JOB] RPC error:', error.message);
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: corsHeaders,
      });
    }

    console.log('[EXPIRE_JOB] Successfully processed expirations:', data);

    return new Response(JSON.stringify(data), {
      status: 200,
      headers: corsHeaders,
    });
  } catch (err: any) {
    console.error('[EXPIRE_JOB] Exception:', err);
    return new Response(JSON.stringify({ error: err.message ?? 'internal_error' }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});
