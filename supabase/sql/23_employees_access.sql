-- =============================================================================
-- 23_employees_access.sql — Anplwaye (aksè pòt pa anprent), rapèl J-7/J-2/J0,
-- lang imèl manm yo. Idempotent. Aplike APRÈ 22_email_delivery_fix.sql.
--  * public.employees: antrenè, resepsyon, netwayaj, sekirite... (pa gen kont app)
--  * sync_push / sync_pull: antite 'employees' (owner/supervisor ekri, tout staff li)
--  * process_daily_reminders: imèl 7 jou, 2 jou, ak jou abònman an fini
--  * gym_email_branding: 'language' (gyms.settings->>'member_language', default fr)
-- =============================================================================

create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  first_name text not null check (length(trim(first_name)) between 1 and 80),
  last_name text not null default '' check (length(last_name) <= 80),
  phone text check (phone is null or length(phone) <= 32),
  email text check (email is null or length(email) <= 254),
  job_type text not null default 'other'
    check (job_type in ('coach', 'reception', 'cleaning', 'security', 'manager', 'maintenance', 'other')),
  job_title text check (job_title is null or length(job_title) <= 80),
  hired_on date,
  notes text check (notes is null or length(notes) <= 1000),
  active boolean not null default true,
  fingerprint_template text check (fingerprint_template is null or length(fingerprint_template) <= 8192),
  fingerprint_templates jsonb not null default '[]'::jsonb,
  fingerprint_registered boolean not null default false,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);
create index if not exists employees_gym_updated on public.employees(gym_id, updated_at, id);

alter table public.employees enable row level security;
drop policy if exists employees_read on public.employees;
create policy employees_read on public.employees for select to authenticated
  using (public.is_super_admin() or gym_id = public.current_gym_id());
