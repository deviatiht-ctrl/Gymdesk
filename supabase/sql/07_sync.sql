begin;

alter table public.staff add constraint staff_tenant_key unique (gym_id, id);
alter table public.members add constraint members_tenant_key unique (gym_id, id);
alter table public.plans add constraint plans_tenant_key unique (gym_id, id);
alter table public.subscriptions add constraint subscriptions_tenant_key unique (gym_id, id);
alter table public.subscriptions add constraint subscriptions_member_key unique (gym_id, member_id, id);
alter table public.members add constraint members_creator_tenant foreign key (gym_id, created_by) references public.staff(gym_id, id);
alter table public.subscriptions add constraint subscriptions_member_tenant foreign key (gym_id, member_id) references public.members(gym_id, id);
alter table public.subscriptions add constraint subscriptions_plan_tenant foreign key (gym_id, plan_id) references public.plans(gym_id, id);
alter table public.subscriptions add constraint subscriptions_creator_tenant foreign key (gym_id, created_by) references public.staff(gym_id, id);
alter table public.subscriptions add constraint subscriptions_renewal_member foreign key (gym_id, member_id, renewed_from) references public.subscriptions(gym_id, member_id, id);
alter table public.payments add constraint payments_member_tenant foreign key (gym_id, member_id) references public.members(gym_id, id);
alter table public.payments add constraint payments_subscription_member foreign key (gym_id, member_id, subscription_id) references public.subscriptions(gym_id, member_id, id);
alter table public.payments add constraint payments_receiver_tenant foreign key (gym_id, received_by) references public.staff(gym_id, id);
alter table public.attendance add constraint attendance_member_tenant foreign key (gym_id, member_id) references public.members(gym_id, id);
alter table public.attendance add constraint attendance_subscription_member foreign key (gym_id, member_id, subscription_id) references public.subscriptions(gym_id, member_id, id);
alter table public.attendance add constraint attendance_scanner_tenant foreign key (gym_id, scanned_by) references public.staff(gym_id, id);
alter table public.members add constraint members_nif_format check (nif is null or nif ~ '^[0-9]{10}$');

create table public.sync_receipts (
    id uuid primary key,
    gym_id uuid not null references public.gyms(id),
    user_id uuid not null references auth.users(id),
    entity text not null,
    entity_id uuid not null,
    outcome text not null check (outcome in ('accepted', 'conflict')),
    created_at timestamptz not null default clock_timestamp()
);
alter table public.sync_receipts enable row level security;
create policy receipts_read on public.sync_receipts for select to authenticated
using (gym_id = public.current_gym_id() and user_id = auth.uid() and public.is_gym_active(gym_id));
create policy receipts_insert on public.sync_receipts for insert to authenticated
with check (gym_id = public.current_gym_id() and user_id = auth.uid() and public.is_gym_active(gym_id));
grant select, insert on public.sync_receipts to authenticated;

create or replace function public.current_gym_id()
returns uuid language sql stable security definer set search_path = '' as $$
    select s.gym_id from public.staff s join public.gyms g on g.id = s.gym_id
    where s.user_id = auth.uid() and s.active and s.deleted_at is null and g.status = 'active'
$$;

create or replace function public.gym_setting(p_gym uuid, p_key text)
returns jsonb language sql stable security definer set search_path = '' as $$
    select g.settings -> p_key from public.gyms g
    where g.id = p_gym and g.id = public.current_gym_id()
$$;

create or replace function public.gym_setting_bool(p_gym uuid, p_key text)
returns boolean language sql stable security definer set search_path = '' as $$
    select coalesce(public.gym_setting(p_gym, p_key) = 'true'::jsonb, false)
$$;

create or replace function public.is_gym_active(p_gym uuid)
returns boolean language sql stable security definer set search_path = '' as $$
    select exists(select 1 from public.gyms g where g.id = p_gym and g.status = 'active'
      and (public.is_super_admin() or exists(select 1 from public.staff s
        where s.user_id = auth.uid() and s.gym_id = g.id and s.active and s.deleted_at is null)))
