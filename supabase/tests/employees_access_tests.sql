begin;

do $$
declare
  gym uuid := gen_random_uuid(); other_gym uuid := gen_random_uuid();
  owner_user uuid := gen_random_uuid(); owner_staff uuid := gen_random_uuid();
  recep_user uuid := gen_random_uuid(); recep_staff uuid := gen_random_uuid();
  member uuid := gen_random_uuid(); plan uuid := gen_random_uuid(); sub uuid := gen_random_uuid();
  emp uuid := gen_random_uuid();
  v_today date := (clock_timestamp() at time zone 'America/Port-au-Prince')::date;
  v_result jsonb; v_rows int;
begin
  if exists(select 1 from public.email_outbox) then raise exception 'Run only on an empty disposable test database'; end if;
  insert into auth.users(id, email, aud, role) values
    (owner_user, 'owner@example.invalid', 'authenticated', 'authenticated'),
    (recep_user, 'recep@example.invalid', 'authenticated', 'authenticated');
  insert into public.gyms(id, code, name, timezone, currency, status, settings)
    values(gym, 'EMP', 'Emp Gym', 'America/Port-au-Prince', 'HTG', 'active', '{"member_language":"ht"}'::jsonb),
          (other_gym, 'OTH', 'Other Gym', 'America/Port-au-Prince', 'HTG', 'active', '{}'::jsonb);
  insert into public.staff(id, user_id, gym_id, role, full_name) values
    (owner_staff, owner_user, gym, 'owner', 'Owner'), (recep_staff, recep_user, gym, 'reception', 'Recep');

  -- Owner creates an employee through the generic sync layer
  perform set_config('request.jwt.claim.sub', owner_user::text, true);
  execute 'set local role authenticated';
  v_result := public.sync_push(gen_random_uuid(), 'employees', jsonb_build_object(
    'id', emp, 'gym_id', gym, 'first_name', 'Jean', 'last_name', 'Coach', 'job_type', 'coach',
    'fingerprint_template', 'AAAA', 'fingerprint_templates', '["AAAA","BBBB"]'::jsonb, 'fingerprint_registered', true),
    clock_timestamp(), null);
  if v_result->>'outcome' <> 'accepted' then raise exception 'FAIL employee push %', v_result; end if;
  if (v_result->'row'->>'job_type') <> 'coach' or jsonb_array_length(v_result->'row'->'fingerprint_templates') <> 2 then
    raise exception 'FAIL employee row %', v_result;
  end if;
  select count(*) into v_rows from public.sync_pull('employees', '1970-01-01', clock_timestamp() + interval '1 minute');
  if v_rows <> 1 then raise exception 'FAIL employee pull %', v_rows; end if;

  -- Cross-tenant writes are refused
  begin
    perform public.sync_push(gen_random_uuid(), 'employees', jsonb_build_object(
      'id', gen_random_uuid(), 'gym_id', other_gym, 'first_name', 'X', 'job_type', 'coach'), clock_timestamp(), null);
    raise exception 'FAIL cross-tenant employee';
  exception when insufficient_privilege then null; end;

  -- Invalid job types are rejected by the table constraint
  begin
    perform public.sync_push(gen_random_uuid(), 'employees', jsonb_build_object(
      'id', gen_random_uuid(), 'gym_id', gym, 'first_name', 'Bad', 'job_type', 'astronaut'), clock_timestamp(), null);
    raise exception 'FAIL invalid job type accepted';
  exception when check_violation then null; end;

  -- Reception reads employees but cannot modify them
  perform set_config('request.jwt.claim.sub', recep_user::text, true);
  select count(*) into v_rows from public.sync_pull('employees', '1970-01-01', clock_timestamp() + interval '1 minute');
  if v_rows <> 1 then raise exception 'FAIL reception read %', v_rows; end if;
  begin
    perform public.sync_push(gen_random_uuid(), 'employees', jsonb_build_object(
      'id', emp, 'gym_id', gym, 'first_name', 'Hacked', 'job_type', 'coach'), clock_timestamp(), null);
    raise exception 'FAIL reception modified employee';
  exception when insufficient_privilege then null; end;
  execute 'reset role';

  -- Reminders J-7, J-2, J0 only (J-3 no longer), with the gym member language
  perform set_config('request.jwt.claim.sub', owner_user::text, true);
  insert into public.plans(id, gym_id, name, duration_days, price) values(plan, gym, 'Mensuel', 30, 1500);
  insert into public.members(id, gym_id, member_number, first_name, last_name, email)
    values(member, gym, '01', 'Marie', 'Jean', 'marie@example.invalid');
  insert into public.subscriptions(id, gym_id, member_id, plan_id, start_date, end_date, price, status)
    values(sub, gym, member, plan, v_today - 27, v_today + 3, 1500, 'active');
  perform public.process_daily_reminders();
  if exists(select 1 from public.email_outbox where kind = 'renewal_reminder') then raise exception 'FAIL J-3 reminder still sent'; end if;
  update public.subscriptions set end_date = v_today + 2 where id = sub;
  perform public.process_daily_reminders();
  perform public.process_daily_reminders();
  if (select count(*) from public.email_outbox where kind = 'renewal_reminder') <> 1 then raise exception 'FAIL J-2 reminder count'; end if;
  if (select payload->>'language' from public.email_outbox where kind = 'renewal_reminder') <> 'ht' then raise exception 'FAIL reminder language'; end if;
  update public.subscriptions set end_date = v_today + 7 where id = sub;
  perform public.process_daily_reminders();
  update public.subscriptions set end_date = v_today where id = sub;
  perform public.process_daily_reminders();
  if (select count(*) from public.email_outbox where kind = 'renewal_reminder') <> 3 then raise exception 'FAIL J-7/J0 reminders'; end if;

  -- The owner saves the member email language from the gym settings page
  execute 'set local role authenticated';
  v_result := public.sync_branding(gen_random_uuid(), 'gyms', jsonb_build_object(
      'id', gym, 'name', 'Emp Gym', 'accent_color', '#0F766E', 'currency', 'HTG',
      'timezone', 'America/Port-au-Prince', 'settings', '{"member_language":"en","grace_days":0}'::jsonb),
    clock_timestamp(), (select updated_at from public.gyms where id = gym));
  if v_result->>'outcome' <> 'accepted' then raise exception 'FAIL branding %', v_result; end if;
  execute 'reset role';
  if public.gym_email_branding(gym)->>'language' <> 'en' then raise exception 'FAIL member_language saved'; end if;
end $$;

rollback;
