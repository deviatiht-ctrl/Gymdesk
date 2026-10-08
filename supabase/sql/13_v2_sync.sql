-- =============================================================
-- 13_v2_sync.sql — GymDesk V2 Sync & Platform Billing
-- Extends sync_push/sync_pull to V2 entities, adds member_pins.id,
-- platform_invoices, anon offer reads for self-signup, and the
-- payment-declaration / PIN-reset / extra-badge RPCs.
-- Idempotent: safe to re-run.
-- =============================================================

begin;

-- -------------------------------------------------------------
-- 1. member_pins : clé 'id' requise par la couche de sync générique
-- -------------------------------------------------------------
alter table public.member_pins add column if not exists id uuid;
update public.member_pins set id = member_id where id is null;
alter table public.member_pins alter column id set default gen_random_uuid();
alter table public.member_pins alter column id set not null;
create unique index if not exists member_pins_id_key on public.member_pins(id);

-- -------------------------------------------------------------
-- 2. Facturation plateforme
-- -------------------------------------------------------------
create table if not exists public.platform_invoices (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  contract_id uuid references public.gym_contracts(id) on delete set null,
  period_start date not null,
  period_end date not null,
  amount numeric(12,2) not null check (amount >= 0),
  currency text not null default 'USD',
  status text not null default 'open' check (status in ('open', 'paid', 'overdue', 'void')),
  due_date date,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'payment_declarations_invoice_id_fkey'
  ) then
    alter table public.payment_declarations
      add constraint payment_declarations_invoice_id_fkey
      foreign key (invoice_id) references public.platform_invoices(id) on delete set null;
  end if;
end $$;

create index if not exists idx_platform_invoices_gym on public.platform_invoices(gym_id);
create index if not exists idx_platform_invoices_status on public.platform_invoices(status);

alter table public.platform_invoices enable row level security;
drop policy if exists platform_invoices_read on public.platform_invoices;
create policy platform_invoices_read on public.platform_invoices for select to authenticated
  using (public.is_super_admin() or (gym_id = public.current_gym_id() and public.current_role() = 'owner'));
drop policy if exists platform_invoices_admin on public.platform_invoices;
create policy platform_invoices_admin on public.platform_invoices for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

-- -------------------------------------------------------------
-- 3. RLS : activation au comptoir (réception) + lecture anonyme
--    des offres publiques pour l'inscription en self-service
-- -------------------------------------------------------------
drop policy if exists badges_update_reception on public.badges;
create policy badges_update_reception on public.badges for update to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() = 'reception')
  with check (gym_id = public.current_gym_id() and public.current_role() = 'reception');

drop policy if exists member_pins_manage on public.member_pins;
create policy member_pins_manage on public.member_pins for all to authenticated
  using (public.is_super_admin() or (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'reception')))
  with check (public.is_super_admin() or (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'reception')));

drop policy if exists platform_offers_read_anon on public.platform_offers;
create policy platform_offers_read_anon on public.platform_offers for select to anon
  using (active);

drop policy if exists platform_settings_read_anon on public.platform_settings;
create policy platform_settings_read_anon on public.platform_settings for select to anon
  using (key = 'payment_instructions');

