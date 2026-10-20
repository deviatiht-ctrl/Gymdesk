-- =============================================================================
-- Migration 28 : Permissions détaillées du personnel (staff)
-- POSTE (caissier / secrétaire / superviseur) + cases d'accès granulaires
-- =============================================================================

begin;

-- 1. Colonnes permissions et empreintes dans public.staff
alter table public.staff
    add column if not exists permissions jsonb not null default '{}'::jsonb,
    add column if not exists fingerprint_template text,
    add column if not exists fingerprint_backup_template text,
    add column if not exists fingerprint_registered boolean not null default false,
    add column if not exists fingerprint_enrolled_at timestamptz;

-- 2. Mise à jour de staff_provision_begin pour accepter permissions
create or replace function public.staff_provision_begin(p_request uuid, p_actor uuid, p_staff uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    v_gym uuid := public.staff_owner_gym(p_actor);
    r public.staff_provisioning;
begin
    if p_request is null or p_staff is null or p_payload is null
      or coalesce(p_payload->>'role', '') not in ('manager','reception')
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
    values(p_request, p_actor, v_gym, p_staff, p_payload) returning * into r;
    return to_jsonb(r);
end $$;

-- 3. Mise à jour de staff_provision_finish pour insérer permissions
create or replace function public.staff_provision_finish(p_request uuid, p_actor uuid, p_user uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    v_gym uuid := public.staff_owner_gym(p_actor);
    r public.staff_provisioning;
    s public.staff;
begin
    select * into strict r from public.staff_provisioning where id = p_request and actor_id = p_actor and gym_id = v_gym for update;
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
        r.payload->>'full_name',
        nullif(r.payload->>'phone',''),
        coalesce(r.payload->'permissions', '{}'::jsonb)
    ) returning * into s;
    update public.staff_provisioning set user_id = p_user where id = r.id;
    insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id)
    select gen_random_uuid(), v_gym, st.id, 'create', 'staff', s.id from public.staff st where st.user_id = p_actor;
    return to_jsonb(s);
end $$;

-- 4. Mise à jour de update_staff_access pour accepter p_permissions
create or replace function public.update_staff_access(
    p_staff uuid,
    p_role text,
    p_active boolean,
    p_version timestamptz,
    p_permissions jsonb default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    v_gym uuid := public.staff_owner_gym(auth.uid());
    s public.staff;
begin
    if p_role is null or p_role not in ('manager','reception') or p_active is null then
        raise exception 'invalid_record' using errcode = '22023';
    end if;
    if p_permissions is not null and jsonb_typeof(p_permissions) is distinct from 'object' then
        raise exception 'invalid_record' using errcode = '22023';
    end if;
    select * into s from public.staff where id = p_staff and gym_id = v_gym and role in ('manager','reception') and deleted_at is null for update;
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
    where id = s.id returning * into s;
    insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id)
    values(gen_random_uuid(), v_gym, public.current_staff_id(), 'update', 'staff', s.id);
    return to_jsonb(s);
end $$;

-- 5. RPCs pour Enregistrer et Supprimer l'Empreinte Staff
create or replace function public.register_staff_fingerprint(
  p_staff uuid,
  p_template text,
  p_backup_template text default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym uuid := public.current_gym_id();
  s public.staff;
begin
  if p_staff is null or p_template is null or length(trim(p_template)) < 32 then
    raise exception 'invalid_record' using errcode = '22023';
  end if;

  select * into s from public.staff where id = p_staff and gym_id = v_gym and deleted_at is null;
  if not found then
    raise exception 'invalid_record' using errcode = '22023';
  end if;

  if public.current_role() <> 'owner' and s.id <> public.current_staff_id() and not public.is_super_admin() then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  update public.staff
  set fingerprint_template = p_template,
      fingerprint_backup_template = p_backup_template,
      fingerprint_registered = true,
      fingerprint_enrolled_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where id = p_staff returning * into s;

  insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id)
  values(gen_random_uuid(), v_gym, public.current_staff_id(), 'fingerprint_registered', 'staff', s.id);

  return to_jsonb(s);
end;
$$;

create or replace function public.remove_staff_fingerprint(
  p_staff uuid
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym uuid := public.current_gym_id();
  s public.staff;
begin
  if p_staff is null then
    raise exception 'invalid_record' using errcode = '22023';
  end if;

  select * into s from public.staff where id = p_staff and gym_id = v_gym and deleted_at is null;
  if not found then
    raise exception 'invalid_record' using errcode = '22023';
  end if;

  if public.current_role() <> 'owner' and s.id <> public.current_staff_id() and not public.is_super_admin() then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  update public.staff
  set fingerprint_template = null,
      fingerprint_backup_template = null,
      fingerprint_registered = false,
      fingerprint_enrolled_at = null,
      updated_at = clock_timestamp()
  where id = p_staff returning * into s;

  insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id)
  values(gen_random_uuid(), v_gym, public.current_staff_id(), 'fingerprint_removed', 'staff', s.id);

  return to_jsonb(s);
