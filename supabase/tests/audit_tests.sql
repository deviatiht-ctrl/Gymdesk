begin;

do $$
declare
    gym uuid := gen_random_uuid(); owner_user uuid := gen_random_uuid(); reception_user uuid := gen_random_uuid();
    member uuid := gen_random_uuid();
begin
    insert into auth.users(id, email, aud, role) values
      (owner_user, owner_user::text || '@example.invalid', 'authenticated', 'authenticated'),
      (reception_user, reception_user::text || '@example.invalid', 'authenticated', 'authenticated');
    insert into public.gyms(id, code, name) values(gym, 'AUD', 'Audit SQL');
    insert into public.staff(user_id, gym_id, role, full_name) values
      (owner_user, gym, 'owner', 'Owner SQL'), (reception_user, gym, 'reception', 'Reception SQL');
    insert into public.members(id, gym_id, member_number, qr_token, first_name, last_name)
      values(member, gym, 'AUD-000001', 'audit-token-0000000000000000000000000000', 'Marie', 'Jean');
    perform set_config('gymdesk.audit_gym', gym::text, true);
    perform set_config('gymdesk.audit_member', member::text, true);
    perform set_config('gymdesk.audit_owner_user', owner_user::text, true);
    perform set_config('gymdesk.audit_reception_user', reception_user::text, true);
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('gymdesk.audit_reception_user'), true);
do $$
declare member uuid := current_setting('gymdesk.audit_member')::uuid;
begin
    perform public.audit('export', 'members', member, '{"document":"badge"}'::jsonb);
    begin
      perform public.audit('invented_action', 'members', member);
      raise exception 'FAIL: arbitrary audit action accepted';
    exception when raise_exception then
      if sqlerrm <> 'invalid_audit_event' then raise; end if;
    end;
end $$;

select set_config('request.jwt.claim.sub', current_setting('gymdesk.audit_owner_user'), true);
do $$
declare gym uuid := current_setting('gymdesk.audit_gym')::uuid;
begin
    if not exists(select 1 from public.audit_log where gym_id = gym and action = 'export' and entity = 'members'
      and details->>'document' = 'badge') then raise exception 'FAIL: audit details'; end if;
end $$;

select set_config('request.jwt.claim.sub', current_setting('gymdesk.audit_reception_user'), true);
do $$
begin
    if exists(select 1 from public.audit_log) then raise exception 'FAIL: reception audit read'; end if;
end $$;

reset role;
select 'GymDesk audit assertions completed; fixtures rolled back.' as result;
rollback;
