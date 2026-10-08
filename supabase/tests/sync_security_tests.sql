begin;

do $$
declare ga uuid := gen_random_uuid(); gb uuid := gen_random_uuid();
    ua uuid := gen_random_uuid(); ub uuid := gen_random_uuid(); ur uuid := gen_random_uuid(); us uuid := gen_random_uuid();
    sa uuid := gen_random_uuid(); sb uuid := gen_random_uuid(); sr uuid := gen_random_uuid();
    ma uuid := gen_random_uuid(); mb uuid := gen_random_uuid();
begin
    perform set_config('gymdesk.test_ga', ga::text, true);
    perform set_config('gymdesk.test_gb', gb::text, true);
    perform set_config('gymdesk.test_ua', ua::text, true);
    perform set_config('gymdesk.test_ur', ur::text, true);
    perform set_config('gymdesk.test_us', us::text, true);
    perform set_config('gymdesk.test_sr', sr::text, true);
    perform set_config('gymdesk.test_ma', ma::text, true);
    perform set_config('gymdesk.test_mb', mb::text, true);
    insert into auth.users(id, email, aud, role) values
      (ua, ua::text || '@example.invalid', 'authenticated', 'authenticated'),
      (ub, ub::text || '@example.invalid', 'authenticated', 'authenticated'),
      (ur, ur::text || '@example.invalid', 'authenticated', 'authenticated'),
      (us, us::text || '@example.invalid', 'authenticated', 'authenticated');
    insert into public.gyms(id, code, name) values
      (ga, upper(substr(replace(ga::text, '-', ''), 1, 6)), 'SQL test A'),
      (gb, upper(substr(replace(gb::text, '-', ''), 1, 6)), 'SQL test B');
    insert into public.staff(id, user_id, gym_id, role, full_name) values
      (sa, ua, ga, 'owner', 'SQL owner A'), (sb, ub, gb, 'owner', 'SQL owner B'),
      (sr, ur, ga, 'reception', 'SQL reception'), (gen_random_uuid(), us, null, 'super_admin', 'SQL platform');
    insert into public.members(id, gym_id, member_number, qr_token, first_name, last_name) values
      (ma, ga, 'TEST-000001', repeat('a', 32), 'SQL', 'A'),
      (mb, gb, 'TEST-000001', repeat('b', 32), 'SQL', 'B');
    insert into public.payments(id, gym_id, member_id, amount, method, received_by, paid_at) values
      (gen_random_uuid(), ga, ma, 1, 'cash', sr, now()),
      (gen_random_uuid(), ga, ma, 1, 'cash', sr, now() - interval '2 days'),
      (gen_random_uuid(), ga, ma, 1, 'cash', sa, now());
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('gymdesk.test_ua'), true);

do $$
declare ga uuid := current_setting('gymdesk.test_ga')::uuid;
    gb uuid := current_setting('gymdesk.test_gb')::uuid;
    mb uuid := current_setting('gymdesk.test_mb')::uuid;
    op uuid := gen_random_uuid(); mid uuid := gen_random_uuid(); payload jsonb; first_result jsonb; second_result jsonb;
begin
    if exists(select 1 from public.members where gym_id = gb) then raise exception 'FAIL: cross-tenant read'; end if;
    begin
      insert into public.members(id, gym_id, member_number, qr_token, first_name, last_name)
      values(gen_random_uuid(), gb, 'FAIL', repeat('x',32), 'SQL', 'Test');
      raise exception 'FAIL: cross-tenant insert allowed';
    exception when insufficient_privilege then null; end;
    begin
      perform public.next_member_number(gb);
      raise exception 'FAIL: cross-tenant number allocation allowed';
    exception when insufficient_privilege then null; end;
    begin
      insert into public.subscriptions(id, gym_id, member_id, start_date, end_date, price)
      values(gen_random_uuid(), ga, mb, current_date, current_date, 1);
      raise exception 'FAIL: cross-tenant foreign key accepted';
    exception when foreign_key_violation then null; end;
    if (select valid from public.member_validity(mb)) then raise exception 'FAIL: cross-tenant validity'; end if;
    if public.gym_setting(gb, 'grace_days') is not null then raise exception 'FAIL: cross-tenant settings'; end if;
    payload := jsonb_build_object('id', mid, 'gym_id', ga, 'member_number', 'TMP-' || mid::text,
      'qr_token', repeat('c',32), 'first_name', 'SQL', 'last_name', 'Sync', 'status', 'active');
    first_result := public.sync_push(op, 'members', payload, now());
    second_result := public.sync_push(op, 'members', payload, now());
    if first_result->'row'->>'member_number' like 'TMP-%' then raise exception 'FAIL: provisional number'; end if;
    if first_result is distinct from second_result then raise exception 'FAIL: replay differs'; end if;
    if (select count(*) from public.members where id = mid) <> 1 then raise exception 'FAIL: duplicate member'; end if;
    if (select count(*) from public.sync_receipts where id = op) <> 1 then raise exception 'FAIL: duplicate receipt'; end if;
