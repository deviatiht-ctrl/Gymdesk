begin;

alter table public.gyms add column deleted_at timestamptz;
create unique index staff_single_owner on public.staff(gym_id) where role = 'owner' and deleted_at is null;

create table public.gym_provisioning (
    id uuid primary key,
    actor_id uuid not null references auth.users(id),
    gym_id uuid not null unique,
    staff_id uuid not null unique,
    payload jsonb not null,
    state text not null default 'pending' check (state in ('pending','completed')),
    owner_user_id uuid references auth.users(id),
    created_at timestamptz not null default clock_timestamp(),
    updated_at timestamptz not null default clock_timestamp()
);
create unique index provisioning_code on public.gym_provisioning((payload->'gym'->>'code'));
alter table public.gym_provisioning enable row level security;
revoke all on public.gym_provisioning from anon, authenticated;
grant all on public.gym_provisioning to service_role;
create trigger provisioning_updated before update on public.gym_provisioning for each row execute function public.set_updated_at();

create or replace function public.current_gym_id()
returns uuid language sql stable security definer set search_path = '' as $$
    select s.gym_id from public.staff s join public.gyms g on g.id = s.gym_id
    where s.user_id = auth.uid() and s.active and s.deleted_at is null and g.status = 'active' and g.deleted_at is null
$$;

create or replace function public.validate_gym_metadata()
returns trigger language plpgsql set search_path = '' as $$
begin
    if char_length(trim(new.name)) not between 2 and 120
      or new.accent_color !~ '^#[0-9A-Fa-f]{6}$' or new.currency not in ('HTG','USD')
      or not exists(select 1 from pg_timezone_names z where z.name = new.timezone)
      or jsonb_typeof(new.settings) <> 'object' then
        raise exception 'invalid_record' using errcode = '22023';
    end if;
    if tg_op = 'UPDATE' and new.deleted_at is distinct from old.deleted_at
      and auth.uid() is not null and not public.is_super_admin() then
        raise exception 'access_denied' using errcode = '42501';
    end if;
    if new.deleted_at is not null then new.status := 'suspended'; end if;
    return new;
end $$;
create trigger gyms_metadata before insert or update on public.gyms for each row execute function public.validate_gym_metadata();

create or replace function public.provision_gym_begin(p_request uuid, p_actor uuid, p_gym uuid, p_staff uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_request public.gym_provisioning;
begin
    if not exists(select 1 from public.staff where user_id = p_actor and role = 'super_admin' and active and deleted_at is null) then
        raise exception 'access_denied' using errcode = '42501';
    end if;
    if p_request is null or p_gym is null or p_staff is null or p_payload is null
      or coalesce(p_payload->'gym'->>'code', '') !~ '^[A-Z]{3,4}$'
      or char_length(trim(coalesce(p_payload->'gym'->>'name', ''))) not between 2 and 120
      or coalesce(p_payload->'gym'->>'accent_color', '') !~ '^#[0-9A-Fa-f]{6}$'
      or coalesce(p_payload->'gym'->>'currency', '') not in ('HTG','USD')
      or not exists(select 1 from pg_timezone_names where name = p_payload->'gym'->>'timezone')
      or coalesce(p_payload->>'owner_email', '') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
      or char_length(trim(coalesce(p_payload->>'owner_name', ''))) not between 2 and 120
      or p_payload ? 'password' or p_payload ? 'owner_password'
      or (select count(*) from jsonb_object_keys(p_payload)) <> 3
      or (p_payload - array['gym','owner_email','owner_name']) <> '{}'::jsonb
      or ((p_payload->'gym') - array['name','code','accent_color','timezone','currency','address','phone','email']) <> '{}'::jsonb then
        raise exception 'invalid_record' using errcode = '22023';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('provision:' || p_request::text, 0));
    select * into v_request from public.gym_provisioning where id = p_request;
    if found then
        if v_request.actor_id <> p_actor or v_request.gym_id <> p_gym or v_request.staff_id <> p_staff or v_request.payload <> p_payload then
            raise exception 'request_mismatch' using errcode = '22023';
        end if;
        return to_jsonb(v_request);
    end if;
    if exists(select 1 from public.gyms where code = p_payload->'gym'->>'code') then
        raise exception 'duplicate_code' using errcode = '23505';
    end if;
    if exists(select 1 from auth.users where lower(email) = lower(p_payload->>'owner_email')) then
        raise exception 'owner_exists' using errcode = '23505';
    end if;
    insert into public.gym_provisioning(id, actor_id, gym_id, staff_id, payload)
    values(p_request, p_actor, p_gym, p_staff, p_payload) returning * into v_request;
    return to_jsonb(v_request);
end $$;

create or replace function public.provision_gym_auth_user(p_request uuid, p_actor uuid)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_request public.gym_provisioning; v_user uuid;
begin
    if not exists(select 1 from public.staff where user_id = p_actor and role = 'super_admin' and active and deleted_at is null) then
        raise exception 'access_denied' using errcode = '42501';
    end if;
    select * into strict v_request from public.gym_provisioning where id = p_request and actor_id = p_actor;
    select id into v_user from auth.users where lower(email) = lower(v_request.payload->>'owner_email')
      and raw_app_meta_data->>'gymdesk_provision_request' = p_request::text;
    return v_user;
end $$;

