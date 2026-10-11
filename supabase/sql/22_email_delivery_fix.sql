-- ============================================================================
-- 22 — Email delivery fix (idempotent). Apply after 21_messaging.sql.
--  * email_outbox accepts every kind produced by 21 (reminders, campaigns, receipts)
--  * payloads carry logo_path (what the worker signs) and reply_to (gym email)
--  * daily renewal reminders are scheduled with pg_cron
--  * campaigns are queued server-side for the selected members
--  * the provider configuration is managed by the super admin only
-- ============================================================================
begin;

alter table public.email_outbox drop constraint if exists email_outbox_kind_check;
alter table public.email_outbox add constraint email_outbox_kind_check
  check (kind in ('gym_welcome', 'member_welcome', 'member_renewal', 'renewal_reminder', 'campaign', 'payment_receipt'));

-- 20 ordered by platform_offers.sort_order, which does not exist: every active subscription
-- of a gym without max_members in its contract failed, so the member never synced nor got an email.
create or replace function public.gym_member_limit(p_gym uuid)
returns int language plpgsql security definer set search_path = '' as $$
declare v_limit int := 0; v_contract record;
begin
  select * into v_contract from public.gym_contracts
    where gym_id = p_gym and status in ('trial', 'active', 'grace') order by created_at desc limit 1;
  if v_contract.id is not null and v_contract.price_snapshot is not null then
    v_limit := coalesce((v_contract.price_snapshot->'config'->>'max_members')::int, 0);
  end if;
  if v_limit = 0 then
    select coalesce((config->>'max_members')::int, 0) into v_limit
      from public.platform_offers where active = true order by created_at, id limit 1;
  end if;
  return coalesce(v_limit, 0);
end $$;

alter table public.campaigns drop constraint if exists campaigns_template_key_check;
alter table public.campaigns add constraint campaigns_template_key_check check (length(template_key) between 1 and 40);

