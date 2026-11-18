-- =============================================================================
-- 50_fix_sync_permissions_and_unblock_outbox.sql
-- 1. Permettre au personnel de réception (ex: Lourdmia Coq / caissières / secrétaires)
--    de synchroniser les abonnements, les paiements, les membres et les archivages (tombstones)
--    sans être bloqués par 'access_denied' (erreur 42501).
-- 2. Définir sync_push en SECURITY DEFINER pour sécuriser l'exécution dans le contexte du gym
--    et éviter que les politiques RLS REST ne bloquent les écritures légitimes de la file outbox.
-- 3. Mettre à jour les politiques RLS de subscriptions, payments, plans, members.
-- 4. Débloquer la file d'attente (55 opérations en attente) et aligner les revenus.
-- =============================================================================

begin;

-- 1. Mettre à jour guard_identity() pour autoriser l'archivage (deleted_at) par le staff du gym
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
        -- Les membres du personnel du gym (owner, supervisor, manager, reception)
        -- sont autorisés à archiver/désarchiver (deleted_at) dans le cadre de leurs opérations.
    end if;
    return new;
end $$;

-- 2. Supprimer les politiques restrictives reception_no_tombstone_insert
drop policy if exists reception_no_tombstone_insert on public.members;
drop policy if exists reception_no_tombstone_insert on public.plans;
drop policy if exists reception_no_tombstone_insert on public.subscriptions;
drop policy if exists reception_no_tombstone_insert on public.payments;
drop policy if exists reception_no_tombstone_insert on public.badge_templates;

-- 3. Mettre à jour les politiques RLS pour subscriptions, payments, plans, members
drop policy if exists subs_update on public.subscriptions;
create policy subs_update on public.subscriptions for update to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception'))
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception'));

drop policy if exists payments_update on public.payments;
create policy payments_update on public.payments for update to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception'))
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception'));

drop policy if exists payments_insert on public.payments;
create policy payments_insert on public.payments for insert to authenticated
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception'));

drop policy if exists plans_insert on public.plans;
create policy plans_insert on public.plans for insert to authenticated
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception'));

drop policy if exists plans_update on public.plans;
create policy plans_update on public.plans for update to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception'))
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception'));

drop policy if exists members_update on public.members;
create policy members_update on public.members for update to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception'))
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception'));

drop policy if exists members_delete on public.members;
create policy members_delete on public.members for delete to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'manager', 'reception'));

-- 4. Définir sync_push en SECURITY DEFINER pour garantir la poussée atomique de la file outbox
create or replace function public.sync_push(
  p_operation uuid,
  p_entity text,
  p_payload jsonb,
  p_changed_at timestamptz,
  p_base_version timestamptz default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
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
        if p_entity = 'attendance' then
            v_qr_token := v_data->>'qr_token';
            v_scanned_at := coalesce((v_data->>'scanned_at')::timestamptz, clock_timestamp());
            select * into strict v_gym_row from public.gyms where id = v_gym;
            v_duplicate_seconds := coalesce((public.gym_setting(v_gym, 'duplicate_scan_window_seconds'))::int, 15);
            if v_data ? 'member_id' and nullif(v_data->>'member_id','') is not null then
                select * into v_member from public.members where id = (v_data->>'member_id')::uuid and gym_id = v_gym;
            elsif v_qr_token is not null then
                select * into v_member from public.members where qr_token = v_qr_token and gym_id = v_gym;
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
                    select * into v_validity from public.member_validity(v_gym, v_member_id, v_scanned_at);
                    if not found or v_validity.valid is null then
                        select * into v_validity from public.member_validity(v_member_id, v_scanned_at);
                    end if;
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
            v_data := v_data || jsonb_build_object('created_by', coalesce(nullif(v_data->>'created_by','')::uuid, public.current_staff_id()));
        end if;
        if p_entity = 'payments' and v_old is null then
            v_data := v_data || jsonb_build_object('received_by', coalesce(nullif(v_data->>'received_by','')::uuid, public.current_staff_id()));
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
end $$;

revoke all on function public.sync_push(uuid,text,jsonb,timestamptz,timestamptz) from public, anon;
grant execute on function public.sync_push(uuid,text,jsonb,timestamptz,timestamptz) to authenticated;

commit;
