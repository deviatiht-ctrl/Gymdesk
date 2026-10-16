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

-- 2. Netwaye ansyen plan ki pa gen manm ki relye ak yo
delete from public.plans
where gym_id = (select id from public.gyms where code = 'JLF')
  and id not in (select plan_id from public.subscriptions)
  and (currency = 'HTG' or (name = 'Pas 1 Jou (Séance)' and price = 10.00));

-- 3. Asire plan USD yo aktif e yo gen bon deviz
update public.plans
set currency = 'USD', active = true
where gym_id = (select id from public.gyms where code = 'JLF');
