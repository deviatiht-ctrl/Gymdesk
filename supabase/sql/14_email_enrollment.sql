begin;

alter table public.plans add column if not exists enrollment_price numeric(12,2) check (enrollment_price >= 0);
alter table public.members add column if not exists enrollment_origin text not null default 'new' check (enrollment_origin in ('new', 'existing'));
alter table public.subscriptions add column if not exists opening_credit numeric(12,2) not null default 0 check (opening_credit >= 0 and opening_credit <= price);
alter table public.subscriptions add column if not exists enrollment_kind text not null default 'standard' check (enrollment_kind in ('standard', 'registration', 'import', 'renewal'));

do $$ declare v_table text; begin
  foreach v_table in array array['members','plans','subscriptions'] loop
    execute format('drop policy if exists enrollment_supervisor_insert on public.%I', v_table);
    execute format('create policy enrollment_supervisor_insert on public.%I for insert to authenticated with check (gym_id = public.current_gym_id() and public.current_role() = ''supervisor'')', v_table);
    execute format('drop policy if exists enrollment_supervisor_update on public.%I', v_table);
    execute format('create policy enrollment_supervisor_update on public.%I for update to authenticated using (gym_id = public.current_gym_id() and public.current_role() = ''supervisor'') with check (gym_id = public.current_gym_id() and public.current_role() = ''supervisor'')', v_table);
  end loop;
end $$;
drop policy if exists enrollment_supervisor_payments_read on public.payments;
create policy enrollment_supervisor_payments_read on public.payments for select to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() = 'supervisor');
drop policy if exists enrollment_supervisor_payments_insert on public.payments;
create policy enrollment_supervisor_payments_insert on public.payments for insert to authenticated
  with check (gym_id = public.current_gym_id() and public.current_role() = 'supervisor' and received_by = public.current_staff_id());

create or replace function public.guard_enrollment()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_table_name = 'members' then
    if new.enrollment_origin = 'existing' and (tg_op = 'INSERT' or old.enrollment_origin is distinct from new.enrollment_origin)
       and coalesce(public.current_role(), '') not in ('owner', 'supervisor', 'super_admin') then
      raise exception 'access_denied' using errcode = '42501';
    end if;
  else
    if (new.enrollment_kind = 'import' or new.opening_credit > 0) and
       (tg_op = 'INSERT' or (new.price, new.opening_credit, new.start_date, new.end_date, new.member_id, new.gym_id)
         is distinct from (old.price, old.opening_credit, old.start_date, old.end_date, old.member_id, old.gym_id)) then
      if coalesce(public.current_role(), '') not in ('owner', 'supervisor', 'super_admin') then
        raise exception 'access_denied' using errcode = '42501';
      end if;
      if new.enrollment_kind <> 'import' or new.opening_credit <> new.price
         or not exists (select 1 from public.members where id = new.member_id and gym_id = new.gym_id and enrollment_origin = 'existing') then
        raise exception 'invalid_record' using errcode = '22023';
      end if;
    end if;
    if public.current_role() = 'reception' and new.status = 'active'
       and (new.enrollment_kind = 'renewal' or new.renewed_from is not null or exists (
         select 1 from public.subscriptions where member_id = new.member_id and gym_id = new.gym_id and id <> new.id and deleted_at is null
       )) then
      new.status := 'pending'; new.validated_by := null; new.validated_at := null;
    end if;
    if tg_op = 'UPDATE' and (new.opening_credit is distinct from old.opening_credit or new.enrollment_kind is distinct from old.enrollment_kind) then
      raise exception 'enrollment_immutable' using errcode = '22023';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.guard_enrollment() from public, anon, authenticated;
drop trigger if exists guard_member_enrollment on public.members;
create trigger guard_member_enrollment before insert or update on public.members for each row execute function public.guard_enrollment();
drop trigger if exists guard_subscription_enrollment on public.subscriptions;
create trigger guard_subscription_enrollment before insert or update on public.subscriptions for each row execute function public.guard_enrollment();

create table if not exists public.email_delivery_settings (
  id boolean primary key default true check (id),
  daily_limit int not null default 300 check (daily_limit between 1 and 1000000),
  paused_until timestamptz,
  last_error text
);
insert into public.email_delivery_settings(id) values(true) on conflict do nothing;

create table if not exists public.email_outbox (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id),
  event_key text not null unique,
  kind text not null check (kind in ('gym_welcome', 'member_welcome', 'member_renewal')),
  recipient text not null,
  payload jsonb not null,
  status text not null default 'pending' check (status in ('pending','sending','sent','failed','uncertain')),
  attempts int not null default 0,
  available_at timestamptz not null default clock_timestamp(),
  locked_at timestamptz,
  lease_token uuid,
  message_id text,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists email_outbox_pending on public.email_outbox(available_at, created_at) where status = 'pending';
