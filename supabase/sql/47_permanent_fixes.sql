-- ============================================================================
-- 47_permanent_fixes.sql — Correctifs Permanents SecurGYM (Idempotent)
--  1. Rôles 'supervisor' / 'secretaire' : provisioning, RLS, Storage, Sync
--  2. Accès salles 'trial' / 'grace' dans is_gym_active & staff_owner_gym
--  3. Caisse (cash_sessions) : ouverture/fermeture fiables + supervision owner
--  4. WhatsApp : correction colonnes logs, rappels STRICTEMENT J-7 et J-2,
--     anti-doublon strict logs + outbox, Contrôle des messages (batch + stats),
--     et pont commandes à distance pour Agrandir Chat depuis Vercel Web.
-- ============================================================================
begin;

-- ----------------------------------------------------------------------------
-- 1. Rôles personnel + gyms 'active' / 'trial' / 'grace'
-- ----------------------------------------------------------------------------
alter table public.staff drop constraint if exists staff_role_check;
alter table public.staff add constraint staff_role_check
  check (role in ('super_admin', 'owner', 'supervisor', 'manager', 'reception'));

create or replace function public.current_gym_id()
returns uuid
language sql stable security definer
set search_path = ''
as $$
  select s.gym_id
  from public.staff s
  join public.gyms g on g.id = s.gym_id
  where s.user_id = auth.uid()
    and s.active is true
    and s.deleted_at is null
    and g.status in ('active', 'trial', 'grace')
    and g.deleted_at is null
  limit 1
$$;

create or replace function public.is_gym_active(p_gym uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.gyms g
    where g.id = p_gym
      and g.status in ('active', 'trial', 'grace')
      and g.deleted_at is null
      and (
        public.is_super_admin()
        or exists(
          select 1 from public.staff s
          where s.user_id = auth.uid()
            and s.gym_id = g.id
            and s.active is true
            and s.deleted_at is null
        )
      )
  )
$$;

create or replace function public.staff_owner_gym(p_actor uuid)
returns uuid
language plpgsql stable security definer
set search_path = ''
as $$
declare v_gym uuid;
begin
  select s.gym_id into v_gym
  from public.staff s
  join public.gyms g on g.id = s.gym_id
  where s.user_id = p_actor
    and s.role = 'owner'
    and s.active is true
    and s.deleted_at is null
    and g.status in ('active', 'trial', 'grace')
    and g.deleted_at is null
  limit 1;
  if v_gym is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  return v_gym;
end $$;

-- ----------------------------------------------------------------------------
-- 2. Provisioning & Gestion du personnel (supervisor / manager / reception)
-- ----------------------------------------------------------------------------
create or replace function public.staff_provision_begin(
  p_request uuid,
  p_actor uuid,
  p_staff uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym uuid := public.staff_owner_gym(p_actor);
  r public.staff_provisioning;
begin
  if p_request is null or p_staff is null or p_payload is null
    or coalesce(p_payload->>'role', '') not in ('supervisor', 'manager', 'reception')
    or char_length(trim(coalesce(p_payload->>'full_name', ''))) not between 2 and 120
    or coalesce(p_payload->>'email', '') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or char_length(coalesce(p_payload->>'email', '')) > 254
    or char_length(coalesce(p_payload->>'phone', '')) > 32
    or (p_payload - array['role','full_name','email','phone','permissions']) <> '{}'::jsonb then
      raise exception 'invalid_record' using errcode = '22023';
  end if;
  if (p_payload ? 'permissions') and jsonb_typeof(p_payload->'permissions') is distinct from 'object' then
    raise exception 'invalid_record' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('staff-provision:' || p_request::text, 0));
  select * into r from public.staff_provisioning where id = p_request;
  if found then
    if r.actor_id <> p_actor or r.gym_id <> v_gym or r.staff_id <> p_staff or r.payload <> p_payload then
      raise exception 'request_mismatch' using errcode = '22023';
    end if;
    return to_jsonb(r);
  end if;

  if exists(select 1 from auth.users where lower(email) = lower(p_payload->>'email')) then
    raise exception 'owner_exists' using errcode = '23505';
  end if;

  insert into public.staff_provisioning(id, actor_id, gym_id, staff_id, payload)
  values(p_request, p_actor, v_gym, p_staff, p_payload)
  returning * into r;
  return to_jsonb(r);
end $$;

create or replace function public.staff_provision_finish(
  p_request uuid,
  p_actor uuid,
  p_user uuid
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym uuid := public.staff_owner_gym(p_actor);
  r public.staff_provisioning;
  s public.staff;
begin
  select * into strict r from public.staff_provisioning
  where id = p_request and actor_id = p_actor and gym_id = v_gym
  for update;

  if r.user_id is not null then
    select * into strict s from public.staff where id = r.staff_id;
    return to_jsonb(s);
  end if;

  if p_user is null or p_user is distinct from public.staff_provision_auth_user(p_request, p_actor) then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  insert into public.staff(id, user_id, gym_id, role, full_name, phone, permissions)
  values(
    r.staff_id,
    p_user,
    v_gym,
    r.payload->>'role',
    trim(r.payload->>'full_name'),
    nullif(trim(coalesce(r.payload->>'phone', '')), ''),
    coalesce(r.payload->'permissions', '{}'::jsonb)
  )
  returning * into s;

  update public.staff_provisioning set user_id = p_user, updated_at = clock_timestamp() where id = r.id;

  insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id)
  select gen_random_uuid(), v_gym, st.id, 'create', 'staff', s.id
  from public.staff st
  where st.user_id = p_actor and st.deleted_at is null
  limit 1;

  return to_jsonb(s);