-- ----------------------------------------------------------------------------
-- Provider configuration (super admin only, never readable by gym staff)
-- ----------------------------------------------------------------------------
create table if not exists public.platform_email_config (
  id boolean primary key default true check (id),
  api_key text,
  sender_email text check (sender_email is null or sender_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  sender_name text not null default 'GymDesk',
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid
);
insert into public.platform_email_config(id) values (true) on conflict do nothing;
alter table public.platform_email_config enable row level security;
revoke all on public.platform_email_config from public, anon, authenticated;
grant select on public.platform_email_config to service_role;

create or replace function public.platform_email_config_get()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare c public.platform_email_config; d public.email_delivery_settings; v_counts jsonb;
begin
  if not public.is_super_admin() then raise exception 'access_denied' using errcode = '42501'; end if;
  select * into c from public.platform_email_config where id;
  select * into d from public.email_delivery_settings where id;
  select jsonb_object_agg(status, total) into v_counts from (
    select status, count(*) as total from public.email_outbox group by status
  ) t;
  return jsonb_build_object(
    'has_key', coalesce(length(c.api_key), 0) > 0,
    'key_hint', case when coalesce(length(c.api_key), 0) > 8 then '••••' || right(c.api_key, 4) end,
    'sender_email', c.sender_email, 'sender_name', c.sender_name, 'updated_at', c.updated_at,
    'daily_limit', d.daily_limit, 'paused_until', d.paused_until, 'last_error', d.last_error,
    'counts', coalesce(v_counts, '{}'::jsonb));
end $$;
revoke all on function public.platform_email_config_get() from public, anon;
grant execute on function public.platform_email_config_get() to authenticated;

create or replace function public.platform_email_config_set(
  p_sender_email text, p_sender_name text, p_daily_limit int, p_api_key text default null
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_super_admin() then raise exception 'access_denied' using errcode = '42501'; end if;
  if p_sender_email is null or trim(p_sender_email) !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or length(trim(coalesce(p_sender_name, ''))) not between 2 and 80
     or p_daily_limit is null or p_daily_limit not between 1 and 1000000
     or (nullif(trim(p_api_key), '') is not null and length(trim(p_api_key)) not between 20 and 200) then
    raise exception 'invalid_record' using errcode = '22023';
  end if;
  update public.platform_email_config set
    sender_email = lower(trim(p_sender_email)), sender_name = trim(p_sender_name),
    api_key = coalesce(nullif(trim(p_api_key), ''), api_key),
    updated_at = clock_timestamp(), updated_by = auth.uid()
  where id;
  update public.email_delivery_settings set daily_limit = p_daily_limit, paused_until = null, last_error = null where id;
end $$;
revoke all on function public.platform_email_config_set(text, text, int, text) from public, anon;
grant execute on function public.platform_email_config_set(text, text, int, text) to authenticated;

create or replace function public.email_worker_config()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('api_key', api_key, 'sender_email', sender_email, 'sender_name', sender_name)
  from public.platform_email_config where id;
$$;
revoke all on function public.email_worker_config() from public, anon, authenticated;
grant execute on function public.email_worker_config() to service_role;

-- ----------------------------------------------------------------------------
-- Reply-To: the gym email, otherwise the owner's login email
-- ----------------------------------------------------------------------------
create or replace function public.gym_reply_to(p_gym uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select lower(trim(email)) from public.gyms where id = p_gym and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
    (select lower(u.email) from public.staff s join auth.users u on u.id = s.user_id
      where s.gym_id = p_gym and s.role = 'owner' and s.active and s.deleted_at is null order by s.created_at limit 1));
$$;
revoke all on function public.gym_reply_to(uuid) from public, anon, authenticated;

create or replace function public.gym_email_branding(p_gym uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('gym_id', g.id, 'gym_name', g.name, 'logo_path', g.logo_url, 'accent_color', g.accent_color,
    'gym_phone', g.phone, 'gym_address', g.address, 'reply_to', public.gym_reply_to(g.id))
  from public.gyms g where g.id = p_gym;
$$;
revoke all on function public.gym_email_branding(uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- Welcome / renewal (replaces 20: logo_path + reply_to)
-- ----------------------------------------------------------------------------
create or replace function public.enqueue_member_email(p_subscription uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare s public.subscriptions; m public.members; g public.gyms; p public.plans; v_first uuid; v_kind text; v_key text;
begin
  select * into s from public.subscriptions where id = p_subscription and deleted_at is null and status <> 'cancelled';
  if not found then return; end if;
  select * into m from public.members where id = s.member_id and gym_id = s.gym_id and deleted_at is null;
  if not found or coalesce(m.email, '') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then return; end if;
  select id into v_first from public.subscriptions
    where member_id = m.id and gym_id = s.gym_id and deleted_at is null and status <> 'cancelled'
    order by created_at, id limit 1;
  if s.id = v_first and s.enrollment_kind <> 'renewal' and s.renewed_from is null then
    v_kind := 'member_welcome'; v_key := 'member_welcome:' || m.id;
  elsif s.status = 'active' then
    v_kind := 'member_renewal'; v_key := 'member_renewal:' || s.id;
  else return;
  end if;
  select * into g from public.gyms where id = s.gym_id;
  select * into p from public.plans where id = s.plan_id and gym_id = s.gym_id;
  insert into public.email_outbox(gym_id, event_key, kind, recipient, payload)
  values (s.gym_id, v_key, v_kind, lower(trim(m.email)), public.gym_email_branding(g.id) || jsonb_build_object(
    'member_id', m.id, 'member_number', m.member_number, 'name', trim(m.first_name || ' ' || m.last_name),
    'plan_name', coalesce(p.name, 'Abonnement'), 'start_date', s.start_date, 'end_date', s.end_date,
    'price', s.price, 'currency', coalesce(p.currency, g.currency, 'HTG'), 'status', s.status,
    'imported', (s.enrollment_kind = 'import' or s.opening_credit > 0)))
  on conflict (event_key) do nothing;
end $$;
revoke all on function public.enqueue_member_email(uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- Renewal reminders J-7, J-3, J-1, J0 (skips members who already renewed)
-- ----------------------------------------------------------------------------
create or replace function public.process_daily_reminders()
returns void language plpgsql security definer set search_path = '' as $$
declare v_gym record; v_sub record; v_today date; v_days int;
begin
  for v_gym in select * from public.gyms where status in ('active', 'trial', 'grace') and deleted_at is null loop
    v_today := (clock_timestamp() at time zone coalesce(v_gym.timezone, 'America/Port-au-Prince'))::date;
    for v_sub in
      select s.id, s.end_date, coalesce(p.price, s.price) as renewal_price, coalesce(p.currency, v_gym.currency, 'HTG') as currency,
             p.name as plan_name, m.first_name, m.last_name, m.email, m.member_number
      from public.subscriptions s
      join public.members m on m.id = s.member_id and m.gym_id = s.gym_id
      left join public.plans p on p.id = s.plan_id
      where s.gym_id = v_gym.id and s.status = 'active' and s.deleted_at is null and m.deleted_at is null
        and m.email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
        and s.end_date between v_today and v_today + 7
        and not exists (select 1 from public.subscriptions n where n.member_id = s.member_id and n.gym_id = s.gym_id
          and n.id <> s.id and n.deleted_at is null and n.status in ('active', 'pending') and n.end_date > s.end_date)
    loop
      v_days := v_sub.end_date - v_today;
      continue when v_days not in (7, 3, 1, 0);
      insert into public.email_outbox(gym_id, event_key, kind, recipient, payload)
      values (v_gym.id, 'reminder:' || v_sub.id || ':' || v_days, 'renewal_reminder', lower(trim(v_sub.email)),
        public.gym_email_branding(v_gym.id) || jsonb_build_object(
          'name', trim(v_sub.first_name || ' ' || v_sub.last_name), 'member_number', v_sub.member_number,
          'plan_name', coalesce(v_sub.plan_name, 'Abonnement'), 'end_date', v_sub.end_date, 'days_left', v_days,
          'renewal_price', v_sub.renewal_price, 'currency', v_sub.currency))
      on conflict (event_key) do nothing;
    end loop;
  end loop;
end $$;
revoke all on function public.process_daily_reminders() from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- Campaigns: queued server-side for the members selected in the app
-- ----------------------------------------------------------------------------
create or replace function public.campaign_send_members(
  p_title text, p_subject text, p_body text, p_template_key text, p_member_ids uuid[], p_filter jsonb default '{}'::jsonb
) returns int language plpgsql security definer set search_path = '' as $$
declare v_gym uuid := public.current_gym_id(); v_campaign uuid := gen_random_uuid(); v_brand jsonb; v_count int := 0; r record;
begin
  if v_gym is null or public.current_role() not in ('owner', 'supervisor') then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_title, ''))) not between 1 and 200 or length(trim(coalesce(p_subject, ''))) not between 1 and 200
     or length(trim(coalesce(p_body, ''))) not between 1 and 10000 or coalesce(cardinality(p_member_ids), 0) not between 1 and 5000 then
    raise exception 'invalid_record' using errcode = '22023';
  end if;
  v_brand := public.gym_email_branding(v_gym);
  insert into public.campaigns(id, gym_id, title, subject, body_text, template_key, filter, status, created_by)
  values (v_campaign, v_gym, trim(p_title), trim(p_subject), trim(p_body), coalesce(nullif(trim(p_template_key), ''), 'custom'),
    coalesce(p_filter, '{}'::jsonb), 'sending', public.current_staff_id());
  for r in
    select m.id, lower(trim(m.email)) as email, trim(m.first_name || ' ' || m.last_name) as name
    from public.members m
    where m.gym_id = v_gym and m.id = any(p_member_ids) and m.deleted_at is null
      and coalesce(m.marketing_opt_out, false) = false
      and m.email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  loop
    insert into public.email_outbox(gym_id, event_key, kind, recipient, payload)
    values (v_gym, 'campaign:' || v_campaign || ':' || r.id, 'campaign', r.email, v_brand || jsonb_build_object(
      'name', r.name, 'campaign_title', replace(replace(trim(p_title), '{nom}', r.name), '{gym}', v_brand->>'gym_name'),
      'subject', replace(replace(trim(p_subject), '{nom}', r.name), '{gym}', v_brand->>'gym_name'),
      'body_text', replace(replace(replace(replace(trim(p_body), '{nom}', r.name), '{non}', r.name), '{name}', r.name), '{gym}', v_brand->>'gym_name')))
    on conflict (event_key) do nothing;
    insert into public.campaign_recipients(campaign_id, member_id, recipient, channel, status)
    values (v_campaign, r.id, r.email, 'email', 'pending');
    v_count := v_count + 1;
  end loop;
  update public.campaigns set status = 'sent', sent_at = clock_timestamp(), recipient_count = v_count, updated_at = clock_timestamp()
    where id = v_campaign;
  return v_count;
end $$;
revoke all on function public.campaign_send_members(text, text, text, text, uuid[], jsonb) from public, anon;
grant execute on function public.campaign_send_members(text, text, text, text, uuid[], jsonb) to authenticated;

-- Jobs already queued by 20/21 stored the logo under logo_url and had no reply_to
update public.email_outbox
  set payload = payload || jsonb_build_object('logo_path', payload->>'logo_url', 'reply_to', public.gym_reply_to(gym_id))
  where status = 'pending' and payload ? 'logo_url' and not payload ? 'logo_path';

do $$ begin
  if exists(select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('gymdesk-renewal-reminders', '0 12 * * *', 'select public.process_daily_reminders()');
  end if;
end $$;

commit;
