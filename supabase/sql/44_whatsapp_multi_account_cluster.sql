-- ============================================================================
-- 44_whatsapp_multi_account_cluster.sql
-- Sipò Multi-Kont WhatsApp (Cluster & Load Balancing Anti-Bann)
-- Pèmèt konekte 1 a 20 kont WhatsApp pou distribye mesaj yo entèlijanman
-- ak delè sekirite moun (human pacing) pou evite WhatsApp bloke nimewo yo
-- ============================================================================
begin;

-- 1. Tablo platform_whatsapp_accounts
create table if not exists public.platform_whatsapp_accounts (
  id uuid primary key default gen_random_uuid(),
  account_index integer not null unique,
  label text not null,
  phone_number text,
  push_name text,
  service_status text not null default 'DISCONNECTED', -- DISCONNECTED, INITIALIZING, SCAN_QR, AUTHENTICATED, READY, RESTRICTED, ERROR
  qr_code text,
  is_enabled boolean not null default true,
  daily_limit integer not null default 40,
  sent_today integer not null default 0,
  total_sent integer not null default 0,
  last_sent_at timestamptz,
  last_heartbeat timestamptz,
  restricted_until timestamptz,
  restriction_reason text,
  last_error text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create index if not exists idx_whatsapp_accounts_status 
  on public.platform_whatsapp_accounts(service_status, is_enabled);

alter table public.platform_whatsapp_accounts enable row level security;
revoke all on public.platform_whatsapp_accounts from public, anon;
grant select, insert, update, delete on public.platform_whatsapp_accounts to authenticated, service_role, anon;

drop policy if exists whatsapp_accounts_policy on public.platform_whatsapp_accounts;
create policy whatsapp_accounts_policy on public.platform_whatsapp_accounts
  for all to public using (true) with check (true);

-- 2. Mete ajou whatsapp_messages_outbox
alter table public.whatsapp_messages_outbox
  add column if not exists assigned_account_index integer,
  add column if not exists sent_by_phone text,
  add column if not exists retry_count integer not null default 0,
  add column if not exists template_seed integer not null default floor(random() * 10000)::integer;

-- 3. Inisyalize 3 premye kont pa defo si tablo a vid
insert into public.platform_whatsapp_accounts (account_index, label, daily_limit, service_status)
values 
  (1, 'Liy Prensipal', 40, 'DISCONNECTED'),
  (2, 'Liy Sekou 1', 40, 'DISCONNECTED'),
  (3, 'Liy Sekou 2', 40, 'DISCONNECTED')
on conflict (account_index) do nothing;

-- 4. Fonksyon pou remete sent_today a 0 chak jou pou chak kont
create or replace function public.whatsapp_reset_daily_limits_if_needed()
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.platform_whatsapp_accounts
  set sent_today = 0
  where last_sent_at is not null 
    and (last_sent_at at time zone 'UTC')::date < (clock_timestamp() at time zone 'UTC')::date;
end $$;

-- 5. RPC: Rale lis tout kont WhatsApp yo
create or replace function public.platform_whatsapp_accounts_list()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_res jsonb;
begin
  perform public.whatsapp_reset_daily_limits_if_needed();

  -- Tcheke si restriksyon fin pase
  update public.platform_whatsapp_accounts
  set service_status = 'DISCONNECTED', restricted_until = null, restriction_reason = null
  where service_status = 'RESTRICTED' 
    and restricted_until is not null 
    and restricted_until <= clock_timestamp();

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', a.id,
      'account_index', a.account_index,
      'label', a.label,
      'phone_number', a.phone_number,
      'push_name', a.push_name,
      'service_status', a.service_status,
      'qr_code', a.qr_code,
      'is_enabled', a.is_enabled,
      'daily_limit', a.daily_limit,
      'sent_today', a.sent_today,
      'total_sent', a.total_sent,
      'last_sent_at', a.last_sent_at,
      'last_heartbeat', a.last_heartbeat,
      'is_online', (a.last_heartbeat is not null and a.last_heartbeat >= (clock_timestamp() - interval '25 seconds')),
      'restricted_until', a.restricted_until,
      'restriction_reason', a.restriction_reason,
      'last_error', a.last_error,
      'created_at', a.created_at
    ) order by a.account_index asc
  ), '[]'::jsonb)
  into v_res
  from public.platform_whatsapp_accounts a;

  return v_res;
