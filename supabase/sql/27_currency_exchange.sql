-- ============================================================================
-- 27 — Devises USD / HTG + taux du jour (idempotent). Apply after 26.
--  * payments.paid_currency  : devise réellement donnée par le client
--  * payments.exchange_rate  : HTG pour 1 USD au moment du paiement
--  * payments.paid_amount    : montant encaissé (gardé) dans paid_currency
--  * payments.tendered_amount: billets remis dans paid_currency (avant monnaie)
--    amount / received_amount / credit_* restent dans la devise du plan
--    (`currency`), donc toute la logique de solde existante est inchangée.
--  * gyms.settings.exchange_rate_htg : taux du jour réglé par le propriétaire
--  * sync_branding : whitelist + 'exchange_rate_htg' (validé 1..100000)
--  * enqueue_payment_receipt : payload email + devise payée / taux
-- ============================================================================
begin;

alter table public.payments
  add column if not exists paid_currency text
    check (paid_currency is null or paid_currency in ('HTG','USD')),
  add column if not exists exchange_rate numeric(12,4)
    check (exchange_rate is null or exchange_rate > 0),
  add column if not exists paid_amount numeric(14,2)
    check (paid_amount is null or paid_amount >= 0),
  add column if not exists tendered_amount numeric(14,2)
    check (tendered_amount is null or tendered_amount >= 0);

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
        if exists(select 1 from jsonb_object_keys(v_settings) k where k not in (
            'doc_footer','offline_lease_hours','auto_logout_minutes','pin_lock_minutes',
            'allow_access_pending','grace_days','reception_see_all_payments','scan_sound',
            'scan_vibrate','entry_duplicate_seconds','qr_defaults',
            'badge_theme','badge_qr_style','badge_positions',
            'biometric_mode','biometric_enabled',
            'door_terminal_ip','door_terminal_port','door_terminal_enabled',
            'temporary_pin_duration_hours','member_language','exchange_rate_htg')) then
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        if v_settings ? 'exchange_rate_htg' and (
             jsonb_typeof(v_settings->'exchange_rate_htg') is distinct from 'number'
             or (v_settings->>'exchange_rate_htg')::numeric not between 0 and 100000) then
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

create or replace function public.enqueue_payment_receipt(
  p_payment uuid,
  p_receipt_path text
) returns text language plpgsql security definer set search_path = '' as $$
declare
  v_gym uuid := public.current_gym_id();
  v_pay public.payments; v_member public.members; v_sub public.subscriptions;
  v_plan public.plans; v_rows int; v_lang text;
begin
  if v_gym is null
     or coalesce(public.current_role(), '') not in ('owner','supervisor','reception','manager') then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  select * into strict v_pay from public.payments
    where id = p_payment and gym_id = v_gym;
  if v_pay.deleted_at is not null or v_pay.voided_at is not null
     or p_receipt_path is null
     or p_receipt_path !~ ('^' || v_gym::text || '/receipts/[0-9a-fA-F-]{36}\.pdf$') then
    raise exception 'invalid_record' using errcode = '22023';
  end if;
  if not exists (select 1 from storage.objects
      where bucket_id = 'receipts' and name = p_receipt_path) then
    raise exception 'invalid_receipt' using errcode = '22023';
  end if;
  select * into strict v_member from public.members
    where id = v_pay.member_id and gym_id = v_gym and deleted_at is null;
  if coalesce(v_member.email, '') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return 'no_email';
  end if;
  if v_pay.subscription_id is not null then
    select * into v_sub from public.subscriptions where id = v_pay.subscription_id;
    select * into v_plan from public.plans where id = v_sub.plan_id and gym_id = v_gym;
  end if;
  select coalesce(nullif(settings->>'member_language', ''), 'fr')
    into v_lang from public.gyms where id = v_gym;
  insert into public.email_outbox(gym_id, event_key, kind, recipient, payload)
  values (v_gym, 'payment_receipt:' || v_pay.id, 'payment_receipt', lower(trim(v_member.email)),
    public.gym_email_branding(v_gym) || jsonb_build_object(
      'name', trim(v_member.first_name || ' ' || v_member.last_name),
      'member_number', v_member.member_number,
      'receipt_no', upper(substr(replace(v_pay.id::text, '-', ''), 1, 8)),
      'receipt_path', p_receipt_path,
      'amount', v_pay.amount, 'currency', v_pay.currency,
      'paid_currency', coalesce(v_pay.paid_currency, v_pay.currency),
      'paid_amount', v_pay.paid_amount, 'exchange_rate', v_pay.exchange_rate,
      'received_amount', coalesce(v_pay.received_amount, v_pay.amount),
      'credit_amount', v_pay.credit_amount, 'credit_used', v_pay.credit_used,
      'credit_balance', v_member.credit_balance,
      'method', v_pay.method, 'paid_at', to_char(v_pay.paid_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI"Z"'),
      'plan_name', coalesce(v_plan.name, 'Abonnement'),
      'start_date', v_sub.start_date, 'end_date', v_sub.end_date,
      'language', case when v_lang in ('ht','en','fr') then v_lang else 'fr' end))
  on conflict (event_key) do nothing;
  get diagnostics v_rows = row_count;
  return case when v_rows > 0 then 'queued' else 'already_queued' end;
end $$;
revoke all on function public.enqueue_payment_receipt(uuid, text) from public, anon;
grant execute on function public.enqueue_payment_receipt(uuid, text) to authenticated;

commit;
