-- =============================================================
-- 19_one_time_payment_offers.sql — Peman an 1 sèl fwa (One-Time Turnkey Payment)
-- -------------------------------------------------------------
-- Chanjman :
-- 1. Modifye kontrent 'billing_period' sou public.platform_offers pou aksepte
--    'one_time' (peman inik / a vi) anplis de 'annual' ak 'monthly'.
-- 2. Mete ajou 4 plan ofisyèl yo (Basic, Medium, Pro, Enterprise) pou yo vin
--    'one_time' (pa gen renouvèlman anyèl oswa chak mwa).
-- 3. Toujou kenbe tout chwa yo (4 plan selon kantite manm) ak opsyon peman an
--    3 tranch pou fasilite kliyan an.
-- 4. Mete ajou 'platform_register_payment' ak 'review_payment_declaration' pou
--    yon plan 'one_time' pa janm ekspire (expires_at = null / a vi).
-- =============================================================

begin;

-- -------------------------------------------------------------
-- 1. Relache kontrent billing_period pou pèmèt 'one_time'
-- -------------------------------------------------------------
alter table public.platform_offers
  drop constraint if exists platform_offers_billing_period_check;

alter table public.platform_offers
  add constraint platform_offers_billing_period_check
  check (billing_period in ('one_time', 'annual', 'monthly', 'lifetime', 'unique'));