create table if not exists public.email_delivery_attempts (
  id bigint generated always as identity primary key,
  email_id uuid not null references public.email_outbox(id),
  reserved_at timestamptz not null default clock_timestamp()
);
create index if not exists email_attempts_reserved on public.email_delivery_attempts(reserved_at);

alter table public.email_outbox enable row level security;
alter table public.email_delivery_settings enable row level security;
alter table public.email_delivery_attempts enable row level security;
revoke all on public.email_outbox, public.email_delivery_settings, public.email_delivery_attempts from anon, authenticated;
grant select, insert, update on public.email_outbox, public.email_delivery_settings, public.email_delivery_attempts to service_role;
grant usage, select on sequence public.email_delivery_attempts_id_seq to service_role;

create or replace function public.enqueue_member_email(p_subscription uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s public.subscriptions; m public.members; g public.gyms; p public.plans;
  v_first uuid; v_kind text; v_key text;
begin
  select * into s from public.subscriptions where id = p_subscription and deleted_at is null and status <> 'cancelled';
  if not found then return; end if;
  select * into m from public.members where id = s.member_id and gym_id = s.gym_id and deleted_at is null;
  if not found or coalesce(m.email, '') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then return; end if;
  if not exists (select 1 from public.badges where gym_id = m.gym_id and member_id = m.id and status = 'bound') then return; end if;
  select id into v_first from public.subscriptions where member_id = m.id and gym_id = m.gym_id and deleted_at is null and status <> 'cancelled' order by created_at, id limit 1;
  if s.id = v_first and s.enrollment_kind <> 'renewal' and s.renewed_from is null then
    v_kind := 'member_welcome'; v_key := 'member_welcome:' || m.id;
  elsif s.status = 'active' then
    v_kind := 'member_renewal'; v_key := 'member_renewal:' || s.id;
  else return;
  end if;
  select * into g from public.gyms where id = s.gym_id;
  select * into p from public.plans where id = s.plan_id and gym_id = s.gym_id;
  insert into public.email_outbox(gym_id, event_key, kind, recipient, payload)
  values (g.id, v_key, v_kind, lower(trim(m.email)), jsonb_build_object(
    'gym_name', g.name, 'logo_path', g.logo_url, 'accent_color', g.accent_color,
    'gym_phone', g.phone, 'gym_address', g.address, 'name', m.first_name || ' ' || m.last_name,
    'member_number', m.member_number, 'plan_name', coalesce(p.name, 'Abonnement'),
    'price', s.price, 'currency', coalesce(p.currency, g.currency), 'start_date', s.start_date,
    'end_date', s.end_date, 'status', s.status, 'imported', s.enrollment_kind = 'import'
  )) on conflict(event_key) do nothing;
end $$;
revoke all on function public.enqueue_member_email(uuid) from public, anon, authenticated;

create or replace function public.queue_enrollment_email()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_subscription uuid; v_owner record; v_gym public.gyms;
begin
  if tg_table_name = 'gym_contracts' then
    select s.full_name, u.email into v_owner from public.staff s join auth.users u on u.id = s.user_id
      where s.gym_id = new.gym_id and s.role = 'owner' and s.active and s.deleted_at is null limit 1;
    select * into v_gym from public.gyms where id = new.gym_id;
    if v_owner.email is not null then
      insert into public.email_outbox(gym_id, event_key, kind, recipient, payload)
      values (new.gym_id, 'gym_welcome:' || new.gym_id, 'gym_welcome', v_owner.email, jsonb_build_object(
        'name', v_owner.full_name, 'gym_name', v_gym.name, 'plan_name', coalesce(new.price_snapshot->>'name', new.offer_id),
        'price', new.price_snapshot->'price', 'currency', new.price_snapshot->>'currency',
        'badge_quota', new.price_snapshot->'config'->'badge_quota', 'status', new.status,
        'end_date', to_char(new.expires_at at time zone v_gym.timezone, 'YYYY-MM-DD')
      )) on conflict(event_key) do nothing;
    end if;
  elsif tg_table_name = 'subscriptions' then
    perform public.enqueue_member_email(new.id);
  elsif tg_table_name = 'badges' and new.status = 'bound' and new.member_id is not null then
    if old.member_id is distinct from new.member_id or old.status is distinct from new.status then
      if not exists (select 1 from public.members where id = new.member_id and gym_id = new.gym_id and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then
        raise exception 'invalid_email' using errcode = '22023';
      end if;
      insert into public.badge_history(id, gym_id, badge_id, member_id, event, actor_id, reason)
      values(new.member_id, new.gym_id, new.id, new.member_id, 'bound', public.current_staff_id(), 'Activation de carte')
      on conflict(id) do nothing;
      for v_subscription in select id from public.subscriptions where gym_id = new.gym_id and member_id = new.member_id loop
        perform public.enqueue_member_email(v_subscription);
      end loop;
    end if;
  end if;
  return new;
end $$;
revoke all on function public.queue_enrollment_email() from public, anon, authenticated;
drop trigger if exists email_gym_welcome on public.gym_contracts;
create trigger email_gym_welcome after insert on public.gym_contracts for each row execute function public.queue_enrollment_email();
drop trigger if exists email_subscription on public.subscriptions;
create trigger email_subscription after insert or update on public.subscriptions for each row execute function public.queue_enrollment_email();
drop trigger if exists email_badge_activation on public.badges;
create trigger email_badge_activation after update on public.badges for each row execute function public.queue_enrollment_email();

create or replace function public.claim_email()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_settings public.email_delivery_settings; v_row public.email_outbox;
begin
  select * into v_settings from public.email_delivery_settings where id for update;
  update public.email_outbox set status = 'uncertain', last_error = 'worker_interrupted'
    where status = 'sending' and locked_at < clock_timestamp() - interval '5 minutes';
  if v_settings.paused_until > clock_timestamp() then return null; end if;
  if (select count(*) from public.email_delivery_attempts where reserved_at > clock_timestamp() - interval '24 hours') >= v_settings.daily_limit then return null; end if;
  select * into v_row from public.email_outbox where status = 'pending' and available_at <= clock_timestamp()
    order by created_at, id for update skip locked limit 1;
  if not found then return null; end if;
  update public.email_outbox set status = 'sending', locked_at = clock_timestamp(), lease_token = gen_random_uuid(), attempts = attempts + 1
    where id = v_row.id returning * into v_row;
  insert into public.email_delivery_attempts(email_id) values(v_row.id);
  return to_jsonb(v_row);
end $$;

create or replace function public.finish_email(p_id uuid, p_lease uuid, p_result text, p_message_id text default null, p_error text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_row public.email_outbox; v_wait interval;
begin
  if p_result not in ('sent','retry','quota','configuration','failed','uncertain') then raise exception 'invalid_result'; end if;
  perform 1 from public.email_delivery_settings where id for update;
  select * into v_row from public.email_outbox where id = p_id and lease_token = p_lease and status = 'sending' for update;
  if not found then raise exception 'invalid_lease'; end if;
  v_wait := make_interval(secs => least(3600, (30 * power(2, least(v_row.attempts, 7)))::int));
  if p_result = 'quota' then v_wait := interval '24 hours'; end if;
  if p_result = 'configuration' then v_wait := interval '1 hour'; end if;
  if p_result in ('quota','configuration') then
    update public.email_delivery_settings set paused_until = clock_timestamp() + v_wait, last_error = left(p_error, 80) where id;
  end if;
  update public.email_outbox set
    status = case when p_result in ('retry','quota','configuration') then 'pending' else p_result end,
    message_id = case when p_result = 'sent' then left(p_message_id, 500) else null end,
    sent_at = case when p_result = 'sent' then clock_timestamp() else null end,
    available_at = clock_timestamp() + v_wait, last_error = left(p_error, 80), lease_token = null
  where id = p_id;
end $$;
revoke all on function public.claim_email() from public, anon, authenticated;
revoke all on function public.finish_email(uuid,uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.claim_email(), public.finish_email(uuid,uuid,text,text,text) to service_role;

create or replace function public.email_delivery_status()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_gym uuid := public.current_gym_id(); v_counts jsonb;
begin
  if v_gym is null or coalesce(public.current_role(), '') not in ('owner','supervisor') then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  select jsonb_object_agg(status, total) into v_counts from (
    select status, count(*) as total from public.email_outbox where gym_id = v_gym group by status
  ) counts;
  return jsonb_build_object('counts', coalesce(v_counts, '{}'::jsonb),
    'daily_limit', (select daily_limit from public.email_delivery_settings where id),
    'paused_until', (select paused_until from public.email_delivery_settings where id));
end $$;
revoke all on function public.email_delivery_status() from public, anon;
grant execute on function public.email_delivery_status() to authenticated;

create or replace function public.dispatch_email_worker()
returns void language plpgsql security definer set search_path = '' as $$
declare v_url text; v_token text;
begin
  if to_regclass('vault.decrypted_secrets') is null then return; end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'gymdesk_email_worker_url' limit 1;
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'gymdesk_email_worker_token' limit 1;
  if v_url is null or v_token is null then return; end if;
  perform net.http_post(url := v_url, headers := jsonb_build_object('Content-Type','application/json','x-email-worker-token',v_token), body := '{}'::jsonb, timeout_milliseconds := 120000);
end $$;
revoke all on function public.dispatch_email_worker() from public, anon, authenticated;
do $$ begin
  if exists(select 1 from pg_extension where extname = 'pg_cron') and exists(select 1 from pg_extension where extname = 'pg_net') then
    perform cron.schedule('gymdesk-email-worker', '* * * * *', 'select public.dispatch_email_worker()');
  end if;
end $$;

commit;
