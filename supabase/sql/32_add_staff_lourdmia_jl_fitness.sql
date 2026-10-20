-- ==============================================================================
-- 32_add_staff_lourdmia_jl_fitness.sql
-- Ajoute Lourdmia Coq nan pèsonèl JL FITNESS avèk tout aksè li yo
-- ==============================================================================
-- Sal : JL FITNESS (ID: 6ed6093d-557d-4bb9-b3ba-f55fedcf65b3)
-- Manm : Lourdmia Coq
-- Imèl : coqlourdemia@gmail.com
-- Modpas : lourdemia44@@
-- Telefòn : +509 44537955
-- Wòl : Superviseur
-- Aksè :
--   - Ajouter des membres (can_add_members)
--   - Caisse et encaissements (can_cashier)
--   - Voir les paiements (can_view_payments)
--   - Voir et envoyer les reçus (can_view_receipts)
--   - Voir les rapports (can_view_reports)
--   - Gérer les formules et tarifs (can_manage_plans)
--   - Contrôle d'accès et scan (can_access_control)
-- ==============================================================================

create extension if not exists pgcrypto with schema extensions;

do $$
declare
    v_gym_id      uuid := '6ed6093d-557d-4bb9-b3ba-f55fedcf65b3';
    v_user_id     uuid;
    v_email       text := lower(trim('coqlourdemia@gmail.com'));
    v_password    text := 'lourdemia44@@';
    v_full_name   text := 'Lourdmia Coq';
    v_phone       text := '+509 44537955';
    v_permissions jsonb;
begin
    -- 1. Defini tout pèmisyon li yo nan JSON
    v_permissions := jsonb_build_object(
        'job_title', 'superviseur',
        'can_add_members', true,
        'can_cashier', true,
        'can_view_payments', true,
        'can_view_receipts', true,
        'can_view_reports', true,
        'can_manage_plans', true,
        'can_access_control', true
    );

    -- 2. Tcheke si itilizatè auth la deja egziste
    select id into v_user_id
    from auth.users
    where lower(email) = v_email
    limit 1;

    if v_user_id is null then
        v_user_id := gen_random_uuid();

        -- Kreye itilizatè a nan auth.users
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

        -- Kreye antre idantite nan auth.identities
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
        -- Si li te deja la, mete ajou modpas la epi asire imèl la konfime
        update auth.users
        set encrypted_password = extensions.crypt(v_password, extensions.gen_salt('bf')),
            email_confirmed_at = coalesce(email_confirmed_at, now()),
            raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('full_name', v_full_name),
            updated_at = now()
        where id = v_user_id;
    end if;

    -- 3. Mete ajou oswa insere Lourdmia Coq nan public.staff pou JL FITNESS
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
        'supervisor',
        v_full_name,
        v_phone,
        true,
        v_permissions,
        now(),
        now()
    )
    on conflict (user_id) do update
    set gym_id = v_gym_id,
        role = 'supervisor',
        full_name = excluded.full_name,
        phone = excluded.phone,
        active = true,
        permissions = excluded.permissions,
        deleted_at = null,
        updated_at = now();

    raise notice '=======================================================';
    raise notice 'Lourdmia Coq ajoute ak siksè nan JL FITNESS!';
    raise notice 'ID Itilizatè: %', v_user_id;
    raise notice 'Imèl: %', v_email;
    raise notice 'Wòl: Superviseur (tout aksè aktive)';
    raise notice '=======================================================';
end $$;
