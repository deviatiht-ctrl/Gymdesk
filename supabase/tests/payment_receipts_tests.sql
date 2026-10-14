begin;

do $$
declare
  gym uuid := gen_random_uuid(); other_gym uuid := gen_random_uuid();
  owner_user uuid := gen_random_uuid(); owner_staff uuid := gen_random_uuid();
  recep_user uuid := gen_random_uuid(); recep_staff uuid := gen_random_uuid();
  member uuid := gen_random_uuid(); member_noemail uuid := gen_random_uuid();
  plan uuid := gen_random_uuid(); sub uuid := gen_random_uuid();
  pay uuid := gen_random_uuid(); pay2 uuid := gen_random_uuid();
  v_path text; v_result text; v_payload jsonb;
begin
  if exists(select 1 from public.email_outbox) then raise exception 'Run only on an empty disposable test database'; end if;
  insert into auth.users(id, email, aud, role) values
    (owner_user, 'owner@example.invalid', 'authenticated', 'authenticated'),
    (recep_user, 'recep@example.invalid', 'authenticated', 'authenticated');
  insert into public.gyms(id, code, name, timezone, currency, status, settings)
    values(gym, 'RCT', 'Receipt Gym', 'America/Port-au-Prince', 'HTG', 'active', '{"member_language":"ht"}'::jsonb),
          (other_gym, 'OTH', 'Other Gym', 'America/Port-au-Prince', 'HTG', 'active', '{}'::jsonb);
  insert into public.staff(id, user_id, gym_id, role, full_name) values
    (owner_staff, owner_user, gym, 'owner', 'Owner'), (recep_staff, recep_user, gym, 'reception', 'Recep');
  insert into public.plans(id, gym_id, name, duration_days, price) values(plan, gym, 'Mensuel', 30, 1500);
  insert into public.members(id, gym_id, member_number, first_name, last_name, email)
    values(member, gym, '01', 'Marie', 'Jean', 'marie@example.invalid'),
          (member_noemail, gym, '02', 'No', 'Email', null);
  insert into public.subscriptions(id, gym_id, member_id, plan_id, start_date, end_date, price, status)
    values(sub, gym, member, plan, current_date, current_date + 30, 1500, 'active');

  -- New columns: member credit + cash received / credited amounts.
  insert into public.payments(id, gym_id, member_id, subscription_id, amount, currency, method, received_amount, credit_amount, credit_used, paid_at)
    values(pay, gym, member, sub, 1500, 'HTG', 'cash', 2000, 500, 0, clock_timestamp());
  if (select credit_amount from public.payments where id = pay) <> 500
     or (select received_amount from public.payments where id = pay) <> 2000 then
    raise exception 'FAIL payment credit columns';
  end if;
  -- 'credit' is now a valid method; a bogus method is still refused.
  insert into public.payments(id, gym_id, member_id, amount, currency, method, credit_used, paid_at)
    values(pay2, gym, member_noemail, 500, 'HTG', 'credit', 500, clock_timestamp());
  begin
    insert into public.payments(id, gym_id, member_id, amount, currency, method, paid_at)
      values(gen_random_uuid(), gym, member, 10, 'HTG', 'bitcoin', clock_timestamp());
    raise exception 'FAIL bogus method accepted';
  exception when check_violation then null; end;
  -- credit_balance cannot go negative.
  begin
    update public.members set credit_balance = -1 where id = member;
    raise exception 'FAIL negative credit_balance accepted';
  exception when check_violation then null; end;
  update public.members set credit_balance = 500 where id = member;

  -- Bucket created privately.
  if not exists(select 1 from storage.buckets where id = 'receipts' and public = false) then
    raise exception 'FAIL receipts bucket';
  end if;

  -- enqueue_payment_receipt: the PDF must exist in storage first.
  perform set_config('request.jwt.claim.sub', owner_user::text, true);
  execute 'set local role authenticated';
  v_path := gym::text || '/receipts/' || pay::text || '.pdf';
  begin
    perform public.enqueue_payment_receipt(pay, v_path);
    raise exception 'FAIL enqueue without storage object';
  exception when invalid_parameter_value then
    if sqlerrm <> 'invalid_receipt' then raise; end if; end;
  insert into storage.objects(bucket_id, name) values('receipts', v_path);

  v_result := public.enqueue_payment_receipt(pay, v_path);
  if v_result <> 'queued' then raise exception 'FAIL enqueue %', v_result; end if;
  execute 'reset role';
  select payload into v_payload from public.email_outbox where event_key = 'payment_receipt:' || pay::text;
  if v_payload is null then raise exception 'FAIL outbox row'; end if;
  if (select kind from public.email_outbox where event_key = 'payment_receipt:' || pay::text) <> 'payment_receipt' then
    raise exception 'FAIL kind';
  end if;
  if v_payload->>'receipt_path' <> v_path
     or (v_payload->>'received_amount')::numeric <> 2000
     or (v_payload->>'credit_amount')::numeric <> 500
     or (v_payload->>'credit_balance')::numeric <> 500
     or v_payload->>'language' <> 'ht'
     or v_payload->>'receipt_no' is null then
    raise exception 'FAIL payload %', v_payload;
  end if;
  -- Idempotent per payment.
  execute 'set local role authenticated';
  v_result := public.enqueue_payment_receipt(pay, v_path);
  if v_result <> 'already_queued' then raise exception 'FAIL idempotent %', v_result; end if;

  -- Member without email -> 'no_email', nothing queued.
  insert into storage.objects(bucket_id, name) values('receipts', gym::text || '/receipts/' || pay2::text || '.pdf');
  v_result := public.enqueue_payment_receipt(pay2, gym::text || '/receipts/' || pay2::text || '.pdf');
  if v_result <> 'no_email' then raise exception 'FAIL no_email %', v_result; end if;
  execute 'reset role';
  if (select count(*) from public.email_outbox where kind = 'payment_receipt') <> 1 then
    raise exception 'FAIL receipt outbox count %', (select count(*) from public.email_outbox);
  end if;

  -- Path outside the gym folder is rejected.
  execute 'set local role authenticated';
  begin
    perform public.enqueue_payment_receipt(pay, other_gym::text || '/receipts/' || pay::text || '.pdf');
    raise exception 'FAIL cross-tenant receipt path';
  exception when invalid_parameter_value then
    if sqlerrm <> 'invalid_record' then raise; end if; end;

  -- Cash register: open + close must not trip the audit whitelist.
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', owner_user::text, true);
  execute 'set local role authenticated';
  v_payload := public.open_cash_session(5000);
  v_payload := public.close_cash_session((v_payload->>'id')::uuid, 5000, 'test close');
  if v_payload->>'status' <> 'closed' then raise exception 'FAIL cash close %', v_payload; end if;
  execute 'reset role';
  if not exists(select 1 from public.audit_log where action = 'cash_session_closed') then
    raise exception 'FAIL cash_session_closed audit';
  end if;
  execute 'set local role authenticated';

  -- Reception can enqueue, but an unknown role cannot.
  perform set_config('request.jwt.claim.sub', recep_user::text, true);
  v_result := public.enqueue_payment_receipt(pay, v_path);
  if v_result <> 'already_queued' then raise exception 'FAIL reception enqueue %', v_result; end if;
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  begin
    perform public.enqueue_payment_receipt(pay, v_path);
    raise exception 'FAIL non-staff enqueue';
  exception when insufficient_privilege then null; end;
  execute 'reset role';
end $$;

rollback;