-- -------------------------------------------------------------
-- 2. Mete ajou 4 Plan Ofisyèl yo an Peman Inik (One-Time)
--    Tout plan yo enkli : Kit Pòt FSTW F30 + Enstalasyon pa ekip teknik
-- -------------------------------------------------------------
insert into public.platform_offers (
  id, name, description, billing_period, price, currency, config, active
)
values
  (
    'plan_basic',
    'PLAN 1 : DÉMARRAGE (Porte biométrique)',
    'Paiement unique pour les petites salles jusqu''à 150 membres, contrôle d''accès biométrique de porte inclus.',
    'one_time',
    950.00,
    'USD',
    jsonb_build_object(
      'billing_type', 'one_time',
      'max_members', 150,
      'overage_member_fee', 2.0,
      'badge_quota', 0,
      'includes_tablet', false,
      'tablet_count', 0,
      'tablet_optional_price', 180.0,
      'biometric_supported', true,
      'includes_door_access', true,
      'door_hardware_kit', 'Terminal FSTW F30 TCP/IP + Lecteur USB DigitalPersona 4500 + Ventouse 280kg + Bras LZ + Bouton sortie + Alimentation sécurisée',
      'installation_included', true,
      'installments_allowed', true,
      'installment_1_amount', 550.0,
      'installment_2_amount', 200.0,
      'installment_3_amount', 200.0,
      'features', jsonb_build_array(
        'Paiement unique (achat définitif — aucun renouvellement)',
        'Jusqu''à 150 membres actifs',
        'Dépassement : +2,00 USD / membre supplémentaire',
        '✅ Système de contrôle d''accès biométrique inclus',
        '✅ Lecteur d''empreintes USB inclus',
        '🛠️ Installation complète sur place par une équipe technique',
        '📱 Tablette Android d''accueil : sur commande (optionnelle, +180 USD)',
        '🎟️ Badges physiques QR en option (accès possible par empreinte seule)',
        '💳 Paiement en 3 fois possible : 550 USD d''acompte + 200 USD + 200 USD',
        'Code PIN temporaire pour les pass journée',
        'Support technique et mises à jour inclus'
      )
    ),
    true
  ),
  (
    'plan_medium',
    'PLAN 2 : CROISSANCE (Porte biométrique)',
    'Paiement unique pour les salles jusqu''à 1 000 membres, avec rapports financiers et reçus.',
    'one_time',
    1450.00,
    'USD',
    jsonb_build_object(
      'billing_type', 'one_time',
      'max_members', 1000,
      'overage_member_fee', 2.5,
      'badge_quota', 0,
      'includes_tablet', false,
      'tablet_count', 0,
      'tablet_optional_price', 150.0,
      'biometric_supported', true,
      'includes_door_access', true,
      'door_hardware_kit', 'Terminal FSTW F30 TCP/IP + Lecteur USB DigitalPersona 4500 + Ventouse 280kg + Bras LZ + Bouton sortie + Alimentation sécurisée',
      'installation_included', false,
      'installments_allowed', true,
      'installment_1_amount', 850.0,
      'installment_2_amount', 300.0,
      'installment_3_amount', 300.0,
      'features', jsonb_build_array(
        'Paiement unique (achat définitif — aucun renouvellement)',
        'Jusqu''à 1 000 membres actifs',
        'Dépassement : +2,50 USD / membre supplémentaire',
        '✅ Système de contrôle d''accès biométrique inclus',
        '✅ Lecteur d''empreintes USB inclus',
        '🛠️ Installation de la porte par une équipe technique : sur commande (à la charge du client)',
        '📱 Tablette Android d''accueil : sur commande (optionnelle, +150 USD)',
        '🎟️ Badges physiques QR en option (accès possible par empreinte seule)',
        '💳 Paiement en 3 fois possible : 850 USD d''acompte + 300 USD + 300 USD',
        'Code PIN temporaire pour les pass journée',
        'Gestion des paiements, rapports financiers avancés et reçus',
        'Support prioritaire'
      )
    ),
    true
  ),
  (
    'plan_pro',
    'PLAN 3 : PROFESSIONNEL (Expansion)',
    'Solution avancée pour les salles jusqu''à 1 000 membres, tablette et badges offerts.',
    'one_time',
    2200.00,
    'USD',
    jsonb_build_object(
      'billing_type', 'one_time',
      'max_members', 1000,
      'overage_member_fee', 2.0,
      'badge_quota', 200,
      'includes_tablet', true,
      'tablet_count', 1,
      'biometric_supported', true,
      'includes_door_access', true,
      'door_hardware_kit', 'Terminal FSTW F30 TCP/IP + Lecteur USB DigitalPersona 4500 + Ventouse 280kg + Bras LZ + Bouton sortie + Alimentation sécurisée',
      'installation_included', true,
      'installments_allowed', true,
      'installment_1_amount', 1300.0,
      'installment_2_amount', 450.0,
      'installment_3_amount', 450.0,
      'features', jsonb_build_array(
        'Paiement unique (achat définitif — aucun renouvellement)',
        'Jusqu''à 1 000 membres actifs',
        'Dépassement : +2,00 USD / membre supplémentaire',
        '✅ Système de contrôle d''accès biométrique inclus',
        '✅ Lecteur d''empreintes USB inclus',
        '📱 1 tablette Android OFFERTE pour l''accueil',
        '🎟️ 200 badges physiques QR offerts (optionnels)',
        '🛠️ Installation complète sur place par une équipe technique',
        '💳 Paiement en 3 fois possible : 1 300 USD d''acompte + 450 USD + 450 USD',
        'Support prioritaire 24/7'
      )
    ),
    true
  ),
  (
    'plan_enterprise',
    'PLAN 4 : ENTREPRISE (Performance illimitée)',
    'Accompagnement complet, membres illimités, accès API et responsable dédié.',
    'one_time',
    3200.00,
    'USD',
    jsonb_build_object(
      'billing_type', 'one_time',
      'max_members', 0,
      'overage_member_fee', 0.0,
      'badge_quota', 500,
      'includes_tablet', true,
      'tablet_count', 1,
      'biometric_supported', true,
      'includes_door_access', true,
      'door_hardware_kit', 'Terminal FSTW F30 TCP/IP + Lecteur USB DigitalPersona 4500 + Ventouse 280kg + Bras LZ + Bouton sortie + Alimentation sécurisée',
      'installation_included', true,
      'installments_allowed', true,
      'installment_1_amount', 1800.0,
      'installment_2_amount', 700.0,
      'installment_3_amount', 700.0,
      'features', jsonb_build_array(
        'Paiement unique (achat définitif — aucun renouvellement)',
        'MEMBRES ILLIMITÉS (aucune limite) 🚀',
        'Dépassement : 0 USD (tout inclus)',
        '✅ Système de contrôle d''accès biométrique inclus',
        '✅ Lecteur d''empreintes USB inclus',
        '📱 1 tablette Android OFFERTE pour l''accueil',
        '🎟️ 500 badges physiques QR offerts (optionnels)',
        '🛠️ Installation complète sur place par une équipe technique',
        '💳 Paiement en 3 fois possible : 1 800 USD d''acompte + 700 USD + 700 USD',
        'Accès API, rapports avancés et sauvegarde cloud',
        'Équipe technique et responsable de compte dédiés'
      )
    ),
    true
  )
