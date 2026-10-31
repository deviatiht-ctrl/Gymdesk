-- ============================================================================
-- 36 — Admin : détail d'une salle + noms d'offres en français (idempotent).
--  * platform_gym_detail(p_gym) : fiche complète super admin — identité,
--    statistiques (membres, abonnements, paiements, présences, badges,
--    comptes portail, demandes en ligne), contrat/offre courant et
--    propriétaire. Réservé is_super_admin().
--  * platform_update_gym(p_gym, p_payload) : édition super admin des champs
--    d'identité (nom, code unique, couleur, fuseau, devise, contacts, logo)
--    sans passer par sync_branding.
--  * Noms/descriptions/features des 4 plans officiels et des offres héritées
--    corrigés en français (mojibake 'PÃ²t', 'IllimitÃ©', 'DÃ©marrage'… corrigé).
-- ============================================================================
begin;

-- -----------------------------------------------------------------------------
-- 1. Détail complet d'une salle (super admin)
-- -----------------------------------------------------------------------------
create or replace function public.platform_gym_detail(p_gym uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_gym public.gyms;
begin
  if not public.is_super_admin() then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  select * into strict v_gym from public.gyms where id = p_gym;
  return jsonb_build_object(
    'gym', to_jsonb(v_gym),
    'stats', jsonb_build_object(
      'members', (select count(*) from public.members m
                  where m.gym_id = v_gym.id and m.deleted_at is null),
      'members_active', (select count(distinct s.member_id) from public.subscriptions s
                  where s.gym_id = v_gym.id and s.deleted_at is null
                    and s.status = 'active' and s.end_date >= current_date),
      'staff', (select count(*) from public.staff s
                where s.gym_id = v_gym.id and s.active and s.deleted_at is null),
      'plans', (select count(*) from public.plans p
                where p.gym_id = v_gym.id and p.deleted_at is null),
      'subscriptions_active', (select count(*) from public.subscriptions s
                where s.gym_id = v_gym.id and s.deleted_at is null
                  and s.status = 'active' and s.end_date >= current_date),
      'payments_total', (select coalesce(sum(p.amount), 0) from public.payments p
                where p.gym_id = v_gym.id and p.deleted_at is null and p.voided_at is null),
      'payments_count', (select count(*) from public.payments p
                where p.gym_id = v_gym.id and p.deleted_at is null and p.voided_at is null),
      'entries_today', (select count(*) from public.attendance a
                where a.gym_id = v_gym.id and a.result = 'granted'
                  and a.scanned_at >= date_trunc('day', clock_timestamp())),
      'badges', (select count(*) from public.badges b where b.gym_id = v_gym.id),
      'badges_used', (select count(*) from public.badges b
                where b.gym_id = v_gym.id and b.member_id is not null),
      'member_accounts', (select count(*) from public.member_accounts ma
                where ma.gym_id = v_gym.id),
      'portal_pending', (select count(*) from public.portal_requests pr
                where pr.gym_id = v_gym.id and pr.status = 'pending')
    ),
    'contract', coalesce((
      select jsonb_build_object(
        'id', c.id, 'status', c.status, 'starts_at', c.starts_at,
        'expires_at', c.expires_at, 'price_snapshot', c.price_snapshot,
        'offer_id', o.id, 'offer_name', o.name, 'offer_price', o.price,
        'offer_currency', o.currency, 'billing_period', o.billing_period
      )
      from public.gym_contracts c
      left join public.platform_offers o on o.id = c.offer_id
      where c.gym_id = v_gym.id
      order by c.created_at desc limit 1
    ), 'null'::jsonb),
    'owner', coalesce((
      select jsonb_build_object(
        'staff_id', s.id, 'full_name', s.full_name, 'phone', s.phone,
        'email', u.email, 'last_sign_in', u.last_sign_in_at, 'created_at', u.created_at
      )
      from public.staff s
      join auth.users u on u.id = s.user_id
      where s.gym_id = v_gym.id and s.role = 'owner' and s.deleted_at is null
      order by s.created_at limit 1
    ), 'null'::jsonb)
  );
end;
$$;
revoke all on function public.platform_gym_detail(uuid) from public, anon;
grant execute on function public.platform_gym_detail(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Édition des informations de la salle par le super admin
-- -----------------------------------------------------------------------------
create or replace function public.platform_update_gym(p_gym uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_gym public.gyms;
begin
  if not public.is_super_admin() then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  select * into strict v_gym from public.gyms where id = p_gym for update;

  if p_payload ? 'code' and upper(trim(p_payload->>'code')) is distinct from v_gym.code then
    if upper(trim(p_payload->>'code')) !~ '^[A-Z0-9]{2,8}$'
      or exists(select 1 from public.gyms g
                where g.code = upper(trim(p_payload->>'code')) and g.id <> v_gym.id) then
      raise exception 'duplicate_code' using errcode = '22023';
    end if;
  end if;
  if char_length(trim(coalesce(p_payload->>'name', v_gym.name))) not between 2 and 120
    or coalesce(p_payload->>'accent_color', v_gym.accent_color) !~ '^#[0-9A-Fa-f]{6}$'
    or coalesce(p_payload->>'currency', v_gym.currency) not in ('HTG','USD')
    or not exists(select 1 from pg_timezone_names z
                  where z.name = coalesce(p_payload->>'timezone', v_gym.timezone))
    or char_length(coalesce(p_payload->>'address', '')) > 500
    or char_length(coalesce(p_payload->>'phone', '')) > 64
    or char_length(coalesce(p_payload->>'email', '')) > 254
    or (coalesce(p_payload->>'email', '') <> ''
        and p_payload->>'email' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then
    raise exception 'invalid_record' using errcode = '22023';
  end if;

  update public.gyms set
    name = trim(coalesce(p_payload->>'name', v_gym.name)),
    code = coalesce(upper(trim(p_payload->>'code')), v_gym.code),
    accent_color = coalesce(p_payload->>'accent_color', v_gym.accent_color),
    timezone = coalesce(p_payload->>'timezone', v_gym.timezone),
    currency = coalesce(p_payload->>'currency', v_gym.currency),
    address = case when p_payload ? 'address' then nullif(trim(p_payload->>'address'), '') else v_gym.address end,
    phone = case when p_payload ? 'phone' then nullif(trim(p_payload->>'phone'), '') else v_gym.phone end,
    email = case when p_payload ? 'email' then nullif(trim(p_payload->>'email'), '') else v_gym.email end,
    updated_at = clock_timestamp()
  where id = v_gym.id
  returning * into v_gym;

  insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id)
  values (gen_random_uuid(), v_gym.id, public.current_staff_id(),
          'platform_gym_updated', 'gyms', v_gym.id);
  return to_jsonb(v_gym);
end;
$$;
revoke all on function public.platform_update_gym(uuid, jsonb) from public, anon;
grant execute on function public.platform_update_gym(uuid, jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Noms d'offres en français (corrige mojibake + termes anglais).
--    Les textes 'features' reflètent exactement la config en production :
--    basic 150 membres / installation incluse / tablette en option,
--    medium 1000 membres / installation sur commande / tablette en option,
--    pro 1000 membres + tablette offerte + 200 badges + installation incluse,
--    enterprise illimité + tablette offerte + 500 badges + installation incluse.
-- -----------------------------------------------------------------------------
update public.platform_offers set
  name = 'PLAN 1 : DÉMARRAGE (Porte biométrique)',
  description = 'Paiement unique pour les petites salles jusqu''à 150 membres, contrôle d''accès biométrique de porte inclus.',
  config = config || jsonb_build_object('features', jsonb_build_array(
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
    'Support technique et mises à jour inclus'))
where id = 'plan_basic';

update public.platform_offers set
  name = 'PLAN 2 : CROISSANCE (Porte biométrique)',
  description = 'Paiement unique pour les salles jusqu''à 1 000 membres, avec rapports financiers et reçus.',
  config = config || jsonb_build_object('features', jsonb_build_array(
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
    'Support prioritaire'))
where id = 'plan_medium';

update public.platform_offers set
  name = 'PLAN 3 : PROFESSIONNEL (Expansion)',
  description = 'Solution avancée pour les salles jusqu''à 1 000 membres, tablette et badges offerts.',
  config = config || jsonb_build_object('features', jsonb_build_array(
    'Paiement unique (achat définitif — aucun renouvellement)',
    'Jusqu''à 1 000 membres actifs',
    'Dépassement : +2,00 USD / membre supplémentaire',
    '✅ Système de contrôle d''accès biométrique inclus',
    '✅ Lecteur d''empreintes USB inclus',
    '📱 1 tablette Android OFFERTE pour l''accueil',
    '🎟️ 200 badges physiques QR offerts (optionnels)',
    '🛠️ Installation complète sur place par une équipe technique',
    '💳 Paiement en 3 fois possible : 1 300 USD d''acompte + 450 USD + 450 USD',
    'Support prioritaire 24/7'))
where id = 'plan_pro';

update public.platform_offers set
  name = 'PLAN 4 : ENTREPRISE (Performance illimitée)',
  description = 'Accompagnement complet, membres illimités, accès API et responsable dédié.',
  config = config || jsonb_build_object('features', jsonb_build_array(
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
    'Équipe technique et responsable de compte dédiés'))
where id = 'plan_enterprise';

-- Offres héritées : corriger le mojibake des noms.
update public.platform_offers set name = 'Par membre actif' where id = 'per_member' and name <> 'Par membre actif';
update public.platform_offers set name = 'Paliers fixes' where id = 'tiered' and name <> 'Paliers fixes';
update public.platform_offers set name = 'Illimité annuel' where id = 'unlimited_annual' and name <> 'Illimité annuel';

commit;