create or replace function public.provision_gym_finish(p_request uuid, p_actor uuid, p_owner_user uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_request public.gym_provisioning; v_gym public.gyms; v_data jsonb;
begin
    if not exists(select 1 from public.staff where user_id = p_actor and role = 'super_admin' and active and deleted_at is null) then
        raise exception 'access_denied' using errcode = '42501';
    end if;
    select * into strict v_request from public.gym_provisioning where id = p_request and actor_id = p_actor for update;
    if v_request.state = 'completed' then
        select * into strict v_gym from public.gyms where id = v_request.gym_id;
        return to_jsonb(v_gym);
    end if;
    if p_owner_user is null or p_owner_user is distinct from public.provision_gym_auth_user(p_request, p_actor) then
        raise exception 'owner_mismatch' using errcode = '42501';
    end if;
    v_data := v_request.payload->'gym';
    insert into public.gyms(id, code, name, accent_color, timezone, currency, address, phone, email)
    values(v_request.gym_id, v_data->>'code', v_data->>'name', v_data->>'accent_color', v_data->>'timezone',
      v_data->>'currency', nullif(v_data->>'address',''), nullif(v_data->>'phone',''), nullif(v_data->>'email',''))
    returning * into v_gym;
    insert into public.staff(id, user_id, gym_id, role, full_name)
    values(v_request.staff_id, p_owner_user, v_gym.id, 'owner', v_request.payload->>'owner_name');
    update public.gym_provisioning set state = 'completed', owner_user_id = p_owner_user where id = p_request;
    insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id)
    select gen_random_uuid(), v_gym.id, s.id, 'create', 'gyms', v_gym.id from public.staff s where s.user_id = p_actor;
    return to_jsonb(v_gym);
end $$;

create or replace function public.platform_statistics()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
    if not public.is_super_admin() then raise exception 'access_denied' using errcode = '42501'; end if;
    return jsonb_build_object(
      'gyms', (select count(*) from public.gyms where deleted_at is null),
      'active_gyms', (select count(*) from public.gyms where deleted_at is null and status = 'active'),
      'members', (select count(*) from public.members m join public.gyms g on g.id = m.gym_id where m.deleted_at is null and g.deleted_at is null),
      'entries_today', (select count(*) from public.attendance a join public.gyms g on g.id = a.gym_id
        where g.deleted_at is null and a.result = 'granted'
        and a.scanned_at >= date_trunc('day', now() at time zone g.timezone) at time zone g.timezone
        and a.scanned_at < (date_trunc('day', now() at time zone g.timezone) + interval '1 day') at time zone g.timezone)
    );
end $$;

create or replace function public.platform_change_gym(p_gym uuid, p_action text, p_version timestamptz, p_confirmation text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_gym public.gyms;
begin
    if not public.is_super_admin() then raise exception 'access_denied' using errcode = '42501'; end if;
    if p_action is null or p_action not in ('suspend','reactivate','archive') then raise exception 'invalid_action' using errcode = '22023'; end if;
    select * into strict v_gym from public.gyms where id = p_gym for update;
    if v_gym.deleted_at is not null then raise exception 'gym_archived' using errcode = '22023'; end if;
    if p_version is distinct from v_gym.updated_at then raise exception 'conflict' using errcode = '40001'; end if;
    if p_action = 'archive' and p_confirmation is distinct from v_gym.code then raise exception 'confirmation_required' using errcode = '22023'; end if;
    update public.gyms set status = case when p_action = 'reactivate' then 'active' else 'suspended' end,
      deleted_at = case when p_action = 'archive' then clock_timestamp() else null end
    where id = p_gym returning * into v_gym;
    insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id)
    values(gen_random_uuid(), p_gym, public.current_staff_id(), p_action, 'gyms', p_gym);
    return to_jsonb(v_gym);
end $$;

create or replace function public.platform_request_owner_reset(p_actor uuid, p_gym uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_email text; v_actor uuid;
begin
    select id into v_actor from public.staff where user_id = p_actor and role = 'super_admin' and active and deleted_at is null;
    if v_actor is null then raise exception 'access_denied' using errcode = '42501'; end if;
    perform pg_advisory_xact_lock(hashtextextended('owner-reset:' || p_gym::text, 0));
    if exists(select 1 from public.audit_log where gym_id = p_gym and action = 'password_reset_requested' and created_at > now() - interval '1 minute') then
        raise exception 'rate_limited' using errcode = 'P0001';
    end if;
    select u.email into v_email from public.staff s join auth.users u on u.id = s.user_id
      join public.gyms g on g.id = s.gym_id where s.gym_id = p_gym and s.role = 'owner'
      and s.active and s.deleted_at is null and g.deleted_at is null;
    if v_email is null then raise exception 'owner_missing' using errcode = 'P0001'; end if;
    insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id)
    values(gen_random_uuid(), p_gym, v_actor, 'password_reset_requested', 'gyms', p_gym);
    return v_email;
end $$;
revoke execute on function public.platform_request_owner_reset(uuid,uuid) from public, anon, authenticated;
grant execute on function public.platform_request_owner_reset(uuid,uuid) to service_role;

revoke execute on function public.validate_gym_metadata(), public.provision_gym_begin(uuid,uuid,uuid,uuid,jsonb), public.provision_gym_auth_user(uuid,uuid), public.provision_gym_finish(uuid,uuid,uuid), public.platform_statistics(), public.platform_change_gym(uuid,text,timestamptz,text) from public, anon, authenticated;
grant execute on function public.provision_gym_begin(uuid,uuid,uuid,uuid,jsonb), public.provision_gym_auth_user(uuid,uuid), public.provision_gym_finish(uuid,uuid,uuid) to service_role;
grant execute on function public.platform_statistics(), public.platform_change_gym(uuid,text,timestamptz,text) to authenticated;

commit;
