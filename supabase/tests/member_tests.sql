begin;

-- Fixtures are created as the migration role, then every assertion that matters
-- runs as authenticated staff through RLS.
do $$
declare
    gym uuid := gen_random_uuid(); other uuid := gen_random_uuid();
    owner_user uuid := gen_random_uuid(); reception_user uuid := gen_random_uuid();
    owner_staff uuid := gen_random_uuid(); reception_staff uuid := gen_random_uuid();
    member uuid := gen_random_uuid(); other_member uuid := gen_random_uuid();
    plan uuid := gen_random_uuid(); subscription uuid := gen_random_uuid();
begin
    insert into auth.users(id, email, aud, role) values
      (owner_user, owner_user::text || '@example.invalid', 'authenticated', 'authenticated'),
      (reception_user, reception_user::text || '@example.invalid', 'authenticated', 'authenticated');
    insert into public.gyms(id, code, name, timezone, settings) values
      (gym, 'MBR', 'Member SQL', 'America/Port-au-Prince', '{"grace_days": 0, "allow_access_pending": false}'::jsonb),
      (other, 'OTH', 'Other SQL', 'America/Port-au-Prince', '{}'::jsonb);
    insert into public.staff(id, user_id, gym_id, role, full_name) values
      (owner_staff, owner_user, gym, 'owner', 'Owner SQL'),
      (reception_staff, reception_user, gym, 'reception', 'Reception SQL');
    insert into public.plans(id, gym_id, name, duration_days, price) values(plan, gym, 'Monthly', 30, 1000);
    insert into public.members(id, gym_id, member_number, qr_token, first_name, last_name) values
      (member, gym, 'MBR-000001', 'token-' || member::text, 'Marie', 'Jean'),
      (other_member, other, 'OTH-000001', 'token-' || other_member::text, 'Other', 'Member');
    insert into public.subscriptions(id, gym_id, member_id, plan_id, start_date, end_date, price, status, created_by) values
      (subscription, gym, member, plan, '2026-01-01', '2026-01-31', 1000, 'active', owner_staff);
    perform set_config('gymdesk.member_gym', gym::text, true);
    perform set_config('gymdesk.member_other_member', other_member::text, true);
    perform set_config('gymdesk.member_owner_user', owner_user::text, true);
    perform set_config('gymdesk.member_owner_staff', owner_staff::text, true);
    perform set_config('gymdesk.member_reception_user', reception_user::text, true);
    perform set_config('gymdesk.member_reception_staff', reception_staff::text, true);
    perform set_config('gymdesk.member_member', member::text, true);
    perform set_config('gymdesk.member_plan', plan::text, true);
    perform set_config('gymdesk.member_subscription', subscription::text, true);
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('gymdesk.member_reception_user'), true);

do $$
declare
    gym uuid := current_setting('gymdesk.member_gym')::uuid;
    member uuid := current_setting('gymdesk.member_member')::uuid;
    plan uuid := current_setting('gymdesk.member_plan')::uuid;
    subscription uuid := current_setting('gymdesk.member_subscription')::uuid;
    reception_staff uuid := current_setting('gymdesk.member_reception_staff')::uuid;
    validity record; payment uuid := gen_random_uuid();
begin
    if exists(select 1 from public.members where gym_id <> gym) then raise exception 'FAIL: cross-gym member visible'; end if;

    begin
        insert into public.plans(id, gym_id, name, duration_days, price) values(gen_random_uuid(), gym, 'Forbidden', 7, 100);
        raise exception 'FAIL: reception created plan';
    exception when insufficient_privilege then null; end;

    insert into public.payments(id, gym_id, member_id, subscription_id, amount, currency, method, paid_at, received_by)
    values(payment, gym, member, subscription, 1000, 'HTG', 'cash', now(), reception_staff);
    if not exists(select 1 from public.payments where id = payment) then raise exception 'FAIL: reception payment hidden'; end if;

    insert into public.payments(id, gym_id, member_id, subscription_id, amount, currency, method, paid_at, received_by)
    values(gen_random_uuid(), gym, member, subscription, 1, 'HTG', 'other', now(), current_setting('gymdesk.member_owner_staff')::uuid);
    if (select count(*) from public.payments where member_id = member) <> 1 then raise exception 'FAIL: reception saw another staff payment'; end if;

    begin
        insert into public.members(id, gym_id, member_number, qr_token, first_name, last_name, nif) values
          (gen_random_uuid(), gym, 'MBR-000002', gen_qr_token(), 'Other', 'Member', '1234567890'),
          (gen_random_uuid(), gym, 'MBR-000003', gen_qr_token(), 'Duplicate', 'Nif', '1234567890');
        raise exception 'FAIL: duplicate NIF accepted';
    exception when unique_violation then null; end;

    select * into validity from public.member_validity(member, '2026-01-15 12:00+00');
    if not validity.valid or validity.reason <> 'ok' then raise exception 'FAIL: active member validity'; end if;
    begin
        update public.subscriptions set status = 'cancelled' where id = subscription;
        raise exception 'FAIL: reception cancelled subscription';
    exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub', current_setting('gymdesk.member_owner_user'), true);
do $$
declare
    gym uuid := current_setting('gymdesk.member_gym')::uuid;
    member uuid := current_setting('gymdesk.member_member')::uuid;
    subscription uuid := current_setting('gymdesk.member_subscription')::uuid;
    owner_staff uuid := current_setting('gymdesk.member_owner_staff')::uuid;
    validity record;
begin
    update public.subscriptions set status = 'cancelled' where id = subscription;
    select * into validity from public.member_validity(member, '2026-01-15 12:00+00');
    if validity.valid or validity.reason <> 'no_subscription' then raise exception 'FAIL: cancelled subscription still grants access'; end if;

    insert into public.plans(id, gym_id, name, duration_days, price) values(gen_random_uuid(), gym, 'Quarterly', 90, 2500);
    insert into public.members(id, gym_id, member_number, qr_token, first_name, last_name, status) values
      (gen_random_uuid(), gym, 'MBR-ARCH', gen_qr_token(), 'Archived', 'Member', 'archived');
end $$;

reset role;
select 'GymDesk member, subscription and payment assertions completed; fixtures rolled back.' as result;
rollback;
