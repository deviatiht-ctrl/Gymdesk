begin;

do $$
declare
  gym uuid := gen_random_uuid(); owner_user uuid := gen_random_uuid(); owner_staff uuid := gen_random_uuid();
  admin_user uuid := gen_random_uuid(); admin_staff uuid := gen_random_uuid();
  member uuid := gen_random_uuid(); quiet uuid := gen_random_uuid(); plan uuid := gen_random_uuid();
  sub uuid := gen_random_uuid(); v_today date := (clock_timestamp() at time zone 'America/Port-au-Prince')::date;
  v_payload jsonb; v_count int;
begin
  if exists(select 1 from public.email_outbox) then raise exception 'Run only on an empty disposable test database'; end if;
  insert into auth.users(id, email, aud, role) values
    (owner_user, 'owner@example.invalid', 'authenticated', 'authenticated'),
    (admin_user, 'admin@example.invalid', 'authenticated', 'authenticated');
  insert into public.gyms(id, code, name, timezone, currency, logo_url, status)
    values(gym, 'FIX', 'Fix Gym', 'America/Port-au-Prince', 'HTG', gym || '/logos/logo.png', 'active');
  insert into public.staff(id, user_id, gym_id, role, full_name) values
    (owner_staff, owner_user, gym, 'owner', 'Owner'), (admin_staff, admin_user, null, 'super_admin', 'Admin');
  perform set_config('request.jwt.claim.sub', owner_user::text, true);
  insert into public.plans(id, gym_id, name, duration_days, price) values(plan, gym, 'Mensuel', 30, 1500);
  insert into public.members(id, gym_id, member_number, first_name, last_name, email) values
    (member, gym, '01', 'Marie', 'Jean', 'Marie@Example.invalid'),
    (quiet, gym, '02', 'No', 'Mail', 'quiet@example.invalid');
  update public.members set marketing_opt_out = true where id = quiet;

  -- Welcome: logo_path + reply_to fallback to the owner's login email
  insert into public.subscriptions(id, gym_id, member_id, plan_id, start_date, end_date, price, status)
    values(sub, gym, member, plan, v_today - 27, v_today + 3, 1500, 'active');
  select payload into v_payload from public.email_outbox where kind = 'member_welcome';
  if v_payload is null then raise exception 'FAIL welcome not queued'; end if;
  if v_payload->>'logo_path' <> gym || '/logos/logo.png' then raise exception 'FAIL logo_path %', v_payload; end if;
  if v_payload->>'reply_to' <> 'owner@example.invalid' then raise exception 'FAIL owner reply_to %', v_payload; end if;
  if (select recipient from public.email_outbox where kind = 'member_welcome') <> 'marie@example.invalid' then raise exception 'FAIL recipient normalised'; end if;

  -- The gym email takes precedence as Reply-To
  update public.gyms set email = 'Contact@FixGym.invalid' where id = gym;
  if public.gym_reply_to(gym) <> 'contact@fixgym.invalid' then raise exception 'FAIL gym reply_to'; end if;

  -- Reminders: J-3 is queued once, idempotent
  perform public.process_daily_reminders();
  perform public.process_daily_reminders();
  if (select count(*) from public.email_outbox where kind = 'renewal_reminder') <> 1 then raise exception 'FAIL reminder count'; end if;
  if (select (payload->>'days_left')::int from public.email_outbox where kind = 'renewal_reminder') <> 3 then raise exception 'FAIL reminder days'; end if;
  if (select (payload->>'renewal_price')::numeric from public.email_outbox where kind = 'renewal_reminder') <> 1500 then raise exception 'FAIL reminder price'; end if;
  -- Already renewed members are skipped
  delete from public.email_outbox where kind = 'renewal_reminder';
  insert into public.subscriptions(gym_id, member_id, plan_id, start_date, end_date, price, status, enrollment_kind, renewed_from)
    values(gym, member, plan, v_today + 4, v_today + 33, 1500, 'active', 'renewal', sub);
  perform public.process_daily_reminders();
  if exists(select 1 from public.email_outbox where kind = 'renewal_reminder') then raise exception 'FAIL renewed member reminded'; end if;

  -- Campaigns: personalised, opt-out respected, tenant-scoped
  execute 'set local role authenticated';
  v_count := public.campaign_send_members('Info {gym}', 'Nouveauté chez {gym}', 'Bonjour {nom},' || chr(10) || 'À bientôt', 'inactive_winback', array[member, quiet, gen_random_uuid()]);
  if v_count <> 1 then raise exception 'FAIL campaign count %', v_count; end if;
  execute 'reset role';
  select payload into v_payload from public.email_outbox where kind = 'campaign';
  if v_payload->>'subject' <> 'Nouveauté chez Fix Gym' or v_payload->>'body_text' not like 'Bonjour Marie Jean,%' then raise exception 'FAIL campaign personalisation %', v_payload; end if;
  if v_payload->>'reply_to' <> 'contact@fixgym.invalid' then raise exception 'FAIL campaign reply_to'; end if;
  if (select recipient_count from public.campaigns) <> 1 then raise exception 'FAIL campaign history'; end if;

  -- Provider configuration: invisible to gym staff, writable by super admin only
  execute 'set local role authenticated';
  begin
    perform public.platform_email_config_set('noreply@gymdesk.invalid', 'GymDesk', 300, 'xkeysib-owner-should-not-write-this');
    raise exception 'FAIL owner changed provider config';
  exception when insufficient_privilege then null; end;
  begin
    perform * from public.platform_email_config;
    raise exception 'FAIL owner read provider config';
  exception when insufficient_privilege then null; end;
  begin
    perform public.email_worker_config();
    raise exception 'FAIL owner read worker config';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub', admin_user::text, true);
  perform public.platform_email_config_set('NoReply@GymDesk.invalid', 'GymDesk', 500, 'xkeysib-0123456789abcdef-test');
  perform public.platform_email_config_set('noreply@gymdesk.invalid', 'GymDesk', 500, '');
  v_payload := public.platform_email_config_get();
  if not (v_payload->>'has_key')::boolean or v_payload->>'key_hint' <> '••••test' or (v_payload->>'daily_limit')::int <> 500 then raise exception 'FAIL admin config %', v_payload; end if;
  if v_payload::text like '%0123456789abcdef%' then raise exception 'FAIL key leaked to client'; end if;
  execute 'reset role';
  if (public.email_worker_config()->>'api_key') <> 'xkeysib-0123456789abcdef-test' then raise exception 'FAIL key kept when blank'; end if;
end $$;

rollback;
