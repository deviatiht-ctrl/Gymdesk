begin;

do $$
declare
    gym uuid := gen_random_uuid(); owner_user uuid := gen_random_uuid(); reception_user uuid := gen_random_uuid();
    owner_staff uuid := gen_random_uuid(); reception_staff uuid := gen_random_uuid();
    member uuid := gen_random_uuid(); plan uuid := gen_random_uuid(); subscription uuid := gen_random_uuid();
begin
    insert into auth.users(id, email, aud, role) values
      (owner_user, owner_user::text || '@example.invalid', 'authenticated', 'authenticated'),
      (reception_user, reception_user::text || '@example.invalid', 'authenticated', 'authenticated');
    insert into public.gyms(id, code, name, timezone, settings) values
      (gym, 'SCN', 'Scan SQL', 'America/Port-au-Prince', '{"entry_duplicate_seconds": 3, "allow_access_pending": false}'::jsonb);
    insert into public.staff(id, user_id, gym_id, role, full_name) values
      (owner_staff, owner_user, gym, 'owner', 'Owner SQL'),
      (reception_staff, reception_user, gym, 'reception', 'Reception SQL');
    insert into public.plans(id, gym_id, name, duration_days, price) values(plan, gym, 'Monthly', 30, 1000);
    insert into public.members(id, gym_id, member_number, qr_token, first_name, last_name) values
      (member, gym, 'SCN-000001', 'valid-token-00000000000000000000000000000000', 'Marie', 'Jean');
    insert into public.subscriptions(id, gym_id, member_id, plan_id, start_date, end_date, price, status, created_by) values
      (subscription, gym, member, plan, current_date - 10, current_date + 20, 1000, 'active', owner_staff);
    perform set_config('gymdesk.scan_gym', gym::text, true);
    perform set_config('gymdesk.scan_member', member::text, true);
    perform set_config('gymdesk.scan_subscription', subscription::text, true);
    perform set_config('gymdesk.scan_reception_user', reception_user::text, true);
    perform set_config('gymdesk.scan_reception_staff', reception_staff::text, true);
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('gymdesk.scan_reception_user'), true);

do $$
declare
    gym uuid := current_setting('gymdesk.scan_gym')::uuid;
    member uuid := current_setting('gymdesk.scan_member')::uuid;
    subscription uuid := current_setting('gymdesk.scan_subscription')::uuid;
    reception_staff uuid := current_setting('gymdesk.scan_reception_staff')::uuid;
    first uuid := gen_random_uuid(); second uuid := gen_random_uuid(); bad uuid := gen_random_uuid();
    response jsonb; row jsonb;
begin
    response := public.sync_push(first, 'attendance', jsonb_build_object(
      'id', first, 'gym_id', gym, 'member_id', member, 'qr_token', 'valid-token-00000000000000000000000000000000',
      'scanned_at', clock_timestamp(), 'result', 'denied_unknown', 'entry_number_today', 99,
      'device_id', 'device-test', 'was_offline', true, 'suspect_clock', false
    ), clock_timestamp());
    row := response->'row';
    if response->>'outcome' <> 'accepted' or row->>'result' <> 'granted'
       or (row->>'entry_number_today')::int <> 1 or row->>'subscription_id' <> subscription::text
       or row->>'scanned_by' <> reception_staff::text then raise exception 'FAIL: authoritative granted scan'; end if;

    response := public.sync_push(second, 'attendance', jsonb_build_object(
      'id', second, 'gym_id', gym, 'member_id', member, 'qr_token', 'valid-token-00000000000000000000000000000000',
      'scanned_at', clock_timestamp() + interval '1 second', 'result', 'granted', 'device_id', 'device-test'
    ), clock_timestamp());
    row := response->'row';
    if row->>'result' <> 'denied_duplicate' or row->>'entry_number_today' is not null then raise exception 'FAIL: duplicate scan guard'; end if;
    if (select count(*) from public.attendance where member_id = member and result = 'granted') <> 1 then raise exception 'FAIL: duplicate granted entry'; end if;

    response := public.sync_push(bad, 'attendance', jsonb_build_object(
      'id', bad, 'gym_id', gym, 'member_id', member, 'qr_token', 'wrong-token-000000000000000000000000000000',
      'scanned_at', clock_timestamp(), 'result', 'granted', 'device_id', 'device-test'
    ), clock_timestamp());
    row := response->'row';
    if row->>'result' <> 'denied_unknown' or row->>'member_id' is not null then raise exception 'FAIL: token spoofing'; end if;

    begin
      update public.attendance set result = 'denied_unknown' where id = first;
      raise exception 'FAIL: attendance update';
    exception when insufficient_privilege then null; end;
end $$;

reset role;
do $$
begin
    if not exists(select 1 from public.audit_log where action = 'attendance_scan' and entity = 'attendance') then
        raise exception 'FAIL: attendance audit';
    end if;
end $$;
select 'GymDesk attendance assertions completed; fixtures rolled back.' as result;
rollback;