end $$;

-- Supprimer l'ancienne surcharge 4-arguments pour éviter toute ambiguïté PostgREST
drop function if exists public.update_staff_access(uuid, text, boolean, timestamptz);
create or replace function public.update_staff_access(
  p_staff uuid,
  p_role text,
  p_active boolean,
  p_version timestamptz,
  p_permissions jsonb default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym uuid := public.staff_owner_gym(auth.uid());
  s public.staff;
begin
  if p_role is null or p_role not in ('supervisor', 'manager', 'reception') or p_active is null then
    raise exception 'invalid_record' using errcode = '22023';
  end if;
  if p_permissions is not null and jsonb_typeof(p_permissions) is distinct from 'object' then
    raise exception 'invalid_record' using errcode = '22023';
  end if;

  select * into s
  from public.staff
  where id = p_staff
    and gym_id = v_gym
    and role in ('supervisor', 'manager', 'reception')
    and deleted_at is null
  for update;

  if not found or s.user_id = auth.uid() then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  if p_version is distinct from s.updated_at then
    raise exception 'conflict' using errcode = '40001';
  end if;

  update public.staff
  set role = p_role,
      active = p_active,
      permissions = case when p_permissions is not null then p_permissions else permissions end,
      updated_at = clock_timestamp()
  where id = s.id
  returning * into s;

  insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id)
  values(gen_random_uuid(), v_gym, public.current_staff_id(), 'update', 'staff', s.id);

  return to_jsonb(s);
end $$;

revoke execute on function public.staff_owner_gym(uuid), public.staff_provision_begin(uuid,uuid,uuid,jsonb), public.staff_provision_finish(uuid,uuid,uuid), public.update_staff_access(uuid,text,boolean,timestamptz,jsonb) from public, anon, authenticated;
grant execute on function public.update_staff_access(uuid,text,boolean,timestamptz,jsonb) to authenticated;
grant execute on function public.staff_owner_gym(uuid), public.staff_provision_begin(uuid,uuid,uuid,jsonb), public.staff_provision_finish(uuid,uuid,uuid) to service_role;

-- ----------------------------------------------------------------------------
-- 3. Politiques RLS & Storage complètes pour 'supervisor'
-- ----------------------------------------------------------------------------
drop policy if exists staff_insert on public.staff;
create policy staff_insert on public.staff for insert to authenticated
  with check (
    public.is_super_admin()
    or (gym_id = public.current_gym_id() and public.current_role() = 'owner' and role in ('supervisor', 'manager', 'reception'))
  );

drop policy if exists staff_delete on public.staff;
create policy staff_delete on public.staff for delete to authenticated
  using (
    public.is_super_admin()
    or (gym_id = public.current_gym_id() and public.current_role() = 'owner' and role in ('supervisor', 'manager', 'reception'))
  );

drop policy if exists staff_no_owner_promotion on public.staff;
create policy staff_no_owner_promotion on public.staff as restrictive for update to authenticated
  using (
    public.is_super_admin()
    or id = public.current_staff_id()
    or (gym_id = public.current_gym_id() and public.current_role() = 'owner' and role in ('supervisor', 'manager', 'reception'))
  )
  with check (
    public.is_super_admin()
    or (id = public.current_staff_id() and role = public.current_role())
    or (gym_id = public.current_gym_id() and public.current_role() = 'owner' and role in ('supervisor', 'manager', 'reception'))
  );

drop policy if exists members_insert on public.members;
create policy members_insert on public.members for insert to authenticated
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception'));

drop policy if exists members_update on public.members;
create policy members_update on public.members for update to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception'))
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception'));

drop policy if exists plans_insert on public.plans;
create policy plans_insert on public.plans for insert to authenticated
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager'));

drop policy if exists plans_update on public.plans;
create policy plans_update on public.plans for update to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager'))
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager'));

drop policy if exists subs_insert on public.subscriptions;
create policy subs_insert on public.subscriptions for insert to authenticated
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception'));

drop policy if exists subs_update on public.subscriptions;
create policy subs_update on public.subscriptions for update to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager'))
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager'));

drop policy if exists payments_select on public.payments;
create policy payments_select on public.payments for select to authenticated
  using (
    gym_id = public.current_gym_id()
    and (
      public.current_role() in ('owner', 'supervisor', 'manager')
      or public.gym_setting_bool(gym_id, 'reception_see_all_payments')
      or (
        received_by = public.current_staff_id()
        and (paid_at at time zone (select g.timezone from public.gyms g where g.id = gym_id))::date
          = (now() at time zone (select g.timezone from public.gyms g where g.id = gym_id))::date
      )
    )
  );

drop policy if exists payments_insert on public.payments;
create policy payments_insert on public.payments for insert to authenticated
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception') and received_by = public.current_staff_id());

drop policy if exists payments_update on public.payments;
create policy payments_update on public.payments for update to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager'))
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager'));

drop policy if exists badge_insert on public.badge_templates;
create policy badge_insert on public.badge_templates for insert to authenticated
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager'));

drop policy if exists badge_update on public.badge_templates;
create policy badge_update on public.badge_templates for update to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager'))
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager'));

drop policy if exists audit_select on public.audit_log;
create policy audit_select on public.audit_log for select to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager'));

-- Storage member-photos & exports pour 'supervisor'
drop policy if exists member_photos_insert on storage.objects;
create policy member_photos_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'member-photos'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() in ('owner', 'supervisor', 'manager', 'reception')
  );