end $$;

select set_config('request.jwt.claim.sub', current_setting('gymdesk.test_ur'), true);
do $$
declare ga uuid := current_setting('gymdesk.test_ga')::uuid;
    ma uuid := current_setting('gymdesk.test_ma')::uuid;
    aid uuid := gen_random_uuid(); op uuid := gen_random_uuid(); payload jsonb;
begin
    if (select count(*) from public.payments where gym_id = ga) <> 1 then raise exception 'FAIL: reception payment scope'; end if;
    begin
      update public.staff set role = 'owner' where user_id = auth.uid();
      raise exception 'FAIL: self-promotion';
    exception when insufficient_privilege then null; end;
    begin
      update public.staff set gym_id = current_setting('gymdesk.test_gb')::uuid where user_id = auth.uid();
      raise exception 'FAIL: tenant reassignment';
    exception when insufficient_privilege then null; end;
    begin
      update public.members set deleted_at = now() where id = ma;
      raise exception 'FAIL: reception soft-delete';
    exception when insufficient_privilege then null; end;
    payload := jsonb_build_object('id', aid, 'gym_id', ga, 'member_id', ma,
      'scanned_at', now(), 'result', 'denied_no_subscription', 'was_offline', true);
    perform public.sync_push(op, 'attendance', payload, now());
    perform public.sync_push(op, 'attendance', payload, now());
    if (select count(*) from public.attendance where id = aid) <> 1 then raise exception 'FAIL: attendance replay'; end if;
    update public.attendance set result = 'granted' where id = aid;
    if (select result from public.attendance where id = aid) <> 'denied_no_subscription' then raise exception 'FAIL: mutable attendance'; end if;
    perform public.sync_push(gen_random_uuid(), 'payments', jsonb_build_object('id', gen_random_uuid(),
      'gym_id', ga, 'member_id', ma, 'amount', 1, 'method', 'cash', 'paid_at', now() - interval '2 days'), now());
    if (select count(*) from public.payments where gym_id = ga) <> 1 then raise exception 'FAIL: old offline payment disclosed'; end if;
end $$;

select set_config('request.jwt.claim.sub', current_setting('gymdesk.test_us'), true);
do $$
begin
    if exists(select 1 from public.members) then raise exception 'FAIL: platform member access'; end if;
    if exists(select 1 from public.payments) then raise exception 'FAIL: platform payments access'; end if;
    update public.gyms set status = 'suspended' where id = current_setting('gymdesk.test_ga')::uuid;
end $$;

select set_config('request.jwt.claim.sub', current_setting('gymdesk.test_ua'), true);
do $$
declare ga uuid := current_setting('gymdesk.test_ga')::uuid;
begin
    if public.current_gym_id() is not null then raise exception 'FAIL: suspended tenant context'; end if;
    if exists(select 1 from public.members where gym_id = ga) then raise exception 'FAIL: suspended tenant read'; end if;
    begin
      perform public.reserve_member_numbers(ga, 1);
      raise exception 'FAIL: suspended allocation';
    exception when insufficient_privilege then null; end;
    begin
      perform public.sync_push(gen_random_uuid(), 'members', jsonb_build_object('id', gen_random_uuid(), 'gym_id', ga), now());
      raise exception 'FAIL: suspended sync';
    exception when insufficient_privilege then null; end;
end $$;

reset role;
select 'GymDesk SQL security assertions completed; fixtures rolled back.' as result;
rollback;
