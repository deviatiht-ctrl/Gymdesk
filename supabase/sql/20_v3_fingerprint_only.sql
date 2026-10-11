-- ============================================================================
-- GYMDESK V3 MIGRATION: FINGERPRINT-ONLY, ACTIVE MEMBER QUOTA, CASH SESSIONS,
-- ACCESS EVENTS & FRAUD DETECTION, PAYMENTS SECURITY & ROLE PERMISSIONS
-- ============================================================================
begin;

-- ----------------------------------------------------------------------------
-- 1. Netwaye & Achive relasyon ak Badges (Retire Badge nèt nan lojik la)
-- ----------------------------------------------------------------------------
-- Pa efase tab yo dirèkteman pou pa kase ansyen done achiv yo, men rann yo endepandan.
alter table if exists public.members alter column qr_token drop not null;
alter table if exists public.members add column if not exists fingerprint_enrolled_at timestamptz;
alter table if exists public.members add column if not exists door_user_id int;
alter table if exists public.members add column if not exists marketing_opt_out boolean not null default false;
alter table if exists public.members add column if not exists unsubscribe_token uuid not null default gen_random_uuid();
alter table if exists public.members add column if not exists access_status text not null default 'active'
    check (access_status in ('active', 'pending_payment', 'pending_fingerprint', 'expired', 'suspended', 'archived'));

-- Sekans nimerik door_user_id pa gym pou tèminal pòt yo
create sequence if not exists public.door_user_id_seq minvalue 1001 maxvalue 999999 start 1001;

create or replace function public.assign_door_user_id()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.door_user_id is null then
    new.door_user_id := nextval('public.door_user_id_seq');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_assign_door_user_id on public.members;
create trigger trg_assign_door_user_id
before insert on public.members
for each row execute function public.assign_door_user_id();

-- ----------------------------------------------------------------------------
-- 2. Tab sekirize pou Byometri (member_biometrics) - Aksè sèvè/Agent sèlman
-- ----------------------------------------------------------------------------
create table if not exists public.member_biometrics (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  finger_index smallint not null default 1 check (finger_index between 0 and 9),
  template_enc text not null, -- Chifre oswa fòma estanda ISO/ANSI
  format text not null default 'iso19794-2',
  quality int not null default 80 check (quality between 0 and 100),
  enrolled_by uuid references public.staff(id),
  enrolled_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz,
  constraint uq_member_finger unique(gym_id, member_id, finger_index)
);

alter table public.member_biometrics enable row level security;
revoke all on public.member_biometrics from anon, authenticated;
grant select, insert, update, delete on public.member_biometrics to service_role;

-- Migre nenpòt ki ansyen template ki te nan members si te genyen
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'members' and column_name = 'fingerprint_template'
  ) then
    insert into public.member_biometrics (gym_id, member_id, template_enc, enrolled_at)
    select gym_id, id, fingerprint_template, coalesce(updated_at, clock_timestamp())
    from public.members
    where fingerprint_template is not null and length(fingerprint_template) > 20
    on conflict do nothing;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 3. Kalkil Kota Manm Aktif (Sèlman manm aktif ki konte nan kota a)
-- ----------------------------------------------------------------------------
create or replace function public.gym_member_limit(p_gym uuid)
returns int language plpgsql security definer set search_path = '' as $$
declare
  v_limit int := 0;
  v_contract record;
begin
  select * into v_contract from public.gym_contracts
  where gym_id = p_gym and status in ('trial', 'active', 'grace')
  order by created_at desc limit 1;

  if v_contract.id is not null and v_contract.price_snapshot is not null then
    v_limit := coalesce((v_contract.price_snapshot->'config'->>'max_members')::int, 0);
  end if;

  if v_limit = 0 then
    select coalesce((config->>'max_members')::int, 0) into v_limit
    from public.platform_offers
    where active = true order by sort_order limit 1;
  end if;

  return coalesce(v_limit, 0);
end;
$$;