end;
$$;

-- 6. Outbox email kind daily_report
alter table public.email_outbox drop constraint if exists email_outbox_kind_check;
alter table public.email_outbox add constraint email_outbox_kind_check
  check (kind in ('gym_welcome', 'member_welcome', 'member_renewal', 'renewal_reminder', 'campaign', 'payment_receipt', 'daily_report'));

-- 7. Enqueue daily report RPC
create or replace function public.enqueue_daily_report(
  p_report_date date default null,
  p_payload jsonb default null
) returns text
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym uuid := public.current_gym_id();
  v_date date := coalesce(p_report_date, (clock_timestamp() at time zone 'UTC')::date);
  v_owner_email text;
  v_owner_name text;
  v_payload jsonb;
  v_total_usd numeric := 0;
  v_total_htg numeric := 0;
  v_payments_count int := 0;
  v_checkins_count int := 0;
  v_new_members_count int := 0;
  v_event_key text;
  v_rows int;
begin
  if v_gym is null or coalesce(public.current_role(), '') not in ('owner', 'supervisor', 'manager') then
    if not public.is_super_admin() then
      raise exception 'access_denied' using errcode = '42501';
    end if;
  end if;

  select lower(trim(u.email)), coalesce(s.full_name, 'Propriétaire')
  into v_owner_email, v_owner_name
  from public.staff s
  join auth.users u on u.id = s.user_id
  where s.gym_id = v_gym and s.role = 'owner' and s.deleted_at is null
  order by s.created_at asc limit 1;

  if v_owner_email is null or v_owner_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return 'no_owner_email';
  end if;

  if p_payload is not null then
    v_payload := p_payload;
  else
    select coalesce(sum(case when currency = 'USD' then amount else 0 end), 0),
           coalesce(sum(case when currency = 'HTG' then amount else 0 end), 0),
           count(*)
    into v_total_usd, v_total_htg, v_payments_count
    from public.payments
    where gym_id = v_gym and (paid_at at time zone 'UTC')::date = v_date and deleted_at is null and voided_at is null;

    select count(*) into v_checkins_count
    from public.attendance
    where gym_id = v_gym and (scanned_at at time zone 'UTC')::date = v_date and result = 'granted';

    select count(*) into v_new_members_count
    from public.members
    where gym_id = v_gym and (created_at at time zone 'UTC')::date = v_date and deleted_at is null;

    v_payload := jsonb_build_object(
      'report_date', v_date::text,
      'owner_name', v_owner_name,
      'total_usd', v_total_usd,
      'total_htg', v_total_htg,
      'payments_count', v_payments_count,
      'checkins_count', v_checkins_count,
      'new_members_count', v_new_members_count
    );
  end if;

  v_event_key := 'daily_report:' || v_gym::text || ':' || v_date::text || ':' || extract(epoch from clock_timestamp())::bigint;

  insert into public.email_outbox(gym_id, event_key, kind, recipient, payload)
  values (
    v_gym,
    v_event_key,
    'daily_report',
    v_owner_email,
    public.gym_email_branding(v_gym) || v_payload
  );
  get diagnostics v_rows = row_count;
  return case when v_rows > 0 then 'queued' else 'already_queued' end;
end $$;

revoke execute on function public.staff_provision_begin(uuid,uuid,uuid,jsonb), public.staff_provision_finish(uuid,uuid,uuid), public.update_staff_access(uuid,text,boolean,timestamptz,jsonb), public.register_staff_fingerprint(uuid,text,text), public.remove_staff_fingerprint(uuid), public.enqueue_daily_report(date,jsonb) from public, anon, authenticated;
grant execute on function public.update_staff_access(uuid,text,boolean,timestamptz,jsonb) to authenticated;
grant execute on function public.register_staff_fingerprint(uuid, text, text) to authenticated;
grant execute on function public.remove_staff_fingerprint(uuid) to authenticated;
grant execute on function public.enqueue_daily_report(date, jsonb) to authenticated;
grant execute on function public.staff_provision_begin(uuid,uuid,uuid,jsonb), public.staff_provision_finish(uuid,uuid,uuid) to service_role;

commit;