drop policy if exists employees_manage on public.employees;
create policy employees_manage on public.employees for all to authenticated
  using (public.is_super_admin() or (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor')))
  with check (public.is_super_admin() or (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor')));

-- -----------------------------------------------------------------------------
-- Audit (= 11 + anplwaye yo + aksyon V2 sync_push deja voye yo: badges,
-- member_pins, payment_declarations — san yo, sync_push te refize ak
-- invalid_audit_event pou antite sa yo).
-- -----------------------------------------------------------------------------
create or replace function public.audit(p_action text, p_entity text, p_entity_id uuid, p_details jsonb default '{}'::jsonb, p_gym uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid := gen_random_uuid(); v_gym uuid := public.current_gym_id();
begin
    if v_gym is null or public.current_staff_id() is null or (p_gym is not null and p_gym <> v_gym) then
        raise exception 'access_denied' using errcode = '42501';
    end if;
    if jsonb_typeof(coalesce(p_details, '{}'::jsonb)) is distinct from 'object' or char_length(p_details::text) > 4096 then
        raise exception 'invalid_audit_event' using errcode = '22023';
    end if;
    if p_entity not in ('members','plans','subscriptions','payments','attendance','badge_templates','gyms','staff',
                        'badges','member_pins','payment_declarations','employees')
       or p_action not in (
         'create','update','delete','sync_conflict',
         'member_create','member_update','member_archive','qr_regenerate',
         'plan_save','plan_archive',
         'subscription_create','subscription_update','subscription_renew','subscription_cancel','subscription_archive',
         'payment_create','payment_update','payment_archive',
         'attendance_scan','badge_template_save','badge_template_archive','export',
         'badge_bind','badge_update','pin_set','pin_update','payment_declaration',
         'employee_create','employee_update','employee_archive','branding_updated'
       ) then
        raise exception 'invalid_audit_event' using errcode = '22023';
    end if;
    insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id, details)
    values(v_id, v_gym, public.current_staff_id(), p_action, p_entity, p_entity_id, coalesce(p_details, '{}'::jsonb));
    return v_id;
end $$;

revoke execute on function public.audit(text,text,uuid,jsonb,uuid) from public, anon;
grant execute on function public.audit(text,text,uuid,jsonb,uuid) to authenticated;

do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'employees') then
    execute 'alter publication supabase_realtime add table public.employees';
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- sync_push (= 16 + 'employees')
-- -----------------------------------------------------------------------------

create or replace function public.sync_push(
  p_operation uuid,
  p_entity text,
  p_payload jsonb,
  p_changed_at timestamptz,
  p_base_version timestamptz default null
)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
    v_gym uuid := public.current_gym_id(); v_id uuid := (p_payload->>'id')::uuid;
    v_old jsonb; v_row jsonb; v_receipt public.sync_receipts;
    v_columns text; v_assignments text; v_outcome text := 'accepted'; v_data jsonb := p_payload;
    v_member public.members; v_member_id uuid; v_qr_token text; v_scanned_at timestamptz;
    v_validity record; v_duplicate_id uuid; v_duplicate_seconds int; v_entry_number int; v_gym_row public.gyms;
    v_audit_action text; v_audit_details jsonb := '{}'::jsonb;
begin
    if v_gym is null or v_id is null or (p_payload->>'gym_id')::uuid is distinct from v_gym then
        raise exception 'access_denied' using errcode = '42501';
    end if;
    if p_entity not in ('members','plans','subscriptions','payments','attendance','badge_templates',
                        'badges','member_pins','payment_declarations','employees') then
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
    elsif v_old is not null and p_entity = 'badges'
          and nullif(v_old->>'member_id', '') is not null
          and v_old->>'member_id' is distinct from v_data->>'member_id' then
        v_outcome := 'conflict'; v_row := v_old;
        perform public.audit('sync_conflict', p_entity, v_id);
    elsif v_old is not null and p_entity = 'payment_declarations' then
        v_outcome := 'conflict'; v_row := v_old;
    elsif v_old is not null and p_base_version is distinct from (v_old->>'updated_at')::timestamptz
          and p_changed_at <= (v_old->>'updated_at')::timestamptz then
        v_outcome := 'conflict'; v_row := v_old;
        perform public.audit('sync_conflict', p_entity, v_id);
    else
        if v_old is not null and p_base_version is distinct from (v_old->>'updated_at')::timestamptz then
            perform public.audit('sync_conflict', p_entity, v_id);
        end if;
        if p_entity = 'badges' and v_old is null then
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        if p_entity = 'member_pins' then
            if v_old is not null
               and v_old->>'pin_hash' is distinct from 'UNSET'
               and coalesce((v_old->>'reset_required')::boolean, false)
               and not coalesce((v_data->>'reset_required')::boolean, true)
               and v_data->>'pin_hash' is distinct from v_old->>'pin_hash'
               and public.current_role() not in ('owner', 'supervisor')
               and not public.is_super_admin() then
                raise exception 'access_denied' using errcode = '42501';
            end if;

            -- Otorize 'UNSET' lè se yon reset PIN
            if coalesce((v_data->>'reset_required')::boolean, false) or v_data->>'pin_hash' = 'UNSET' then
                null;
            elsif v_data->>'pin_hash' is null or length(v_data->>'pin_hash') < 20
               or v_data->>'salt' is null or length(v_data->>'salt') < 10 then
                raise exception 'invalid_record' using errcode = '22023';
            end if;
            v_data := v_data || jsonb_build_object('member_id', coalesce(nullif(v_data->>'member_id','')::uuid, v_id));
        end if;
        if p_entity = 'payment_declarations' then
            v_data := v_data || jsonb_build_object(
                'status', 'pending', 'reviewed_by', null, 'reviewed_at', null,
                'created_by', auth.uid());
            if nullif(v_data->>'method','') is null or (v_data->>'amount')::numeric < 0 then
                raise exception 'invalid_record' using errcode = '22023';
            end if;
        end if;
        if p_entity = 'members' and (v_data->>'member_number') like 'TMP-%' then
            v_data := jsonb_set(v_data, '{member_number}', to_jsonb(coalesce(v_old->>'member_number', public.next_member_number(v_gym))));
        end if;
        if p_entity = 'badge_templates' and coalesce((v_data->>'is_default')::boolean, false) then
            update public.badge_templates set is_default = false
            where gym_id = v_gym and id <> v_id and is_default and deleted_at is null;
        end if;
        if p_entity = 'attendance' then
            v_member_id := nullif(v_data->>'member_id', '')::uuid;
            v_qr_token := nullif(v_data->>'qr_token', '');
            v_scanned_at := nullif(v_data->>'scanned_at', '')::timestamptz;
            if v_scanned_at is null or v_scanned_at > clock_timestamp() + interval '10 minutes'
               or v_scanned_at < clock_timestamp() - interval '30 days' then
                raise exception 'invalid_record' using errcode = '22023';
            end if;
            select * into strict v_gym_row from public.gyms where id = v_gym;
            v_duplicate_seconds := greatest(0, least(3600, coalesce((v_gym_row.settings->>'entry_duplicate_seconds')::int, 3)));
            if v_member_id is not null then
                select * into v_member from public.members m where m.gym_id = v_gym and m.id = v_member_id;
            elsif v_qr_token is not null then
                select * into v_member from public.members m where m.gym_id = v_gym and m.qr_token = v_qr_token;
            end if;
            if v_member.id is null or v_member.deleted_at is not null then
                v_data := v_data - 'qr_token' || jsonb_build_object(
                    'member_id', null, 'subscription_id', null, 'result', 'denied_unknown',
                    'denial_reason', 'unknown_token', 'entry_number_today', null);
            else
                v_member_id := v_member.id;
                v_data := v_data - 'qr_token' || jsonb_build_object('member_id', v_member_id);
                if v_duplicate_seconds > 0 then
                    select a.id into v_duplicate_id from public.attendance a
                    where a.gym_id = v_gym and a.member_id = v_member_id and a.result = 'granted'
                      and a.scanned_at between v_scanned_at - (v_duplicate_seconds || ' seconds')::interval
                                          and v_scanned_at + (v_duplicate_seconds || ' seconds')::interval
                    limit 1;
                end if;
                if v_duplicate_id is not null then
                    v_data := v_data || jsonb_build_object('result', 'denied_duplicate', 'denial_reason', 'duplicate_scan', 'entry_number_today', null);
                else
                    select * into v_validity from public.member_validity(v_member_id, v_scanned_at);
                    if v_validity.valid then
                        select count(*) + 1 into v_entry_number from public.attendance a
                        where a.gym_id = v_gym and a.member_id = v_member_id and a.result = 'granted'
                          and (a.scanned_at at time zone v_gym_row.timezone)::date = (v_scanned_at at time zone v_gym_row.timezone)::date;
                        v_data := v_data - 'qr_token' || jsonb_build_object(
                            'member_id', v_member_id, 'subscription_id', v_validity.subscription_id, 'result', 'granted',
                            'denial_reason', null, 'entry_number_today', v_entry_number);
                    else
                        v_data := v_data - 'qr_token' || jsonb_build_object(
                            'member_id', v_member_id, 'subscription_id', v_validity.subscription_id,
                            'result', case v_validity.reason
                                when 'pending_payment' then 'denied_pending'
                                when 'expired' then 'denied_expired'
                                when 'no_subscription' then 'denied_no_subscription'
                                else 'denied_suspended' end,
                            'denial_reason', v_validity.reason, 'entry_number_today', null);
                    end if;
                end if;
            end if;
            v_data := v_data || jsonb_build_object(
                'scanned_by', public.current_staff_id(), 'server_received_at', clock_timestamp(), 'created_at', clock_timestamp(),
                'was_offline', coalesce((v_data->>'was_offline')::boolean, false),
                'suspect_clock', coalesce((v_data->>'suspect_clock')::boolean, false));
            if length(coalesce(v_data->>'device_id', '')) > 120 or length(coalesce(v_data->>'denial_reason', '')) > 120 then
                raise exception 'invalid_record' using errcode = '22023';
            end if;
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
            execute format('select to_jsonb(t) from public.%1$I t where id = $1 and gym_id = $2', p_entity)
            into v_row using v_id, v_gym;
        else
            execute format('update public.%1$I as target set %2$s from jsonb_populate_record(null::public.%1$I, $1) incoming where target.id = $2 and target.gym_id = $3 returning to_jsonb(target)', p_entity, v_assignments)
            into v_row using v_data, v_id, v_gym;
            if v_row is null then raise exception 'access_denied' using errcode = '42501'; end if;
        end if;
        v_audit_action := case
            when p_entity = 'attendance' then 'attendance_scan'
            when p_entity = 'members' and v_old is null then 'member_create'
            when p_entity = 'members' and v_data->>'deleted_at' is not null then 'member_archive'
            when p_entity = 'members' and v_old->>'qr_token' is distinct from v_data->>'qr_token' then 'qr_regenerate'
            when p_entity = 'members' then 'member_update'
            when p_entity = 'plans' and v_data->>'deleted_at' is not null then 'plan_archive'
            when p_entity = 'plans' then 'plan_save'
            when p_entity = 'subscriptions' and v_old is null and v_data->>'renewed_from' is not null then 'subscription_renew'
            when p_entity = 'subscriptions' and v_old is null then 'subscription_create'
            when p_entity = 'subscriptions' and v_data->>'deleted_at' is not null then 'subscription_archive'
            when p_entity = 'subscriptions' and v_data->>'status' = 'cancelled' and v_old->>'status' is distinct from 'cancelled' then 'subscription_cancel'
            when p_entity = 'subscriptions' then 'subscription_update'
            when p_entity = 'payments' and v_old is null then 'payment_create'
            when p_entity = 'payments' and v_data->>'deleted_at' is not null then 'payment_archive'
            when p_entity = 'payments' then 'payment_update'
            when p_entity = 'badge_templates' and v_data->>'deleted_at' is not null then 'badge_template_archive'
            when p_entity = 'badge_templates' then 'badge_template_save'
            when p_entity = 'badges' and v_data->>'member_id' is not null and v_old->>'member_id' is null then 'badge_bind'
            when p_entity = 'badges' then 'badge_update'
            when p_entity = 'member_pins' and v_old is null then 'pin_set'
            when p_entity = 'member_pins' then 'pin_update'
            when p_entity = 'payment_declarations' then 'payment_declaration'
            when p_entity = 'employees' and v_old is null then 'employee_create'
            when p_entity = 'employees' and v_data->>'deleted_at' is not null then 'employee_archive'
            when p_entity = 'employees' then 'employee_update'
            else 'update' end;
        v_audit_details := jsonb_build_object('operation', p_operation, 'changed_at', p_changed_at,
            'result', v_data->>'result', 'member_id', v_data->>'member_id', 'was_offline', v_data->>'was_offline',
            'suspect_clock', v_data->>'suspect_clock');
        perform public.audit(v_audit_action, p_entity, v_id, v_audit_details);
    end if;
    insert into public.sync_receipts(id, gym_id, user_id, entity, entity_id, outcome)
    values(p_operation, v_gym, auth.uid(), p_entity, v_id, v_outcome);
    return jsonb_build_object('outcome', v_outcome, 'row', v_row);
end;
$$;

revoke all on function public.sync_push(uuid,text,jsonb,timestamptz,timestamptz) from public, anon;
grant execute on function public.sync_push(uuid,text,jsonb,timestamptz,timestamptz) to authenticated;

-- -----------------------------------------------------------------------------
-- sync_pull (= 13 + 'employees')
-- -----------------------------------------------------------------------------
create or replace function public.sync_pull(
  p_entity text,
  p_since timestamptz,
  p_until timestamptz,
  p_after_time timestamptz default null,
  p_after_id uuid default null,
  p_limit int default 250
)
returns setof jsonb
language plpgsql stable security invoker
set search_path = ''
as $$
declare
  v_column text;
begin
  if public.current_gym_id() is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  if p_entity not in (
    'staff', 'members', 'plans', 'subscriptions', 'payments', 'attendance',
    'badge_templates', 'audit_log', 'badge_batches', 'badges', 'badge_history',
    'member_pins', 'payment_declarations', 'gym_contracts', 'platform_invoices', 'employees'
  ) or p_limit not between 1 and 500 then
    raise exception 'invalid_request' using errcode = '22023';
  end if;

  v_column := case
    when p_entity = 'attendance' then 'server_received_at'
    when p_entity in ('audit_log', 'badge_history', 'badge_batches', 'payment_declarations') then 'created_at'
    else 'updated_at'
  end;

  return query execute format(
    'select to_jsonb(t) from public.%1$I t where gym_id = $1 and %2$I >= $2 and %2$I <= $3 and ($4 is null or (%2$I, id) > ($4, $5)) order by %2$I, id limit $6',
    p_entity, v_column
  ) using public.current_gym_id(), p_since, p_until, p_after_time, p_after_id, p_limit;
end;
$$;

grant execute on function public.sync_pull(text, timestamptz, timestamptz, timestamptz, uuid, int) to authenticated;

-- -----------------------------------------------------------------------------
-- Lang imèl manm yo (chwazi pa pwopriyetè a nan Paramèt sal la)
-- -----------------------------------------------------------------------------
create or replace function public.gym_email_branding(p_gym uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('gym_id', g.id, 'gym_name', g.name, 'logo_path', g.logo_url, 'accent_color', g.accent_color,
    'gym_phone', g.phone, 'gym_address', g.address, 'reply_to', public.gym_reply_to(g.id),
    'language', case when g.settings->>'member_language' in ('ht', 'fr', 'en') then g.settings->>'member_language' else 'fr' end)
  from public.gyms g where g.id = p_gym;
$$;
revoke all on function public.gym_email_branding(uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Rapèl renouvèlman: J-7, J-2 ak J0 (manm ki deja renouvle yo pa resevwa anyen)
-- -----------------------------------------------------------------------------
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
      continue when v_days not in (7, 2, 0);
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

-- -----------------------------------------------------------------------------
-- sync_branding (= 18 + 'member_language'). 'branding_updated' ajoute nan
-- whitelist audit la pi wo: san li, anrejistreman paramèt sal la te echwe.
-- -----------------------------------------------------------------------------
create or replace function public.sync_branding(
  p_operation uuid,
  p_entity text,
  p_payload jsonb,
  p_changed_at timestamptz,
  p_base_version timestamptz default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    g public.gyms; r public.sync_receipts; outcome text := 'accepted';
    v_logo text := nullif(p_payload->>'logo_url', '');
    v_settings jsonb := coalesce(p_payload->'settings', '{}'::jsonb);
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

        -- Whitelist elaji ki gen ladan paramèt pòt FSTW F30 ak byometri
        if exists(select 1 from jsonb_object_keys(v_settings) k where k not in (
            'doc_footer','offline_lease_hours','auto_logout_minutes','pin_lock_minutes',
            'allow_access_pending','grace_days','reception_see_all_payments','scan_sound',
            'scan_vibrate','entry_duplicate_seconds','qr_defaults',
            'badge_theme','badge_qr_style','badge_positions',
            'biometric_mode','biometric_enabled',
            'door_terminal_ip','door_terminal_port','door_terminal_enabled',
            'temporary_pin_duration_hours','member_language')) then
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
        if v_logo is not null and v_logo !~ '^https?://' and v_logo !~ '^gym-assets/[0-9a-fA-F-]{36}/' then
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        update public.gyms set
            name = trim(p_payload->>'name'),
            accent_color = p_payload->>'accent_color',
            currency = p_payload->>'currency',
            timezone = p_payload->>'timezone',
            address = nullif(trim(p_payload->>'address'), ''),
            phone = nullif(trim(p_payload->>'phone'), ''),
            email = nullif(trim(p_payload->>'email'), ''),
            logo_url = v_logo,
            settings = v_settings,
            updated_at = clock_timestamp()
        where id = g.id
        returning * into g;
    end if;
    insert into public.sync_receipts(id, gym_id, user_id, entity, entity_id, outcome)
    values (p_operation, g.id, auth.uid(), 'gyms', g.id, outcome);
    perform public.audit('branding_updated', 'gyms', g.id, jsonb_build_object('settings', v_settings));
    return jsonb_build_object('outcome', outcome, 'row', to_jsonb(g));
end;
$$;

revoke all on function public.sync_branding(uuid, text, jsonb, timestamptz, timestamptz) from public, anon;
grant execute on function public.sync_branding(uuid, text, jsonb, timestamptz, timestamptz) to authenticated;
