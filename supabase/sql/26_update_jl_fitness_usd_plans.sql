-- ==============================================================================
-- 26_update_jl_fitness_usd_plans.sql — Ti SQL kout pou mete deviz an USD ak 2 plan sèlman
-- ==============================================================================
-- Sal : JL FITNESS (JLF)
-- Deviz : USD ($)
-- Plan 1 : Séance $10 USD (1 jou)
-- Plan 2 : Abònman 1 Mwa $40 USD (30 jou)
-- ==============================================================================

-- 1. Mete deviz sal la an USD ($)
update public.gyms
set currency = 'USD'
where code = 'JLF';

-- 2. Netwaye ansyen plan yo pou sal JLF
delete from public.plans
where gym_id = (select id from public.gyms where code = 'JLF');

-- 3. Mete sèlman 2 plan yo an USD ($)
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
    (
        gen_random_uuid(),
        (select id from public.gyms where code = 'JLF'),
        'Séance (1 Jou)',
        1,
        10.00,
        'USD',
        true,
        1,
        'Aksè pou yon jounen konplè ($10 USD)'
    ),
    (
        gen_random_uuid(),
        (select id from public.gyms where code = 'JLF'),
        'Abònman 1 Mwa',
        30,
        40.00,
        'USD',
        true,
        2,
        'Aksè san limit pou 30 jou avèk anprent dijital ($40 USD)'
    );
