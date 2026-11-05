-- ============================================================================
-- 40_whatsapp_automation.sql
-- Sipò automatizasyon WhatsApp (Byenvini, Resi, Rapèl 7 Jou, Kanpay)
-- ============================================================================
begin;

-- 1. Ajoute kolòn automatizasyon nan platform_whatsapp_config si yo pa egziste
alter table public.platform_whatsapp_config 
  add column if not exists auto_send_welcome boolean not null default true,
  add column if not exists reminder_days_before integer not null default 7;

-- 2. Tablo pou istorik notifikasyon WhatsApp voye pou evite doublon
create table if not exists public.whatsapp_notification_logs (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  member_id uuid references public.members(id) on delete set null,
  kind text not null, -- 'welcome', 'receipt', 'reminder_7d', 'campaign'
  recipient_phone text not null,
  recipient_name text,
  status text not null default 'sent',
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp()
);

create index if not exists idx_whatsapp_logs_member_kind 
  on public.whatsapp_notification_logs(member_id, kind, created_at desc);

alter table public.whatsapp_notification_logs enable row level security;
revoke all on public.whatsapp_notification_logs from public, anon;
grant select, insert on public.whatsapp_notification_logs to authenticated;

-- 3. Mete ajou platform_whatsapp_config_get
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
    'auto_send_welcome', coalesce(c.auto_send_welcome, true),
    'auto_send_receipts', coalesce(c.auto_send_receipts, true),
    'auto_send_reminders', coalesce(c.auto_send_reminders, true),
    'reminder_days_before', coalesce(c.reminder_days_before, 7),
    'updated_at', c.updated_at
  );
end $$;

-- 4. Mete ajou platform_whatsapp_config_set
create or replace function public.platform_whatsapp_config_set(
  p_gateway_url text default 'http://127.0.0.1:47812',
  p_valid_number text default null,
  p_default_country_code text default '509',
  p_auto_send_receipts boolean default true,
  p_auto_send_reminders boolean default true,
  p_auto_send_welcome boolean default true,
  p_reminder_days_before integer default 7
) returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.platform_whatsapp_config set
    gateway_url = coalesce(nullif(trim(p_gateway_url), ''), 'http://127.0.0.1:47812'),
    valid_number = trim(p_valid_number),
    default_country_code = coalesce(nullif(trim(p_default_country_code), ''), '509'),
    auto_send_welcome = coalesce(p_auto_send_welcome, true),
    auto_send_receipts = coalesce(p_auto_send_receipts, true),
    auto_send_reminders = coalesce(p_auto_send_reminders, true),
    reminder_days_before = coalesce(p_reminder_days_before, 7),
    updated_at = clock_timestamp(),
    updated_by = auth.uid()
  where id;
end $$;

commit;
