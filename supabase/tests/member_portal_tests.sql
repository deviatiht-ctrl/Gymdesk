begin;

do $$
declare
  gym uuid := gen_random_uuid(); other_gym uuid := gen_random_uuid();
  owner_user uuid := gen_random_uuid(); owner_staff uuid := gen_random_uuid();
  member_user uuid := gen_random_uuid(); intruder_user uuid := gen_random_uuid();
  applicant_user uuid := gen_random_uuid(); noemail_user uuid := gen_random_uuid();
  member uuid := gen_random_uuid(); member_other uuid := gen_random_uuid();
  member_noemail uuid := gen_random_uuid(); applicant_member uuid := gen_random_uuid();
  plan uuid := gen_random_uuid(); sub uuid := gen_random_uuid(); pay uuid := gen_random_uuid();
  req uuid; v jsonb;
begin
  if exists(select 1 from public.member_accounts) then raise exception 'Run only on an empty disposable test database'; end if;
  insert into auth.users(id, email, aud, role) values
    (owner_user, 'owner@example.invalid', 'authenticated', 'authenticated'),
    (member_user, 'marie@example.invalid', 'authenticated', 'authenticated'),
    (intruder_user, 'intruder@example.invalid', 'authenticated', 'authenticated'),
    (applicant_user, 'new@example.invalid', 'authenticated', 'authenticated'),
    (noemail_user, 'paul@example.invalid', 'authenticated', 'authenticated');
  insert into public.gyms(id, code, name, timezone, currency, status, logo_url)
    values(gym, 'MPG', 'Portal Gym', 'America/Port-au-Prince', 'HTG', 'active', gym::text || '/logo.png'),
          (other_gym, 'OTG', 'Other Gym', 'America/Port-au-Prince', 'HTG', 'active', null);
  insert into public.staff(id, user_id, gym_id, role, full_name) values (owner_staff, owner_user, gym, 'owner', 'Owner');
  insert into public.plans(id, gym_id, name, duration_days, price) values(plan, gym, 'Mensuel', 30, 1500);
  insert into public.members(id, gym_id, member_number, qr_token, first_name, last_name, email, phone, photo_url)
    values(member, gym, 'MPG-1', md5(random()::text) || md5(random()::text), 'Marie', 'Jean', 'Marie@Example.invalid', '+509 3711-2233', gym::text || '/m.jpg'),
          (member_other, other_gym, 'OTG-1', md5(random()::text) || md5(random()::text), 'Marie', 'Jean', 'marie@example.invalid', '37112233', null),
          (member_noemail, gym, 'MPG-2', md5(random()::text) || md5(random()::text), 'Paul', 'Noel', null, '3400 1122', null);
  insert into public.subscriptions(id, gym_id, member_id, plan_id, start_date, end_date, price, status)
    values(sub, gym, member, plan, current_date - 5, current_date + 24, 1500, 'active');
  insert into public.payments(id, gym_id, member_id, subscription_id, amount, currency, method, paid_at)
    values(pay, gym, member, sub, 1000, 'HTG', 'cash', clock_timestamp());
  insert into public.attendance(gym_id, member_id, scanned_at, result)
    values(gym, member, clock_timestamp() - interval '1 day', 'granted'),
          (gym, member, clock_timestamp() - interval '2 days', 'granted'),
          (gym, member, clock_timestamp() - interval '2 days', 'denied_expired');
  insert into storage.objects(bucket_id, name) values('receipts', gym::text || '/receipts/' || pay::text || '.pdf');

  -- Public gym list (anon).
  execute 'set local role anon';
  if jsonb_array_length(public.member_portal_gyms()) <> 2 then raise exception 'FAIL gym list'; end if;
  if (public.member_portal_check(gym, 'marie@example.invalid', '37112233'))->>'status' <> 'ok' then raise exception 'FAIL check ok'; end if;
  if (public.member_portal_check(gym, 'marie@example.invalid', '99999999'))->>'status' <> 'not_found' then raise exception 'FAIL wrong phone accepted'; end if;
  if (public.member_portal_check(gym, 'paul@example.invalid', '34001122'))->>'status' <> 'need_member_number' then raise exception 'FAIL need number'; end if;
  if (public.member_portal_check(gym, 'paul@example.invalid', '34001122', 'mpg-2'))->>'status' <> 'ok' then raise exception 'FAIL number match'; end if;
  if not public.mp_can_read_object('gym-assets', gym::text || '/logo.png') then raise exception 'FAIL public logo'; end if;
  if public.mp_can_read_object('gym-assets', gym::text || '/other.png') then raise exception 'FAIL non-logo readable'; end if;
  begin
    perform public.member_portal_me(gym);
    raise exception 'FAIL anon me';
  exception when insufficient_privilege then null; end;
  execute 'reset role';

  -- Not linked yet: state none, photo/receipt not readable.
  perform set_config('request.jwt.claim.sub', member_user::text, true);
  execute 'set local role authenticated';
  if (public.member_portal_me(gym))->>'state' <> 'none' then raise exception 'FAIL state none'; end if;
  if public.mp_can_read_object('member-photos', gym::text || '/m.jpg') then raise exception 'FAIL photo before link'; end if;
  -- Link with wrong phone fails, right phone works.
  if (public.member_portal_link(gym, '11112222'))->>'status' <> 'not_found' then raise exception 'FAIL link wrong phone'; end if;
  if (public.member_portal_link(gym, '(509) 37-11-22-33'))->>'status' <> 'ok' then raise exception 'FAIL link'; end if;
  v := public.member_portal_me(gym);
  if v->>'state' <> 'member' or v->'member'->>'first_name' <> 'Marie' then raise exception 'FAIL me member %', v; end if;
  if (v->'subscription'->>'days_left')::int <> 24 or v->'subscription'->>'status' <> 'active' then raise exception 'FAIL sub %', v->'subscription'; end if;
  if (v->'subscription'->>'balance')::numeric <> 500 then raise exception 'FAIL balance %', v->'subscription'->>'balance'; end if;
  if (v->'attendance'->>'total')::int <> 2 then raise exception 'FAIL attendance total'; end if;
  if jsonb_array_length(v->'attendance'->'weeks') <> 8 then raise exception 'FAIL weeks'; end if;
  if v->'payments'->0->>'receipt_path' is null then raise exception 'FAIL receipt path'; end if;
  if not public.mp_can_read_object('member-photos', gym::text || '/m.jpg') then raise exception 'FAIL own photo'; end if;
  if not public.mp_can_read_object('receipts', gym::text || '/receipts/' || pay::text || '.pdf') then raise exception 'FAIL own receipt'; end if;
  -- Same email at another gym: not linked there (strict isolation per gym).
  if (public.member_portal_me(other_gym))->>'state' <> 'none' then raise exception 'FAIL cross gym leak'; end if;
  -- Members cannot read staff tables directly.
  if exists(select 1 from public.members) then raise exception 'FAIL member reads members table'; end if;
  if exists(select 1 from public.member_accounts) then raise exception 'FAIL member reads accounts table'; end if;
  -- Renewal request (one pending at a time).
  if (public.member_portal_request_renewal(gym, plan))->>'status' <> 'ok' then raise exception 'FAIL renewal'; end if;
  if (public.member_portal_request_renewal(gym, plan))->>'status' <> 'already_pending' then raise exception 'FAIL renewal dup'; end if;
  if (public.member_portal_me(gym))->'pending_renewal' is null then raise exception 'FAIL pending renewal'; end if;
  execute 'reset role';

  -- Intruder with same phone but other email cannot take the member.
  perform set_config('request.jwt.claim.sub', intruder_user::text, true);
  execute 'set local role authenticated';
  if (public.member_portal_link(gym, '37112233'))->>'status' <> 'not_found' then raise exception 'FAIL intruder link'; end if;
  if public.mp_can_read_object('member-photos', gym::text || '/m.jpg') then raise exception 'FAIL intruder photo'; end if;
  if (public.member_portal_request_renewal(gym, plan))->>'status' <> 'forbidden' then raise exception 'FAIL intruder renewal'; end if;
  execute 'reset role';

  -- Member without email on file links with phone + member number.
  perform set_config('request.jwt.claim.sub', noemail_user::text, true);
  execute 'set local role authenticated';
  if (public.member_portal_link(gym, '34001122'))->>'status' <> 'need_member_number' then raise exception 'FAIL noemail need number'; end if;
  if (public.member_portal_link(gym, '34001122', 'MPG-2'))->>'status' <> 'ok' then raise exception 'FAIL noemail link'; end if;
  execute 'reset role';

  -- Online applicant: submits, attaches account, sees pending, activated once validated.
  execute 'set local role anon';
  req := (public.portal_submit(gym::text, plan, 'Nouvo', 'Manm', '+509 4455 6677', 'new@example.invalid'))->>'request_id';
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', intruder_user::text, true);
  execute 'set local role authenticated';
  if (public.member_portal_attach_request(req))->>'status' <> 'forbidden' then raise exception 'FAIL attach other email'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', applicant_user::text, true);
  execute 'set local role authenticated';
  if (public.member_portal_attach_request(req))->>'status' <> 'ok' then raise exception 'FAIL attach'; end if;
  v := public.member_portal_me(gym);
  if v->>'state' <> 'pending' or v->'request'->>'plan_name' <> 'Mensuel' then raise exception 'FAIL pending state %', v; end if;
  execute 'reset role';
  -- Gym validates: member created (member_id not set on request, as when sync lags).
  insert into public.members(id, gym_id, member_number, qr_token, first_name, last_name, email, phone)
    values(applicant_member, gym, 'MPG-3', md5(random()::text) || md5(random()::text), 'Nouvo', 'Manm', 'new@example.invalid', '44556677');
  update public.portal_requests set status = 'completed' where id = req;
  execute 'set local role authenticated';
  v := public.member_portal_me(gym);
  if v->>'state' <> 'member' or (v->'member'->>'id')::uuid <> applicant_member then raise exception 'FAIL activation %', v; end if;
  execute 'reset role';

  -- Announcements: owner manages, members see active ones.
  perform set_config('request.jwt.claim.sub', owner_user::text, true);
  execute 'set local role authenticated';
  insert into public.gym_announcements(gym_id, title, body, pinned) values (gym, 'Fermé lundi', 'Jour férié', true);
  insert into public.gym_announcements(gym_id, title, active) values (gym, 'Ancien', false);
  begin
    insert into public.gym_announcements(gym_id, title) values (other_gym, 'Hack');
    raise exception 'FAIL cross gym announcement';
  exception when insufficient_privilege then null; end;
  if (select count(*) from public.member_accounts) <> 3 then raise exception 'FAIL staff sees accounts'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', member_user::text, true);
  execute 'set local role authenticated';
  v := public.member_portal_me(gym);
  if jsonb_array_length(v->'announcements') <> 1 or v->'announcements'->0->>'title' <> 'Fermé lundi' then raise exception 'FAIL announcements %', v->'announcements'; end if;
  execute 'reset role';

  raise notice 'member portal tests passed';
end;
$$;

rollback;
