-- ==============================================================================
-- 46_employee_portal_profile.sql — Aksè Espas Pwofil pou Anplwaye yo
-- ==============================================================================
-- Pèmèt anplwaye yo (antrenè, resepsyon, sekirite, kesyè...) konekte sou sit la ak
-- nimewo telefòn yo menm jan ak manm yo, gade pwofil yo, epi mete / chanje foto yo.

begin;

-- 1. Ajoute kolòn employee_number ak photo_url nan public.employees
alter table public.employees add column if not exists employee_number text;
alter table public.employees add column if not exists photo_url text;

-- 2. Retire contrainte foreign key sou member_id nan member_accounts pou l ka kenbe
-- swa yon member_id oswa yon employee_id san erè.
alter table public.member_accounts drop constraint if exists member_accounts_member_id_fkey;

-- 3. Aktyalize mp_phone_member pou l chèche manm DABÒ, epi si pa gen manm, li chèche nan anplwaye yo
create or replace function public.mp_phone_member(p_gym uuid, p_phone text)
returns table(member_id uuid, email text, first_name text)
language sql stable security definer set search_path = '' as $$
  -- 1) Manm sal la
  select m.id, nullif(lower(trim(coalesce(m.email, ''))), ''), m.first_name
  from public.members m
  where m.gym_id = p_gym
    and public.mp_gym_open(p_gym)
    and m.deleted_at is null
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

  union all

  -- 2) Anplwaye sal la (si pa gen manm ki koresponn)
  select e.id, nullif(lower(trim(coalesce(e.email, ''))), ''), e.first_name
  from public.employees e
  where e.gym_id = p_gym
    and public.mp_gym_open(p_gym)
    and e.deleted_at is null
    and not exists (
      select 1 from public.members m
      where m.gym_id = p_gym and m.deleted_at is null
        and (
          (length(public.mp_phone_key(p_phone)) = 8 and (
            public.mp_phone_key(m.phone) = public.mp_phone_key(p_phone)
            or public.mp_phone_key(m.whatsapp) = public.mp_phone_key(p_phone)
          ))
          or (length(trim(p_phone)) >= 2 and (
            lower(trim(m.first_name || ' ' || m.last_name)) = lower(trim(p_phone))
            or upper(trim(m.member_number)) = upper(trim(p_phone))
          ))
        )
    )
    and (
      (length(public.mp_phone_key(p_phone)) = 8 and public.mp_phone_key(e.phone) = public.mp_phone_key(p_phone))
      or (
        length(trim(p_phone)) >= 2 and (
          lower(trim(e.first_name || ' ' || e.last_name)) = lower(trim(p_phone))
          or lower(trim(e.last_name || ' ' || e.first_name)) = lower(trim(p_phone))
          or lower(trim(e.first_name)) = lower(trim(p_phone))
          or lower(trim(e.last_name)) = lower(trim(p_phone))
          or upper(trim(coalesce(e.employee_number, ''))) = upper(trim(p_phone))
          or lower(trim(e.first_name || ' ' || e.last_name)) like '%' || lower(trim(p_phone)) || '%'
        )
      )
    )
  limit 1
$$;