end $$;

revoke all on function public.platform_whatsapp_accounts_list() from public, anon;
grant execute on function public.platform_whatsapp_accounts_list() to authenticated, anon;

-- 6. RPC: Kreye yon nouvo plas kont WhatsApp (egz: Liy 4, Liy 5)
create or replace function public.platform_whatsapp_account_create(
  p_label text,
  p_daily_limit integer default 40
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_next_idx integer;
  v_row record;
begin
  select coalesce(max(account_index), 0) + 1 into v_next_idx
  from public.platform_whatsapp_accounts;

  if v_next_idx > 25 then
    raise exception 'Ou rive nan limit maksimòm (25 liy WhatsApp).';
  end if;

  insert into public.platform_whatsapp_accounts (
    account_index, label, daily_limit, service_status
  ) values (
    v_next_idx, coalesce(nullif(trim(p_label), ''), 'Liy ' || v_next_idx), coalesce(p_daily_limit, 40), 'DISCONNECTED'
  ) returning * into v_row;

  return jsonb_build_object(
    'ok', true,
    'account_index', v_row.account_index,
    'label', v_row.label,
    'id', v_row.id
  );
end $$;

revoke all on function public.platform_whatsapp_account_create(text, integer) from public, anon;
grant execute on function public.platform_whatsapp_account_create(text, integer) to authenticated, anon;

-- 7. RPC: Mete ajou estati ak heartbeat yon kont WhatsApp espesifik (Node.js rele sa)
create or replace function public.platform_whatsapp_account_heartbeat(
  p_account_index integer,
  p_service_status text,
  p_phone_number text default null,
  p_push_name text default null,
  p_qr_code text default null,
  p_last_error text default null
) returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.platform_whatsapp_accounts set
    service_status = coalesce(p_service_status, service_status),
    phone_number = coalesce(p_phone_number, phone_number),
    push_name = coalesce(p_push_name, push_name),
    qr_code = p_qr_code,
    last_error = p_last_error,
    last_heartbeat = clock_timestamp(),
    updated_at = clock_timestamp()
  where account_index = p_account_index;
end $$;

revoke all on function public.platform_whatsapp_account_heartbeat(integer, text, text, text, text, text) from public, anon;
grant execute on function public.platform_whatsapp_account_heartbeat(integer, text, text, text, text, text) to authenticated, anon;

-- 8. RPC: Deklare yon kont kòm RESTREINT (si WhatsApp voye erè 24h)
create or replace function public.platform_whatsapp_account_report_restricted(
  p_account_index integer,
  p_hours integer default 24,
  p_reason text default 'Restriksyon sekirite WhatsApp'
) returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.platform_whatsapp_accounts set
    service_status = 'RESTRICTED',
    restricted_until = clock_timestamp() + (coalesce(p_hours, 24) || ' hours')::interval,
    restriction_reason = coalesce(p_reason, 'Restriksyon sekirite WhatsApp'),
    qr_code = null,
    updated_at = clock_timestamp()
  where account_index = p_account_index;
end $$;

revoke all on function public.platform_whatsapp_account_report_restricted(integer, integer, text) from public, anon;
grant execute on function public.platform_whatsapp_account_report_restricted(integer, integer, text) to authenticated, anon;

-- 9. RPC: Anrejistre yon voye siksè pou yon kont
create or replace function public.platform_whatsapp_account_record_send(
  p_account_index integer,
  p_message_id uuid default null
) returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.whatsapp_reset_daily_limits_if_needed();

  update public.platform_whatsapp_accounts set
    sent_today = sent_today + 1,
    total_sent = total_sent + 1,
    last_sent_at = clock_timestamp(),
    updated_at = clock_timestamp()
  where account_index = p_account_index;

  if p_message_id is not null then
    update public.whatsapp_messages_outbox set
      assigned_account_index = p_account_index,
      sent_at = clock_timestamp()
    where id = p_message_id;
  end if;
end $$;

revoke all on function public.platform_whatsapp_account_record_send(integer, uuid) from public, anon;
grant execute on function public.platform_whatsapp_account_record_send(integer, uuid) to authenticated, anon;

-- 10. RPC: Aktive oswa Dezatilve yon liy WhatsApp
create or replace function public.platform_whatsapp_account_toggle(
  p_account_index integer,
  p_is_enabled boolean
) returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.platform_whatsapp_accounts set
    is_enabled = p_is_enabled,
    updated_at = clock_timestamp()
  where account_index = p_account_index;
end $$;

revoke all on function public.platform_whatsapp_account_toggle(integer, boolean) from public, anon;
grant execute on function public.platform_whatsapp_account_toggle(integer, boolean) to authenticated, anon;

-- 11. RPC: Debloke manyèlman yon liy
create or replace function public.platform_whatsapp_account_unrestrict(
  p_account_index integer
) returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.platform_whatsapp_accounts set
    service_status = 'DISCONNECTED',
    restricted_until = null,
    restriction_reason = null,
    updated_at = clock_timestamp()
  where account_index = p_account_index;
end $$;

revoke all on function public.platform_whatsapp_account_unrestrict(integer) from public, anon;
grant execute on function public.platform_whatsapp_account_unrestrict(integer) to authenticated, anon;

-- 12. RPC: Efase yon liy WhatsApp
create or replace function public.platform_whatsapp_account_delete(
  p_account_index integer
) returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.platform_whatsapp_accounts
  where account_index = p_account_index and account_index > 1; -- Pa janm efase plas 1
end $$;

revoke all on function public.platform_whatsapp_account_delete(integer) from public, anon;
grant execute on function public.platform_whatsapp_account_delete(integer) to authenticated, anon;

-- 13. Fonksyon Entèlijan Spintax & Anti-Spam nan cron_check_whatsapp_expiration_reminders
create or replace function public.cron_check_whatsapp_expiration_reminders(
  p_target_gym_id uuid default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_gym record;
  v_sub record;
  v_milestone text;
  v_diff int;
  v_portal_url text;
  v_clean_phone text;
  v_formatted_date text;
  v_queued_count int := 0;
  v_already_logged boolean;
  v_msg text;
  v_seed int;
  v_greeting text;
  v_intro text;
  v_detail text;
  v_action text;
  v_footer text;
  v_ref_hash text;
begin
  -- Boucle sou tout gym ki gen aksè WhatsApp aktif
  for v_gym in
    select 
      g.id as gym_id,
      g.name as gym_name,
      coalesce(g.phone, '') as gym_phone,
      coalesce(a.backup_phone, '') as backup_phone
    from public.gym_whatsapp_access a
    join public.gyms g on g.id = a.gym_id
    where a.is_enabled is true
      and a.status = 'active'
      and a.end_date > clock_timestamp()
      and g.deleted_at is null
      and (p_target_gym_id is null or g.id = p_target_gym_id)
  loop
    v_portal_url := 'https://securgym.com/m/' || v_gym.gym_id::text;

    for v_sub in
      select 
        s.id as sub_id,
        s.member_id,
        s.end_date::date as end_date,
        coalesce(p.name, 'Abonnement Gym') as plan_name,
        m.first_name,
        m.last_name,
        coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')) as raw_phone,
        (s.end_date::date - CURRENT_DATE) as days_diff
      from public.subscriptions s
      join public.members m on m.id = s.member_id
      left join public.plans p on p.id = s.plan_id
      where s.gym_id = v_gym.gym_id
        and s.deleted_at is null
        and m.deleted_at is null
        and (s.end_date::date - CURRENT_DATE) in (7, 2, 0, -1)
      order by s.end_date asc
    loop
      v_diff := v_sub.days_diff;
      if v_sub.raw_phone is null or length(regexp_replace(v_sub.raw_phone, '\D', '', 'g')) < 8 then
        continue;
      end if;

      v_clean_phone := regexp_replace(v_sub.raw_phone, '\D', '', 'g');
      if length(v_clean_phone) = 8 then
        v_clean_phone := '509' || v_clean_phone;
      end if;

      if v_diff = 7 then
        v_milestone := 'reminder_7d';
      elsif v_diff = 2 then
        v_milestone := 'reminder_2d';
      elsif v_diff = 0 then
        v_milestone := 'reminder_0d';
      elsif v_diff = -1 then
        v_milestone := 'reminder_expired';
      else
        continue;
      end if;

      -- Anti-Doublon: pa voye si te deja gen rapèl nan 3 dènye jou yo
      select exists (
        select 1 from public.whatsapp_notification_logs
        where gym_id = v_gym.gym_id
          and member_id = v_sub.member_id
          and kind = v_milestone
          and created_at >= (clock_timestamp() - interval '3 days')
      ) into v_already_logged;

      if v_already_logged then
        continue;
      end if;

      -- Pa voye si deja nan outbox k ap tann
      select exists (
        select 1 from public.whatsapp_messages_outbox
        where gym_id = v_gym.gym_id
          and (to_phone = v_clean_phone or to_phone = v_sub.raw_phone)
          and kind = v_milestone
          and status in ('pending', 'processing')
      ) into v_already_logged;

      if v_already_logged then
        continue;
      end if;

      v_formatted_date := to_char(v_sub.end_date, 'DD/MM/YYYY');
      v_seed := floor(random() * 4)::integer;
      v_ref_hash := substr(md5(random()::text || clock_timestamp()::text), 1, 6);

      -- Spintax Variasyon 1: Salitasyon
      if v_seed = 0 then
        v_greeting := 'Bonjour ' || v_sub.first_name || ' ! 👋';
      elsif v_seed = 1 then
        v_greeting := 'Bonjour cher(e) ' || v_sub.first_name || ' ' || v_sub.last_name || ' ! 🏋️';
      elsif v_seed = 2 then
        v_greeting := 'Salutations ' || v_sub.first_name || ' ! ✨';
      else
        v_greeting := 'Cher(e) membre ' || v_sub.first_name || ', bonjour ! 🏃';
      end if;

      -- Spintax Variasyon 2: Intro
      if v_seed in (0, 2) then
        v_intro := 'Votre salle *' || v_gym.gym_name || '* vous informe :';
      else
        v_intro := 'L''équipe *' || v_gym.gym_name || '* vous transmet ce rappel :';
      end if;

      -- Spintax Variasyon 3: Detay Échéance
      if v_diff = 7 then
        v_detail := 'Votre abonnement (*' || v_sub.plan_name || '*) arrive à son terme dans *7 jours*, le *' || v_formatted_date || '*.';
      elsif v_diff = 2 then
        v_detail := 'Votre abonnement (*' || v_sub.plan_name || '*) arrive à échéance très bientôt, le *' || v_formatted_date || '* (dans 2 jours).';
      elsif v_diff = 0 then
        v_detail := 'Votre abonnement (*' || v_sub.plan_name || '*) prend fin *aujourd''hui*, le *' || v_formatted_date || '*.';
      else
        v_detail := 'Votre abonnement (*' || v_sub.plan_name || '*) est arrivé à échéance hier (*' || v_formatted_date || '*).';
      end if;

      -- Spintax Variasyon 4: Aksyon pou manm nan pran
      if v_seed in (0, 3) then
        v_action := 'Pour conserver votre accès sans coupure, merci de passer à la réception pour renouveler votre forfait.';
      else
        v_action := 'Afin d''éviter tout blocage au tourniquet d''accès, rapprochez-vous de l''accueil de votre salle pour votre réabonnement.';
      end if;

      -- Footer ak enfòmasyon sekirite
      v_footer := '📱 *Enregistrez ce contact SecurGYM* pour être notifié de vos reçus et échéances.' || E'\n' ||
                  'ℹ️ _Pour toute question, contactez directement votre salle' || 
                  case when v_gym.gym_phone <> '' then ' au ' || v_gym.gym_phone else '' end || '._' || E'\n' ||
                  '🌐 Votre espace : ' || v_portal_url || E'\n' ||
                  '🏷️ _Réf: SG-' || v_ref_hash || '_';

      v_msg := v_greeting || E'\n\n' ||
               v_intro || E'\n' ||
               v_detail || E'\n\n' ||
               v_action || E'\n\n' ||
               v_footer;

      -- Mete nan outbox
      insert into public.whatsapp_messages_outbox (
        gym_id, to_phone, message, kind, status, template_seed
      ) values (
        v_gym.gym_id, v_clean_phone, v_msg, v_milestone, 'pending', v_seed
      );

      -- Anrejistre nan logs pou evite doublon
      insert into public.whatsapp_notification_logs (
        gym_id, member_id, member_phone, member_name, kind, message_preview
      ) values (
        v_gym.gym_id, v_sub.member_id, v_clean_phone, (v_sub.first_name || ' ' || v_sub.last_name), v_milestone, substr(v_msg, 1, 140)
      );

      v_queued_count := v_queued_count + 1;
    end loop;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'queued_count', v_queued_count,
    'timestamp', clock_timestamp()
  );
end $$;

commit;