drop policy if exists member_photos_update on storage.objects;
create policy member_photos_update on storage.objects for update to authenticated
  using (
    bucket_id = 'member-photos'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() in ('owner', 'supervisor', 'manager', 'reception')
  )
  with check (
    bucket_id = 'member-photos'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
  );

drop policy if exists member_photos_delete on storage.objects;
create policy member_photos_delete on storage.objects for delete to authenticated
  using (
    bucket_id = 'member-photos'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() in ('owner', 'supervisor', 'manager')
  );

drop policy if exists exports_select on storage.objects;
create policy exports_select on storage.objects for select to authenticated
  using (
    bucket_id = 'exports'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() in ('owner', 'supervisor', 'manager')
  );

drop policy if exists exports_insert on storage.objects;
create policy exports_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'exports'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() in ('owner', 'supervisor', 'manager')
  );

-- ----------------------------------------------------------------------------
-- 4. Audit superset + Caisse (open, close & supervision owner/supervisor)
-- ----------------------------------------------------------------------------
create or replace function public.audit(
  p_action text,
  p_entity text,
  p_entity_id uuid,
  p_details jsonb default '{}'::jsonb,
  p_gym uuid default null
)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
  v_gym uuid := public.current_gym_id();
begin
  if v_gym is null or public.current_staff_id() is null or (p_gym is not null and p_gym <> v_gym) then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_details, '{}'::jsonb)) is distinct from 'object' or char_length(p_details::text) > 4096 then
    raise exception 'invalid_audit_event' using errcode = '22023';
  end if;
  if p_entity not in (
      'members','plans','subscriptions','payments','attendance','badge_templates','gyms','staff',
      'badges','member_pins','payment_declarations','employees',
      'cash_sessions','access_events','campaigns'
    )
    or p_action not in (
      'create','update','delete','sync_conflict',
      'member_create','member_update','member_archive','qr_regenerate',
      'plan_save','plan_archive',
      'subscription_create','subscription_update','subscription_renew','subscription_cancel','subscription_archive',
      'payment_create','payment_update','payment_archive','payment_voided',
      'attendance_scan','badge_template_save','badge_template_archive','export',
      'badge_bind','badge_update','pin_set','pin_update','pin_reset','payment_declaration',
      'employee_create','employee_update','employee_archive','branding_updated',
      'cash_session_opened','cash_session_closed','manual_door_open',
      'fingerprint_registered','fingerprint_removed','extra_badges_request',
      'payment_declaration_review','campaign_sent'
    ) then
    raise exception 'invalid_audit_event' using errcode = '22023';
  end if;
  insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id, details)
  values(v_id, v_gym, public.current_staff_id(), p_action, p_entity, p_entity_id, coalesce(p_details, '{}'::jsonb));
  return v_id;
end $$;

revoke execute on function public.audit(text,text,uuid,jsonb,uuid) from public, anon;
grant execute on function public.audit(text,text,uuid,jsonb,uuid) to authenticated;

drop policy if exists cash_sessions_select on public.cash_sessions;
create policy cash_sessions_select on public.cash_sessions for select to authenticated
  using (
    gym_id = public.current_gym_id()
    and (public.current_role() in ('owner', 'supervisor', 'manager') or staff_id = public.current_staff_id())
  );

drop policy if exists cash_sessions_insert on public.cash_sessions;
create policy cash_sessions_insert on public.cash_sessions for insert to authenticated
  with check (gym_id = public.current_gym_id() and staff_id = public.current_staff_id());

drop policy if exists cash_sessions_update on public.cash_sessions;
create policy cash_sessions_update on public.cash_sessions for update to authenticated
  using (
    gym_id = public.current_gym_id()
    and (public.current_role() in ('owner', 'supervisor', 'manager') or staff_id = public.current_staff_id())
  )
  with check (gym_id = public.current_gym_id());

create or replace function public.open_cash_session(p_opening_float numeric default 0)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym uuid := public.current_gym_id();
  v_staff uuid := public.current_staff_id();
  v_float numeric := greatest(0, coalesce(p_opening_float, 0));
  v_existing public.cash_sessions;
  v_session public.cash_sessions;
begin
  if v_gym is null or v_staff is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  select * into v_existing
  from public.cash_sessions
  where gym_id = v_gym and staff_id = v_staff and status = 'open'
  order by opened_at desc
  limit 1;

  if v_existing.id is not null then
    return to_jsonb(v_existing);
  end if;

  insert into public.cash_sessions(gym_id, staff_id, opening_float, expected_cash, status)
  values(v_gym, v_staff, v_float, v_float, 'open')
  returning * into v_session;

  perform public.audit('cash_session_opened', 'cash_sessions', v_session.id, jsonb_build_object('float', v_float));
  return to_jsonb(v_session);
end $$;