create or replace function public.gym_active_member_count(p_gym uuid)
returns int language plpgsql security definer set search_path = '' as $$
declare
  v_today date;
  v_tz text := 'America/Port-au-Prince';
  v_count int := 0;
begin
  select coalesce(timezone, 'America/Port-au-Prince') into v_tz from public.gyms where id = p_gym;
  v_today := (clock_timestamp() at time zone v_tz)::date;

  -- Nou konte SÈLMAN manm ki 'active' e ki gen yon abònman valid jodi a
  select count(distinct m.id) into v_count
  from public.members m
  inner join public.subscriptions s on s.member_id = m.id and s.gym_id = m.gym_id
  where m.gym_id = p_gym
    and m.deleted_at is null
    and m.status = 'active'
    and s.deleted_at is null
    and s.status = 'active'
    and s.start_date <= v_today
    and s.end_date >= v_today;

  return coalesce(v_count, 0);
end;
$$;

create or replace function public.gym_quota_state(p_gym uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_gym uuid := coalesce(p_gym, public.current_gym_id());
  v_limit int;
  v_active int;
begin
  if v_gym is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  v_limit := public.gym_member_limit(v_gym);
  v_active := public.gym_active_member_count(v_gym);
  return jsonb_build_object(
    'gym_id', v_gym,
    'active_members', v_active,
    'max_members', v_limit,
    'remaining_slots', case when v_limit > 0 then greatest(0, v_limit - v_active) else 999999 end,
    'quota_exceeded', case when v_limit > 0 and v_active >= v_limit then true else false end
  );
end;
$$;
grant execute on function public.gym_quota_state(uuid) to authenticated;

-- Verifikasyon Kota pandan aktivasyon abònman
create or replace function public.guard_subscription_quota()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_limit int;
  v_active int;
  v_is_already_counted boolean := false;
  v_today date;
  v_tz text := 'America/Port-au-Prince';
begin
  if new.status = 'active' and (tg_op = 'INSERT' or old.status is distinct from 'active') then
    select coalesce(timezone, 'America/Port-au-Prince') into v_tz from public.gyms where id = new.gym_id;
    v_today := (clock_timestamp() at time zone v_tz)::date;

    if new.start_date <= v_today and new.end_date >= v_today then
      v_limit := public.gym_member_limit(new.gym_id);
      if v_limit > 0 then
        -- Verifye si manb sa a pa t deja konte grasa yon lòt abònman aktif
        select exists (
          select 1 from public.subscriptions s
          where s.gym_id = new.gym_id and s.member_id = new.member_id and s.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
            and s.deleted_at is null and s.status = 'active'
            and s.start_date <= v_today and s.end_date >= v_today
        ) into v_is_already_counted;

        if not v_is_already_counted then
          v_active := public.gym_active_member_count(new.gym_id);
          if v_active >= v_limit then
            raise exception 'member_quota_exceeded' using errcode = 'P0001';
          end if;
        end if;
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_subscription_quota on public.subscriptions;
create trigger trg_guard_subscription_quota
before insert or update on public.subscriptions
for each row execute function public.guard_subscription_quota();

-- ----------------------------------------------------------------------------
-- 4. Amelyorasyon Peman: Metòd, Tip, Konfimasyon Obligatwa, Anti-Fwod
-- ----------------------------------------------------------------------------
-- Elaji metòd peman yo
alter table public.payments drop constraint if exists payments_method_check;
alter table public.payments add constraint payments_method_check
    check (method in ('cash', 'moncash', 'natcash', 'bank', 'card', 'cheque', 'other'));

-- Ajoute tip peman ak kolòn konfimasyon
alter table public.payments add column if not exists kind text not null default 'membership'
    check (kind in ('registration', 'membership', 'session', 'renewal', 'other'));
alter table public.payments add column if not exists confirmed_by uuid references public.staff(id);
alter table public.payments add column if not exists confirmed_at timestamptz;
alter table public.payments add column if not exists voided_at timestamptz;
alter table public.payments add column if not exists voided_by uuid references public.staff(id);
alter table public.payments add column if not exists void_reason text;
alter table public.payments add column if not exists cash_session_id uuid;

-- Sekirite: Kesyè PA KA efase oswa anile peman
create or replace function public.guard_payment_security()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'payments_cannot_be_deleted' using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' then
    if new.deleted_at is not null and old.deleted_at is null then
      raise exception 'payments_cannot_be_deleted' using errcode = '42501';
    end if;

    if public.current_role() = 'reception' then
      if new.amount is distinct from old.amount or
         new.method is distinct from old.method or
         new.kind is distinct from old.kind or
         new.voided_at is distinct from old.voided_at then
        raise exception 'reception_cannot_modify_payments' using errcode = '42501';
      end if;
    end if;
  end if;

  -- Referans tranzaksyon obligatwa si se pa Cash
  if new.method in ('moncash', 'natcash', 'bank', 'card', 'cheque') and (new.reference is null or trim(new.reference) = '') then
    raise exception 'payment_reference_required' using errcode = '22023';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_payment_security on public.payments;
create trigger trg_guard_payment_security
before update or delete on public.payments
for each row execute function public.guard_payment_security();

-- RPC pou anile peman (Owner oswa Supervisor sèlman, avèk rezon obligatwa)
create or replace function public.void_payment(p_payment uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_gym uuid := public.current_gym_id();
  v_pay public.payments;
begin
  if public.current_role() not in ('owner', 'supervisor') and not public.is_super_admin() then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  if p_reason is null or length(trim(p_reason)) < 5 then
    raise exception 'reason_required' using errcode = '22023';
  end if;

  select * into strict v_pay from public.payments where id = p_payment and gym_id = v_gym;
  if v_pay.voided_at is not null then
    raise exception 'already_voided' using errcode = '22023';
  end if;

  update public.payments
  set voided_at = clock_timestamp(),
      voided_by = public.current_staff_id(),
      void_reason = trim(p_reason),
      updated_at = clock_timestamp()
  where id = p_payment;

  perform public.audit('payment_voided', 'payments', p_payment, jsonb_build_object('reason', p_reason, 'amount', v_pay.amount));

  return jsonb_build_object('success', true, 'payment_id', p_payment);
end;
$$;
grant execute on function public.void_payment(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. Jesyon Kès (cash_sessions) pou Klòti ak Kontwòl Kesyè
-- ----------------------------------------------------------------------------
create table if not exists public.cash_sessions (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  staff_id uuid not null references public.staff(id),
  opened_at timestamptz not null default clock_timestamp(),
  closed_at timestamptz,
  opening_float numeric(12,2) not null default 0 check (opening_float >= 0),
  expected_cash numeric(12,2) not null default 0,
  counted_cash numeric(12,2),
  difference numeric(12,2),
  status text not null default 'open' check (status in ('open', 'closed')),
  notes text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

alter table public.cash_sessions enable row level security;

create policy cash_sessions_select on public.cash_sessions for select to authenticated
  using (
    gym_id = public.current_gym_id() and
    (public.current_role() in ('owner', 'supervisor') or staff_id = public.current_staff_id())
  );

create policy cash_sessions_insert on public.cash_sessions for insert to authenticated
  with check (gym_id = public.current_gym_id() and staff_id = public.current_staff_id());

create policy cash_sessions_update on public.cash_sessions for update to authenticated
  using (gym_id = public.current_gym_id() and (public.current_role() in ('owner', 'supervisor') or staff_id = public.current_staff_id()))
  with check (gym_id = public.current_gym_id());

-- RPCs pou ouvri ak fèmen sesyon kès
create or replace function public.open_cash_session(p_opening_float numeric default 0)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_gym uuid := public.current_gym_id();
  v_staff uuid := public.current_staff_id();
  v_existing public.cash_sessions;
  v_session public.cash_sessions;
begin
  if v_gym is null or v_staff is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  select * into v_existing from public.cash_sessions
  where gym_id = v_gym and staff_id = v_staff and status = 'open' limit 1;
  if v_existing.id is not null then
    return to_jsonb(v_existing);
  end if;

  insert into public.cash_sessions(gym_id, staff_id, opening_float, expected_cash, status)
  values(v_gym, v_staff, coalesce(p_opening_float, 0), coalesce(p_opening_float, 0), 'open')
  returning * into v_session;

  perform public.audit('cash_session_opened', 'cash_sessions', v_session.id, jsonb_build_object('float', p_opening_float));
  return to_jsonb(v_session);
end;
$$;
grant execute on function public.open_cash_session(numeric) to authenticated;

create or replace function public.close_cash_session(
  p_session uuid,
  p_counted numeric,
  p_notes text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_gym uuid := public.current_gym_id();
  v_staff uuid := public.current_staff_id();
  v_session public.cash_sessions;
  v_total_cash numeric := 0;
begin
  select * into strict v_session from public.cash_sessions
  where id = p_session and gym_id = v_gym;

  if v_session.status = 'closed' then
    return to_jsonb(v_session);
  end if;

  -- Kalkile tout kob cash ki antre nan sesyon sa a (pa anile)
  select coalesce(sum(amount), 0) into v_total_cash
  from public.payments
  where gym_id = v_gym
    and received_by = v_session.staff_id
    and method = 'cash'
    and voided_at is null
    and paid_at >= v_session.opened_at
    and paid_at <= clock_timestamp();

  update public.cash_sessions
  set closed_at = clock_timestamp(),
      status = 'closed',
      expected_cash = v_session.opening_float + v_total_cash,
      counted_cash = p_counted,
      difference = p_counted - (v_session.opening_float + v_total_cash),
      notes = p_notes,
      updated_at = clock_timestamp()
  where id = p_session
  returning * into v_session;

  perform public.audit('cash_session_closed', 'cash_sessions', v_session.id,
    jsonb_build_object('expected', v_session.expected_cash, 'counted', p_counted, 'diff', v_session.difference));

  return to_jsonb(v_session);
end;
$$;
grant execute on function public.close_cash_session(uuid, numeric, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 6. Evènman Pòt & Deteksyon Fwod ("Ti Kle" / Ouvèti Sispèk) (access_events)
-- ----------------------------------------------------------------------------
create table if not exists public.access_events (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  member_id uuid references public.members(id) on delete set null,
  event_type text not null check (
    event_type in (
      'granted',
      'denied_expired',
      'denied_pending',
      'denied_no_subscription',
      'denied_suspended',
      'denied_no_fingerprint',
      'denied_unknown',
      'door_forced',
      'door_manual_open',
      'exit_button',
      'door_held_open'
    )
  ),
  source text not null default 'terminal' check (source in ('terminal', 'agent', 'app')),
  device_id text,
  occurred_at timestamptz not null default clock_timestamp(),
  server_received_at timestamptz not null default clock_timestamp(),
  staff_id uuid references public.staff(id),
  reason text,
  details jsonb default '{}'::jsonb,
  member_snapshot jsonb -- Non, plan, dat fen, foto, pou popup rapid
);

create index if not exists idx_access_events_gym_time on public.access_events(gym_id, server_received_at desc);

alter table public.access_events enable row level security;
create policy access_events_select on public.access_events for select to authenticated
  using (gym_id = public.current_gym_id());
create policy access_events_insert on public.access_events for insert to authenticated
  with check (gym_id = public.current_gym_id());

-- Pibliye sou Realtime pou popup an dirèk
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.access_events;
  end if;
exception when others then null;
end $$;

-- RPC pou ouvri pòt manyèlman (avèk rezon odite pou evite fwod)
create or replace function public.manual_door_open(p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_gym uuid := public.current_gym_id();
  v_staff uuid := public.current_staff_id();
  v_event public.access_events;
begin
  if v_gym is null or v_staff is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'reason_required' using errcode = '22023';
  end if;

  insert into public.access_events(gym_id, event_type, source, staff_id, reason, details)
  values(v_gym, 'door_manual_open', 'app', v_staff, trim(p_reason), jsonb_build_object('actor', v_staff))
  returning * into v_event;

  perform public.audit('manual_door_open', 'access_events', v_event.id, jsonb_build_object('reason', p_reason));

  return jsonb_build_object('success', true, 'event_id', v_event.id);
end;
$$;
grant execute on function public.manual_door_open(text) to authenticated;

-- ----------------------------------------------------------------------------
-- 7. Sekirite RLS Resepsyon (Kesyè pa ka efase manm ni plan ni modifye pri)
-- ----------------------------------------------------------------------------
create or replace function public.guard_member_deletion()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    if public.current_role() <> 'owner' and not public.is_super_admin() then
      raise exception 'access_denied: sèlman pwopryetè a ka efase yon manm' using errcode = '42501';
    end if;
  end if;
  if tg_op = 'UPDATE' and new.deleted_at is not null and old.deleted_at is null then
    if public.current_role() <> 'owner' and not public.is_super_admin() then
      raise exception 'access_denied: sèlman pwopryetè a ka achive yon manm' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_member_deletion on public.members;
create trigger trg_guard_member_deletion
before update or delete on public.members
for each row execute function public.guard_member_deletion();

-- ----------------------------------------------------------------------------
-- 8. Ranplase enqueue_member_email pou li PA depann sou badges ankò!
-- ----------------------------------------------------------------------------
create or replace function public.enqueue_member_email(p_subscription uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s public.subscriptions;
  m public.members;
  g public.gyms;
  p public.plans;
  v_first uuid;
  v_kind text;
  v_key text;
begin
  select * into s from public.subscriptions where id = p_subscription and deleted_at is null and status <> 'cancelled';
  if not found then return; end if;

  select * into m from public.members where id = s.member_id and gym_id = s.gym_id and deleted_at is null;
  if not found or coalesce(m.email, '') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then return; end if;

  -- NOUVÈL REG V3: Nou PA verifye si gen badge ankò! Olye de sa, nou voye depi se premye abònman oswa renouvèlman.
  select id into v_first from public.subscriptions
  where member_id = m.id and gym_id = s.gym_id and deleted_at is null and status <> 'cancelled'
  order by created_at, id limit 1;

  if s.id = v_first and s.enrollment_kind <> 'renewal' and s.renewed_from is null then
    v_kind := 'member_welcome';
    v_key := 'member_welcome:' || m.id;
  elsif s.status = 'active' then
    v_kind := 'member_renewal';
    v_key := 'member_renewal:' || s.id;
  else
    return;
  end if;

  select * into g from public.gyms where id = s.gym_id;
  select * into p from public.plans where id = s.plan_id and gym_id = s.gym_id;

  insert into public.email_outbox(
    gym_id, event_key, kind, recipient, payload, status, available_at
  )
  values (
    s.gym_id,
    v_key,
    v_kind,
    m.email,
    jsonb_build_object(
      'gym_id', g.id,
      'gym_name', g.name,
      'gym_phone', g.phone,
      'gym_address', g.address,
      'accent_color', g.accent_color,
      'logo_url', g.logo_url,
      'member_id', m.id,
      'member_number', m.member_number,
      'name', m.first_name || ' ' || m.last_name,
      'email', m.email,
      'phone', m.phone,
      'whatsapp', m.whatsapp,
      'plan_name', p.name,
      'start_date', s.start_date,
      'end_date', s.end_date,
      'price', s.price,
      'currency', coalesce(g.currency, 'HTG'),
      'status', s.status,
      'imported', (s.enrollment_kind = 'import' or s.opening_credit > 0)
    ),
    'pending',
    clock_timestamp()
  )
  on conflict (event_key) do nothing;
end;
$$;

commit;
