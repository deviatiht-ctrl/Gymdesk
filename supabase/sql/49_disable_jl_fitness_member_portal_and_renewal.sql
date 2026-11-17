-- ==============================================================================
-- 49_disable_jl_fitness_member_portal_and_renewal.sql
-- Restriksyon Espace Membre & Renouvèlman pou JL FITNESS Sèlman
-- ==============================================================================
-- 1. Retire JL FITNESS nan lis sal pou verifye / espace membre (member_portal_gyms)
-- 2. Bloke rechèch pwofil pa nimewo telefòn pou JL FITNESS (portal_lookup_member)
-- 3. Bloke tout demann renouvèlman pou JL FITNESS (member_portal_request_renewal)
-- 4. Bloke koneksyon telefòn manm pou JL FITNESS (mp_phone_member)
-- 5. Kenbe sal JL FITNESS 100% aktif nan sistèm nan (gyms, staff, kès, pòt, elatriye)
-- ==============================================================================

begin;

-- 1. Mete ajou paramèt JL FITNESS nan gyms: member_portal_enabled = false
update public.gyms
set settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object('member_portal_enabled', false)
where code = 'JLF' 
   or id = '6ed6093d-557d-4bb9-b3ba-f55fedcf65b3'
   or name ilike '%JL FITNESS%';

-- 2. Lis sal piblik yo pou espace membre: ekskli JL FITNESS
create or replace function public.member_portal_gyms()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', g.id,
    'name', g.name,
    'logo_url', g.logo_url,
    'address', g.address,
    'phone', g.phone,
    'accent_color', g.accent_color
  ) order by lower(g.name)), '[]'::jsonb)
  from public.gyms g
  where g.deleted_at is null
    and g.status in ('active', 'trial', 'grace')
    and coalesce((g.settings->>'member_portal_enabled')::boolean, true)
    and g.code <> 'JLF'
    and g.id <> '6ed6093d-557d-4bb9-b3ba-f55fedcf65b3'
    and g.name not ilike '%JL FITNESS%'
$$;

revoke all on function public.member_portal_gyms() from public;
grant execute on function public.member_portal_gyms() to anon, authenticated;