-- 4. Aktyalize member_portal_me pou sipòte pwofil anplwaye yo ('state': 'employee')
create or replace function public.member_portal_me(p_gym uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_gym public.gyms;
  v_acc public.member_accounts;
  v_req public.portal_requests;
  v_has_req boolean := false;
  v_member public.members;
  v_employee public.employees;
  v_member_id uuid;
  v_today date;
  v_sub record;
  v_paid numeric := 0;
  v_status text := 'none';
  v_gym_json jsonb;
  v_req_json jsonb;
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select * into v_gym from public.gyms g
  where g.id = p_gym and g.deleted_at is null and g.status in ('active', 'trial', 'grace');
  if not found then
    return jsonb_build_object('state', 'gym_not_found');
  end if;
  v_today := public.mp_today(p_gym);
  v_gym_json := jsonb_build_object(
    'id', v_gym.id, 'name', v_gym.name, 'logo_url', v_gym.logo_url, 'address', v_gym.address,
    'phone', v_gym.phone, 'email', v_gym.email, 'accent_color', v_gym.accent_color,
    'currency', v_gym.currency);

  select * into v_acc from public.member_accounts ma where ma.user_id = v_uid and ma.gym_id = p_gym;

  if v_acc.id is null then
    select * into v_req from public.portal_requests r
    where r.auth_user_id = v_uid and r.gym_id = p_gym
    order by r.created_at desc limit 1;
    v_has_req := found;

    if v_has_req and v_req.status in ('approved', 'completed') then
      select m.id into v_member_id from public.members m
      where m.id = v_req.member_id and m.gym_id = p_gym and m.deleted_at is null;
      if v_member_id is null then
        select m.id into v_member_id from public.members m
        where m.gym_id = p_gym and m.deleted_at is null
          and m.created_at >= v_req.created_at - interval '1 day'
          and (
            (coalesce(trim(v_req.email), '') <> '' and lower(trim(m.email)) = lower(trim(v_req.email)))
            or public.mp_phone_key(m.phone) = public.mp_phone_key(v_req.phone)
            or public.mp_phone_key(m.whatsapp) = public.mp_phone_key(v_req.phone))
        order by m.created_at desc limit 1;
      end if;
      if v_member_id is not null
         and not exists (select 1 from public.member_accounts ma where ma.gym_id = p_gym and ma.member_id = v_member_id) then
        insert into public.member_accounts(user_id, gym_id, member_id, email)
        values (v_uid, p_gym, v_member_id, public.mp_user_email())
        on conflict do nothing;
        select * into v_acc from public.member_accounts ma where ma.user_id = v_uid and ma.gym_id = p_gym;
      end if;
    end if;
  end if;

  if v_acc.id is null then
    if v_has_req then
      v_req_json := jsonb_build_object(
        'id', v_req.id, 'status', v_req.status, 'kind', v_req.kind,
        'first_name', v_req.first_name, 'last_name', v_req.last_name,
        'created_at', v_req.created_at, 'updated_at', v_req.updated_at,
        'plan_name', (select p.name from public.plans p where p.id = v_req.plan_id),
        'plan_price', (select p.price from public.plans p where p.id = v_req.plan_id),
        'plan_currency', (select p.currency from public.plans p where p.id = v_req.plan_id));
    end if;
    return jsonb_build_object(
      'state', case when v_has_req and v_req.status <> 'rejected' then 'pending'
                    when v_has_req then 'rejected' else 'none' end,
      'email', public.mp_user_email(),
      'gym', v_gym_json,
      'request', v_req_json);
  end if;

  update public.member_accounts set last_seen_at = clock_timestamp() where id = v_acc.id;

  -- Verifye si se yon anplwaye
  select * into v_employee from public.employees e
  where e.id = v_acc.member_id and e.gym_id = p_gym and e.deleted_at is null;
  if found then
    return jsonb_build_object(
      'state', 'employee',
      'email', public.mp_user_email(),
      'gym', v_gym_json,
      'today', v_today,
      'employee', jsonb_build_object(
        'id', v_employee.id,
        'first_name', v_employee.first_name,
        'last_name', v_employee.last_name,
        'employee_number', coalesce(v_employee.employee_number, 'EMP-' || upper(substr(replace(v_employee.id::text, '-', ''), 1, 6))),
        'job_type', v_employee.job_type,
        'job_title', coalesce(v_employee.job_title, v_employee.job_type),
        'phone', v_employee.phone,
        'email', v_employee.email,
        'active', v_employee.active,
        'photo_url', v_employee.photo_url,
        'fingerprint_registered', coalesce(v_employee.fingerprint_registered, false),
        'created_at', v_employee.created_at
      )
    );
  end if;

  -- Sinon se yon manm nòmal
  select * into v_member from public.members m where m.id = v_acc.member_id;

  select s.*, p.name as plan_name, p.duration_days as plan_days, p.currency as plan_currency
  into v_sub
  from public.subscriptions s
  left join public.plans p on p.id = s.plan_id
  where s.member_id = v_member.id and s.gym_id = p_gym and s.deleted_at is null
    and s.status <> 'cancelled'
  order by s.end_date desc, s.created_at desc
  limit 1;

  if v_sub.id is not null then
    select coalesce(sum(greatest(0, pay.amount - coalesce(pay.registration_fee, 0))), 0) into v_paid
    from public.payments pay
    where pay.subscription_id = v_sub.id and pay.deleted_at is null and pay.voided_at is null;
    v_status := case
      when v_member.status = 'suspended' then 'suspended'
      when v_sub.status = 'pending' then 'pending'
      when v_sub.start_date > v_today then 'upcoming'
      when v_sub.end_date >= v_today then 'active'
      else 'expired' end;
  end if;

  v_result := jsonb_build_object(
    'state', 'member',
    'email', public.mp_user_email(),
    'gym', v_gym_json,
    'today', v_today,
    'member', jsonb_build_object(
      'id', v_member.id, 'first_name', v_member.first_name, 'last_name', v_member.last_name,
      'member_number', v_member.member_number, 'phone', v_member.phone, 'email', v_member.email,
      'whatsapp', v_member.whatsapp, 'birth_date', v_member.birth_date, 'sex', v_member.sex,
      'address', v_member.address, 'nif', v_member.nif, 'cin', v_member.cin,
      'emergency_contact_name', v_member.emergency_contact_name,
      'emergency_contact_phone', v_member.emergency_contact_phone,
      'guardian_name', v_member.guardian_name,
      'status', v_member.status, 'photo_url', v_member.photo_url, 'created_at', v_member.created_at,
      'fingerprint_registered', coalesce(v_member.fingerprint_registered, false)),
    'subscription', case when v_sub.id is null then null else jsonb_build_object(
      'id', v_sub.id, 'plan_name', coalesce(v_sub.plan_name, 'Abonnement'),
      'start_date', v_sub.start_date, 'end_date', v_sub.end_date,
      'days_left', greatest(0, v_sub.end_date - v_today),
      'total_days', greatest(1, v_sub.end_date - v_sub.start_date + 1),
      'status', v_status, 'price', v_sub.price,
      'currency', coalesce(v_sub.plan_currency, v_gym.currency),
      'balance', greatest(0, v_sub.price - coalesce(v_sub.opening_credit, 0) - v_paid)) end,
    'subscriptions', coalesce((
      select jsonb_agg(x.j order by x.end_date desc) from (
        select s.end_date, jsonb_build_object(
          'id', s.id, 'plan_name', coalesce(p.name, 'Abonnement'), 'start_date', s.start_date,
          'end_date', s.end_date, 'status', s.status, 'price', s.price,
          'currency', coalesce(p.currency, v_gym.currency)) as j
        from public.subscriptions s left join public.plans p on p.id = s.plan_id
        where s.member_id = v_member.id and s.gym_id = p_gym and s.deleted_at is null
        order by s.end_date desc limit 12) x), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(x.j order by x.paid_at desc) from (
        select pay.paid_at, jsonb_build_object(
          'id', pay.id, 'amount', pay.amount, 'currency', pay.currency, 'paid_at', pay.paid_at,
          'method', pay.method, 'registration_fee', coalesce(pay.registration_fee, 0),
          'plan_name', coalesce(p.name, 'Paiement')) as j
        from public.payments pay
        left join public.subscriptions s on s.id = pay.subscription_id
        left join public.plans p on p.id = s.plan_id
        where pay.member_id = v_member.id and pay.gym_id = p_gym and pay.deleted_at is null
          and pay.voided_at is null
        order by pay.paid_at desc limit 20) x), '[]'::jsonb),
    'announcements', coalesce((
      select jsonb_agg(x.j order by x.pinned desc, x.created_at desc) from (
        select a.pinned, a.created_at, jsonb_build_object(
          'id', a.id, 'title', a.title, 'body', a.body, 'kind', a.kind, 'pinned', a.pinned,
          'created_at', a.created_at) as j
        from public.gym_announcements a
        where a.gym_id = p_gym and a.active = true
          and (a.starts_at is null or a.starts_at <= clock_timestamp())
          and (a.ends_at is null or a.ends_at >= clock_timestamp())
        order by a.pinned desc, a.created_at desc limit 10) x), '[]'::jsonb),
    'attendance', coalesce((
      select jsonb_agg(x.j order by x.scanned_at desc) from (
        select att.scanned_at, jsonb_build_object(
          'id', att.id, 'scanned_at', att.scanned_at, 'result', att.result) as j
        from public.attendance att
        where att.member_id = v_member.id and att.gym_id = p_gym and att.deleted_at is null
        order by att.scanned_at desc limit 15) x), '[]'::jsonb));

  return v_result;
