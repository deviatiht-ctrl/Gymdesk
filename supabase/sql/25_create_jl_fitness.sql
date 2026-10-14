-- ==============================================================================
-- 25_create_jl_fitness.sql — Kreyasyon & Konfigirasyon Konplè JL FITNESS
-- ==============================================================================
-- Sal : JL FITNESS (Kòd: JLF)
-- Pwopriyetè : JEAN LESLY (jeanlesly1990@gmail.com)
-- Telefòn : +509 48170828 / 37774354 / 41433933
-- Adrès : Delmas 75, Frangneauville 15, #27
-- Koulè : #FFA726 (Jaune Abricot / Ambre)
-- Deviz : USD ($ Dollars)
-- Plan Platfòm : PLAN 3 : PRO (1 000 manm, anprent dijital & pòt byometrik enkli)
-- Plan Kliyan : Séance $10 USD | Mensuel $40 USD
-- ==============================================================================

do $$
declare
    v_owner_id uuid;
    v_gym_id   uuid;
begin
    -- --------------------------------------------------------------------------
    -- 1. Jwenn itilizatè auth.users pou jeanlesly1990@gmail.com
    -- --------------------------------------------------------------------------
    select id into v_owner_id
    from auth.users
    where lower(email) = 'jeanlesly1990@gmail.com'
    limit 1;

    if v_owner_id is null then
        raise exception 'Itilizatè jeanlesly1990@gmail.com pa jwenn nan auth.users! Tanpri verifye imèl la.';
    end if;

    -- Konfime imèl la epi mete non konplè nan metadata
    update auth.users
    set email_confirmed_at = coalesce(email_confirmed_at, now()),
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('full_name', 'JEAN LESLY')
    where id = v_owner_id;

    -- --------------------------------------------------------------------------
    -- 2. Kreye oswa Mete Ajou Sal la nan public.gyms (Deviz: USD)
    -- --------------------------------------------------------------------------
    select id into v_gym_id
    from public.gyms
    where code = 'JLF'
    limit 1;

    if v_gym_id is null then
        v_gym_id := gen_random_uuid();
        insert into public.gyms (
            id,
            code,
            name,
            accent_color,
            address,
            phone,
            email,
            timezone,
            currency,
            status,
            settings
        ) values (
            v_gym_id,
            'JLF',
            'JL FITNESS',
            '#FFA726',
            'Delmas 75, Frangneauville 15, #27',
            '+509 48170828 / 37774354 / 41433933',
            'jeanlesly1990@gmail.com',
            'America/Port-au-Prince',
            'USD',
            'active',
            jsonb_build_object(
                'biometric_enabled', true,
                'biometric_mode', 'fingerprint_only',
                'door_terminal_enabled', true,
                'door_terminal_ip', '192.168.1.201',
                'door_terminal_port', 5005,
                'scan_sound', true,
                'scan_vibrate', true,
                'allow_access_pending', false,
                'entry_duplicate_seconds', 3,
                'auto_logout_minutes', 30,
                'pin_lock_minutes', 5,
                'reception_see_all_payments', true,
                'doc_footer', 'Mèsi paske w chwazi JL FITNESS!'
            )
        );
        raise notice 'Sal JL FITNESS kreye avèk ID: %', v_gym_id;
    else
        update public.gyms
        set name = 'JL FITNESS',
            accent_color = '#FFA726',
            address = 'Delmas 75, Frangneauville 15, #27',
            phone = '+509 48170828 / 37774354 / 41433933',
            email = 'jeanlesly1990@gmail.com',
            timezone = 'America/Port-au-Prince',
            currency = 'USD',
            status = 'active',
            deleted_at = null,
            settings = jsonb_build_object(
                'biometric_enabled', true,
                'biometric_mode', 'fingerprint_only',
                'door_terminal_enabled', true,
                'door_terminal_ip', '192.168.1.201',
                'door_terminal_port', 5005,
                'scan_sound', true,
                'scan_vibrate', true,
                'allow_access_pending', false,
                'entry_duplicate_seconds', 3,
                'auto_logout_minutes', 30,
                'pin_lock_minutes', 5,
                'reception_see_all_payments', true,
                'doc_footer', 'Mèsi paske w chwazi JL FITNESS!'
            )
        where id = v_gym_id;
        raise notice 'Sal JL FITNESS mete ajou avèk ID: %', v_gym_id;
    end if;

    -- --------------------------------------------------------------------------
    -- 3. Asiyen JEAN LESLY kòm Sèl e Inik Pwopriyetè (Owner) nan public.staff
    --    - Retire nenpòt ansyen owner sou sal sa a (evite 'staff_single_owner')
    --    - Retire nenpòt ansyen sal itilizatè sa a te genyen
    -- --------------------------------------------------------------------------
    delete from public.staff where gym_id = v_gym_id and role = 'owner';
    delete from public.staff where user_id = v_owner_id;

    insert into public.staff (
        id,
        user_id,
        gym_id,
        role,
        full_name,
        phone,
        active
    ) values (
        gen_random_uuid(),
        v_owner_id,
        v_gym_id,
        'owner',
        'JEAN LESLY',
        '+509 48170828',
        true
    );

    -- --------------------------------------------------------------------------
    -- 4. Inisyalize Kontè Manm nan public.gym_counters
    -- --------------------------------------------------------------------------
    insert into public.gym_counters (gym_id, member_seq)
    values (v_gym_id, 0)
    on conflict (gym_id) do nothing;

    -- --------------------------------------------------------------------------
    -- 5. Mete Kontra Platfòm PRO (1 000 Manm) — Peman Inik / A vi
    -- --------------------------------------------------------------------------
    delete from public.gym_contracts where gym_id = v_gym_id;

    insert into public.gym_contracts (
        id,
        gym_id,
        offer_id,
        status,
        starts_at,
        expires_at,
        price_snapshot
    ) values (
        gen_random_uuid(),
        v_gym_id,
        'plan_pro',
        'active',
        clock_timestamp(),
        null, -- null vle di peman inik / pa janm ekspire (one_time / a vi)
        jsonb_build_object(
            'offer_id', 'plan_pro',
            'name', 'PLAN 3 : PRO (1 000 manm & Pòt Byometrik)',
            'price', 2200.00,
            'currency', 'USD',
            'billing_period', 'one_time',
            'config', jsonb_build_object(
                'max_members', 1000,
                'biometric_supported', true,
                'includes_door_access', true,
                'badge_quota', 0,
                'door_hardware_kit', 'Tèminal FSTW F30 TCP/IP + Lektè USB DigitalPersona 4500 + Ventouse 280kg + Bra LZ + Bouton sòti + Alimantasyon sekirize'
            )
        )
    );

    -- --------------------------------------------------------------------------
    -- 6. Enskri Peman Platfòm nan kòm Deklarasyon Apwouve
    -- --------------------------------------------------------------------------
    delete from public.payment_declarations where gym_id = v_gym_id;

    insert into public.payment_declarations (
        id,
        gym_id,
        method,
        reference,
        amount,
        currency,
        status,
        reviewed_by,
        reviewed_at,
        note,
        created_by
    ) values (
        gen_random_uuid(),
        v_gym_id,
        'cash',
        'PAID-IN-FULL-PRO-1000',
        2200.00,
        'USD',
        'approved',
        v_owner_id,
        clock_timestamp(),
        'Peman konplè Plan PRO (1 000 manm) - Sistèm Pòt & Anprent Byometrik Enkli',
        v_owner_id
    );

    -- --------------------------------------------------------------------------
    -- 7. Kreye Plan Abònman Estanda (Sèlman Séance $10 USD & Mois $40 USD)
    -- --------------------------------------------------------------------------
    delete from public.plans where gym_id = v_gym_id;

    insert into public.plans (
        id,
        gym_id,
        name,
        duration_days,
        price,
        currency,
        active,
        sort_order,
        description
    ) values
        (gen_random_uuid(), v_gym_id, 'Séance (1 Jou)', 1, 10.00, 'USD', true, 1, 'Aksè pou yon jounen konplè ($10 USD)'),
        (gen_random_uuid(), v_gym_id, 'Abònman 1 Mwa', 30, 40.00, 'USD', true, 2, 'Aksè san limit pou 30 jou avèk anprent dijital ($40 USD)');

    raise notice '=======================================================';
    raise notice 'FELISITASYON! Sal JL FITNESS monte avèk siksè nan sistèm nan:';
    raise notice 'ID Sal: %', v_gym_id;
    raise notice 'Kòd: JLF';
    raise notice 'Pwopriyetè: JEAN LESLY (ID: %)', v_owner_id;
    raise notice 'Imèl: jeanlesly1990@gmail.com';
    raise notice 'Deviz: USD ($)';
    raise notice 'Plan Kliyan: Séance $10 USD | Mwa $40 USD';
    raise notice 'Plan Platfòm: 1 000 Manm Byometrik & Pòt (A vi)';
    raise notice '=======================================================';
end $$;
