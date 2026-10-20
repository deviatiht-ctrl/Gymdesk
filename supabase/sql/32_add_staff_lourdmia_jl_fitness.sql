-- ==============================================================================
-- 32_add_staff_lourdmia_jl_fitness.sql
-- Ajoute Lourdmia Coq nan pèsonèl JL FITNESS (Secrétaire & Caissière)
-- ==============================================================================
-- Sal : JL FITNESS (ID: 6ed6093d-557d-4bb9-b3ba-f55fedcf65b3)
-- Manm : Lourdmia Coq
-- Imèl : coqlourdemia@gmail.com
-- Modpas : lourdemia44@@
-- Telefòn : +509 44537955
-- Pòs : Secrétaire & Caissière (Role: reception)
-- Aksè :
--   - Ajouter des membres (can_add_members = true)
--   - Caisse et encaissements (can_cashier = true)
--   - Voir les paiements (can_view_payments = true)
--   - Voir et envoyer les reçus (can_view_receipts = true)
--   - Voir les rapports (can_view_reports = true)
--   - Gérer les formules et tarifs (can_manage_plans = true)
--   - Contrôle d'accès et scan (can_access_control = true)
-- ==============================================================================

create extension if not exists pgcrypto with schema extensions;

do $$
declare
    v_gym_id      uuid := '6ed6093d-557d-4bb9-b3ba-f55fedcf65b3'; -- ID JL FITNESS
    v_user_id     uuid;
    v_email       text := lower(trim('coqlourdemia@gmail.com'));
    v_password    text := 'lourdemia44@@';
    v_full_name   text := 'Lourdmia Coq';
    v_phone       text := '+509 44537955';
    v_permissions jsonb;
begin
    -- 1. Konfigirasyon pèmisyon yo (Secrétaire ak dwa kès, manm, resi, rapò, tarif, scan)
    v_permissions := jsonb_build_object(
        'job_title', 'secretaire',
        'can_add_members', true,       -- Ajouter des membres
        'can_cashier', true,           -- Caisse et encaisser
        'can_view_payments', true,     -- Voir les paiements
        'can_view_receipts', true,     -- Voir et envoyer les reçus
        'can_view_reports', true,      -- Voir les rapports
        'can_manage_plans', true,      -- Gérer les formules et tarifs
        'can_access_control', true     -- Contrôle d'accès et scan
    );

    -- 2. Tcheke si itilizatè a egziste deja nan auth.users
    select id into v_user_id
    from auth.users
    where lower(email) = v_email
    limit 1;

    if v_user_id is null then
        v_user_id := gen_random_uuid();

        -- Kreye itilizatè a nan sistèm otantifikasyon auth.users
        insert into auth.users (
            instance_id,
            id,
            aud,
            role,
            email,
            encrypted_password,
            email_confirmed_at,
            raw_app_meta_data,
            raw_user_meta_data,
            created_at,
            updated_at,
            confirmation_token,
            email_change,
            email_change_token_new,
            recovery_token
        ) values (
            '00000000-0000-0000-0000-000000000000',
            v_user_id,
            'authenticated',
            'authenticated',
            v_email,
            extensions.crypt(v_password, extensions.gen_salt('bf')),
            now(),
            '{"provider": "email", "providers": ["email"]}'::jsonb,
            jsonb_build_object('full_name', v_full_name),
            now(),
            now(),
            '',
            '',
            '',
            ''
        );

        -- Kreye idantite pou login GoTrue
        if to_regclass('auth.identities') is not null then
            begin
                insert into auth.identities (
                    id,
                    user_id,
                    identity_data,
                    provider,
                    provider_id,
                    last_sign_in_at,
                    created_at,
                    updated_at
                ) values (
                    v_user_id::text,
                    v_user_id,
                    jsonb_build_object('sub', v_user_id::text, 'email', v_email),
                    'email',
                    v_user_id::text,
                    now(),
                    now(),
                    now()
                );
            exception when others then
                null;
            end;
        end if;
    else
        -- Si kont lan te deja la, mete ajou modpas la epi konfime imèl la
        update auth.users
        set encrypted_password = extensions.crypt(v_password, extensions.gen_salt('bf')),
            email_confirmed_at = coalesce(email_confirmed_at, now()),
            raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('full_name', v_full_name),
            updated_at = now()
        where id = v_user_id;
    end if;

    -- 3. Ajoute oswa mete ajou Lourdmia Coq kòm Secrétaire / Caissière (role: reception)
    insert into public.staff (
        id,
        user_id,
        gym_id,
        role,
        full_name,
        phone,
        active,
        permissions,
        created_at,
        updated_at
    ) values (
        gen_random_uuid(),
        v_user_id,
        v_gym_id,
        'reception',
        v_full_name,
        v_phone,
        true,
        v_permissions,
        now(),
        now()
    )
    on conflict (user_id) do update
    set gym_id = v_gym_id,
        role = 'reception',
        full_name = excluded.full_name,
        phone = excluded.phone,
        active = true,
        permissions = excluded.permissions,
        deleted_at = null,
        updated_at = now();

    raise notice '=======================================================';
    raise notice 'Lourdmia Coq ajoute ak siksè nan JL FITNESS!';
    raise notice 'ID Itilizatè : %', v_user_id;
    raise notice 'Imèl : %', v_email;
    raise notice 'Pòs : Secrétaire & Caissière (role: reception)';
    raise notice 'Aksè : Manm, Kès, Peman, Resi, Rapò, Fòmil, Kontwòl aksè';
    raise notice '=======================================================';
end $$;