on conflict (id) do update set
  name           = excluded.name,
  description    = excluded.description,
  billing_period = excluded.billing_period,
  price          = excluded.price,
  currency       = excluded.currency,
  config         = excluded.config,
  active         = true;

-- -------------------------------------------------------------
-- 3. Mete ajou fonksyon platform_register_payment pou jere 'one_time'
--    Pou yon kontra 'one_time', li pa janm ekspire (expires_at = null).
-- -------------------------------------------------------------
create or replace function public.platform_register_payment(
  p_gym uuid,
  p_offer text,
  p_method text,
  p_amount numeric,
  p_currency text default 'USD',
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
  v_expires timestamptz;
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

  -- Dat ekspirasyon :
  -- Si se 'one_time', 'lifetime', 'unique' : pa gen ekspirasyon (null)
  -- Si se 'annual' : 1 ane
  -- Sinon : 1 mwa
  if v_offer.billing_period in ('one_time', 'lifetime', 'unique') then
    v_expires := null;
  elsif v_offer.billing_period = 'annual' then
    v_expires := clock_timestamp() + interval '1 year';
  else
    v_expires := clock_timestamp() + interval '1 month';
  end if;

  insert into public.gym_contracts (
    gym_id, offer_id, status, starts_at, expires_at, price_snapshot
  ) values (
    p_gym, p_offer,
    case when p_paid then 'active' else 'trial' end,
    clock_timestamp(),
    case when p_paid then v_expires else null end,
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
-- 4. Mete ajou review_payment_declaration pou jere 'one_time'
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
  v_period interval;
begin
  if not public.is_super_admin() then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  select * into strict v_decl from public.payment_declarations
  where id = p_declaration and status = 'pending';

  update public.payment_declarations
  set status = case when p_approve then 'approved' else 'rejected' end,
      reviewed_by = auth.uid(),
      reviewed_at = clock_timestamp(),
      note = coalesce(p_note, note)
  where id = p_declaration;

  if p_approve then
    if v_decl.invoice_id is not null and exists (
      select 1 from public.platform_invoices where id = v_decl.invoice_id and type = 'badge_purchase'
    ) then
      update public.platform_invoices
      set status = 'paid', updated_at = clock_timestamp()
      where id = v_decl.invoice_id;
    else
      update public.gyms
      set status = 'active', suspension_reason = null, updated_at = clock_timestamp()
      where id = v_decl.gym_id;

      select * into v_contract from public.gym_contracts
      where gym_id = v_decl.gym_id order by created_at desc limit 1;

      if v_contract.id is not null then
        select * into v_offer from public.platform_offers where id = v_contract.offer_id;
        
        update public.gym_contracts
        set status = 'active',
            expires_at = case 
              when v_offer.billing_period in ('one_time', 'lifetime', 'unique') then null
              when v_offer.billing_period = 'annual' then greatest(coalesce(expires_at, clock_timestamp()), clock_timestamp()) + interval '1 year'
              else greatest(coalesce(expires_at, clock_timestamp()), clock_timestamp()) + interval '1 month'
            end,
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

  return jsonb_build_object('success', true, 'approved', p_approve);
end;
$$;

commit;
