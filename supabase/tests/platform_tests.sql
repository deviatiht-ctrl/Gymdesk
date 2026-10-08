begin;

do $$
declare actor uuid := gen_random_uuid(); owner_user uuid := gen_random_uuid();
    request_id uuid := gen_random_uuid(); gym uuid := gen_random_uuid(); owner_staff uuid := gen_random_uuid();
    payload jsonb; gym_code text; created jsonb; replay jsonb;
begin
    loop
        gym_code := translate(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4), '0123456789abcdef', 'ABCDEFGHIJKLMNOP');
        exit when not exists(select 1 from public.gyms where code = gym_code)
          and not exists(select 1 from public.gym_provisioning gp where gp.payload->'gym'->>'code' = gym_code);
    end loop;
    insert into auth.users(id, email, aud, role) values(actor, actor::text || '@example.invalid', 'authenticated', 'authenticated');
    insert into public.staff(id, user_id, role, full_name) values(gen_random_uuid(), actor, 'super_admin', 'SQL platform');
    payload := jsonb_build_object('gym', jsonb_build_object('name','SQL Gym', 'code',gym_code, 'accent_color','#1F6F4A', 'timezone','America/Port-au-Prince', 'currency','HTG'),
      'owner_email', owner_user::text || '@example.invalid', 'owner_name', 'SQL Owner');
    perform public.provision_gym_begin(request_id, actor, gym, owner_staff, payload);
    if exists(select 1 from public.gyms where id = gym) then raise exception 'FAIL: gym created before Auth'; end if;
    insert into auth.users(id, email, aud, role, raw_app_meta_data)
    values(owner_user, owner_user::text || '@example.invalid', 'authenticated', 'authenticated', jsonb_build_object('gymdesk_provision_request', request_id));
    if public.provision_gym_auth_user(request_id, actor) is distinct from owner_user then raise exception 'FAIL: Auth recovery'; end if;
    created := public.provision_gym_finish(request_id, actor, owner_user);
    replay := public.provision_gym_finish(request_id, actor, owner_user);
    if created <> replay then raise exception 'FAIL: provisioning replay'; end if;
    if (select count(*) from public.staff where gym_id = gym and role = 'owner') <> 1 then raise exception 'FAIL: duplicate owner'; end if;
    if (select count(*) from public.audit_log where entity_id = gym and action = 'create') <> 1 then raise exception 'FAIL: duplicate audit'; end if;
    begin
      perform public.provision_gym_begin(request_id, actor, gym, owner_staff, jsonb_set(payload, '{owner_name}', '"Changed"'::jsonb));
      raise exception 'FAIL: mutable provisioning request';
    exception when sqlstate '22023' then null; end;
    perform set_config('gymdesk.platform_actor', actor::text, true);
    perform set_config('gymdesk.platform_owner', owner_user::text, true);
    perform set_config('gymdesk.platform_gym', gym::text, true);
    perform set_config('gymdesk.platform_request', request_id::text, true);
    perform set_config('gymdesk.platform_code', gym_code, true);
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('gymdesk.platform_owner'), true);
do $$
declare gym uuid := current_setting('gymdesk.platform_gym')::uuid;
begin
    begin
      perform public.platform_statistics();
      raise exception 'FAIL: owner can read platform statistics';
    exception when insufficient_privilege then null; end;
    begin
      perform public.platform_change_gym(gym, 'suspend', now());
      raise exception 'FAIL: owner can suspend tenant';
    exception when insufficient_privilege then null; end;
    begin
      update public.gyms set deleted_at = now() where id = gym;
      raise exception 'FAIL: owner can archive tenant';
    exception when insufficient_privilege then null; end;
    begin
      perform public.provision_gym_auth_user(current_setting('gymdesk.platform_request')::uuid, current_setting('gymdesk.platform_actor')::uuid);
      raise exception 'FAIL: provisioning RPC publicly executable';
    exception when insufficient_privilege then null; end;
    begin
      perform id from public.gym_provisioning;
      raise exception 'FAIL: provisioning table publicly readable';
    exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub', current_setting('gymdesk.platform_actor'), true);
do $$
declare gym uuid := current_setting('gymdesk.platform_gym')::uuid; version timestamptz; result jsonb;
begin
    result := public.platform_statistics();
    if not (result ?& array['gyms','active_gyms','members','entries_today']) or (select count(*) from jsonb_object_keys(result)) <> 4 then
        raise exception 'FAIL: unexpected statistics shape';
    end if;
    if exists(select 1 from public.members) then raise exception 'FAIL: platform can read members'; end if;
    select updated_at into version from public.gyms where id = gym;
    begin
      perform public.platform_change_gym(gym, 'suspend', version - interval '1 second');
      raise exception 'FAIL: stale version accepted';
    exception when serialization_failure then null; end;
    result := public.platform_change_gym(gym, 'suspend', version);
    if result->>'status' <> 'suspended' then raise exception 'FAIL: suspension'; end if;
    result := public.platform_change_gym(gym, 'reactivate', (result->>'updated_at')::timestamptz);
    if result->>'status' <> 'active' then raise exception 'FAIL: reactivation'; end if;
    begin
      perform public.platform_change_gym(gym, 'archive', (result->>'updated_at')::timestamptz, 'WRONG');
      raise exception 'FAIL: archive without code';
    exception when sqlstate '22023' then null; end;
    result := public.platform_change_gym(gym, 'archive', (result->>'updated_at')::timestamptz, current_setting('gymdesk.platform_code'));
    if result->>'deleted_at' is null or result->>'status' <> 'suspended' then raise exception 'FAIL: archive'; end if;
    if not exists(select 1 from public.gyms where id = gym) then raise exception 'FAIL: physical deletion'; end if;
end $$;

select set_config('request.jwt.claim.sub', current_setting('gymdesk.platform_owner'), true);
do $$ begin
    if public.current_gym_id() is not null then raise exception 'FAIL: archived gym remains accessible'; end if;
end $$;

reset role;
select 'GymDesk platform assertions completed; fixtures rolled back.' as result;
rollback;
