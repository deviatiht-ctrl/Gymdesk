begin;

-- Attendance is accepted as an immutable client observation, but the result,
-- linked subscription and daily entry number are authoritative server fields.
-- The raw QR token is used only for verification and is never stored in the
-- attendance row.
alter table public.attendance drop constraint attendance_result_check;
alter table public.attendance add constraint attendance_result_check check (result in (
  'granted','denied_expired','denied_no_subscription','denied_suspended','denied_pending','denied_duplicate','denied_unknown'
));

create or replace function public.sync_push(p_operation uuid, p_entity text, p_payload jsonb, p_changed_at timestamptz, p_base_version timestamptz default null)
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
            if v_qr_token is not null then
                select * into v_member from public.members m where m.gym_id = v_gym and m.qr_token = v_qr_token;
            end if;
            if v_member.id is null or v_member.deleted_at is not null or (v_member_id is not null and v_member_id <> v_member.id) then
                v_data := v_data - 'qr_token' || jsonb_build_object(
                    'member_id', null, 'subscription_id', null, 'result', 'denied_unknown',
                    'denial_reason', 'unknown_token', 'entry_number_today', null);
            else
                v_member_id := v_member.id;
                select * into v_validity from public.member_validity(v_member_id, v_scanned_at);
                if v_validity.valid then
                    select a.id into v_duplicate_id from public.attendance a
                    where a.gym_id = v_gym and a.member_id = v_member_id and a.result = 'granted'
                      and abs(extract(epoch from a.scanned_at - v_scanned_at)) <= v_duplicate_seconds
                    order by a.scanned_at desc limit 1;
                    if v_duplicate_id is not null then
                        v_data := v_data - 'qr_token' || jsonb_build_object(
                            'member_id', v_member_id, 'subscription_id', v_validity.subscription_id,
                            'result', 'denied_duplicate', 'denial_reason', 'duplicate_scan', 'entry_number_today', null);
                    else
                        select count(*) + 1 into v_entry_number from public.attendance a
                        where a.gym_id = v_gym and a.member_id = v_member_id and a.result = 'granted'
                          and (a.scanned_at at time zone v_gym_row.timezone)::date = (v_scanned_at at time zone v_gym_row.timezone)::date;
                        v_data := v_data - 'qr_token' || jsonb_build_object(
                            'member_id', v_member_id, 'subscription_id', v_validity.subscription_id, 'result', 'granted',
                            'denial_reason', null, 'entry_number_today', v_entry_number);
                    end if;
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
            else 'update' end;
        v_audit_details := jsonb_build_object('operation', p_operation, 'changed_at', p_changed_at,
            'result', v_data->>'result', 'member_id', v_data->>'member_id', 'was_offline', v_data->>'was_offline',
            'suspect_clock', v_data->>'suspect_clock');
        perform public.audit(v_audit_action, p_entity, v_id, v_audit_details);
    end if;
    insert into public.sync_receipts(id, gym_id, user_id, entity, entity_id, outcome)
    values(p_operation, v_gym, auth.uid(), p_entity, v_id, v_outcome);
    return jsonb_build_object('outcome', v_outcome, 'row', v_row);
end $$;

revoke all on function public.sync_push(uuid,text,jsonb,timestamptz,timestamptz) from public, anon;
grant execute on function public.sync_push(uuid,text,jsonb,timestamptz,timestamptz) to authenticated;

commit;
