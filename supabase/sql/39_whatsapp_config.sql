-- ============================================================================
-- GYMDESK: KONFIGIRASYON WHATSAPP (whatsapp-web.js)
-- ============================================================================
begin;

create table if not exists public.platform_whatsapp_config (
  id boolean primary key default true check (id),
  gateway_url text not null default 'http://127.0.0.1:47812',
  valid_number text,
  default_country_code text not null default '509',
  auto_send_receipts boolean not null default true,
  auto_send_reminders boolean not null default true,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid
);

insert into public.platform_whatsapp_config(id) values (true) on conflict do nothing;

alter table public.platform_whatsapp_config enable row level security;
revoke all on public.platform_whatsapp_config from public, anon, authenticated;
grant select on public.platform_whatsapp_config to service_role;

-- 1. RPC pou li konfigirasyon WhatsApp la
create or replace function public.platform_whatsapp_config_get()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  c public.platform_whatsapp_config;
begin
  select * into c from public.platform_whatsapp_config where id;
  return jsonb_build_object(
    'gateway_url', coalesce(c.gateway_url, 'http://127.0.0.1:47812'),
    'valid_number', coalesce(c.valid_number, ''),
    'default_country_code', coalesce(c.default_country_code, '509'),
    'auto_send_receipts', coalesce(c.auto_send_receipts, true),
    'auto_send_reminders', coalesce(c.auto_send_reminders, true),
    'updated_at', c.updated_at
  );
end $$;

revoke all on function public.platform_whatsapp_config_get() from public, anon;
grant execute on function public.platform_whatsapp_config_get() to authenticated;

-- 2. RPC pou sove konfigirasyon WhatsApp la
create or replace function public.platform_whatsapp_config_set(
  p_gateway_url text default 'http://127.0.0.1:47812',
  p_valid_number text default null,
  p_default_country_code text default '509',
  p_auto_send_receipts boolean default true,
  p_auto_send_reminders boolean default true
) returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.platform_whatsapp_config set
    gateway_url = coalesce(nullif(trim(p_gateway_url), ''), 'http://127.0.0.1:47812'),
    valid_number = trim(p_valid_number),
    default_country_code = coalesce(nullif(trim(p_default_country_code), ''), '509'),
    auto_send_receipts = coalesce(p_auto_send_receipts, true),
    auto_send_reminders = coalesce(p_auto_send_reminders, true),
    updated_at = clock_timestamp(),
    updated_by = auth.uid()
  where id;
end $$;

revoke all on function public.platform_whatsapp_config_set(text, text, text, boolean, boolean) from public, anon;
grant execute on function public.platform_whatsapp_config_set(text, text, text, boolean, boolean) to authenticated;

commit;
