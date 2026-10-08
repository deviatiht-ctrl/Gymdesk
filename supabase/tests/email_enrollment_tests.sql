begin;

do $$
declare
  gym uuid := gen_random_uuid(); other_gym uuid := gen_random_uuid();
  owner_user uuid := gen_random_uuid(); reception_user uuid := gen_random_uuid();
  owner_staff uuid := gen_random_uuid(); reception_staff uuid := gen_random_uuid();
  member uuid := gen_random_uuid(); plan uuid := gen_random_uuid();
  badge uuid := gen_random_uuid(); subscription uuid := gen_random_uuid(); renewal uuid := gen_random_uuid();
  claimed jsonb; second jsonb; v_count int;
  supervisor_user uuid := gen_random_uuid(); supervisor_staff uuid := gen_random_uuid(); imported_member uuid := gen_random_uuid();
begin
  if exists(select 1 from public.email_outbox) then raise exception 'Run only on an empty disposable test database'; end if;
  insert into auth.users(id, email, aud, role) values
    (owner_user, owner_user || '@example.invalid', 'authenticated', 'authenticated'),
    (reception_user, reception_user || '@example.invalid', 'authenticated', 'authenticated'),
    (supervisor_user, supervisor_user || '@example.invalid', 'authenticated', 'authenticated');
  insert into public.gyms(id, code, name, timezone, currency) values
    (gym, 'EML', 'Email Test', 'America/Port-au-Prince', 'HTG'),
    (other_gym, 'EM2', 'Other Gym', 'America/Port-au-Prince', 'HTG');
  insert into public.staff(id, user_id, gym_id, role, full_name) values
    (owner_staff, owner_user, gym, 'owner', 'Owner'),
    (reception_staff, reception_user, gym, 'reception', 'Reception'),
    (supervisor_staff, supervisor_user, gym, 'supervisor', 'Supervisor');
  perform set_config('request.jwt.claim.sub', owner_user::text, true);
  insert into public.gym_contracts(gym_id, offer_id, status, price_snapshot)
    values(gym, 'per_member', 'trial', '{"name":"Test 100","price":50,"currency":"USD","config":{"badge_quota":100}}');
  if (select count(*) from public.email_outbox where kind = 'gym_welcome') <> 1 then raise exception 'FAIL gym welcome'; end if;
  if (select payload->>'plan_name' from public.email_outbox where kind = 'gym_welcome') <> 'Test 100' then raise exception 'FAIL offer snapshot'; end if;
  insert into public.plans(id, gym_id, name, duration_days, price, enrollment_price) values(plan, gym, 'Monthly', 30, 500, 800);
  insert into public.members(id, gym_id, member_number, qr_token, first_name, last_name, email, enrollment_origin)
    values(member, gym, '01', gen_random_uuid()::text, 'Marie', 'Jean', 'member@example.invalid', 'existing');
  insert into public.badges(id, gym_id, badge_number, qr_token) values(badge, gym, 1, gen_random_uuid()::text);
  insert into public.subscriptions(id, gym_id, member_id, plan_id, start_date, end_date, price, opening_credit, enrollment_kind, status)
    values(subscription, gym, member, plan, '2026-09-01', '2026-09-30', 500, 500, 'import', 'active');
  if exists(select 1 from public.email_outbox where kind = 'member_welcome') then raise exception 'FAIL premature email'; end if;
  update public.badges set status = 'bound', member_id = member where id = badge;
  update public.badges set status = 'bound' where id = badge;
  update public.subscriptions set status = 'active' where id = subscription;
  if (select count(*) from public.email_outbox where kind = 'member_welcome') <> 1 then raise exception 'FAIL duplicate welcome'; end if;
  if (select count(*) from public.badge_history where id = member) <> 1 then raise exception 'FAIL server badge history'; end if;
  if exists(select 1 from public.payments where member_id = member) then raise exception 'FAIL import created cash'; end if;
  perform set_config('request.jwt.claim.sub', '', true);
  update public.subscriptions set status = 'expired' where id = subscription;
  perform set_config('request.jwt.claim.sub', reception_user::text, true);
  begin
    insert into public.members(gym_id, member_number, qr_token, first_name, last_name, enrollment_origin)
      values(gym, '02', gen_random_uuid()::text, 'No', 'Import', 'existing');
    raise exception 'FAIL reception imported a member';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.subscriptions(gym_id, member_id, plan_id, start_date, end_date, price, opening_credit, enrollment_kind)
      values(gym, member, plan, '2026-10-01', '2026-10-31', 500, 500, 'import');
    raise exception 'FAIL reception imported credit';
  exception when insufficient_privilege then null; end;
  insert into public.subscriptions(id, gym_id, member_id, plan_id, start_date, end_date, price, enrollment_kind, status, renewed_from)
    values(renewal, gym, member, plan, '2026-10-01', '2026-10-31', 500, 'renewal', 'active', subscription);
  if (select status from public.subscriptions where id = renewal) <> 'pending' then raise exception 'FAIL reception approved renewal'; end if;
  if exists(select 1 from public.email_outbox where kind = 'member_renewal') then raise exception 'FAIL pending renewal emailed'; end if;
  perform set_config('request.jwt.claim.sub', owner_user::text, true);
  update public.subscriptions set status = 'active' where id = renewal;
  update public.subscriptions set status = 'active' where id = renewal;
  if (select count(*) from public.email_outbox where kind = 'member_renewal') <> 1 then raise exception 'FAIL renewal email dedup'; end if;
  begin
    update public.subscriptions set opening_credit = 0 where id = subscription;
    raise exception 'FAIL imported credit mutable';
  exception when invalid_parameter_value then null; end;
  if has_function_privilege('authenticated', 'public.claim_email()', 'EXECUTE') or has_function_privilege('anon', 'public.claim_email()', 'EXECUTE') then raise exception 'FAIL public worker RPC'; end if;
  if has_table_privilege('authenticated', 'public.email_outbox', 'INSERT') then raise exception 'FAIL client arbitrary email'; end if;

  perform set_config('request.jwt.claim.sub', supervisor_user::text, true);
  execute 'set local role authenticated';
  insert into public.members(id, gym_id, member_number, qr_token, first_name, last_name, email, enrollment_origin)
    values(imported_member, gym, '03', gen_random_uuid()::text, 'Legacy', 'Member', 'legacy@example.invalid', 'existing');
  insert into public.subscriptions(gym_id, member_id, plan_id, start_date, end_date, price, opening_credit, enrollment_kind, status)
    values(gym, imported_member, plan, '2026-09-01', '2026-09-30', 500, 500, 'import', 'active');
  update public.plans set enrollment_price = 850 where id = plan;
  if (select enrollment_price from public.plans where id = plan) <> 850 then raise exception 'FAIL supervisor plan configuration'; end if;
  begin
    insert into public.members(gym_id, member_number, qr_token, first_name, last_name, enrollment_origin)
      values(other_gym, '03', gen_random_uuid()::text, 'Cross', 'Gym', 'existing');
    raise exception 'FAIL supervisor crossed tenant';
  exception when insufficient_privilege then null; end;
  begin
    perform public.claim_email();
    raise exception 'FAIL staff claimed email';
  exception when insufficient_privilege then null; end;
  if ((public.email_delivery_status()->'counts')->>'pending')::int <> 3 then raise exception 'FAIL email status counts'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', owner_user::text, true);

  update public.email_outbox set status = 'sent';
  insert into public.email_outbox(gym_id, event_key, kind, recipient, payload)
    select case when n % 2 = 0 then gym else other_gym end, 'quota-test:' || n, 'member_welcome', 'test@example.invalid', '{}'::jsonb from generate_series(1, 301) n;
  for v_count in 1..300 loop
    claimed := public.claim_email();
    if claimed is null then raise exception 'FAIL premature quota %', v_count; end if;
    perform public.finish_email((claimed->>'id')::uuid, (claimed->>'lease_token')::uuid, 'sent', 'test-message');
  end loop;
  if public.claim_email() is not null then raise exception 'FAIL global 300 quota exceeded'; end if;
  if (select count(*) from public.email_outbox where status = 'pending') <> 1 then raise exception 'FAIL 301st email lost'; end if;
  update public.email_delivery_attempts set reserved_at = clock_timestamp() - interval '25 hours';
  claimed := public.claim_email();
  if claimed is null then raise exception 'FAIL next day did not resume'; end if;
  perform public.finish_email((claimed->>'id')::uuid, (claimed->>'lease_token')::uuid, 'quota', null, 'not_enough_credits');
  if public.claim_email() is not null then raise exception 'FAIL provider quota did not pause globally'; end if;
  update public.email_delivery_settings set paused_until = null where id;
  update public.email_outbox set available_at = clock_timestamp() where status = 'pending';
  second := public.claim_email();
  if second->>'id' is distinct from claimed->>'id' then raise exception 'FAIL retry did not preserve job'; end if;
  begin
    perform public.finish_email((second->>'id')::uuid, (claimed->>'lease_token')::uuid, 'sent');
    raise exception 'FAIL stale lease accepted';
  exception when raise_exception then
    if sqlerrm <> 'invalid_lease' then raise; end if;
  end;
  update public.email_outbox set locked_at = clock_timestamp() - interval '6 minutes' where id = (second->>'id')::uuid;
  perform public.claim_email();
  if (select status from public.email_outbox where id = (second->>'id')::uuid) <> 'uncertain' then raise exception 'FAIL interrupted send blindly retried'; end if;
end $$;

rollback;
