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
    values(sub, gym, member, plan, public.mp_today(gym) - 5, public.mp_today(gym) + 24, 1500, 'active');
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
  -- Messagerie : le membre écrit au gym, relit sa conversation.
  if (public.member_portal_send_message(gym, '  '))->>'status' <> 'invalid' then raise exception 'FAIL empty message'; end if;
  if (public.member_portal_send_message(gym, 'Bonjour, la salle ouvre à quelle heure demain ?'))->>'status' <> 'ok' then raise exception 'FAIL send message'; end if;
  v := public.member_portal_messages(gym);
  if jsonb_array_length(v) <> 1 or v->0->>'sender' <> 'member' then raise exception 'FAIL messages %', v; end if;
  -- Le membre voit sa conversation via la policy (direct + realtime).
  if (select count(*) from public.member_messages) <> 1 then raise exception 'FAIL member reads own messages'; end if;
  -- Profil : champs autorisés seulement, date/email validés, photo contrôlée.
  if (public.member_portal_update_profile(gym, jsonb_build_object('role', 'x')))->>'status' <> 'invalid' then raise exception 'FAIL patch whitelist'; end if;
  if (public.member_portal_update_profile(gym, jsonb_build_object('birth_date', 'pas-une-date')))->>'status' <> 'invalid' then raise exception 'FAIL bad birth_date'; end if;
  if (public.member_portal_update_profile(gym, jsonb_build_object('email', 'nope')))->>'status' <> 'invalid' then raise exception 'FAIL bad email'; end if;
  if (public.member_portal_update_profile(gym, jsonb_build_object('photo_url', other_gym::text || '/' || member::text || '/x.jpg')))->>'status' <> 'invalid' then raise exception 'FAIL foreign photo'; end if;
  v := public.member_portal_update_profile(gym, jsonb_build_object(
        'phone', '+509 9999 0000', 'birth_date', '1995-04-12', 'sex', 'female',
        'emergency_contact_name', 'Maman', 'photo_url', gym::text || '/' || member::text || '/abcd1234.jpg'));
  if v->>'status' <> 'ok' then raise exception 'FAIL update profile %', v; end if;
  v := public.member_portal_me(gym);
  if v->'member'->>'phone' <> '+509 9999 0000' or v->'member'->>'birth_date' <> '1995-04-12'
     or v->'member'->>'sex' <> 'female' or v->'member'->>'emergency_contact_name' <> 'Maman'
     or v->'member'->>'photo_url' <> gym::text || '/' || member::text || '/abcd1234.jpg' then
    raise exception 'FAIL profile fields %', v->'member';
  end if;
  -- Upload photo : seulement dans le dossier du membre lié.
  if not public.mp_can_write_photo(gym::text || '/' || member::text || '/p1.jpg') then raise exception 'FAIL own photo write'; end if;
  if public.mp_can_write_photo(gym::text || '/' || member_noemail::text || '/p1.jpg') then raise exception 'FAIL other member photo write'; end if;
  if public.mp_can_write_photo(other_gym::text || '/' || member::text || '/p1.jpg') then raise exception 'FAIL other gym photo write'; end if;
  execute 'reset role';

  -- Intruder with same phone but other email cannot take the member.
  perform set_config('request.jwt.claim.sub', intruder_user::text, true);
  execute 'set local role authenticated';
  if (public.member_portal_link(gym, '37112233'))->>'status' <> 'not_found' then raise exception 'FAIL intruder link'; end if;
  if public.mp_can_read_object('member-photos', gym::text || '/m.jpg') then raise exception 'FAIL intruder photo'; end if;
  if (public.member_portal_request_renewal(gym, plan))->>'status' <> 'forbidden' then raise exception 'FAIL intruder renewal'; end if;
  if (public.member_portal_send_message(gym, 'hack'))->>'status' <> 'forbidden' then raise exception 'FAIL intruder send'; end if;
  if jsonb_array_length(public.member_portal_messages(gym)) <> 0 then raise exception 'FAIL intruder messages'; end if;
  if (select count(*) from public.member_messages) <> 0 then raise exception 'FAIL intruder reads messages'; end if;
  if (public.member_portal_update_profile(gym, jsonb_build_object('phone', '1')))->>'status' <> 'forbidden' then raise exception 'FAIL intruder profile'; end if;
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
  -- Messagerie côté accueil : inbox, réponse, accusé de lecture.
  if (select count(*) from public.member_messages where gym_id = gym and sender = 'member' and read_by_gym_at is null) <> 1 then
    raise exception 'FAIL staff inbox';
  end if;
  insert into public.member_messages(gym_id, member_id, sender, body, read_by_gym_at)
  values (gym, member, 'gym', 'Nous ouvrons à 6h demain.', clock_timestamp());
  update public.member_messages set read_by_gym_at = clock_timestamp()
  where gym_id = gym and sender = 'member' and read_by_gym_at is null;
  begin
    insert into public.member_messages(gym_id, member_id, sender, body)
    values (other_gym, member_other, 'gym', 'Hack');
    raise exception 'FAIL cross gym message';
  exception when insufficient_privilege then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', member_user::text, true);
  execute 'set local role authenticated';
  v := public.member_portal_messages(gym);
  if jsonb_array_length(v) <> 2 or v->1->>'sender' <> 'gym' or v->1->>'read_by_member_at' is null then
    raise exception 'FAIL gym reply read %', v;
  end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', owner_user::text, true);
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', member_user::text, true);
  execute 'set local role authenticated';
  v := public.member_portal_me(gym);
  if jsonb_array_length(v->'announcements') <> 1 or v->'announcements'->0->>'title' <> 'Fermé lundi' then raise exception 'FAIL announcements %', v->'announcements'; end if;
  -- Generic member login: only the gyms of this account.
  v := public.member_portal_my_gyms();
  if jsonb_array_length(v) <> 1 or (v->0->>'id')::uuid <> gym or v->0->>'state' <> 'member' then raise exception 'FAIL my gyms %', v; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', intruder_user::text, true);
  execute 'set local role authenticated';
  if jsonb_array_length(public.member_portal_my_gyms()) <> 0 then raise exception 'FAIL intruder my gyms'; end if;
  execute 'reset role';

  -- sync_branding (migration 35) : biometric_config dans settings, téléphone
  -- long (35+) et logo dans le dossier de la salle acceptés ; logo d'un autre
  -- gym refusé.
  perform set_config('request.jwt.claim.sub', owner_user::text, true);
  execute 'set local role authenticated';
  v := public.sync_branding(gen_random_uuid(), 'gyms',
    jsonb_build_object(
      'id', gym, 'name', 'Portal Gym', 'accent_color', '#112233', 'currency', 'HTG',
      'timezone', 'America/Port-au-Prince',
      'phone', '+509 3711-2233 / +509 4400-5566 (WhatsApp)',
      'logo_url', gym::text || '/logos/' || gen_random_uuid()::text || '.png',
      'settings', jsonb_build_object(
        'biometric_config', jsonb_build_object('mode', 'app_controls_door'),
        'scan_sound', true)),
    clock_timestamp(), (select updated_at from public.gyms where id = gym));
  if v->>'outcome' <> 'accepted' then raise exception 'FAIL branding fix %', v; end if;
  begin
    perform public.sync_branding(gen_random_uuid(), 'gyms',
      jsonb_build_object(
        'id', gym, 'name', 'Portal Gym', 'accent_color', '#112233', 'currency', 'HTG',
        'timezone', 'America/Port-au-Prince', 'phone', '37112233',
        'logo_url', other_gym::text || '/logos/x.png', 'settings', '{}'::jsonb),
      clock_timestamp(), (select updated_at from public.gyms where id = gym));
    raise exception 'FAIL foreign logo accepted';
  exception when invalid_parameter_value then null; end;
  execute 'reset role';

  raise notice 'member portal tests passed';
end;
$$;

rollback;