-- 3. Rekipere yon sal espesifik pou espace membre: ekskli JL FITNESS
create or replace function public.member_portal_gym(p_gym uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_gym public.gyms;
begin
  select * into v_gym from public.gyms g
  where g.id = p_gym 
    and g.deleted_at is null 
    and g.status in ('active', 'trial', 'grace')
    and coalesce((g.settings->>'member_portal_enabled')::boolean, true)
    and g.code <> 'JLF'
    and g.id <> '6ed6093d-557d-4bb9-b3ba-f55fedcf65b3'
    and g.name not ilike '%JL FITNESS%';

  if not found then
    return jsonb_build_object('found', false);
  end if;

  return jsonb_build_object(
    'found', true,
    'gym', jsonb_build_object(
      'id', v_gym.id, 'name', v_gym.name, 'logo_url', v_gym.logo_url,
      'address', v_gym.address, 'phone', v_gym.phone, 'email', v_gym.email,
      'accent_color', v_gym.accent_color, 'currency', v_gym.currency)
  );
end;
$$;

revoke all on function public.member_portal_gym(uuid) from public;
grant execute on function public.member_portal_gym(uuid) to anon, authenticated;

-- 4. Rechèch manm pa nimewo telefòn: Bloke pou JL FITNESS (pa montre okenn pwofil)
create or replace function public.portal_lookup_member(
  p_gym_code text,
  p_query text
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym public.gyms;
  v_member public.members;
  v_sub public.subscriptions;
  v_plan public.plans;
  v_clean_query text;
  v_status text := 'none';
  v_days_left int := 0;
begin
  if p_gym_code is null or trim(p_gym_code) = '' then
    raise exception 'invalid_gym' using errcode = '22023';
  end if;

  select * into v_gym from public.gyms
  where (id::text = lower(trim(p_gym_code)) or lower(name) = lower(trim(p_gym_code)) or code = upper(trim(p_gym_code)))
    and status in ('active', 'trial')
  limit 1;

  if not found then
    raise exception 'gym_not_found' using errcode = '22023';
  end if;

  -- SEKIRITE: Pou JL FITNESS, pa janm afiche pwofil manm nan rechèch nimewo
  if v_gym.code = 'JLF' 
     or v_gym.id = '6ed6093d-557d-4bb9-b3ba-f55fedcf65b3'
     or v_gym.name ilike '%JL FITNESS%' then
    return jsonb_build_object('found', false);
  end if;

  if p_query is null or trim(p_query) = '' then
    return jsonb_build_object('found', false);
  end if;

  v_clean_query := trim(p_query);

  select * into v_member from public.members
  where gym_id = v_gym.id
    and deleted_at is null
    and (
      id::text = lower(v_clean_query)
      or regexp_replace(coalesce(phone, ''), '\D', '', 'g') = regexp_replace(v_clean_query, '\D', '', 'g')
      or lower(first_name || ' ' || last_name) = lower(v_clean_query)
    )
  order by created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('found', false);
  end if;

  select * into v_sub from public.subscriptions
  where member_id = v_member.id
    and gym_id = v_gym.id
    and deleted_at is null
  order by end_date desc
  limit 1;

  if found then
    select * into v_plan from public.plans where id = v_sub.plan_id;
    if v_sub.status = 'active' and v_sub.end_date >= current_date then
      v_status := 'active';
      v_days_left := v_sub.end_date - current_date;
    elsif v_sub.status = 'expired' or v_sub.end_date < current_date then
      v_status := 'expired';
      v_days_left := 0;
    else
      v_status := v_sub.status;
    end if;
  end if;

  return jsonb_build_object(
    'found', true,
    'member_id', v_member.id,
    'first_name', v_member.first_name,
    'last_name', v_member.last_name,
    'phone', v_member.phone,
    'email', v_member.email,
    'status', v_status,
    'days_left', v_days_left,
    'current_plan_name', coalesce(v_plan.name, 'Abonnement antérieur'),
    'expiration_date', case when v_sub.end_date is not null then v_sub.end_date::text else null end
  );
end;
$$;

revoke all on function public.portal_lookup_member(text, text) from public, anon, authenticated;
grant execute on function public.portal_lookup_member(text, text) to anon, authenticated;

-- 5. Demann renouvèlman: Bloke pou JL FITNESS
create or replace function public.member_portal_request_renewal(p_gym uuid, p_plan_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_acc public.member_accounts;
  v_member public.members;
  v_req public.portal_requests;
  v_gym public.gyms;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select * into v_gym from public.gyms where id = p_gym;
  if found and (v_gym.code = 'JLF' or v_gym.id = '6ed6093d-557d-4bb9-b3ba-f55fedcf65b3' or v_gym.name ilike '%JL FITNESS%') then
    return jsonb_build_object('status', 'renewal_disabled_for_gym');
  end if;

  select * into v_acc from public.member_accounts ma where ma.user_id = v_uid and ma.gym_id = p_gym;
  if not found then
    return jsonb_build_object('status', 'forbidden');
  end if;

  if p_plan_id is not null and not exists (
    select 1 from public.plans p where p.id = p_plan_id and p.gym_id = p_gym and p.active and p.deleted_at is null
  ) then
    return jsonb_build_object('status', 'invalid_plan');
  end if;

  select * into v_req from public.portal_requests r
  where r.gym_id = p_gym and r.member_id = v_acc.member_id and r.kind = 'renewal'
    and r.status in ('pending', 'approved')
  order by r.created_at desc limit 1;
  if found then
    return jsonb_build_object('status', 'already_pending', 'request_id', v_req.id);
  end if;

  select * into v_member from public.members m where m.id = v_acc.member_id;
  insert into public.portal_requests(gym_id, plan_id, first_name, last_name, phone, email, kind, notes, member_id, auth_user_id)
  values (p_gym, p_plan_id, v_member.first_name, v_member.last_name,
          coalesce(nullif(trim(v_member.phone), ''), nullif(trim(v_member.whatsapp), ''), '00000000'),
          nullif(trim(v_member.email), ''), 'renewal', 'Demande de renouvellement via l’espace membre.',
          v_acc.member_id, v_uid)
  returning * into v_req;

  return jsonb_build_object('status', 'ok', 'request_id', v_req.id);
end;
$$;

revoke all on function public.member_portal_request_renewal(uuid, uuid) from public, anon;
grant execute on function public.member_portal_request_renewal(uuid, uuid) to authenticated;

-- 6. Koneksyon pa telefòn sèlman: Bloke pou JL FITNESS
create or replace function public.mp_phone_member(p_gym uuid, p_phone text)
returns table(member_id uuid, email text, first_name text)
language sql stable security definer set search_path = '' as $$
  select m.id, nullif(lower(trim(coalesce(m.email, ''))), ''), m.first_name
  from public.members m
  join public.gyms g on g.id = m.gym_id
  where m.gym_id = p_gym
    and public.mp_gym_open(p_gym)
    and m.deleted_at is null
    and g.code <> 'JLF'
    and g.id <> '6ed6093d-557d-4bb9-b3ba-f55fedcf65b3'
    and g.name not ilike '%JL FITNESS%'
    and (
      (length(public.mp_phone_key(p_phone)) = 8 and (
        public.mp_phone_key(m.phone) = public.mp_phone_key(p_phone)
        or public.mp_phone_key(m.whatsapp) = public.mp_phone_key(p_phone)
      ))
      or (
        length(trim(p_phone)) >= 2 and (
          lower(trim(m.first_name || ' ' || m.last_name)) = lower(trim(p_phone))
          or lower(trim(m.last_name || ' ' || m.first_name)) = lower(trim(p_phone))
          or lower(trim(m.first_name)) = lower(trim(p_phone))
          or lower(trim(m.last_name)) = lower(trim(p_phone))
          or upper(trim(m.member_number)) = upper(trim(p_phone))
          or lower(trim(m.first_name || ' ' || m.last_name)) like '%' || lower(trim(p_phone)) || '%'
        )
      )
    )
  order by (select max(s.end_date) from public.subscriptions s
            where s.member_id = m.id and s.deleted_at is null and s.status <> 'cancelled') desc nulls last,
           m.created_at desc
  limit 1
$$;

revoke all on function public.mp_phone_member(uuid, text) from public, anon, authenticated;
grant execute on function public.mp_phone_member(uuid, text) to service_role;

commit;