end $$;

-- 5. Aktyalize member_portal_update_profile pou anplwaye yo ka chanje foto yo
create or replace function public.member_portal_update_profile(p_gym uuid, p_patch jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_acc public.member_accounts;
  v_member public.members;
  v_employee public.employees;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_photo text := null;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select * into v_acc from public.member_accounts ma where ma.user_id = v_uid and ma.gym_id = p_gym;
  if not found then
    return jsonb_build_object('status', 'forbidden');
  end if;

  -- Si se yon anplwaye
  select * into v_employee from public.employees e
  where e.id = v_acc.member_id and e.gym_id = p_gym and e.deleted_at is null;
  if found then
    if v_patch ? 'photo_url' and coalesce(v_patch->>'photo_url', '') <> '' then
      v_photo := v_patch->>'photo_url';
      if v_photo !~ ('^' || p_gym::text || '/' || v_employee.id::text || '/[0-9a-zA-Z_-]{4,80}\.(jpg|jpeg|png)$') then
        return jsonb_build_object('status', 'invalid', 'field', 'photo_url');
      end if;
      update public.employees
      set photo_url = v_photo, updated_at = clock_timestamp()
      where id = v_employee.id;
    end if;
    return jsonb_build_object('status', 'ok');
  end if;

  -- Sinon se yon manm
  select * into v_member from public.members m
  where m.id = v_acc.member_id and m.gym_id = p_gym and m.deleted_at is null;
  if not found then
    return jsonb_build_object('status', 'forbidden');
  end if;

  if v_patch ? 'photo_url' and coalesce(v_patch->>'photo_url', '') <> '' then
    v_photo := v_patch->>'photo_url';
    if v_photo !~ ('^' || p_gym::text || '/' || v_member.id::text || '/[0-9a-zA-Z_-]{4,80}\.(jpg|jpeg|png)$') then
      return jsonb_build_object('status', 'invalid', 'field', 'photo_url');
    end if;
  end if;

  update public.members
  set first_name = coalesce(nullif(trim(v_patch->>'first_name'), ''), first_name),
      last_name = coalesce(trim(v_patch->>'last_name'), last_name),
      phone = coalesce(nullif(trim(v_patch->>'phone'), ''), phone),
      whatsapp = coalesce(nullif(trim(v_patch->>'whatsapp'), ''), whatsapp),
      email = coalesce(nullif(trim(v_patch->>'email'), ''), email),
      photo_url = coalesce(nullif(trim(v_patch->>'photo_url'), ''), photo_url),
      updated_at = clock_timestamp()
  where id = v_member.id;

  return jsonb_build_object('status', 'ok');
end $$;

-- 6. Aktyalize mp_can_read_object pou anplwaye yo ka li/afiche foto yo soti nan storage
create or replace function public.mp_can_read_object(p_bucket text, p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case p_bucket
    when 'gym-assets' then exists (
      select 1 from public.gyms g
      where g.logo_url = p_name and g.deleted_at is null and g.status in ('active', 'trial', 'grace'))
    when 'member-photos' then auth.uid() is not null and exists (
      select 1 from public.member_accounts ma
      left join public.members m on m.id = ma.member_id
      left join public.employees e on e.id = ma.member_id
      where ma.user_id = auth.uid() and (m.photo_url = p_name or e.photo_url = p_name))
    when 'receipts' then auth.uid() is not null and exists (
      select 1 from public.member_accounts ma
      join public.payments p on p.member_id = ma.member_id and p.gym_id = ma.gym_id
      where ma.user_id = auth.uid()
        and p_name = p.gym_id::text || '/receipts/' || p.id::text || '.pdf')
    else false
  end
$$;

revoke all on function public.mp_can_read_object(text, text) from public;
grant execute on function public.mp_can_read_object(text, text) to anon, authenticated;

grant execute on function public.mp_phone_member(uuid, text) to service_role;
grant execute on function public.member_portal_me(uuid) to authenticated;
grant execute on function public.member_portal_update_profile(uuid, jsonb) to authenticated;
notify pgrst, 'reload schema';

commit;
