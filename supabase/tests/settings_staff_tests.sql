begin;

do $$
declare
    gym uuid := gen_random_uuid(); owner_user uuid := gen_random_uuid(); manager_user uuid := gen_random_uuid();
    owner_staff uuid := gen_random_uuid(); manager_staff uuid := gen_random_uuid();
    new_user uuid := gen_random_uuid(); new_staff uuid := gen_random_uuid(); request_id uuid := gen_random_uuid();
    payload jsonb; created jsonb; replay jsonb;
begin
    insert into auth.users(id, email, aud, role) values
      (owner_user, owner_user::text || '@example.invalid', 'authenticated', 'authenticated'),
      (manager_user, manager_user::text || '@example.invalid', 'authenticated', 'authenticated');
    insert into public.gyms(id, code, name, settings) values
      (gym, 'TGS', 'Settings SQL', '{"grace_days": 0, "scan_vibrate": true}'::jsonb);
    insert into public.staff(id, user_id, gym_id, role, full_name) values
      (owner_staff, owner_user, gym, 'owner', 'SQL owner'),
      (manager_staff, manager_user, gym, 'manager', 'SQL manager');
    insert into storage.objects(bucket_id, name) values('gym-assets', gym::text || '/logos/test.png');

    insert into auth.users(id, email, aud, role, raw_app_meta_data) values
      (new_user, new_user::text || '@example.invalid', 'authenticated', 'authenticated', jsonb_build_object('gymdesk_staff_request', request_id));
    payload := jsonb_build_object('email', new_user::text || '@example.invalid', 'full_name', 'SQL reception', 'phone', '+50937000000', 'role', 'reception');
    perform public.staff_provision_begin(request_id, owner_user, new_staff, payload);
    if exists(select 1 from public.staff where id = new_staff) then raise exception 'FAIL: staff created before Auth binding'; end if;
    if public.staff_provision_auth_user(request_id, owner_user) is distinct from new_user then raise exception 'FAIL: staff Auth recovery'; end if;
    created := public.staff_provision_finish(request_id, owner_user, new_user);
    replay := public.staff_provision_finish(request_id, owner_user, new_user);
    if created is distinct from replay or created->>'role' <> 'reception' then raise exception 'FAIL: staff provisioning replay'; end if;
    if exists(select 1 from public.staff_provisioning where payload::text like '%password%') then raise exception 'FAIL: password persisted'; end if;
    begin
      perform public.staff_provision_begin(request_id, owner_user, new_staff, jsonb_set(payload, '{role}', '"manager"'::jsonb));
      raise exception 'FAIL: mutable staff request';
    exception when sqlstate '22023' then null; end;
    perform set_config('gymdesk.settings_gym', gym::text, true);
    perform set_config('gymdesk.settings_owner', owner_user::text, true);
    perform set_config('gymdesk.settings_owner_staff', owner_staff::text, true);
    perform set_config('gymdesk.settings_manager', manager_user::text, true);
    perform set_config('gymdesk.settings_manager_staff', manager_staff::text, true);
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('gymdesk.settings_owner'), true);

do $$
declare
    gym uuid := current_setting('gymdesk.settings_gym')::uuid;
    owner_staff uuid := current_setting('gymdesk.settings_owner_staff')::uuid;
    manager_staff uuid := current_setting('gymdesk.settings_manager_staff')::uuid;
    version timestamptz; result jsonb; op uuid := gen_random_uuid();
begin
    select updated_at into version from public.gyms where id = gym;
    result := public.sync_branding(op, 'gyms', jsonb_build_object(
      'id', gym, 'name', 'Updated Gym', 'accent_color', '#305F8A', 'timezone', 'America/Port-au-Prince', 'currency', 'USD',
      'address', 'Delmas', 'phone', '+50937000000', 'email', 'gym@example.invalid', 'logo_url', gym::text || '/logos/test.png',
      'settings', jsonb_build_object('doc_footer', 'Footer', 'offline_lease_hours', 24, 'pin_lock_minutes', 5,
        'grace_days', 0, 'allow_access_pending', false, 'reception_see_all_payments', false, 'scan_sound', true, 'scan_vibrate', true,
        'entry_duplicate_seconds', 3, 'qr_defaults', jsonb_build_object('eye','square'))
    ), now(), version);
    if result->>'outcome' <> 'accepted' or result->'row'->>'name' <> 'Updated Gym' then raise exception 'FAIL: branding update'; end if;
    if public.sync_branding(op, 'gyms', jsonb_build_object('id', gym), now(), version) is distinct from result then raise exception 'FAIL: branding replay'; end if;
    begin
      perform public.sync_branding(gen_random_uuid(), 'gyms', jsonb_build_object('id', gym, 'settings', jsonb_build_object('admin', true)), now(), result->'row'->>'updated_at');
      raise exception 'FAIL: unknown settings key';
    exception when sqlstate '22023' then null; end;
    begin
      perform public.sync_branding(gen_random_uuid(), 'gyms', jsonb_build_object('id', gym, 'logo_url', gym::text || '/logos/missing.png',
        'name', 'Updated Gym', 'accent_color', '#305F8A', 'timezone', 'America/Port-au-Prince', 'currency', 'USD', 'settings', '{}'::jsonb), now(), result->'row'->>'updated_at');
      raise exception 'FAIL: missing logo accepted';
    exception when sqlstate '22023' then null; end;
    begin
      perform public.update_staff_access(manager_staff, 'owner', true, now());
      raise exception 'FAIL: owner promotion';
    exception when sqlstate '22023' then null; end;
    select updated_at into version from public.staff where id = manager_staff;
    begin
      perform public.update_staff_access(manager_staff, 'reception', false, version - interval '1 second');
      raise exception 'FAIL: stale staff access version';
    exception when serialization_failure then null; end;
    result := public.update_staff_access(manager_staff, 'reception', false, version);
    if result->>'role' <> 'reception' or (result->>'active')::boolean then raise exception 'FAIL: staff access update'; end if;
    begin
      update public.staff set active = false where id = owner_staff;
      raise exception 'FAIL: owner deactivated own access';
    exception when insufficient_privilege then null; end;
    begin
      update public.staff set role = 'owner' where id = manager_staff;
      raise exception 'FAIL: direct owner promotion';
    exception when insufficient_privilege then null; end;
    update public.staff set full_name = 'SQL owner renamed' where id = owner_staff;
end $$;

select set_config('request.jwt.claim.sub', current_setting('gymdesk.settings_manager'), true);
do $$
declare gym uuid := current_setting('gymdesk.settings_gym')::uuid;
begin
    begin
      perform public.sync_branding(gen_random_uuid(), 'gyms', jsonb_build_object('id', gym, 'name', 'Blocked', 'accent_color', '#000000',
        'timezone', 'America/Port-au-Prince', 'currency', 'HTG', 'settings', '{}'::jsonb), now(), now());
      raise exception 'FAIL: manager changed branding';
    exception when insufficient_privilege then null; end;
    begin
      insert into storage.objects(bucket_id, name) values('gym-assets', gym::text || '/logos/manager.png');
      raise exception 'FAIL: manager wrote gym asset';
    exception when insufficient_privilege then null; end;
    begin
      perform public.update_staff_access(gen_random_uuid(), 'reception', true, now());
      raise exception 'FAIL: manager changed staff access';
    exception when insufficient_privilege then null; end;
end $$;

reset role;
select 'GymDesk settings and staff assertions completed; fixtures rolled back.' as result;
rollback;