$$;

create or replace function public.reserve_member_numbers(p_gym uuid, p_count int)
returns table(prefix text, seq_first bigint, seq_last bigint)
language plpgsql security definer set search_path = '' as $$
declare v_last bigint; v_code text;
begin
    if p_gym is distinct from public.current_gym_id() or p_gym is null then
        raise exception 'access_denied' using errcode = '42501';
    end if;
    if p_count is null or p_count not between 1 and 500 then
        raise exception 'invalid_count' using errcode = '22023';
    end if;
    select g.code into strict v_code from public.gyms g where g.id = p_gym;
    update public.gym_counters set member_seq = member_seq + p_count
    where gym_id = p_gym returning member_seq into strict v_last;
    return query select v_code || '-', v_last - p_count + 1, v_last;
end $$;

create or replace function public.next_member_number(p_gym uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare r record;
begin
    select * into strict r from public.reserve_member_numbers(p_gym, 1);
    return r.prefix || lpad(r.seq_first::text, greatest(6, length(r.seq_first::text)), '0');
end $$;

create or replace function public.member_validity(p_member uuid, p_at timestamptz default now())
returns table(valid boolean, reason text, subscription_id uuid, end_date date, days_left int)
language plpgsql stable security invoker set search_path = '' as $$
declare v_member public.members; v_gym public.gyms; v_sub public.subscriptions;
    v_date date; v_grace int; v_pending boolean;
begin
    select * into v_member from public.members m where m.id = p_member and m.deleted_at is null;
    if not found then return query select false, 'unknown'::text, null::uuid, null::date, null::int; return; end if;
    select * into strict v_gym from public.gyms g where g.id = v_member.gym_id;
    if v_gym.status <> 'active' then return query select false, 'gym_suspended'::text, null::uuid, null::date, null::int; return; end if;
    if v_member.status <> 'active' then return query select false, v_member.status, null::uuid, null::date, null::int; return; end if;
    v_date := (p_at at time zone v_gym.timezone)::date;
    v_grace := greatest(0, least(365, coalesce((v_gym.settings->>'grace_days')::int, 0)));
    v_pending := coalesce((v_gym.settings->>'allow_access_pending')::boolean, false);
    select * into v_sub from public.subscriptions s where s.member_id = p_member
      and s.deleted_at is null and s.status <> 'cancelled' and s.start_date <= v_date
      and s.end_date + v_grace >= v_date and (s.status <> 'pending' or v_pending)
      order by s.end_date desc, s.id limit 1;
    if found then return query select true, 'ok'::text, v_sub.id, v_sub.end_date, greatest(0, v_sub.end_date - v_date); return; end if;
    select * into v_sub from public.subscriptions s where s.member_id = p_member
      and s.deleted_at is null and s.status = 'pending' and s.start_date <= v_date
      and s.end_date + v_grace >= v_date order by s.end_date desc, s.id limit 1;
    if found then return query select false, 'pending_payment'::text, v_sub.id, v_sub.end_date, greatest(0, v_sub.end_date - v_date); return; end if;
    select * into v_sub from public.subscriptions s where s.member_id = p_member
      and s.deleted_at is null and s.status <> 'cancelled' and s.end_date < v_date
      order by s.end_date desc, s.id limit 1;
    if found then return query select false, 'expired'::text, v_sub.id, v_sub.end_date, 0; return; end if;
    return query select false, 'no_subscription'::text, null::uuid, null::date, null::int;
end $$;

create or replace function public.compute_subscription_status()
returns int language plpgsql security definer set search_path = '' as $$
declare v_count int;
begin
    update public.subscriptions s set status = 'expired'
    from public.gyms g where s.gym_id = g.id and s.status = 'active'
      and s.deleted_at is null and s.end_date < (now() at time zone g.timezone)::date;
    get diagnostics v_count = row_count;
    return v_count;
end $$;

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
    new.updated_at := clock_timestamp();
    return new;
end $$;

create or replace function public.guard_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
    if auth.uid() is null then return new; end if;
    if new.id <> old.id then raise exception 'immutable_identity' using errcode = '42501'; end if;
    if tg_table_name = 'staff' then
        if new.user_id <> old.user_id or new.gym_id is distinct from old.gym_id then
            raise exception 'immutable_identity' using errcode = '42501';
        end if;
        if not public.is_super_admin() and (
            (old.role = 'owner' and (new.role <> old.role or new.active <> old.active or new.deleted_at is distinct from old.deleted_at))
            or (public.current_role() <> 'owner' and (new.role <> old.role or new.active <> old.active or new.deleted_at is distinct from old.deleted_at))
            or new.role = 'super_admin'
        ) then raise exception 'access_denied' using errcode = '42501'; end if;
    elsif tg_table_name = 'gyms' then
        if new.code <> old.code or (not public.is_super_admin() and new.status <> old.status) then
            raise exception 'access_denied' using errcode = '42501';
        end if;
    else
        if new.gym_id <> old.gym_id or new.created_at <> old.created_at then
            raise exception 'immutable_identity' using errcode = '42501';
        end if;
        if public.current_role() = 'reception' and new.deleted_at is distinct from old.deleted_at then
            raise exception 'access_denied' using errcode = '42501';
        end if;
    end if;
    return new;
end $$;

create trigger staff_identity before update on public.staff for each row execute function public.guard_identity();
create trigger gyms_identity before update on public.gyms for each row execute function public.guard_identity();
do $$ declare t text; begin
    foreach t in array array['members','plans','subscriptions','payments','badge_templates'] loop
        execute format('create trigger identity_guard before update on public.%I for each row execute function public.guard_identity()', t);
    end loop;
end $$;

drop policy gyms_select on public.gyms;
create policy gyms_select on public.gyms for select to authenticated using (
    public.is_super_admin() or exists(select 1 from public.staff s where s.gym_id = gyms.id and s.user_id = auth.uid() and s.active and s.deleted_at is null)
);
drop policy staff_select on public.staff;
create policy staff_select on public.staff for select to authenticated using (
    public.is_super_admin() or gym_id = public.current_gym_id() or user_id = auth.uid()
);
drop policy staff_delete on public.staff;
create policy staff_delete on public.staff for delete to authenticated using (
    public.is_super_admin() or (gym_id = public.current_gym_id() and public.current_role() = 'owner' and role in ('manager','reception'))
);

drop policy payments_select on public.payments;
create policy payments_select on public.payments for select to authenticated using (
    gym_id = public.current_gym_id() and (public.current_role() in ('owner','manager')
    or public.gym_setting_bool(gym_id, 'reception_see_all_payments')
    or (received_by = public.current_staff_id() and (paid_at at time zone (select g.timezone from public.gyms g where g.id = gym_id))::date
      = (now() at time zone (select g.timezone from public.gyms g where g.id = gym_id))::date))
);
drop policy payments_insert on public.payments;
create policy payments_insert on public.payments for insert to authenticated with check (
    gym_id = public.current_gym_id() and public.current_role() in ('owner','manager','reception') and received_by = public.current_staff_id()
);
drop policy audit_select on public.audit_log;
create policy audit_select on public.audit_log for select to authenticated using (gym_id = public.current_gym_id() and public.current_role() = 'owner');

create or replace function public.audit(p_action text, p_entity text, p_entity_id uuid, p_details jsonb default '{}'::jsonb, p_gym uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid := gen_random_uuid(); v_gym uuid := public.current_gym_id();
begin
    if v_gym is null or (p_gym is not null and p_gym <> v_gym) then
        raise exception 'access_denied' using errcode = '42501';
    end if;
    if p_action not in ('create','update','delete','sync_conflict')
       or p_entity not in ('members','plans','subscriptions','payments','attendance','badge_templates') then
        raise exception 'invalid_audit_event' using errcode = '22023';
    end if;
    insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id, details)
    values(v_id, v_gym, public.current_staff_id(), p_action, p_entity, p_entity_id, '{}'::jsonb);
    return v_id;
end $$;

create or replace function public.sync_context()
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare s public.staff; g public.gyms;
begin
    select * into s from public.staff where user_id = auth.uid() and active and deleted_at is null;
    if not found then raise exception 'access_denied' using errcode = '42501'; end if;
    if s.gym_id is not null then select * into strict g from public.gyms where id = s.gym_id; end if;
    return jsonb_build_object('server_time', clock_timestamp(), 'staff', to_jsonb(s), 'gym', case when g.id is null then null else to_jsonb(g) end);
end $$;

create or replace function public.sync_push(p_operation uuid, p_entity text, p_payload jsonb, p_changed_at timestamptz, p_base_version timestamptz default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
    v_gym uuid := public.current_gym_id(); v_id uuid := (p_payload->>'id')::uuid;
    v_old jsonb; v_row jsonb; v_receipt public.sync_receipts;
    v_columns text; v_assignments text; v_outcome text := 'accepted'; v_data jsonb := p_payload;
begin
    if v_gym is null or v_id is null or (p_payload->>'gym_id')::uuid is distinct from v_gym then
        raise exception 'access_denied' using errcode = '42501';
    end if;
    if p_entity not in ('members','plans','subscriptions','payments','attendance','badge_templates') then
        raise exception 'invalid_entity' using errcode = '22023';
    end if;
    if p_changed_at is null or p_changed_at > clock_timestamp() + interval '10 minutes' then
        raise exception 'invalid_clock' using errcode = '22023';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(p_entity || v_id::text, 0));
    select * into v_receipt from public.sync_receipts where id = p_operation;
    execute format('select to_jsonb(t) from public.%I t where id = $1 and gym_id = $2', p_entity)
      into v_old using v_id, v_gym;
    if v_receipt.id is not null then
        if v_receipt.entity <> p_entity or v_receipt.entity_id <> v_id then raise exception 'invalid_operation'; end if;
        return jsonb_build_object('outcome', v_receipt.outcome, 'row', v_old);
    end if;
    if v_old is not null and p_entity = 'attendance' then
        v_row := v_old;
    elsif v_old is not null and p_base_version is distinct from (v_old->>'updated_at')::timestamptz
          and p_changed_at <= (v_old->>'updated_at')::timestamptz then
        v_outcome := 'conflict'; v_row := v_old;
        perform public.audit('sync_conflict', p_entity, v_id);
    else
        if v_old is not null and p_base_version is distinct from (v_old->>'updated_at')::timestamptz then
            perform public.audit('sync_conflict', p_entity, v_id);
        end if;
        if p_entity = 'members' and (v_data->>'member_number') like 'TMP-%' then
            v_data := jsonb_set(v_data, '{member_number}', to_jsonb(coalesce(v_old->>'member_number', public.next_member_number(v_gym))));
        end if;
        if p_entity = 'attendance' then
            v_data := v_data || jsonb_build_object('scanned_by', public.current_staff_id(), 'server_received_at', clock_timestamp(), 'created_at', clock_timestamp());
        else
            v_data := v_data || jsonb_build_object('updated_at', clock_timestamp(), 'created_at', coalesce(v_old->'created_at', to_jsonb(clock_timestamp())));
        end if;
        if p_entity in ('members','subscriptions') and v_old is null then
            v_data := v_data || jsonb_build_object('created_by', public.current_staff_id());
        end if;
        if p_entity = 'payments' and v_old is null then
            v_data := v_data || jsonb_build_object('received_by', public.current_staff_id());
        end if;
        select string_agg(format('%I', a.attname), ', '),
               string_agg(format('%1$I = incoming.%1$I', a.attname), ', ')
        into v_columns, v_assignments from pg_attribute a
        where a.attrelid = format('public.%I', p_entity)::regclass
          and a.attnum > 0 and not a.attisdropped and v_data ? a.attname;
        if v_old is null then
            execute format('insert into public.%1$I (%2$s) select %2$s from jsonb_populate_record(null::public.%1$I, $1)', p_entity, v_columns)
            using v_data;
            execute format('select to_jsonb(t) from public.%I t where id = $1 and gym_id = $2', p_entity)
            into v_row using v_id, v_gym;
        else
            execute format('update public.%1$I as target set %2$s from jsonb_populate_record(null::public.%1$I, $1) incoming where target.id = $2 and target.gym_id = $3 returning to_jsonb(target)', p_entity, v_assignments)
            into v_row using v_data, v_id, v_gym;
            if v_row is null then raise exception 'access_denied' using errcode = '42501'; end if;
        end if;
        perform public.audit(case when v_old is null then 'create' when v_data->>'deleted_at' is not null then 'delete' else 'update' end, p_entity, v_id);
    end if;
    insert into public.sync_receipts(id, gym_id, user_id, entity, entity_id, outcome)
    values(p_operation, v_gym, auth.uid(), p_entity, v_id, v_outcome);
    return jsonb_build_object('outcome', v_outcome, 'row', v_row);
end $$;

create or replace function public.sync_pull(p_entity text, p_since timestamptz, p_until timestamptz, p_after_time timestamptz default null, p_after_id uuid default null, p_limit int default 250)
returns setof jsonb language plpgsql stable security invoker set search_path = '' as $$
declare v_column text;
begin
    if public.current_gym_id() is null then raise exception 'access_denied' using errcode = '42501'; end if;
    if p_entity not in ('staff','members','plans','subscriptions','payments','attendance','badge_templates','audit_log')
      or p_limit not between 1 and 500 then raise exception 'invalid_request' using errcode = '22023'; end if;
    v_column := case when p_entity = 'attendance' then 'server_received_at' when p_entity = 'audit_log' then 'created_at' else 'updated_at' end;
    return query execute format('select to_jsonb(t) from public.%1$I t where gym_id = $1 and %2$I >= $2 and %2$I <= $3 and ($4 is null or (%2$I, id) > ($4, $5)) order by %2$I, id limit $6', p_entity, v_column)
    using public.current_gym_id(), p_since, p_until, p_after_time, p_after_id, p_limit;
end $$;

revoke execute on function public.current_staff_id(), public.current_gym_id(), public.current_role(), public.is_super_admin(), public.is_gym_active(uuid), public.gym_setting(uuid,text), public.gym_setting_bool(uuid,text), public.next_member_number(uuid), public.reserve_member_numbers(uuid,int), public.member_validity(uuid,timestamptz), public.audit(text,text,uuid,jsonb,uuid), public.sync_context(), public.sync_push(uuid,text,jsonb,timestamptz,timestamptz), public.sync_pull(text,timestamptz,timestamptz,timestamptz,uuid,int), public.compute_subscription_status(), public.gen_qr_token(), public.guard_identity(), public.set_updated_at(), public.attendance_immutable(), public.init_gym_counter() from public, anon, authenticated;
grant execute on function public.current_staff_id(), public.current_gym_id(), public.current_role(), public.is_super_admin(), public.is_gym_active(uuid), public.gym_setting(uuid,text), public.gym_setting_bool(uuid,text), public.next_member_number(uuid), public.reserve_member_numbers(uuid,int), public.member_validity(uuid,timestamptz), public.audit(text,text,uuid,jsonb,uuid), public.sync_context(), public.sync_push(uuid,text,jsonb,timestamptz,timestamptz), public.sync_pull(text,timestamptz,timestamptz,timestamptz,uuid,int) to authenticated;
grant execute on function public.compute_subscription_status() to service_role;

do $$ declare t text; begin
    foreach t in array array['members','plans','subscriptions','payments','badge_templates'] loop
        execute format('create policy reception_no_tombstone_insert on public.%I as restrictive for insert to authenticated with check (public.current_role() <> ''reception'' or deleted_at is null)', t);
    end loop;
    if exists(select 1 from pg_publication where pubname = 'supabase_realtime') then
        foreach t in array array['staff','members','plans','subscriptions','payments','attendance','badge_templates','audit_log'] loop
            if not exists(select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
                execute format('alter publication supabase_realtime add table public.%I', t);
            end if;
        end loop;
    end if;
end $$;

commit;
