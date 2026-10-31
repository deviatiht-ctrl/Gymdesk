-- Assertions for 36_admin_gym_detail.sql (runs on disposable PGlite only).
-- Requires the extended auth.users fixture (last_sign_in_at, created_at).
do $$
declare
  admin_user uuid := gen_random_uuid();
  other_user uuid := gen_random_uuid();
  gym uuid := gen_random_uuid();
  detail jsonb;
  updated jsonb;
  offer_name text;
begin
  insert into auth.users(id, email, aud, role) values
    (admin_user, 'admin@platform.invalid', 'authenticated', 'authenticated'),
    (other_user, 'nobody@platform.invalid', 'authenticated', 'authenticated');
  insert into public.gyms(id, code, name, timezone, currency, status)
    values(gym, 'DTL', 'Detail Gym', 'America/Port-au-Prince', 'HTG', 'active');
  insert into public.staff(id, user_id, gym_id, role, full_name) values
    (gen_random_uuid(), admin_user, null, 'super_admin', 'Platform Admin');
  insert into public.members(id, gym_id, member_number, qr_token, first_name, last_name)
    values(gen_random_uuid(), gym, 'DTL-1', md5(random()::text) || md5(random()::text), 'Test', 'Member');

  -- Offres en français, sans mojibake ni termes anglais.
  if exists(select 1 from public.platform_offers
            where coalesce(name,'') ~ 'Ã' or coalesce(description,'') ~ 'Ã') then
    raise exception 'mojibake present in platform_offers';
  end if;
  select name into offer_name from public.platform_offers where id = 'plan_basic';
  if offer_name <> 'PLAN 1 : DÉMARRAGE (Porte biométrique)' then
    raise exception 'plan_basic name is not French: %', offer_name;
  end if;
  select name into offer_name from public.platform_offers where id = 'plan_enterprise';
  if offer_name <> 'PLAN 4 : ENTREPRISE (Performance illimitée)' then
    raise exception 'plan_enterprise name is not French: %', offer_name;
  end if;
  if exists(select 1 from public.platform_offers where id in
            ('plan_basic','plan_medium','plan_pro','plan_enterprise')
            and (name ~* 'basic|starter|growth|unlimited performance|medium')) then
    raise exception 'english terms remain in official plan names';
  end if;

  -- Accès refusé pour un utilisateur non super admin.
  perform set_config('request.jwt.claim.sub', other_user::text, true);
  begin
    detail := public.platform_gym_detail(gym);
    raise exception 'platform_gym_detail accepted a non-admin';
  exception when others then
    if sqlerrm not like '%access_denied%' then raise; end if;
  end;
  begin
    updated := public.platform_update_gym(gym, '{"name":"X"}'::jsonb);
    raise exception 'platform_update_gym accepted a non-admin';
  exception when others then
    if sqlerrm not like '%access_denied%' then raise; end if;
  end;

  -- Super admin : détail complet.
  perform set_config('request.jwt.claim.sub', admin_user::text, true);
  detail := public.platform_gym_detail(gym);
  if (detail->'gym'->>'name') <> 'Detail Gym' then
    raise exception 'wrong gym name: %', detail->'gym'->>'name';
  end if;
  if (detail->'stats'->>'members')::int <> 1 then
    raise exception 'wrong members stat: %', detail->'stats';
  end if;
  if detail ? 'contract' is not true or detail ? 'stats' is not true then
    raise exception 'detail payload incomplete: %', detail;
  end if;

  -- Édition des informations de la salle.
  updated := public.platform_update_gym(gym, '{"name":"Detail Gym Pro","phone":"+509 1111"}'::jsonb);
  if (updated->>'name') <> 'Detail Gym Pro' or (updated->>'phone') <> '+509 1111' then
    raise exception 'platform_update_gym did not persist changes: %', updated;
  end if;

  -- Un code de salle déjà pris est refusé.
  insert into public.gyms(id, code, name, timezone, currency, status)
    values(gen_random_uuid(), 'DTL2', 'Other Gym', 'America/Port-au-Prince', 'HTG', 'active');
  begin
    updated := public.platform_update_gym(gym, '{"code":"DTL2"}'::jsonb);
    raise exception 'platform_update_gym accepted a duplicate code';
  exception when others then
    if sqlerrm not like '%duplicate_code%' then raise; end if;
  end;
end $$;
