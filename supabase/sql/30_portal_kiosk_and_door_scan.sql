-- =============================================================================
-- Migration 30 : Fonctions Publiques pour Kiosque Libre-Accès et Renouvellement
-- =============================================================================

begin;

-- 1. Recherche de membre anonyme pour le portail de renouvellement
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
  where (id::text = lower(trim(p_gym_code)) or lower(name) = lower(trim(p_gym_code)))
    and status in ('active', 'trial')
  limit 1;

  if not found then
    raise exception 'gym_not_found' using errcode = '22023';
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

-- 2. Détection en temps réel du dernier scan à la porte pour le renouvellement
create or replace function public.portal_latest_door_scan(p_gym_code text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym public.gyms;
  v_event record;
  v_sub public.subscriptions;
  v_plan public.plans;
  v_status text := 'none';
  v_days_left int := 0;
begin
  select * into v_gym from public.gyms
  where (id::text = lower(trim(p_gym_code)) or lower(name) = lower(trim(p_gym_code)))
  limit 1;

  if not found then
    return jsonb_build_object('found', false);
  end if;

  select ae.*, m.first_name, m.last_name, m.phone, m.email
  into v_event
  from public.access_events ae
  join public.members m on m.id = ae.member_id
  where ae.gym_id = v_gym.id
    and ae.member_id is not null
    and ae.created_at > (clock_timestamp() - interval '45 seconds')
  order by ae.created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('found', false);
  end if;

  -- Chercher statut abonnement
  select * into v_sub from public.subscriptions
  where member_id = v_event.member_id
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
    'member_id', v_event.member_id,
    'first_name', v_event.first_name,
    'last_name', v_event.last_name,
    'phone', v_event.phone,
    'email', v_event.email,
    'status', v_status,
    'days_left', v_days_left,
    'current_plan_name', coalesce(v_plan.name, 'Abonnement antérieur'),
    'expiration_date', case when v_sub.end_date is not null then v_sub.end_date::text else null end,
    'timestamp', v_event.created_at
  );
end;
$$;

revoke all on function public.portal_latest_door_scan(text) from public, anon, authenticated;
grant execute on function public.portal_latest_door_scan(text) to anon, authenticated;

-- 3. Mise à jour de portal_submit pour accepter member_id
create or replace function public.portal_submit(
  p_gym_code text,
  p_plan_id uuid,
  p_first_name text,
  p_last_name text,
  p_phone text,
  p_email text default null,
  p_kind text default 'new_membership',
  p_notes text default null,
  p_member_id uuid default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym public.gyms;
  v_plan public.plans;
  v_req public.portal_requests;
  v_recent_count int;
begin
  if p_gym_code is null or trim(p_gym_code) = '' then
    raise exception 'invalid_gym' using errcode = '22023';
  end if;

  select * into v_gym from public.gyms
  where (id::text = lower(trim(p_gym_code)) or lower(name) = lower(trim(p_gym_code)))
    and status in ('active', 'trial')
  limit 1;

  if not found then
    raise exception 'gym_not_found' using errcode = '22023';
  end if;

  if p_first_name is null or length(trim(p_first_name)) < 2
     or p_last_name is null or length(trim(p_last_name)) < 2
     or p_phone is null or length(regexp_replace(p_phone, '\D', '', 'g')) < 8 then
    raise exception 'invalid_fields' using errcode = '22023';
  end if;

  if p_plan_id is not null then
    select * into v_plan from public.plans where id = p_plan_id and gym_id = v_gym.id and active = true and deleted_at is null;
    if not found then
      raise exception 'invalid_plan' using errcode = '22023';
    end if;
  end if;

  insert into public.portal_requests(
    gym_id, plan_id, first_name, last_name, phone, email, kind, notes, member_id
  )
  values(
    v_gym.id,
    p_plan_id,
    trim(p_first_name),
    trim(p_last_name),
    trim(p_phone),
    nullif(trim(p_email), ''),
    case when p_kind in ('new_membership', 'renewal') then p_kind else 'new_membership' end,
    nullif(trim(p_notes), ''),
    p_member_id
  )
  returning * into v_req;

  return jsonb_build_object(
    'success', true,
    'request_id', v_req.id,
    'status', v_req.status,
    'gym_name', v_gym.name,
    'created_at', v_req.created_at
  );
end;
$$;

revoke all on function public.portal_submit(text, uuid, text, text, text, text, text, text, uuid) from public, anon, authenticated;
grant execute on function public.portal_submit(text, uuid, text, text, text, text, text, text, uuid) to anon, authenticated;

commit;
