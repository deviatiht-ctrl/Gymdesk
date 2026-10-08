-- =============================================================
-- 06_seed.sql — GymDesk (ENVIRONNEMENT DE TEST UNIQUEMENT)
-- Crée une salle de démonstration, ses plans et quelques membres.
-- Ne pas exécuter en production.
--
-- Le compte owner de la salle de démo est créé ici pour
-- laurorejeanclarens9@gmail.com : il exige une ligne auth.users
-- réelle (Authentication → Users → Add user) sinon le script
-- échoue proprement avec les instructions. Les comptes
-- supervisor/reception se créent depuis l'app, comme en production.
-- =============================================================

do $$
declare
    v_gym   uuid;
    v_owner uuid;
    v_plan_month uuid;
    v_plan_trim  uuid;
    v_plan_year  uuid;
    v_plan_day   uuid;
    v_m1 uuid; v_m2 uuid; v_m3 uuid;
begin
    -- ---------------------------------------------------------
    -- Salle de démonstration
    -- ---------------------------------------------------------
    insert into public.gyms (id, code, name, accent_color, address, phone,
                             email, timezone, currency, settings)
    values (
        'a0000000-0000-4000-8000-000000000001',
        'PWR',
        'PowerGym Delmas',
        '#1F6F4A',
        'Delmas 31, Port-au-Prince',
        '+509 3700 0000',
        'contact@powergym.ht',
        'America/Port-au-Prince',
        'HTG',
        '{"grace_days": 0, "allow_access_pending": false,
          "reception_see_all_payments": false,
          "scan_sound": true, "scan_vibrate": true,
          "doc_footer": "Merci de votre visite — PowerGym Delmas"}'::jsonb
    )
    on conflict (id) do nothing
    returning id into v_gym;

    if v_gym is null then
        select id into v_gym from public.gyms
         where id = 'a0000000-0000-4000-8000-000000000001';
    end if;

    -- ---------------------------------------------------------
    -- Propriétaire de la salle de démo
    -- Le compte doit exister : Authentication → Users → Add user
    -- ---------------------------------------------------------
    select u.id into v_owner
      from auth.users u
     where lower(u.email) = 'laurorejeanclarens9@gmail.com'
     limit 1;

    if v_owner is null then
        raise exception
            'Aucun utilisateur laurorejeanclarens9@gmail.com dans auth.users. '
            'Créez le compte via Authentication → Users → Add user, '
            'puis réexécutez ce seed.';
    end if;

    insert into public.staff (id, user_id, gym_id, role, full_name, active)
    values (gen_random_uuid(), v_owner, v_gym, 'owner',
            'Laurore Jean-Clarens', true)
    on conflict (user_id) do nothing;

    -- ---------------------------------------------------------
    -- Plans
    -- ---------------------------------------------------------
    insert into public.plans (id, gym_id, name, duration_days, price,
                              currency, active, sort_order)
    values
        ('b0000000-0000-4000-8000-000000000001', v_gym,
         'Séance',      1,  500,  'HTG', true, 1),
        ('b0000000-0000-4000-8000-000000000002', v_gym,
         'Mensuel',    30,  2500, 'HTG', true, 2),
        ('b0000000-0000-4000-8000-000000000003', v_gym,
         'Trimestriel',90,  6500, 'HTG', true, 3),
        ('b0000000-0000-4000-8000-000000000004', v_gym,
         'Annuel',    365, 22000, 'HTG', true, 4)
    on conflict (id) do nothing;

    v_plan_day   := 'b0000000-0000-4000-8000-000000000001';
    v_plan_month := 'b0000000-0000-4000-8000-000000000002';
    v_plan_trim  := 'b0000000-0000-4000-8000-000000000003';
    v_plan_year  := 'b0000000-0000-4000-8000-000000000004';

    -- ---------------------------------------------------------
    -- Membres de démo (numéros réservés dans gym_counters)
    -- qr_token : valeurs de test — en production ils sont générés
    -- par gen_qr_token() / côté client.
    -- ---------------------------------------------------------
    update public.gym_counters set member_seq = greatest(member_seq, 3)
     where gym_id = v_gym;

    v_m1 := 'c0000000-0000-4000-8000-000000000001';
    v_m2 := 'c0000000-0000-4000-8000-000000000002';
    v_m3 := 'c0000000-0000-4000-8000-000000000003';

    insert into public.members
        (id, gym_id, member_number, qr_token, first_name, last_name,
         sex, birth_date, phone, status)
    values
        (v_m1, v_gym, 'PWR-000001', 'demo-token-00000000000000000001',
         'James',  'Derival', 'male',   '1992-04-17', '+509 3410 0001', 'active'),
        (v_m2, v_gym, 'PWR-000002', 'demo-token-00000000000000000002',
         'Woodna', 'Pierre',  'female', '1998-11-02', '+509 3410 0002', 'active'),
        (v_m3, v_gym, 'PWR-000003', 'demo-token-00000000000000000003',
         'Marc',   'Benjamin','male',   '1985-07-30', '+509 3410 0003', 'active')
    on conflict (id) do nothing;

    -- ---------------------------------------------------------
    -- Abonnements :
    --   PWR-000001 : mensuel actif
    --   PWR-000002 : expiré hier (test refus)
    --   PWR-000003 : sans abonnement (test refus)
    -- ---------------------------------------------------------
    insert into public.subscriptions
        (id, gym_id, member_id, plan_id, start_date, end_date, price, status)
    values
        ('d0000000-0000-4000-8000-000000000001', v_gym, v_m1, v_plan_month,
         ((now() at time zone 'America/Port-au-Prince')::date - 10),
         ((now() at time zone 'America/Port-au-Prince')::date + 20),
         2500, 'active'),
        ('d0000000-0000-4000-8000-000000000002', v_gym, v_m2, v_plan_month,
         ((now() at time zone 'America/Port-au-Prince')::date - 31),
         ((now() at time zone 'America/Port-au-Prince')::date - 1),
         2500, 'expired')
    on conflict (id) do nothing;

    -- paiement correspondant à l'abonnement actif
    insert into public.payments
        (id, gym_id, member_id, subscription_id, amount, currency,
         method, paid_at)
    values
        ('e0000000-0000-4000-8000-000000000001', v_gym, v_m1,
         'd0000000-0000-4000-8000-000000000001',
         2500, 'HTG', 'cash',
         ((now() at time zone 'America/Port-au-Prince')::date - 10))
    on conflict (id) do nothing;

    -- ---------------------------------------------------------
    -- Contrat actif pour PowerGym Delmas : Plan 100+ membres (badge_quota: 100)
    -- ---------------------------------------------------------
    if to_regclass('public.gym_contracts') is not null then
        insert into public.gym_contracts (
            id, gym_id, offer_id, status, starts_at, expires_at,
            price_snapshot
        )
        values (
            'f0000000-0000-4000-8000-000000000001',
            v_gym,
            'per_member',
            'active',
            now() - interval '30 days',
            now() + interval '335 days',
            jsonb_build_object(
                'offer_id', 'per_member',
                'name', 'Plan 100+ Membres',
                'currency', 'USD',
                'billing_cycle', 'monthly',
                'auto_renew', true,
                'config', jsonb_build_object(
                    'badge_quota', 100,
                    'max_members', 150
                )
            )
        )
        on conflict (id) do update
            set price_snapshot = excluded.price_snapshot,
                status = 'active',
                expires_at = excluded.expires_at;
    end if;

    -- ---------------------------------------------------------
    -- V2 : si la migration V2 (08_v2_migration.sql) est déjà
    -- appliquée, créer le lot complet de 100 badges :
    --   - 3 badges liés aux membres démo (PWR-000001..3)
    --   - 97 badges disponibles vierges (4..100)
    -- ---------------------------------------------------------
    if to_regclass('public.badges') is not null then
        declare
            v_batch uuid := gen_random_uuid();
            r record;
            v_num int;
            v_badge uuid;
        begin
            insert into public.badge_batches
                (id, gym_id, label, range_from, range_to, quantity, source)
            values (v_batch, v_gym, 'Lot Initial (100 Cartes)', 1, 100, 100, 'plan_allotment')
            on conflict do nothing;

            -- 1. Lier les 3 membres démo existants aux cartes 1, 2, 3
            for r in select * from public.members
                      where gym_id = v_gym
                      order by created_at asc
            loop
                v_badge := gen_random_uuid();
                v_num := coalesce(substring(r.member_number from '([0-9]+)$')::int, 1);
                insert into public.badges
                    (id, gym_id, batch_id, badge_number, qr_token,
                     status, member_id, bound_at)
                values (v_badge, v_gym, v_batch, v_num, r.qr_token,
                        'bound', r.id, r.created_at)
                on conflict do nothing
                returning id into v_badge;
                if v_badge is null then
                    select id into v_badge from public.badges
                    where gym_id = v_gym
                      and (qr_token = r.qr_token or badge_number = v_num)
                    limit 1;
                    update public.badges
                        set member_id = r.id, status = 'bound'
                    where id = v_badge;
                end if;

                update public.members set badge_id = v_badge where id = r.id;

                if exists (
                    select 1 from information_schema.columns
                    where table_schema = 'public'
                      and table_name = 'member_pins'
                      and column_name = 'id'
                ) then
                    insert into public.member_pins
                        (id, member_id, gym_id, pin_hash, salt, algo,
                         iterations, reset_required)
                    values (r.id, r.id, v_gym, 'UNSET', 'UNSET',
                            'pbkdf2_sha256', 210000, true)
                    on conflict (member_id) do nothing;
                else
                    insert into public.member_pins
                        (member_id, gym_id, pin_hash, salt, algo,
                         iterations, reset_required)
                    values (r.id, v_gym, 'UNSET', 'UNSET',
                            'pbkdf2_sha256', 210000, true)
                    on conflict (member_id) do nothing;
                end if;

                insert into public.badge_history
                    (id, gym_id, badge_id, member_id, event, reason)
                values (gen_random_uuid(), v_gym, v_badge, r.id,
                        'bound', 'Seed démo')
                on conflict do nothing;
            end loop;

            -- 2. Générer les 97 cartes disponibles restantes (4 à 100)
            for v_num in 4..100 loop
                v_badge := gen_random_uuid();
                insert into public.badges
                    (id, gym_id, batch_id, badge_number, qr_token,
                     status, member_id, bound_at)
                values (v_badge, v_gym, v_batch, v_num,
                        'demo-token-' || lpad(v_num::text, 20, '0'),
                        'unassigned', null, null)
                on conflict do nothing;
            end loop;
        end;
    end if;

    raise notice 'Seed OK : salle PWR (%), owner %, 4 plans, 3 membres de démo',
        v_gym, v_owner;
end $$;
