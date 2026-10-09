-- =============================================================
-- 17_update_platform_offers.sql — GymDesk Platform Offers & Biometric Guard
-- -------------------------------------------------------------
-- 1. Mete ajou katalòg 4 plan ofisyèl yo (platform_offers) :
--    - Plan BASIC (Starter) : Kòmanse ak 250 manm (pri $650 USD/an).
--      San lektè anprent (byometri pa enkli). Tablèt sou kòmand.
--    - Plan MEDIUM (Growth) : 500 manm ($950 USD/an).
--      San lektè anprent. Tablèt sou kòmand.
--    - Plan PRO (Expansion) : 1000 manm ($1,500 USD/an).
--      1 Tablèt Android GRATIS enkli. 300 Badj QR gratis.
--      Modil Byometrik Enkli (Lektè USB sou kòmand, se kliyan ki peye l).
--    - Plan ENTERPRISE (Unlimited) : Manm illimités ($2,500 USD/an).
--      1 SÈL Tablèt Android GRATIS enkli (pa 2 ankò). 500 Badj QR gratis.
--      Modil Byometrik Enkli (Lektè USB sou kòmand, se kliyan ki peye l).
-- 2. Dezaktive ansyen plan yo ('per_member', 'tiered', 'unlimited_annual').
-- 3. Verifikasyon nan sync_branding : Si sal la pa nan yon plan
--    ki gen 'biometric_supported' = true, li pa ka aktive byometri.
-- =============================================================

begin;

-- -------------------------------------------------------------
-- 1. Enskri oswa mete ajou 4 plan ofisyèl yo
-- -------------------------------------------------------------
insert into public.platform_offers (id, name, description, billing_period, price, currency, config, active)
values
  (
    'plan_basic',
    'PLAN 1 : BASIC (Starter)',
    'Idéal pour démarrer avec contrôle par badge QR et PIN.',
    'annual',
    650.00,
    'USD',
    jsonb_build_object(
      'max_members', 250,
      'overage_member_fee', 2.0,
      'badge_quota', 0,
      'includes_tablet', false,
      'tablet_count', 0,
      'tablet_optional_price', 180.0,
      'biometric_supported', false,
      'features', jsonb_build_array(
        'Jiska 250 manb aktif',
        'Depasman : +2.00 USD / manb extra',
        'Aksè Badj QR & Kòd PIN sekirize',
        'Opsyon Tablèt Android : +180 USD (sou kòmand)',
        '❌ Lektè anprent pa enkli (rezève pou plan siperyè)',
        'Sipò teknik & mizajou enkli'
      )
    ),
    true
  ),
  (
    'plan_medium',
    'PLAN 2 : MEDIUM (Growth)',
    'Pour salles en croissance avec suivi rigoureux des paiements.',
    'annual',
    950.00,
    'USD',
    jsonb_build_object(
      'max_members', 500,
      'overage_member_fee', 2.5,
      'badge_quota', 0,
      'includes_tablet', false,
      'tablet_count', 0,
      'tablet_optional_price', 150.0,
      'biometric_supported', false,
      'features', jsonb_build_array(
        'Jiska 500 manb aktif',
        'Depasman : +2.50 USD / manb extra',
        'Aksè Badj QR & Kòd PIN sekirize',
        'Opsyon Tablèt Android : +150 USD (sou kòmand)',
        'Jesyon peman, rapò finansye & resi',
        '❌ Lektè anprent pa enkli (rezève pou plan siperyè)'
      )
    ),
    true
  ),
  (
    'plan_pro',
    'PLAN 3 : PRO (Expansion)',
    'Solution complète avec 1 tablette offerte, 300 badges et support biométrique.',
    'annual',
    1500.00,
    'USD',
    jsonb_build_object(
      'max_members', 1000,
      'overage_member_fee', 2.0,
      'badge_quota', 300,
      'includes_tablet', true,
      'tablet_count', 1,
      'biometric_supported', true,
      'is_hot', true,
      'features', jsonb_build_array(
        'Jiska 1 000 manb aktif',
        'Depasman : +2.00 USD / manb extra',
        '300 Badj fizik QR GRATIS enkli 🪪',
        '1 Tablèt Android GRATIS enkli 📱',
        '✅ Modil Byometrik Anprent dijital Enkli',
        'Lektè USB sou kòmand (kliyan peye l, delè 2-4 semèn)',
        'Sipò priyoritè 24/7'
      )
    ),
    true
  ),
  (
    'plan_enterprise',
    'PLAN 4 : ENTERPRISE (Unlimited)',
    'Accompagnement illimité et haute performance avec 1 tablette et 500 badges.',
    'annual',
    2500.00,
    'USD',
    jsonb_build_object(
      'max_members', 0,
      'overage_member_fee', 0.0,
      'badge_quota', 500,
      'includes_tablet', true,
      'tablet_count', 1,
      'biometric_supported', true,
      'features', jsonb_build_array(
        'MEMBRES ILLIMITÉS (San limit) 🚀',
        'Depasman manb : 0 USD (Tout enkli)',
        '500 Badj fizik QR GRATIS enkli 🪪',
        '1 Tablèt Android GRATIS enkli 📱 (1 sèl tablèt)',
        '✅ Modil Byometrik Anprent dijital Enkli',
        'Lektè USB sou kòmand (kliyan peye l, delè 2-4 semèn)',
        'Aksè API, rapò avanse & backup nwaj',
        'Responsab kont dedye'
      )
    ),
    true
  )
on conflict (id) do update set
  name = excluded.name,
  description = excluded.description,
  billing_period = excluded.billing_period,
  price = excluded.price,
  currency = excluded.currency,
  config = excluded.config,
  active = true;

-- -------------------------------------------------------------
-- 2. Dezaktive ansyen plan yo
-- -------------------------------------------------------------
update public.platform_offers
set active = false
where id in ('per_member', 'tiered', 'unlimited_annual');

-- -------------------------------------------------------------
-- 3. Mete ajou sync_branding pou verifye si plan an otorize byometri
-- -------------------------------------------------------------
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
        -- Whitelist elaji ki gen ladan badj ak biometri
        if exists(select 1 from jsonb_object_keys(v_settings) k where k not in (
            'doc_footer','offline_lease_hours','auto_logout_minutes','pin_lock_minutes',
            'allow_access_pending','grace_days','reception_see_all_payments','scan_sound',
            'scan_vibrate','entry_duplicate_seconds','qr_defaults',
            'badge_theme','badge_qr_style','badge_positions',
            'biometric_mode','biometric_enabled')) then
            raise exception 'invalid_record' using errcode = '22023';
        end if;

        -- Kontwòl Plan : Si sal la vle aktive byometri, verifye si plan li a gen 'biometric_supported' = true
        if coalesce((v_settings->>'biometric_enabled')::boolean, false) then
            declare
                v_biometric_ok boolean := false;
            begin
                select coalesce((o.config->>'biometric_supported')::boolean, false) into v_biometric_ok
                from public.gym_contracts c
                join public.platform_offers o on o.id = c.offer_id
                where c.gym_id = g.id and c.status in ('active', 'trial', 'grace')
                order by c.created_at desc limit 1;

                -- Otorize si se Super Admin oswa si se sal démo a
                if v_biometric_ok is false and not public.is_super_admin()
                   and g.id is distinct from 'a0000000-0000-4000-8000-000000000001'::uuid then
                    raise exception 'biometric_not_included_in_plan' using errcode = '42501';
                end if;
            end;
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

commit;