create or replace function public.close_cash_session(
  p_session uuid,
  p_counted numeric,
  p_notes text default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym uuid := public.current_gym_id();
  v_staff uuid := public.current_staff_id();
  v_role text := coalesce(public.current_role(), '');
  v_session public.cash_sessions;
  v_total_cash numeric := 0;
begin
  if v_gym is null or v_staff is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  select * into strict v_session
  from public.cash_sessions
  where id = p_session and gym_id = v_gym
  for update;

  if v_session.staff_id <> v_staff and v_role not in ('owner', 'supervisor', 'manager') then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  if v_session.status = 'closed' then
    return to_jsonb(v_session);
  end if;

  select coalesce(sum(amount), 0) into v_total_cash
  from public.payments
  where gym_id = v_gym
    and received_by = v_session.staff_id
    and lower(method) = 'cash'
    and voided_at is null
    and deleted_at is null
    and paid_at >= v_session.opened_at
    and paid_at <= clock_timestamp();

  update public.cash_sessions
  set closed_at = clock_timestamp(),
      status = 'closed',
      expected_cash = v_session.opening_float + v_total_cash,
      counted_cash = p_counted,
      difference = p_counted - (v_session.opening_float + v_total_cash),
      notes = nullif(trim(coalesce(p_notes, '')), ''),
      updated_at = clock_timestamp()
  where id = p_session
  returning * into v_session;

  perform public.audit(
    'cash_session_closed',
    'cash_sessions',
    v_session.id,
    jsonb_build_object(
      'expected', v_session.expected_cash,
      'counted', p_counted,
      'diff', v_session.difference,
      'closed_by', v_staff
    )
  );

  return to_jsonb(v_session);
end $$;

create or replace function public.list_gym_cash_sessions()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_gym uuid := public.current_gym_id();
  v_staff uuid := public.current_staff_id();
  v_role text := coalesce(public.current_role(), '');
  v_can_supervise boolean := v_role in ('owner', 'supervisor', 'manager');
begin
  if v_gym is null or v_staff is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(row_data order by opened_at desc) from (
      select
        cs.opened_at,
        jsonb_build_object(
          'id', cs.id,
          'gym_id', cs.gym_id,
          'staff_id', cs.staff_id,
          'staff_name', coalesce(st.full_name, 'Personnel'),
          'staff_role', coalesce(st.role, 'reception'),
          'staff_job_title', coalesce(st.permissions->>'job_title', st.role, 'reception'),
          'is_mine', (cs.staff_id = v_staff),
          'status', cs.status,
          'opened_at', cs.opened_at,
          'closed_at', cs.closed_at,
          'opening_float', cs.opening_float,
          'cash_collected', coalesce((
            select sum(p.amount) from public.payments p
            where p.gym_id = v_gym
              and p.received_by = cs.staff_id
              and lower(p.method) = 'cash'
              and p.voided_at is null
              and p.deleted_at is null
              and p.paid_at >= cs.opened_at
              and p.paid_at <= coalesce(cs.closed_at, clock_timestamp())
          ), 0),
          'electronic_collected', coalesce((
            select sum(p.amount) from public.payments p
            where p.gym_id = v_gym
              and p.received_by = cs.staff_id
              and lower(p.method) <> 'cash'
              and p.voided_at is null
              and p.deleted_at is null
              and p.paid_at >= cs.opened_at
              and p.paid_at <= coalesce(cs.closed_at, clock_timestamp())
          ), 0),
          'payments_count', coalesce((
            select count(*) from public.payments p
            where p.gym_id = v_gym
              and p.received_by = cs.staff_id
              and p.voided_at is null
              and p.deleted_at is null
              and p.paid_at >= cs.opened_at
              and p.paid_at <= coalesce(cs.closed_at, clock_timestamp())
          ), 0),
          'expected_cash', cs.opening_float + coalesce((
            select sum(p.amount) from public.payments p
            where p.gym_id = v_gym
              and p.received_by = cs.staff_id
              and lower(p.method) = 'cash'
              and p.voided_at is null
              and p.deleted_at is null
              and p.paid_at >= cs.opened_at
              and p.paid_at <= coalesce(cs.closed_at, clock_timestamp())
          ), 0),
          'counted_cash', cs.counted_cash,
          'difference', cs.difference,
          'notes', cs.notes
        ) as row_data
      from public.cash_sessions cs
      join public.staff st on st.id = cs.staff_id
      where cs.gym_id = v_gym
        and (v_can_supervise or cs.staff_id = v_staff)
        and (cs.status = 'open' or cs.closed_at >= (clock_timestamp() - interval '30 days'))
      order by cs.status desc, cs.opened_at desc
      limit 100
    ) q
  ), '[]'::jsonb);
end $$;

revoke execute on function public.open_cash_session(numeric), public.close_cash_session(uuid, numeric, text), public.list_gym_cash_sessions() from public, anon;
grant execute on function public.open_cash_session(numeric), public.close_cash_session(uuid, numeric, text), public.list_gym_cash_sessions() to authenticated;

-- ----------------------------------------------------------------------------
-- 5. WhatsApp : index anti-doublon, rappels STRICTEMENT J-7 et J-2,
--    Contrôle des messages (Admin) et Pont de discussion à distance
-- ----------------------------------------------------------------------------
create index if not exists idx_whatsapp_logs_phone_kind
  on public.whatsapp_notification_logs(gym_id, recipient_phone, kind, created_at desc);

drop policy if exists wa_logs_select on public.whatsapp_notification_logs;
create policy wa_logs_select on public.whatsapp_notification_logs
  for select to authenticated
  using (public.is_super_admin() or gym_id = public.current_gym_id());

drop policy if exists wa_logs_insert on public.whatsapp_notification_logs;
create policy wa_logs_insert on public.whatsapp_notification_logs
  for insert to authenticated
  with check (public.is_super_admin() or gym_id = public.current_gym_id());

create index if not exists idx_whatsapp_outbox_phone_kind
  on public.whatsapp_messages_outbox(gym_id, to_phone, kind, status, created_at desc);

