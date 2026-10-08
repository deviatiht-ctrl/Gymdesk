begin;

create policy staff_no_owner_promotion on public.staff as restrictive for update to authenticated
using (public.is_super_admin() or id = public.current_staff_id() or (gym_id = public.current_gym_id() and public.current_role() = 'owner' and role in ('manager','reception')))
with check (public.is_super_admin() or (id = public.current_staff_id() and role = public.current_role()) or (gym_id = public.current_gym_id() and public.current_role() = 'owner' and role in ('manager','reception')));

create policy staff_no_self_access_change on public.staff as restrictive for update to authenticated
using (id is distinct from public.current_staff_id() or (role = public.current_role() and active))
with check (id is distinct from public.current_staff_id() or (role = public.current_role() and active));

create policy gym_assets_owner_insert on storage.objects as restrictive for insert to authenticated
with check (bucket_id <> 'gym-assets' or public.current_role() = 'owner');
create policy gym_assets_owner_update on storage.objects as restrictive for update to authenticated
using (bucket_id <> 'gym-assets' or public.current_role() = 'owner')
with check (bucket_id <> 'gym-assets' or public.current_role() = 'owner');
create policy gym_assets_owner_delete on storage.objects as restrictive for delete to authenticated
using (bucket_id <> 'gym-assets' or public.current_role() = 'owner');

