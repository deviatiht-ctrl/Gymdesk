-- ============================================================================
-- GYMDESK V3: MESSAGING, CAMPAIGNS, AUTOMATED EXPIRATION REMINDERS & BREVO INTEGRATION
-- ============================================================================
begin;

-- 1. Tab Kanpay Email & Mesaj Maketing
create table if not exists public.campaigns (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  title text not null,
  subject text not null,
  body_text text not null,
  template_key text not null default 'announcement' check (template_key in ('announcement', 'price_change', 'promotion', 'event', 'custom')),
  filter jsonb not null default '{}'::jsonb,
  channels text[] not null default array['email']::text[],
  status text not null default 'draft' check (status in ('draft', 'scheduled', 'sending', 'sent', 'cancelled')),
  scheduled_at timestamptz,
  sent_at timestamptz,
  recipient_count int not null default 0,
  created_by uuid references public.staff(id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create table if not exists public.campaign_recipients (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  member_id uuid references public.members(id) on delete set null,
  recipient text not null, -- email oswa nimewo whatsapp
  channel text not null default 'email' check (channel in ('email', 'whatsapp')),
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed')),
  sent_at timestamptz,
  last_error text
);

alter table public.campaigns enable row level security;
alter table public.campaign_recipients enable row level security;

create policy campaigns_owner_supervisor on public.campaigns for all to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor'))
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor'));

create policy campaign_recipients_owner_supervisor on public.campaign_recipients for select to authenticated
  using (exists (select 1 from public.campaigns c where c.id = campaign_id and c.gym_id = public.current_gym_id()));

-- 2. RPC pou Preview Moun kap resevwa kanpay la selon filtè a
create or replace function public.campaign_preview(p_filter jsonb default '{}'::jsonb)
returns table(
  member_id uuid,
  name text,
  email text,
  phone text,
  whatsapp text,
  status text,
  end_date date,
  plan_name text
) language plpgsql security definer set search_path = '' as $$
declare
  v_gym uuid := public.current_gym_id();
  v_today date;
  v_tz text := 'America/Port-au-Prince';
  v_filter_status text := p_filter->>'status';
  v_expiring_days int := coalesce((p_filter->>'expiring_days')::int, 7);
  v_inactive_days int := coalesce((p_filter->>'inactive_days')::int, 14);
begin
  if v_gym is null or public.current_role() not in ('owner', 'supervisor') then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  select coalesce(timezone, 'America/Port-au-Prince') into v_tz from public.gyms where id = v_gym;
  v_today := (clock_timestamp() at time zone v_tz)::date;

  return query
  select distinct
    m.id as member_id,
    (m.first_name || ' ' || m.last_name) as name,
    m.email,
    m.phone,
    m.whatsapp,
    m.status,
    s.end_date,
    p.name as plan_name
  from public.members m
  left join lateral (
    select sub.end_date, sub.plan_id
    from public.subscriptions sub
    where sub.member_id = m.id and sub.gym_id = m.gym_id and sub.deleted_at is null
    order by sub.end_date desc limit 1
  ) s on true
  left join public.plans p on p.id = s.plan_id
  where m.gym_id = v_gym
    and m.deleted_at is null
    and coalesce(m.marketing_opt_out, false) = false
    and (m.email is not null and m.email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$')
    and (
      v_filter_status is null or v_filter_status = 'all'
      or (v_filter_status = 'active' and m.status = 'active' and s.end_date >= v_today)
      or (v_filter_status = 'expired' and (s.end_date < v_today or m.status = 'expired'))
      or (v_filter_status = 'expiring' and s.end_date between v_today and (v_today + v_expiring_days))
      or (v_filter_status = 'pending_fingerprint' and (m.fingerprint_registered is null or m.fingerprint_registered = false))
    );
end;
$$;
grant execute on function public.campaign_preview(jsonb) to authenticated;

-- 3. RPC pou Voye oswa Pwograme Kanpay la nan Outbox Brevo
create or replace function public.campaign_send(p_campaign uuid)
returns int language plpgsql security definer set search_path = '' as $$
declare
  v_gym uuid := public.current_gym_id();
  v_c public.campaigns;
  v_g public.gyms;
  v_count int := 0;
  v_row record;
  v_key text;
begin
  if v_gym is null or public.current_role() not in ('owner', 'supervisor') then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  select * into strict v_c from public.campaigns where id = p_campaign and gym_id = v_gym;
  select * into strict v_g from public.gyms where id = v_gym;

  for v_row in select * from public.campaign_preview(v_c.filter) loop
    v_key := 'campaign:' || v_c.id || ':' || v_row.member_id;

    -- Ajoute nan email_outbox pou Brevo
    insert into public.email_outbox (
      gym_id, event_key, kind, recipient, payload, status, available_at
    )
    values (
      v_gym,
      v_key,
      'campaign',
      v_row.email,
      jsonb_build_object(
        'gym_id', v_gym,
        'gym_name', v_g.name,
        'logo_url', v_g.logo_url,
        'accent_color', v_g.accent_color,
        'gym_phone', v_g.phone,
        'gym_address', v_g.address,
        'name', v_row.name,
        'campaign_title', v_c.title,
        'subject', v_c.subject,
        'body_text', v_c.body_text,
        'template_key', v_c.template_key
      ),
      'pending',
      coalesce(v_c.scheduled_at, clock_timestamp())
    )
    on conflict (event_key) do nothing;

    insert into public.campaign_recipients(campaign_id, member_id, recipient, channel, status)
    values (v_c.id, v_row.member_id, v_row.email, 'email', 'pending');

    v_count := v_count + 1;
  end loop;

  update public.campaigns
  set status = 'sent',
      sent_at = clock_timestamp(),
      recipient_count = v_count,
      updated_at = clock_timestamp()
  where id = v_c.id;

  perform public.audit('campaign_sent', 'campaigns', v_c.id, jsonb_build_object('recipients', v_count, 'subject', v_c.subject));

  return v_count;
end;
$$;
grant execute on function public.campaign_send(uuid) to authenticated;

-- 4. Rapèl Otomatik Abònman k ap Fini (J-7, J-3, J-1, J0) via Brevo
create or replace function public.process_daily_reminders()
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_gym record;
  v_sub record;
  v_today date;
  v_days_left int;
  v_key text;
begin
  for v_gym in select * from public.gyms where status in ('active', 'trial', 'grace') loop
    v_today := (clock_timestamp() at time zone coalesce(v_gym.timezone, 'America/Port-au-Prince'))::date;

    for v_sub in
      select
        s.id as sub_id,
        s.gym_id,
        s.end_date,
        s.price,
        p.name as plan_name,
        m.id as member_id,
        m.first_name,
        m.last_name,
        m.email,
        m.whatsapp
      from public.subscriptions s
      join public.members m on m.id = s.member_id and m.gym_id = s.gym_id
      left join public.plans p on p.id = s.plan_id
      where s.gym_id = v_gym.id
        and s.status = 'active'
        and s.deleted_at is null
        and m.deleted_at is null
        and m.email is not null and m.email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
        and s.end_date between (v_today - 1) and (v_today + 7)
    loop
      v_days_left := v_sub.end_date - v_today;

      -- Rapèl nan J-7, J-3, J-1, oswa J0 (Jou li fini an)
      if v_days_left in (7, 3, 1, 0) then
        v_key := 'reminder:' || v_sub.sub_id || ':' || v_days_left || ':' || v_today;

        insert into public.email_outbox(
          gym_id, event_key, kind, recipient, payload, status, available_at
        )
        values (
          v_gym.id,
          v_key,
          'renewal_reminder',
          v_sub.email,
          jsonb_build_object(
            'gym_id', v_gym.id,
            'gym_name', v_gym.name,
            'logo_url', v_gym.logo_url,
            'accent_color', v_gym.accent_color,
            'gym_phone', v_gym.phone,
            'gym_address', v_gym.address,
            'name', v_sub.first_name || ' ' || v_sub.last_name,
            'plan_name', v_sub.plan_name,
            'end_date', v_sub.end_date,
            'days_left', v_days_left,
            'renewal_price', v_sub.price,
            'currency', coalesce(v_gym.currency, 'HTG')
          ),
          'pending',
          clock_timestamp()
        )
        on conflict (event_key) do nothing;
      end if;
    end loop;
  end loop;
end;
$$;

commit;
