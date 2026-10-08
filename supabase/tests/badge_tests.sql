begin;

do $$
declare
    gym uuid := gen_random_uuid(); owner_user uuid := gen_random_uuid(); manager_user uuid := gen_random_uuid(); reception_user uuid := gen_random_uuid();
begin
    insert into auth.users(id, email, aud, role) values
      (owner_user, owner_user::text || '@example.invalid', 'authenticated', 'authenticated'),
      (manager_user, manager_user::text || '@example.invalid', 'authenticated', 'authenticated'),
      (reception_user, reception_user::text || '@example.invalid', 'authenticated', 'authenticated');
    insert into public.gyms(id, code, name) values(gym, 'BDG', 'Badge SQL');
    insert into public.staff(user_id, gym_id, role, full_name) values
      (owner_user, gym, 'owner', 'Owner SQL'), (manager_user, gym, 'manager', 'Manager SQL'), (reception_user, gym, 'reception', 'Reception SQL');
    perform set_config('gymdesk.badge_gym', gym::text, true);
    perform set_config('gymdesk.badge_owner_user', owner_user::text, true);
    perform set_config('gymdesk.badge_manager_user', manager_user::text, true);
    perform set_config('gymdesk.badge_reception_user', reception_user::text, true);
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('gymdesk.badge_manager_user'), true);

do $$
declare
    gym uuid := current_setting('gymdesk.badge_gym')::uuid;
    first uuid := gen_random_uuid(); second uuid := gen_random_uuid();
begin
    insert into public.badge_templates(id, gym_id, name, layout, is_default) values(first, gym, 'Standard', '{}'::jsonb, true);
    begin
      insert into public.badge_templates(id, gym_id, name, layout, is_default) values(second, gym, 'Vertical', '{}'::jsonb, true);
      raise exception 'FAIL: second default accepted';
    exception when unique_violation then null; end;
    update public.badge_templates set is_default = false where id = first;
    insert into public.badge_templates(id, gym_id, name, layout, is_default) values(second, gym, 'Vertical', '{}'::jsonb, true);
end $$;

select set_config('request.jwt.claim.sub', current_setting('gymdesk.badge_reception_user'), true);
do $$
declare gym uuid := current_setting('gymdesk.badge_gym')::uuid;
begin
    if (select count(*) from public.badge_templates where gym_id = gym) <> 2 then raise exception 'FAIL: reception cannot read templates'; end if;
    begin
      insert into public.badge_templates(gym_id, name, layout) values(gym, 'Reception', '{}'::jsonb);
      raise exception 'FAIL: reception insert accepted';
    exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub', current_setting('gymdesk.badge_owner_user'), true);
do $$
declare gym uuid := current_setting('gymdesk.badge_gym')::uuid;
begin
    update public.badge_templates set deleted_at = now() where gym_id = gym and is_default;
end $$;

reset role;
select 'GymDesk badge assertions completed; fixtures rolled back.' as result;
rollback;
