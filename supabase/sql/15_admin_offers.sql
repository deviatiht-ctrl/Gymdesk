-- =============================================================
-- 15_admin_offers.sql — Catalogue d'offres admin + caisse
-- -------------------------------------------------------------
-- - current_gym_id() accepte les salles en trial/grace (sinon une
--   salle nouvellement créée ne peut jamais synchroniser).
-- - platform_gym_overview() : contrat courant + nb de membres par
--   salle pour la console super admin.
-- - platform_register_payment() : le super admin enregistre un
--   encaissement (cash/…), crée le contrat lié à l'offre choisie
--   et active la salle — ou crée un contrat d'essai sans paiement.
-- - platform_statistics() compte aussi les entrées 'granted_in'.
-- Idempotent : rejouable sans risque.
-- =============================================================

begin;

-- -------------------------------------------------------------
-- 1. current_gym_id : les salles en trial/grace restent synchronisables
-- -------------------------------------------------------------
create or replace function public.current_gym_id()
returns uuid language sql stable security definer set search_path = '' as $$
    select s.gym_id from public.staff s join public.gyms g on g.id = s.gym_id
    where s.user_id = auth.uid() and s.active and s.deleted_at is null
      and g.status in ('active', 'trial', 'grace') and g.deleted_at is null
$$;

-- -------------------------------------------------------------
-- 2. Vue d'ensemble : dernier contrat + nombre de membres par salle
-- -------------------------------------------------------------
create or replace function public.platform_gym_overview()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not public.is_super_admin() then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(row) from (
      select jsonb_build_object(
        'gym_id', g.id,
        'members', (
          select count(*) from public.members m
          where m.gym_id = g.id and m.deleted_at is null
        ),
        'contract_status', c.status,
        'expires_at', c.expires_at,
        'offer_id', o.id,
        'offer_name', o.name,
        'offer_price', o.price,
        'offer_currency', o.currency,
        'billing_period', o.billing_period
      ) as row
      from public.gyms g
      left join lateral (
        select cc.status, cc.expires_at, cc.offer_id
        from public.gym_contracts cc
        where cc.gym_id = g.id
        order by cc.created_at desc limit 1
      ) c on true
      left join public.platform_offers o on o.id = c.offer_id
      where g.deleted_at is null
      order by g.created_at desc
    ) rows
  ), '[]'::jsonb);
end;
$$;

-- -------------------------------------------------------------
-- 3. Encaissement plateforme par le super admin (cash desk)
--    p_paid = true  : déclaration approuvée + contrat actif +
--                     expiration = now + période de l'offre +
--                     salle réactivée.
--    p_paid = false : contrat en statut 'trial' lié à l'offre,
--                     aucune déclaration de paiement créée.
-- -------------------------------------------------------------
create or replace function public.platform_register_payment(
  p_gym uuid,
  p_offer text,
  p_amount numeric,
  p_currency text default 'USD',
  p_method text default 'cash',
  p_reference text default null,
  p_note text default null,
  p_paid boolean default true
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_gym public.gyms;
  v_offer public.platform_offers;
  v_period interval;
  v_contract uuid;
  v_decl uuid;
begin
  select s.id into v_actor from public.staff s
  where s.user_id = auth.uid() and s.role = 'super_admin'
    and s.active and s.deleted_at is null;
  if v_actor is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  select * into strict v_gym from public.gyms
    where id = p_gym and deleted_at is null;
  select * into strict v_offer from public.platform_offers
    where id = p_offer and active;

  if p_method not in ('moncash', 'natcash', 'bank', 'cash', 'other')
     or p_currency not in ('HTG', 'USD')
     or p_amount is null or p_amount < 0 or p_amount > 10000000
     or (p_paid and p_amount <= 0) then
    raise exception 'invalid_record' using errcode = '22023';
  end if;

  v_period := case v_offer.billing_period
    when 'annual' then interval '1 year'
    else interval '1 month' end;

  -- Nouveau contrat = snapshot de l'offre au moment de la vente.
  -- L'historique est conservé (les fonctions lisent le plus récent).
  insert into public.gym_contracts (
    gym_id, offer_id, status, starts_at, expires_at, price_snapshot
  ) values (
    p_gym, p_offer,
    case when p_paid then 'active' else 'trial' end,
    clock_timestamp(),
    case when p_paid then clock_timestamp() + v_period else null end,
    jsonb_build_object(
      'offer_id', v_offer.id,
      'name', v_offer.name,
      'price', v_offer.price,
      'currency', v_offer.currency,
      'billing_period', v_offer.billing_period,
      'config', v_offer.config
    )
  ) returning id into v_contract;

  if p_paid then
    insert into public.payment_declarations (
      gym_id, method, reference, amount, currency,
      status, reviewed_by, reviewed_at, note, created_by
    ) values (
      p_gym, p_method,
      nullif(left(coalesce(p_reference, ''), 120), ''),
      p_amount, p_currency,
      'approved', auth.uid(), clock_timestamp(),
      nullif(left(coalesce(p_note, ''), 500), ''),
      auth.uid()
    ) returning id into v_decl;

    update public.gyms
    set status = 'active', suspension_reason = null,
        updated_at = clock_timestamp()
    where id = p_gym;
  end if;

  insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id)
  values (
    gen_random_uuid(), p_gym, v_actor,
    case when p_paid then 'platform_payment' else 'platform_contract' end,
    'gym_contracts', v_contract
  );

  return jsonb_build_object(
    'contract_id', v_contract,
    'declaration_id', v_decl
  );
end;
$$;

-- -------------------------------------------------------------
-- 4. Statistiques plateforme : compter aussi les entrées V2
--    ('granted_in'), l'ancien code utilisait 'granted'.
-- -------------------------------------------------------------
create or replace function public.platform_statistics()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
    if not public.is_super_admin() then raise exception 'access_denied' using errcode = '42501'; end if;
    return jsonb_build_object(
      'gyms', (select count(*) from public.gyms where deleted_at is null),
      'active_gyms', (select count(*) from public.gyms where deleted_at is null and status = 'active'),
      'members', (select count(*) from public.members m join public.gyms g on g.id = m.gym_id where m.deleted_at is null and g.deleted_at is null),
      'entries_today', (select count(*) from public.attendance a join public.gyms g on g.id = a.gym_id
        where g.deleted_at is null and a.result in ('granted', 'granted_in')
        and a.scanned_at >= date_trunc('day', now() at time zone g.timezone) at time zone g.timezone
        and a.scanned_at < (date_trunc('day', now() at time zone g.timezone) + interval '1 day') at time zone g.timezone)
    );
end $$;

revoke all on function public.platform_gym_overview() from public, anon;
revoke all on function public.platform_register_payment(uuid, text, numeric, text, text, text, text, boolean) from public, anon;
grant execute on function public.platform_gym_overview() to authenticated;
grant execute on function public.platform_register_payment(uuid, text, numeric, text, text, text, text, boolean) to authenticated;

commit;