-- Table optionnelle de commandes à distance (permet d'ouvrir/répondre dans Agrandir depuis Vercel Web)
create table if not exists public.whatsapp_bridge_commands (
  id uuid primary key default gen_random_uuid(),
  account_index integer not null default 1,
  action text not null, -- 'list_chats', 'get_messages', 'send_chat'
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending', -- 'pending', 'done', 'error'
  result jsonb,
  error_message text,
  requested_by uuid default auth.uid(),
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz
);

create index if not exists idx_wa_bridge_pending
  on public.whatsapp_bridge_commands(status, created_at)
  where status = 'pending';

alter table public.whatsapp_bridge_commands enable row level security;
revoke all on public.whatsapp_bridge_commands from public, anon;
grant select, insert, update on public.whatsapp_bridge_commands to authenticated, service_role, anon;

drop policy if exists wa_bridge_policy on public.whatsapp_bridge_commands;
create policy wa_bridge_policy on public.whatsapp_bridge_commands
  for all to public using (true) with check (true);

-- Rappels automatiques WhatsApp : STRICTEMENT J-7 et J-2 UNIQUEMENT + Anti-Doublon strict
create or replace function public.cron_check_whatsapp_expiration_reminders(
  p_target_gym_id uuid default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym record;
  v_sub record;
  v_milestone text;
  v_diff int;
  v_today date;
  v_portal_url text;
  v_clean_phone text;
  v_formatted_date text;
  v_queued_count int := 0;
  v_already_exists boolean;
  v_msg text;
  v_seed int;
  v_greeting text;
  v_intro text;
  v_detail text;
  v_action text;
  v_footer text;
  v_ref_hash text;
begin
  for v_gym in
    select
      g.id as gym_id,
      g.name as gym_name,
      coalesce(g.phone, '') as gym_phone,
      coalesce(g.timezone, 'America/Port-au-Prince') as timezone,
      coalesce(a.backup_phone, '') as backup_phone
    from public.gym_whatsapp_access a
    join public.gyms g on g.id = a.gym_id
    where a.is_enabled is true
      and a.status = 'active'
      and a.end_date > clock_timestamp()
      and g.deleted_at is null
      and (p_target_gym_id is null or g.id = p_target_gym_id)
  loop
    v_today := (clock_timestamp() at time zone v_gym.timezone)::date;
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
        (s.end_date::date - v_today) as days_diff
      from public.subscriptions s
      join public.members m on m.id = s.member_id
      left join public.plans p on p.id = s.plan_id
      where s.gym_id = v_gym.gym_id
        and s.deleted_at is null
        and s.status in ('active', 'pending')
        and m.deleted_at is null
        and (s.end_date::date - v_today) in (7, 2)
        -- Sote manm ki deja gen yon lòt abònman pi lwen (deja renouvle)
        and not exists (
          select 1 from public.subscriptions n
          where n.member_id = s.member_id
            and n.gym_id = s.gym_id
            and n.id <> s.id
            and n.deleted_at is null
            and n.status in ('active', 'pending')
            and n.end_date > s.end_date
        )
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
      else
        continue;
      end if;

      -- Anti-Doublon 1 : pa janm voye menm jalon an 2 fwa (ni pa member_id ni pa nimewo)
      select exists (
        select 1 from public.whatsapp_notification_logs l
        where l.gym_id = v_gym.gym_id
          and l.kind = v_milestone
          and (l.member_id = v_sub.member_id or l.recipient_phone = v_clean_phone)
          and (
            l.metadata->>'subscription_id' = v_sub.sub_id::text
            or l.created_at >= (clock_timestamp() - interval '6 days')
          )
      ) into v_already_exists;

      if v_already_exists then
        continue;
      end if;

      -- Anti-Doublon 2 : verifye outbox (pending, processing, sent)
      select exists (
        select 1 from public.whatsapp_messages_outbox o
        where (o.gym_id = v_gym.gym_id or o.gym_id is null)
          and o.kind = v_milestone
          and (o.to_phone = v_clean_phone or o.to_phone = v_sub.raw_phone)
          and o.status in ('pending', 'processing', 'sent')
          and o.created_at >= (clock_timestamp() - interval '6 days')
      ) into v_already_exists;

      if v_already_exists then
        continue;
      end if;

      v_formatted_date := to_char(v_sub.end_date, 'DD/MM/YYYY');
      v_seed := floor(random() * 4)::integer;
      v_ref_hash := substr(md5(random()::text || clock_timestamp()::text), 1, 6);

      if v_seed = 0 then
        v_greeting := 'Bonjour ' || v_sub.first_name || ' ! 👋';
      elsif v_seed = 1 then
        v_greeting := 'Bonjour cher(e) ' || v_sub.first_name || ' ' || v_sub.last_name || ' ! 🏋️';
      elsif v_seed = 2 then
        v_greeting := 'Salutations ' || v_sub.first_name || ' ! ✨';
      else
        v_greeting := 'Cher(e) membre ' || v_sub.first_name || ', bonjour ! 🏃';
      end if;

      if v_seed in (0, 2) then
        v_intro := 'Votre salle *' || v_gym.gym_name || '* vous informe :';
      else
        v_intro := 'L''équipe *' || v_gym.gym_name || '* vous transmet ce rappel :';
      end if;

      if v_diff = 7 then
        v_detail := 'Votre abonnement (*' || v_sub.plan_name || '*) arrive à son terme dans *7 jours*, le *' || v_formatted_date || '*.';
      else
        v_detail := '⚠️ Votre abonnement (*' || v_sub.plan_name || '*) arrive à échéance dans *2 jours*, le *' || v_formatted_date || '*.';
      end if;

      if v_seed in (0, 3) then
        v_action := 'Pour conserver votre accès sans coupure, merci de passer à la réception pour renouveler votre forfait.';
      else
        v_action := 'Afin d''éviter tout blocage au contrôle d''accès, rapprochez-vous de l''accueil de votre salle pour votre réabonnement.';
      end if;

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

      insert into public.whatsapp_messages_outbox (
        gym_id, to_phone, message, kind, status, template_seed
      ) values (
        v_gym.gym_id, v_clean_phone, v_msg, v_milestone, 'pending', v_seed
      );

      insert into public.whatsapp_notification_logs (
        gym_id, member_id, kind, recipient_phone, recipient_name, status, metadata
      ) values (
        v_gym.gym_id,
        v_sub.member_id,
        v_milestone,
        v_clean_phone,
        trim(coalesce(v_sub.first_name, '') || ' ' || coalesce(v_sub.last_name, '')),
        'queued',
        jsonb_build_object(
          'subscription_id', v_sub.sub_id,
          'days_remaining', v_diff,
          'end_date', v_sub.end_date,
          'auto', true
        )
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

-- Contrôle des messages (Super Admin) : vue complète d'état + priorités + inscriptions manquées + J-7/J-2
create or replace function public.platform_whatsapp_control_overview()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_gyms jsonb;
  v_priority jsonb;
  v_missed jsonb;
  v_renewals jsonb;
  v_recent jsonb;
  v_summary jsonb;
begin
  if not public.is_super_admin() and current_setting('role', true) <> 'service_role' then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(row_obj order by is_valid desc, gym_name asc), '[]'::jsonb)
  into v_gyms
  from (
    select
      g.name as gym_name,
      (
        coalesce(a.is_enabled, false) is true
        and coalesce(a.status, '') = 'active'
        and a.end_date > clock_timestamp()
      ) as is_valid,
      jsonb_build_object(
        'gym_id', g.id,
        'gym_name', g.name,
        'gym_code', g.code,
        'gym_phone', coalesce(g.phone, ''),
        'timezone', coalesce(g.timezone, 'America/Port-au-Prince'),
        'is_enabled', coalesce(a.is_enabled, false),
        'status', case
          when a.gym_id is null or a.is_enabled is not true then 'inactive'
          when a.status = 'suspended' then 'suspended'
          when a.end_date < clock_timestamp() then 'expired'
          else 'active'
        end,
        'is_valid', (
          coalesce(a.is_enabled, false) is true
          and coalesce(a.status, '') = 'active'
          and a.end_date > clock_timestamp()
        ),
        'end_date', a.end_date,
        'days_remaining', case
          when a.end_date is not null and a.end_date > clock_timestamp() and a.status = 'active' and a.is_enabled is true
          then greatest(0, ceil(extract(epoch from (a.end_date - clock_timestamp())) / 86400)::int)
          else 0
        end,
        'pending_count', (select count(*) from public.whatsapp_messages_outbox o where o.gym_id = g.id and o.status in ('pending', 'processing')),
        'failed_count', (select count(*) from public.whatsapp_messages_outbox o where o.gym_id = g.id and o.status = 'failed'),
        'sent_today_count', (select count(*) from public.whatsapp_messages_outbox o where o.gym_id = g.id and o.status = 'sent' and o.sent_at >= (clock_timestamp() - interval '24 hours'))
      ) as row_obj
    from public.gym_whatsapp_access a
    join public.gyms g on g.id = a.gym_id
    where g.deleted_at is null
  ) gq;

  select coalesce(jsonb_agg(row_obj), '[]'::jsonb)
  into v_priority
  from (
    select jsonb_build_object(
      'id', o.id,
      'gym_id', o.gym_id,
      'gym_name', coalesce(g.name, 'Plateforme'),
      'to_phone', o.to_phone,
      'kind', coalesce(o.kind, 'manual'),
      'status', o.status,
      'attempts', o.attempts,
      'error_message', o.error_message,
      'message_preview', left(o.message, 160),
      'has_pdf', (o.pdf_base64 is not null and length(o.pdf_base64) > 0),
      'created_at', o.created_at
    ) as row_obj
    from public.whatsapp_messages_outbox o
    left join public.gyms g on g.id = o.gym_id
    where o.status in ('failed', 'pending', 'processing')
    order by
      case o.status when 'failed' then 0 when 'processing' then 1 else 2 end,
      o.created_at asc
    limit 120
  ) pq;

  -- Inscriptions récentes dans les gyms abonnés dont le message de bienvenue n'est JAMAIS parti
  select coalesce(jsonb_agg(row_obj), '[]'::jsonb)
  into v_missed
  from (
    with base as (
      select
        m.id as member_id,
        m.gym_id,
        g.name as gym_name,
        coalesce(g.phone, '') as gym_phone,
        m.member_number,
        trim(m.first_name || ' ' || m.last_name) as member_name,
        m.created_at,
        case
          when length(regexp_replace(coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')), '\D', '', 'g')) = 8
          then '509' || regexp_replace(coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')), '\D', '', 'g')
          else regexp_replace(coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')), '\D', '', 'g')
        end as clean_phone
      from public.members m
      join public.gyms g on g.id = m.gym_id
      join public.gym_whatsapp_access a on a.gym_id = g.id
      where a.is_enabled is true
        and a.status = 'active'
        and a.end_date > clock_timestamp()
        and g.deleted_at is null
        and m.deleted_at is null
        and m.created_at >= (clock_timestamp() - interval '30 days')
    )
    select jsonb_build_object(
      'gym_id', b.gym_id,
      'gym_name', b.gym_name,
      'gym_phone', b.gym_phone,
      'member_id', b.member_id,
      'member_number', b.member_number,
      'member_name', b.member_name,
      'clean_phone', b.clean_phone,
      'created_at', b.created_at,
      'kind', 'welcome'
    ) as row_obj
    from base b
    where length(b.clean_phone) >= 8
      and not exists (
        select 1 from public.whatsapp_notification_logs l
        where l.gym_id = b.gym_id
          and l.kind = 'welcome'
          and (l.member_id = b.member_id or l.recipient_phone = b.clean_phone)
      )
      and not exists (
        select 1 from public.whatsapp_messages_outbox o
        where (o.gym_id = b.gym_id or o.gym_id is null)
          and o.kind = 'welcome'
          and o.to_phone = b.clean_phone
          and o.status in ('pending', 'processing', 'sent')
      )
    order by b.created_at desc
    limit 120
  ) mq;

  -- Renouvèllements à envoyer : STRICTEMENT J-7 ou J-2 et pas déjà envoyés pour ce jalon
  select coalesce(jsonb_agg(row_obj), '[]'::jsonb)
  into v_renewals
  from (
    with base as (
      select
        s.id as sub_id,
        s.member_id,
        s.gym_id,
        g.name as gym_name,
        coalesce(g.phone, '') as gym_phone,
        trim(m.first_name || ' ' || m.last_name) as member_name,
        coalesce(p.name, 'Abonnement') as plan_name,
        s.end_date::date as end_date,
        (s.end_date::date - (clock_timestamp() at time zone coalesce(g.timezone, 'America/Port-au-Prince'))::date) as days_left,
        case
          when (s.end_date::date - (clock_timestamp() at time zone coalesce(g.timezone, 'America/Port-au-Prince'))::date) = 7 then 'reminder_7d'
          else 'reminder_2d'
        end as milestone,
        case
          when length(regexp_replace(coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')), '\D', '', 'g')) = 8
          then '509' || regexp_replace(coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')), '\D', '', 'g')
          else regexp_replace(coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')), '\D', '', 'g')
        end as clean_phone
      from public.subscriptions s
      join public.members m on m.id = s.member_id
      join public.gyms g on g.id = s.gym_id
      join public.gym_whatsapp_access a on a.gym_id = g.id
      left join public.plans p on p.id = s.plan_id
      where a.is_enabled is true
        and a.status = 'active'
        and a.end_date > clock_timestamp()
        and g.deleted_at is null
        and m.deleted_at is null
        and s.deleted_at is null
        and s.status in ('active', 'pending')
        and (s.end_date::date - (clock_timestamp() at time zone coalesce(g.timezone, 'America/Port-au-Prince'))::date) in (7, 2)
        and not exists (
          select 1 from public.subscriptions n
          where n.member_id = s.member_id
            and n.gym_id = s.gym_id
            and n.id <> s.id
            and n.deleted_at is null
            and n.status in ('active', 'pending')
            and n.end_date > s.end_date
        )
    )
    select jsonb_build_object(
      'gym_id', b.gym_id,
      'gym_name', b.gym_name,
      'gym_phone', b.gym_phone,
      'subscription_id', b.sub_id,
      'member_id', b.member_id,
      'member_name', b.member_name,
      'plan_name', b.plan_name,
      'clean_phone', b.clean_phone,
      'end_date', b.end_date,
      'days_left', b.days_left,
      'kind', b.milestone
    ) as row_obj
    from base b
    where length(b.clean_phone) >= 8
      and not exists (
        select 1 from public.whatsapp_notification_logs l
        where l.gym_id = b.gym_id
          and l.kind = b.milestone
          and (l.member_id = b.member_id or l.recipient_phone = b.clean_phone)
          and (
            l.metadata->>'subscription_id' = b.sub_id::text
            or l.created_at >= (clock_timestamp() - interval '6 days')
          )
      )
      and not exists (
        select 1 from public.whatsapp_messages_outbox o
        where (o.gym_id = b.gym_id or o.gym_id is null)
          and o.kind = b.milestone
          and o.to_phone = b.clean_phone
          and o.status in ('pending', 'processing', 'sent')
          and o.created_at >= (clock_timestamp() - interval '6 days')
      )
    order by b.days_left asc, b.gym_name asc
    limit 120
  ) rq;

  select coalesce(jsonb_agg(row_obj), '[]'::jsonb)
  into v_recent
  from (
    select jsonb_build_object(
      'id', l.id,
      'gym_id', l.gym_id,
      'gym_name', coalesce(g.name, 'Plateforme'),
      'member_id', l.member_id,
      'kind', l.kind,
      'recipient_phone', l.recipient_phone,
      'recipient_name', l.recipient_name,
      'status', l.status,
      'created_at', l.created_at
    ) as row_obj
    from public.whatsapp_notification_logs l
    left join public.gyms g on g.id = l.gym_id
    order by l.created_at desc
    limit 60
  ) rl;

  v_summary := jsonb_build_object(
    'subscribed_gyms_count', coalesce(jsonb_array_length(v_gyms), 0),
    'priority_count', coalesce(jsonb_array_length(v_priority), 0),
    'missed_registrations_count', coalesce(jsonb_array_length(v_missed), 0),
    'renewal_candidates_count', coalesce(jsonb_array_length(v_renewals), 0),
    'pending_outbox', (select count(*) from public.whatsapp_messages_outbox where status in ('pending', 'processing')),
    'failed_outbox', (select count(*) from public.whatsapp_messages_outbox where status = 'failed'),
    'sent_24h', (select count(*) from public.whatsapp_messages_outbox where status = 'sent' and sent_at >= (clock_timestamp() - interval '24 hours')),
    'ready_lines', (select count(*) from public.platform_whatsapp_accounts where is_enabled is true and service_status = 'READY' and last_heartbeat >= (clock_timestamp() - interval '45 seconds'))
  );

  return jsonb_build_object(
    'ok', true,
    'checked_at', clock_timestamp(),
    'summary', v_summary,
    'subscribed_gyms', v_gyms,
    'priority_queue', v_priority,
    'missed_registrations', v_missed,
    'renewal_candidates', v_renewals,
    'recent_logs', v_recent
  );
end $$;

-- Dispatch en lot sécurisé avec Anti-Doublon strict côté serveur
create or replace function public.platform_whatsapp_dispatch_batch(
  p_include_missed_registrations boolean default true,
  p_include_renewals boolean default true,
  p_retry_failed boolean default false
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_rec record;
  v_msg text;
  v_portal_url text;
  v_queued_welcome int := 0;
  v_queued_renewals int := 0;
  v_retried_failed int := 0;
  v_skipped int := 0;
  v_exists boolean;
begin
  if not public.is_super_admin() and current_setting('role', true) <> 'service_role' then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  -- 1. Relancer les messages en échec si demandé
  if p_retry_failed then
    update public.whatsapp_messages_outbox
    set status = 'pending',
        error_message = null,
        attempts = 0,
        retry_count = 0,
        processed_at = null
    where status = 'failed';
    get diagnostics v_retried_failed = row_count;
  end if;

  -- 2. Envoyer en lot les inscriptions manquées (Welcome) sans JAMAIS faire de doublon
  if p_include_missed_registrations then
    for v_rec in
      select
        m.id as member_id,
        m.gym_id,
        g.name as gym_name,
        coalesce(nullif(trim(g.phone), ''), 'gym') as gym_phone,
        m.member_number,
        trim(m.first_name || ' ' || m.last_name) as member_name,
        case
          when length(regexp_replace(coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')), '\D', '', 'g')) = 8
          then '509' || regexp_replace(coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')), '\D', '', 'g')
          else regexp_replace(coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')), '\D', '', 'g')
        end as clean_phone
      from public.members m
      join public.gyms g on g.id = m.gym_id
      join public.gym_whatsapp_access a on a.gym_id = g.id
      where a.is_enabled is true
        and a.status = 'active'
        and a.end_date > clock_timestamp()
        and g.deleted_at is null
        and m.deleted_at is null
        and m.created_at >= (clock_timestamp() - interval '30 days')
      order by m.created_at asc
    loop
      if length(v_rec.clean_phone) < 8 then
        continue;
      end if;

      select exists (
        select 1 from public.whatsapp_notification_logs l
        where l.gym_id = v_rec.gym_id
          and l.kind = 'welcome'
          and (l.member_id = v_rec.member_id or l.recipient_phone = v_rec.clean_phone)
      ) or exists (
        select 1 from public.whatsapp_messages_outbox o
        where (o.gym_id = v_rec.gym_id or o.gym_id is null)
          and o.kind = 'welcome'
          and o.to_phone = v_rec.clean_phone
          and o.status in ('pending', 'processing', 'sent')
      ) into v_exists;

      if v_exists then
        v_skipped := v_skipped + 1;
        continue;
      end if;

      v_portal_url := 'https://securgym.com/m/' || v_rec.gym_id::text;
      v_msg := '🏋️ *Bienvenue à ' || v_rec.gym_name || ' !*' || E'\n' ||
               '_Système SecurGYM • https://securgym.com_' || E'\n\n' ||
               'Bonjour *' || v_rec.member_name || '* 👋,' || E'\n' ||
               'Votre inscription est désormais confirmée !' || E'\n\n' ||
               '🆔 *Numéro membre :* ' || v_rec.member_number || E'\n' ||
               '🌐 *Votre espace membre :*' || E'\n' ||
               '👉 ' || v_portal_url || E'\n' ||
               '_Connectez-vous avec votre numéro :_ *' || v_rec.clean_phone || '*' || E'\n\n' ||
               '────────────────────────' || E'\n' ||
               '⚠️ *IMPORTANT :*' || E'\n' ||
               '1. Enregistrez ce numéro sous le nom *SecurGYM* dans vos contacts.' || E'\n' ||
               '2. *Ne répondez pas à ce numéro*. Pour toute question, contactez directement *' || v_rec.gym_name || '* au : *' || v_rec.gym_phone || '*.';

      insert into public.whatsapp_messages_outbox (
        gym_id, to_phone, message, kind, status
      ) values (
        v_rec.gym_id, v_rec.clean_phone, v_msg, 'welcome', 'pending'
      );

      insert into public.whatsapp_notification_logs (
        gym_id, member_id, kind, recipient_phone, recipient_name, status, metadata
      ) values (
        v_rec.gym_id, v_rec.member_id, 'welcome', v_rec.clean_phone, v_rec.member_name, 'queued',
        jsonb_build_object('source', 'control_center_batch', 'member_number', v_rec.member_number)
      );

      v_queued_welcome := v_queued_welcome + 1;
    end loop;
  end if;

  -- 3. Envoyer en lot les rappels de renouvellement J-7 et J-2
  if p_include_renewals then
    select coalesce((res->>'queued_count')::int, 0) into v_queued_renewals
    from (select public.cron_check_whatsapp_expiration_reminders(null) as res) t;
  end if;

  return jsonb_build_object(
    'ok', true,
    'queued_welcome', v_queued_welcome,
    'queued_renewals', v_queued_renewals,
    'retried_failed', v_retried_failed,
    'skipped_duplicates', v_skipped,
    'timestamp', clock_timestamp()
  );
end $$;

revoke execute on function public.cron_check_whatsapp_expiration_reminders(uuid), public.platform_whatsapp_control_overview(), public.platform_whatsapp_dispatch_batch(boolean, boolean, boolean) from public, anon;
grant execute on function public.cron_check_whatsapp_expiration_reminders(uuid), public.platform_whatsapp_control_overview(), public.platform_whatsapp_dispatch_batch(boolean, boolean, boolean) to authenticated, service_role;

commit;