create or replace function public.sync_branding(p_operation uuid, p_entity text, p_payload jsonb, p_changed_at timestamptz, p_base_version timestamptz default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    g public.gyms; r public.sync_receipts; outcome text := 'accepted';
    v_logo text := nullif(p_payload->>'logo_url', '');
    v_settings jsonb := coalesce(p_payload->'settings', '{}'::jsonb);
    v_key text;
begin
    if public.current_role() is distinct from 'owner' or public.current_gym_id() is null
      or p_entity is distinct from 'gyms' or (p_payload->>'id')::uuid is distinct from public.current_gym_id() then
        raise exception 'access_denied' using errcode = '42501';
    end if;
    if p_changed_at is null or p_changed_at > clock_timestamp() + interval '10 minutes' then
        raise exception 'invalid_clock' using errcode = '22023';
    end if;
    select * into strict g from public.gyms where id = public.current_gym_id() for update;
    select * into r from public.sync_receipts where id = p_operation;
    if found then
        if r.user_id <> auth.uid() or r.gym_id <> g.id or r.entity <> 'gyms' or r.entity_id <> g.id then
            raise exception 'access_denied' using errcode = '42501';
        end if;
        return jsonb_build_object('outcome', r.outcome, 'row', to_jsonb(g));
    end if;
    if p_base_version is distinct from g.updated_at then
        outcome := 'conflict';
    else
        if jsonb_typeof(v_settings) is distinct from 'object' then
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        if exists(select 1 from jsonb_object_keys(v_settings) k where k not in (
            'doc_footer','offline_lease_hours','auto_logout_minutes','pin_lock_minutes',
            'allow_access_pending','grace_days','reception_see_all_payments','scan_sound','scan_vibrate','entry_duplicate_seconds','qr_defaults')) then
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        if char_length(trim(coalesce(p_payload->>'name', ''))) not between 2 and 120
          or coalesce(p_payload->>'accent_color', '') !~ '^#[0-9A-Fa-f]{6}$'
          or coalesce(p_payload->>'currency', '') not in ('HTG','USD')
          or not exists(select 1 from pg_timezone_names where name = p_payload->>'timezone')
          or char_length(coalesce(p_payload->>'address', '')) > 500
          or char_length(coalesce(p_payload->>'phone', '')) > 32
          or char_length(coalesce(p_payload->>'email', '')) > 254
          or (coalesce(p_payload->>'email', '') <> '' and p_payload->>'email' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        if (v_settings ? 'doc_footer') and (jsonb_typeof(v_settings->'doc_footer') is distinct from 'string' or char_length(v_settings->>'doc_footer') > 500) then
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        foreach v_key in array array['offline_lease_hours','auto_logout_minutes','pin_lock_minutes','grace_days','entry_duplicate_seconds'] loop
            if (v_settings ? v_key) and (jsonb_typeof(v_settings->v_key) is distinct from 'number'
              or (v_settings->>v_key)::numeric <> trunc((v_settings->>v_key)::numeric)) then
                raise exception 'invalid_record' using errcode = '22023';
            end if;
        end loop;
        if (v_settings ? 'offline_lease_hours') and (v_settings->>'offline_lease_hours')::int not between 1 and 72
          or (v_settings ? 'auto_logout_minutes') and (v_settings->>'auto_logout_minutes')::int not between 0 and 1440
          or (v_settings ? 'pin_lock_minutes') and (v_settings->>'pin_lock_minutes')::int not between 1 and 60
          or (v_settings ? 'grace_days') and (v_settings->>'grace_days')::int not between 0 and 30
          or (v_settings ? 'entry_duplicate_seconds') and (v_settings->>'entry_duplicate_seconds')::int not between 1 and 10 then
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        foreach v_key in array array['allow_access_pending','reception_see_all_payments','scan_sound','scan_vibrate'] loop
            if (v_settings ? v_key) and jsonb_typeof(v_settings->v_key) is distinct from 'boolean' then
                raise exception 'invalid_record' using errcode = '22023';
            end if;
        end loop;
        if (v_settings ? 'qr_defaults') and (jsonb_typeof(v_settings->'qr_defaults') is distinct from 'object' or char_length(v_settings->>'qr_defaults') > 4096) then
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        if v_logo is not null and (v_logo not like g.id::text || '/logos/%'
          or not exists(select 1 from storage.objects where bucket_id = 'gym-assets' and name = v_logo)) then
            raise exception 'invalid_logo' using errcode = '22023';
        end if;
        update public.gyms set name = trim(p_payload->>'name'), accent_color = p_payload->>'accent_color',
          timezone = p_payload->>'timezone', currency = p_payload->>'currency',
          address = nullif(p_payload->>'address',''), phone = nullif(p_payload->>'phone',''), email = nullif(p_payload->>'email',''),
          logo_url = v_logo, settings = coalesce(settings, '{}'::jsonb) || v_settings
        where id = g.id returning * into g;
    end if;
    insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id)
    values(gen_random_uuid(), g.id, public.current_staff_id(), case when outcome = 'conflict' then 'sync_conflict' else 'update' end, 'gyms', g.id);
    insert into public.sync_receipts(id, gym_id, user_id, entity, entity_id, outcome)
    values(p_operation, g.id, auth.uid(), 'gyms', g.id, outcome);
    return jsonb_build_object('outcome', outcome, 'row', to_jsonb(g));
end $$;

create table public.staff_provisioning (
    id uuid primary key,
    actor_id uuid not null references auth.users(id),
    gym_id uuid not null references public.gyms(id),
    staff_id uuid not null unique,
    payload jsonb not null,
    user_id uuid references auth.users(id),
    created_at timestamptz not null default clock_timestamp(),
    updated_at timestamptz not null default clock_timestamp()
);
alter table public.staff_provisioning enable row level security;
revoke all on public.staff_provisioning from anon, authenticated;
grant all on public.staff_provisioning to service_role;
create trigger staff_provision_updated before update on public.staff_provisioning for each row execute function public.set_updated_at();

create or replace function public.staff_owner_gym(p_actor uuid)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_gym uuid;
begin
    select s.gym_id into v_gym from public.staff s join public.gyms g on g.id = s.gym_id
    where s.user_id = p_actor and s.role = 'owner' and s.active and s.deleted_at is null and g.status = 'active' and g.deleted_at is null;
    if v_gym is null then raise exception 'access_denied' using errcode = '42501'; end if;
    return v_gym;
end $$;

create or replace function public.staff_provision_begin(p_request uuid, p_actor uuid, p_staff uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_gym uuid := public.staff_owner_gym(p_actor); r public.staff_provisioning;
begin
    if p_request is null or p_staff is null or p_payload is null
      or coalesce(p_payload->>'role', '') not in ('manager','reception')
      or char_length(trim(coalesce(p_payload->>'full_name', ''))) not between 2 and 120
      or coalesce(p_payload->>'email', '') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
      or char_length(coalesce(p_payload->>'email', '')) > 254
      or char_length(coalesce(p_payload->>'phone', '')) > 32
      or (p_payload - array['role','full_name','email','phone']) <> '{}'::jsonb then
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

create or replace function public.staff_provision_auth_user(p_request uuid, p_actor uuid)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_gym uuid := public.staff_owner_gym(p_actor); r public.staff_provisioning; v_user uuid;
begin
    select * into strict r from public.staff_provisioning where id = p_request and actor_id = p_actor and gym_id = v_gym;
    select id into v_user from auth.users where lower(email) = lower(r.payload->>'email')
      and raw_app_meta_data->>'gymdesk_staff_request' = p_request::text;
    return v_user;
end $$;

create or replace function public.staff_provision_finish(p_request uuid, p_actor uuid, p_user uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_gym uuid := public.staff_owner_gym(p_actor); r public.staff_provisioning; s public.staff;
begin
    select * into strict r from public.staff_provisioning where id = p_request and actor_id = p_actor and gym_id = v_gym for update;
    if r.user_id is not null then
        select * into strict s from public.staff where id = r.staff_id;
        return to_jsonb(s);
    end if;
    if p_user is null or p_user is distinct from public.staff_provision_auth_user(p_request, p_actor) then
        raise exception 'access_denied' using errcode = '42501';
    end if;
    insert into public.staff(id, user_id, gym_id, role, full_name, phone)
    values(r.staff_id, p_user, v_gym, r.payload->>'role', r.payload->>'full_name', nullif(r.payload->>'phone','')) returning * into s;
    update public.staff_provisioning set user_id = p_user where id = r.id;
    insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id)
    select gen_random_uuid(), v_gym, st.id, 'create', 'staff', s.id from public.staff st where st.user_id = p_actor;
    return to_jsonb(s);
end $$;

create or replace function public.update_staff_access(p_staff uuid, p_role text, p_active boolean, p_version timestamptz)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_gym uuid := public.staff_owner_gym(auth.uid()); s public.staff;
begin
    if p_role is null or p_role not in ('manager','reception') or p_active is null then
        raise exception 'invalid_record' using errcode = '22023';
    end if;
    select * into s from public.staff where id = p_staff and gym_id = v_gym and role in ('manager','reception') and deleted_at is null for update;
    if not found or s.user_id = auth.uid() then raise exception 'access_denied' using errcode = '42501'; end if;
    if p_version is distinct from s.updated_at then raise exception 'conflict' using errcode = '40001'; end if;
    update public.staff set role = p_role, active = p_active where id = s.id returning * into s;
    insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id)
    values(gen_random_uuid(), v_gym, public.current_staff_id(), 'update', 'staff', s.id);
    return to_jsonb(s);
end $$;

revoke execute on function public.sync_branding(uuid,text,jsonb,timestamptz,timestamptz), public.staff_owner_gym(uuid), public.staff_provision_begin(uuid,uuid,uuid,jsonb), public.staff_provision_auth_user(uuid,uuid), public.staff_provision_finish(uuid,uuid,uuid), public.update_staff_access(uuid,text,boolean,timestamptz) from public, anon, authenticated;
grant execute on function public.sync_branding(uuid,text,jsonb,timestamptz,timestamptz), public.update_staff_access(uuid,text,boolean,timestamptz) to authenticated;
grant execute on function public.staff_owner_gym(uuid), public.staff_provision_begin(uuid,uuid,uuid,jsonb), public.staff_provision_auth_user(uuid,uuid), public.staff_provision_finish(uuid,uuid,uuid) to service_role;

commit;