-- -------------------------------------------------------------
-- 4. sync_push V2 : badges, member_pins, payment_declarations
-- -------------------------------------------------------------
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
    if p_entity not in ('members','plans','subscriptions','payments','attendance','badge_templates',
                        'badges','member_pins','payment_declarations') then
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
        -- Activation concurrente sur un autre appareil : le premier arrivé gagne.
        v_outcome := 'conflict'; v_row := v_old;
        perform public.audit('sync_conflict', p_entity, v_id);
    elsif v_old is not null and p_entity = 'payment_declarations' then
        -- Déclaration append-only : la revue passe par review_payment_declaration.
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
            -- Les badges sont générés uniquement côté serveur (generate_badge_batch).
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        if p_entity = 'member_pins' then
            -- Effacer un verrou 'reset_required' posé sur un vrai hash (réinitialisation
            -- d'un PIN oublié) est réservé au owner/supervisor. La première définition
            -- du PIN (hash 'UNSET' côté serveur) reste possible à la réception.
            if v_old is not null
               and v_old->>'pin_hash' is distinct from 'UNSET'
               and coalesce((v_old->>'reset_required')::boolean, false)
               and not coalesce((v_data->>'reset_required')::boolean, true)
               and v_data->>'pin_hash' is distinct from v_old->>'pin_hash'
               and public.current_role() not in ('owner', 'supervisor')
               and not public.is_super_admin() then
                raise exception 'access_denied' using errcode = '42501';
            end if;
            -- Le PIN ne doit jamais être poussé en clair.
            if v_data->>'pin_hash' is null or length(v_data->>'pin_hash') < 20
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
            when p_entity = 'badges' and v_data->>'member_id' is not null and v_old->>'member_id' is null then 'badge_bind'
            when p_entity = 'badges' then 'badge_update'
            when p_entity = 'member_pins' and v_old is null then 'pin_set'
            when p_entity = 'member_pins' then 'pin_update'
            when p_entity = 'payment_declarations' then 'payment_declaration'
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

-- -------------------------------------------------------------
-- 5. sync_pull V2 : ajout des contrats et factures plateforme
-- -------------------------------------------------------------
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
    'member_pins', 'payment_declarations', 'gym_contracts', 'platform_invoices'
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

-- -------------------------------------------------------------
-- 6. RPC : Réinitialisation du PIN membre (owner / supervisor)
-- -------------------------------------------------------------
create or replace function public.reset_member_pin(p_member uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_member public.members;
begin
  if public.current_role() not in ('owner', 'supervisor') and not public.is_super_admin() then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  select * into strict v_member from public.members
    where id = p_member and gym_id = public.current_gym_id() and deleted_at is null;

  insert into public.member_pins (id, member_id, gym_id, pin_hash, salt, reset_required, updated_at)
  values (p_member, p_member, v_member.gym_id, 'UNSET', 'UNSET', true, clock_timestamp())
  on conflict (member_id) do update
  set pin_hash = 'UNSET', salt = 'UNSET', failed_count = 0, total_failed = 0,
      locked_until = null, reset_required = true, updated_at = clock_timestamp();

  perform public.audit('pin_reset', 'members', p_member);

  return jsonb_build_object('success', true, 'member_id', p_member);
end;
$$;

grant execute on function public.reset_member_pin(uuid) to authenticated;

-- -------------------------------------------------------------
-- 7. RPC : Demande de badges supplémentaires (hors quota)
-- -------------------------------------------------------------
create or replace function public.request_extra_badges(p_quantity int, p_note text default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym uuid := public.current_gym_id();
  v_id uuid := gen_random_uuid();
  v_currency text := 'USD';
begin
  if public.current_role() <> 'owner' and not public.is_super_admin() then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity <= 0 or p_quantity > 500 then
    raise exception 'invalid_quantity' using errcode = '22023';
  end if;

  insert into public.payment_declarations (id, gym_id, method, amount, currency, status, note, created_by)
  values (v_id, v_gym, 'other', 0, v_currency, 'pending',
          'EXTRA_BADGES:' || p_quantity || coalesce(' — ' || left(p_note, 200), ''),
          auth.uid());

  perform public.audit('extra_badges_request', 'payment_declarations', v_id,
    jsonb_build_object('quantity', p_quantity));

  return jsonb_build_object('success', true, 'declaration_id', v_id, 'quantity', p_quantity);
end;
$$;

grant execute on function public.request_extra_badges(int, text) to authenticated;

-- -------------------------------------------------------------
-- 8. RPC : Revue d'une déclaration de paiement (super admin)
-- -------------------------------------------------------------
create or replace function public.review_payment_declaration(
  p_declaration uuid,
  p_approve boolean,
  p_note text default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_decl public.payment_declarations;
  v_contract public.gym_contracts;
  v_offer public.platform_offers;
  v_extra_qty int;
  v_period interval;
begin
  if not public.is_super_admin() then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  select * into strict v_decl from public.payment_declarations
    where id = p_declaration for update;
  if v_decl.status <> 'pending' then
    raise exception 'already_reviewed' using errcode = 'P0001';
  end if;

  update public.payment_declarations
  set status = case when p_approve then 'approved' else 'rejected' end,
      reviewed_by = auth.uid(),
      reviewed_at = clock_timestamp(),
      note = coalesce(left(p_note, 500), note)
  where id = p_declaration;

  if p_approve then
    if v_decl.note like 'EXTRA_BADGES:%' then
      -- Demande de badges supplémentaires : générer le lot
      v_extra_qty := substring(v_decl.note from 'EXTRA_BADGES:([0-9]+)')::int;
      if v_extra_qty is not null and v_extra_qty > 0 then
        perform public.generate_badge_batch(v_decl.gym_id, v_extra_qty, 'extra_purchase');
      end if;
    else
      -- Paiement d'abonnement plateforme : réactiver la salle et le contrat
      update public.gyms
      set status = 'active', suspension_reason = null, updated_at = clock_timestamp()
      where id = v_decl.gym_id;

      select * into v_contract from public.gym_contracts
      where gym_id = v_decl.gym_id order by created_at desc limit 1;

      if v_contract.id is not null then
        select * into v_offer from public.platform_offers where id = v_contract.offer_id;
        v_period := case coalesce(v_offer.billing_period, 'monthly')
          when 'annual' then interval '1 year' else interval '1 month' end;
        update public.gym_contracts
        set status = 'active',
            expires_at = greatest(coalesce(expires_at, clock_timestamp()), clock_timestamp()) + v_period,
            updated_at = clock_timestamp()
        where id = v_contract.id;
      end if;

      if v_decl.invoice_id is not null then
        update public.platform_invoices
        set status = 'paid', updated_at = clock_timestamp()
        where id = v_decl.invoice_id;
      end if;
    end if;
  end if;

  perform public.audit('payment_declaration_review', 'payment_declarations', p_declaration,
    jsonb_build_object('approved', p_approve, 'gym_id', v_decl.gym_id));

  return jsonb_build_object('success', true, 'approved', p_approve);
end;
$$;

revoke all on function public.review_payment_declaration(uuid, boolean, text) from public, anon;
grant execute on function public.review_payment_declaration(uuid, boolean, text) to authenticated;

commit;
