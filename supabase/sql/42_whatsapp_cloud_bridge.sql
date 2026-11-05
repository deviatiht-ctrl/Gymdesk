-- ============================================================================
-- 42_whatsapp_cloud_bridge.sql
-- Sipò Cloud Bridge WhatsApp pou Tablet, Telefòn, ak Web (Vercel)
-- Pèmèt WhatsApp toujou rete aktif epi resevwa kòmand depi nenpòt kote!
-- ============================================================================
begin;

-- 1. Ajoute kolòn estati ak heartbeat nan platform_whatsapp_config
alter table public.platform_whatsapp_config 
  add column if not exists service_status text not null default 'OFFLINE',
  add column if not exists connected_phone text,
  add column if not exists push_name text,
  add column if not exists qr_code text,
  add column if not exists queue_length integer not null default 0,
  add column if not exists last_error text,
  add column if not exists last_heartbeat timestamptz;

-- 2. Tablo Outbox pou mesaj WhatsApp soti nan Tablet, Telefòn ak Web
create table if not exists public.whatsapp_messages_outbox (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid references public.gyms(id) on delete cascade,
  to_phone text not null,
  message text not null,
  pdf_base64 text,
  pdf_file_name text,
  kind text default 'manual', -- manual, test, welcome, receipt, reminder_7d, reminder_2d, reminder_due
  status text not null default 'pending', -- pending, processing, sent, failed
  error_message text,
  attempts integer not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  processed_at timestamptz,
  sent_at timestamptz
);

create index if not exists idx_whatsapp_outbox_pending 
  on public.whatsapp_messages_outbox(status, created_at) 
  where status = 'pending';

alter table public.whatsapp_messages_outbox enable row level security;
revoke all on public.whatsapp_messages_outbox from public, anon;
grant select, insert, update on public.whatsapp_messages_outbox to authenticated, service_role, anon;

-- Policy pou pèmèt insert ak select
drop policy if exists whatsapp_outbox_policy on public.whatsapp_messages_outbox;
create policy whatsapp_outbox_policy on public.whatsapp_messages_outbox
  for all to public using (true) with check (true);

-- 3. RPC pou sèvis lokal la voye Heartbeat bay Supabase
create or replace function public.platform_whatsapp_heartbeat(
  p_service_status text,
  p_connected_phone text default null,
  p_push_name text default null,
  p_qr_code text default null,
  p_queue_length integer default 0,
  p_last_error text default null
) returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.platform_whatsapp_config set
    service_status = coalesce(p_service_status, 'OFFLINE'),
    connected_phone = p_connected_phone,
    push_name = p_push_name,
    qr_code = p_qr_code,
    queue_length = coalesce(p_queue_length, 0),
    last_error = p_last_error,
    last_heartbeat = clock_timestamp()
  where id;
end $$;

revoke all on function public.platform_whatsapp_heartbeat(text, text, text, text, integer, text) from public, anon;
grant execute on function public.platform_whatsapp_heartbeat(text, text, text, text, integer, text) to authenticated, anon;

-- 4. RPC pou Tablet/Telefòn/Web mete yon mesaj nan ke (Queue) la
create or replace function public.whatsapp_enqueue_message(
  p_to_phone text,
  p_message text,
  p_gym_id uuid default null,
  p_kind text default 'manual',
  p_pdf_base64 text default null,
  p_pdf_file_name text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  insert into public.whatsapp_messages_outbox (
    gym_id, to_phone, message, kind, pdf_base64, pdf_file_name, status
  ) values (
    p_gym_id, trim(p_to_phone), trim(p_message), coalesce(p_kind, 'manual'), p_pdf_base64, p_pdf_file_name, 'pending'
  ) returning id into v_id;
  return v_id;
end $$;

revoke all on function public.whatsapp_enqueue_message(text, text, uuid, text, text, text) from public, anon;
grant execute on function public.whatsapp_enqueue_message(text, text, uuid, text, text, text) to authenticated, anon;

-- 5. Mete ajou platform_whatsapp_config_get pou retounen done cloud yo
create or replace function public.platform_whatsapp_config_get()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  c public.platform_whatsapp_config;
  v_is_online boolean := false;
begin
  select * into c from public.platform_whatsapp_config where id;
  
  -- Sèvis la konsidere kòm online si dènye heartbeat la gen mwens pase 45 segonn
  if c.last_heartbeat is not null and c.last_heartbeat > (clock_timestamp() - interval '45 seconds') then
    v_is_online := true;
  end if;

  return jsonb_build_object(
    'gateway_url', coalesce(c.gateway_url, 'http://127.0.0.1:47812'),
    'valid_number', coalesce(c.valid_number, ''),
    'default_country_code', coalesce(c.default_country_code, '509'),
    'auto_send_welcome', coalesce(c.auto_send_welcome, true),
    'auto_send_receipts', coalesce(c.auto_send_receipts, true),
    'auto_send_reminders', coalesce(c.auto_send_reminders, true),
    'reminder_days_before', coalesce(c.reminder_days_before, 7),
    'service_status', coalesce(c.service_status, 'OFFLINE'),
    'connected_phone', c.connected_phone,
    'push_name', c.push_name,
    'qr_code', c.qr_code,
    'queue_length', coalesce(c.queue_length, 0),
    'last_error', c.last_error,
    'last_heartbeat', c.last_heartbeat,
    'is_online', v_is_online,
    'updated_at', c.updated_at
  );
end $$;

commit;
