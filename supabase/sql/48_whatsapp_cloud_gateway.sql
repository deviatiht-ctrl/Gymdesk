-- ============================================================================
-- 48_whatsapp_cloud_gateway.sql
-- Migrate default WhatsApp Gateway URL to 24/7 Render Cloud Gateway and
-- enforce strict Anti-Ban Slow-Lane daily limit (25/day/SIM) in cluster defaults.
-- ============================================================================
begin;

alter table if exists public.platform_whatsapp_config
  alter column gateway_url set default 'https://cvisual-whatsapp-gateway.onrender.com';

update public.platform_whatsapp_config
set
  gateway_url = 'https://cvisual-whatsapp-gateway.onrender.com',
  updated_at = clock_timestamp()
where id = true
  and (
    gateway_url is null
    or trim(gateway_url) = ''
    or lower(gateway_url) like '%127.0.0.1%'
    or lower(gateway_url) like '%localhost%'
  );

update public.platform_whatsapp_accounts
set daily_limit = 25
where daily_limit is null or daily_limit > 25;

create or replace function public.platform_whatsapp_config_get()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  c public.platform_whatsapp_config;
  v_is_online boolean := false;
  v_cluster_status text := 'OFFLINE';
  v_active_phone text := null;
  v_active_qr text := null;
  v_ready_count integer := 0;
  v_scan_qr_count integer := 0;
  v_gateway text := 'https://cvisual-whatsapp-gateway.onrender.com';
begin
  select * into c from public.platform_whatsapp_config where id = true limit 1;

  if c.gateway_url is not null
     and trim(c.gateway_url) <> ''
     and lower(c.gateway_url) not like '%127.0.0.1%'
     and lower(c.gateway_url) not like '%localhost%' then
    v_gateway := trim(c.gateway_url);
  end if;

  select
    coalesce(count(*) filter (where service_status = 'READY'), 0),
    coalesce(count(*) filter (where service_status = 'SCAN_QR'), 0),
    coalesce(bool_or(last_heartbeat > (clock_timestamp() - interval '45 seconds')), false),
    max(phone_number) filter (where service_status = 'READY'),
    max(qr_code) filter (where service_status = 'SCAN_QR')
  into
    v_ready_count,
    v_scan_qr_count,
    v_is_online,
    v_active_phone,
    v_active_qr
  from public.platform_whatsapp_accounts
  where is_enabled = true;

  if v_is_online then
    if v_ready_count > 0 then
      v_cluster_status := 'READY';
    elsif v_scan_qr_count > 0 then
      v_cluster_status := 'SCAN_QR';
    else
      v_cluster_status := coalesce(c.service_status, 'DISCONNECTED');
    end if;
  else
    v_cluster_status := 'OFFLINE';
  end if;

  return jsonb_build_object(
    'gateway_url', v_gateway,
    'valid_number', coalesce(v_active_phone, c.valid_number, ''),
    'default_country_code', coalesce(c.default_country_code, '509'),
    'auto_send_welcome', coalesce(c.auto_send_welcome, true),
    'auto_send_receipts', coalesce(c.auto_send_receipts, true),
    'auto_send_reminders', coalesce(c.auto_send_reminders, true),
    'reminder_days_before', coalesce(c.reminder_days_before, 7),
    'service_status', v_cluster_status,
    'connected_phone', v_active_phone,
    'push_name', c.push_name,
    'qr_code', v_active_qr,
    'queue_length', (select count(*) from public.whatsapp_messages_outbox where status = 'pending'),
    'last_error', c.last_error,
    'is_online', v_is_online,
    'updated_at', clock_timestamp()
  );
end $$;

revoke all on function public.platform_whatsapp_config_get() from public;
grant execute on function public.platform_whatsapp_config_get() to authenticated, anon;

commit;
