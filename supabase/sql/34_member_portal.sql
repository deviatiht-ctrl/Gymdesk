-- =============================================================================
-- Migration 34 : Espace membre (PWA par gym), annonces du gym, comptes membres
-- À appliquer après 33 (idempotent).
--
-- * public.member_accounts      : lien compte Auth ↔ membre, PAR GYM (isolation stricte :
--                                 un même email peut être membre de plusieurs gyms, chaque
--                                 lien est validé séparément avec le téléphone du dossier).
-- * public.gym_announcements    : messages publiés par le gym dans l'espace membre.
-- * portal_requests.auth_user_id : la personne qui s'inscrit en ligne crée son compte tout
--                                 de suite et suit sa demande en direct ; le compte est
--                                 activé (lié au membre) dès que le gym valide l'inscription.
-- * RPC anon : member_portal_gyms, member_portal_gym, member_portal_check
-- * RPC authentifiées (membre) : member_portal_link, member_portal_attach_request,
--                                member_portal_me, member_portal_request_renewal
-- * Storage : logo des gyms actifs lisible publiquement (URL signée), photo et reçus PDF
--             lisibles par le membre propriétaire uniquement.
-- Les membres n'ont AUCUNE ligne staff : current_gym_id() est null pour eux, donc aucune
-- policy existante ne leur donne accès aux tables — tout passe par ces RPC.
-- =============================================================================

begin;

-- 1. Tables ------------------------------------------------------------------
create table if not exists public.member_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  gym_id uuid not null references public.gyms(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  email text,
  created_at timestamptz not null default clock_timestamp(),
  last_seen_at timestamptz,
  unique (user_id, gym_id),
  unique (gym_id, member_id)
);

create index if not exists idx_member_accounts_gym on public.member_accounts(gym_id, created_at desc);

alter table public.member_accounts enable row level security;

drop policy if exists member_accounts_staff_select on public.member_accounts;
create policy member_accounts_staff_select on public.member_accounts
  for select to authenticated
  using (gym_id = public.current_gym_id());

drop policy if exists member_accounts_staff_delete on public.member_accounts;
create policy member_accounts_staff_delete on public.member_accounts
  for delete to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor'));

grant select, delete on public.member_accounts to authenticated;

create table if not exists public.gym_announcements (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 140),
  body text not null default '' check (char_length(body) <= 4000),
  kind text not null default 'info' check (kind in ('info', 'promo', 'event', 'alert')),
  pinned boolean not null default false,
  active boolean not null default true,
  starts_at timestamptz,
  ends_at timestamptz,
  created_by uuid default public.current_staff_id() references public.staff(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create index if not exists idx_gym_announcements_gym on public.gym_announcements(gym_id, active, created_at desc);

alter table public.gym_announcements enable row level security;

drop policy if exists gym_announcements_staff_select on public.gym_announcements;
create policy gym_announcements_staff_select on public.gym_announcements
  for select to authenticated
  using (gym_id = public.current_gym_id());

drop policy if exists gym_announcements_staff_insert on public.gym_announcements;
create policy gym_announcements_staff_insert on public.gym_announcements
  for insert to authenticated
  with check (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor'));

drop policy if exists gym_announcements_staff_update on public.gym_announcements;
create policy gym_announcements_staff_update on public.gym_announcements
  for update to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor'))
  with check (gym_id = public.current_gym_id());

drop policy if exists gym_announcements_staff_delete on public.gym_announcements;
create policy gym_announcements_staff_delete on public.gym_announcements
  for delete to authenticated
  using (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor'));

grant select, insert, update, delete on public.gym_announcements to authenticated;

alter table public.portal_requests
  add column if not exists auth_user_id uuid references auth.users(id) on delete set null;

create index if not exists idx_portal_requests_auth_user on public.portal_requests(auth_user_id, gym_id);

-- Anti brute force (vérification email + téléphone) : 10 essais / 15 min par email.
create table if not exists public.member_portal_attempts (
  id bigint generated always as identity primary key,
  key text not null,
  at timestamptz not null default clock_timestamp()
);
create index if not exists idx_member_portal_attempts on public.member_portal_attempts(key, at desc);
alter table public.member_portal_attempts enable row level security;

-- 2. Helpers -----------------------------------------------------------------
create or replace function public.mp_phone_key(p text)
returns text language sql immutable set search_path = '' as $$
  select right(regexp_replace(coalesce(p, ''), '\D', '', 'g'), 8)
$$;

create or replace function public.mp_today(p_gym uuid)
returns date language sql stable security definer set search_path = '' as $$
  select (clock_timestamp() at time zone coalesce(
    (select g.timezone from public.gyms g where g.id = p_gym), 'America/Port-au-Prince'))::date
$$;

create or replace function public.mp_user_email()
returns text language sql stable security definer set search_path = '' as $$
  select lower(trim(u.email)) from auth.users u where u.id = auth.uid()
$$;

create or replace function public.mp_gym_open(p_gym uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.gyms g
    where g.id = p_gym and g.deleted_at is null and g.status in ('active', 'trial', 'grace')
  )
$$;

-- Trouve le membre d'un gym qui correspond à (email, téléphone) ou, si le dossier n'a
-- pas d'email, à (téléphone, numéro de membre). Codes : ok, not_found,
-- need_member_number, already_linked.
create or replace function public.mp_match_member(
  p_gym uuid, p_email text, p_phone text, p_member_number text, p_user uuid default null
)
returns table(member_id uuid, code text)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_key text := public.mp_phone_key(p_phone);
  v_email text := lower(trim(coalesce(p_email, '')));
  v_number text := upper(trim(coalesce(p_member_number, '')));
  v_id uuid;
  v_linked_user uuid;
begin
  if length(v_key) < 8 or v_email = '' then
    return query select null::uuid, 'not_found'::text;
    return;
  end if;

  select m.id into v_id from public.members m
  where m.gym_id = p_gym and m.deleted_at is null
    and (public.mp_phone_key(m.phone) = v_key or public.mp_phone_key(m.whatsapp) = v_key)
    and lower(trim(coalesce(m.email, ''))) = v_email
  order by m.created_at desc limit 1;

  if v_id is null and v_number <> '' then
    select m.id into v_id from public.members m
    where m.gym_id = p_gym and m.deleted_at is null
      and (public.mp_phone_key(m.phone) = v_key or public.mp_phone_key(m.whatsapp) = v_key)
      and coalesce(trim(m.email), '') = ''
      and upper(trim(m.member_number)) = v_number
    order by m.created_at desc limit 1;
  end if;

  if v_id is null then
    if exists (
      select 1 from public.members m
      where m.gym_id = p_gym and m.deleted_at is null
        and (public.mp_phone_key(m.phone) = v_key or public.mp_phone_key(m.whatsapp) = v_key)
        and coalesce(trim(m.email), '') = ''
    ) then
      return query select null::uuid, 'need_member_number'::text;
    else
      return query select null::uuid, 'not_found'::text;
    end if;
    return;
  end if;

  select ma.user_id into v_linked_user from public.member_accounts ma
  where ma.gym_id = p_gym and ma.member_id = v_id;
  if v_linked_user is not null and v_linked_user is distinct from p_user then
    return query select v_id, 'already_linked'::text;
    return;
  end if;

  return query select v_id, 'ok'::text;
end;
$$;

revoke all on function public.mp_match_member(uuid, text, text, text, uuid) from public, anon, authenticated;

-- Accès Storage pour l'espace membre (appelé par les policies storage.objects).
create or replace function public.mp_can_read_object(p_bucket text, p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case p_bucket
    when 'gym-assets' then exists (
      select 1 from public.gyms g
      where g.logo_url = p_name and g.deleted_at is null and g.status in ('active', 'trial', 'grace'))
    when 'member-photos' then auth.uid() is not null and exists (
      select 1 from public.member_accounts ma
      join public.members m on m.id = ma.member_id
      where ma.user_id = auth.uid() and m.photo_url = p_name)
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

drop policy if exists member_portal_public_logo on storage.objects;
create policy member_portal_public_logo on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'gym-assets' and public.mp_can_read_object(bucket_id, name));

drop policy if exists member_portal_own_photo on storage.objects;
create policy member_portal_own_photo on storage.objects
  for select to authenticated
  using (bucket_id = 'member-photos' and public.mp_can_read_object(bucket_id, name));

drop policy if exists member_portal_own_receipts on storage.objects;
create policy member_portal_own_receipts on storage.objects
  for select to authenticated
  using (bucket_id = 'receipts' and public.mp_can_read_object(bucket_id, name));

-- 3. RPC publiques -----------------------------------------------------------
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
$$;

revoke all on function public.member_portal_gyms() from public;
grant execute on function public.member_portal_gyms() to anon, authenticated;

create or replace function public.member_portal_gym(p_gym uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_gym public.gyms;
begin
  select * into v_gym from public.gyms g
  where g.id = p_gym and g.deleted_at is null and g.status in ('active', 'trial', 'grace');
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

create or replace function public.member_portal_check(
  p_gym uuid, p_email text, p_phone text, p_member_number text default null
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_key text := 'check:' || lower(trim(coalesce(p_email, '')));
  v_match record;
  v_first text;
begin
  if not public.mp_gym_open(p_gym) then
    return jsonb_build_object('status', 'gym_not_found');
  end if;
  delete from public.member_portal_attempts where at < clock_timestamp() - interval '1 day';
  if (select count(*) from public.member_portal_attempts a
      where a.key = v_key and a.at > clock_timestamp() - interval '15 minutes') >= 10 then
    return jsonb_build_object('status', 'too_many_attempts');
  end if;
  insert into public.member_portal_attempts(key) values (v_key);

  select * into v_match from public.mp_match_member(p_gym, p_email, p_phone, p_member_number, null);
  if v_match.member_id is not null then
    select m.first_name into v_first from public.members m where m.id = v_match.member_id;
  end if;
  return jsonb_build_object('status', v_match.code, 'first_name', v_first);
end;
$$;

revoke all on function public.member_portal_check(uuid, text, text, text) from public;
grant execute on function public.member_portal_check(uuid, text, text, text) to anon, authenticated;

-- 4. RPC membre (authentifié) ------------------------------------------------
create or replace function public.member_portal_link(
  p_gym uuid, p_phone text, p_member_number text default null
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_email text := public.mp_user_email();
  v_match record;
  v_existing public.member_accounts;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not public.mp_gym_open(p_gym) then
    return jsonb_build_object('status', 'gym_not_found');
  end if;

  select * into v_existing from public.member_accounts ma where ma.user_id = v_uid and ma.gym_id = p_gym;
  if found then
    return jsonb_build_object('status', 'ok', 'member_id', v_existing.member_id);
  end if;

  select * into v_match from public.mp_match_member(p_gym, v_email, p_phone, p_member_number, v_uid);
  if v_match.code <> 'ok' then
    return jsonb_build_object('status', v_match.code);
  end if;

  insert into public.member_accounts(user_id, gym_id, member_id, email)
  values (v_uid, p_gym, v_match.member_id, v_email)
  on conflict do nothing;

  if not exists (select 1 from public.member_accounts ma where ma.user_id = v_uid and ma.gym_id = p_gym) then
    return jsonb_build_object('status', 'already_linked');
  end if;
  return jsonb_build_object('status', 'ok', 'member_id', v_match.member_id);
end;
$$;

revoke all on function public.member_portal_link(uuid, text, text) from public, anon;
grant execute on function public.member_portal_link(uuid, text, text) to authenticated;

-- La personne qui vient de soumettre une demande en ligne y rattache son compte.
create or replace function public.member_portal_attach_request(p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_email text := public.mp_user_email();
  v_req public.portal_requests;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select * into v_req from public.portal_requests r where r.id = p_request_id;
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;
  if v_req.auth_user_id = v_uid then
    return jsonb_build_object('status', 'ok', 'gym_id', v_req.gym_id);
  end if;
  if v_req.auth_user_id is not null
     or lower(trim(coalesce(v_req.email, ''))) <> coalesce(v_email, '')
     or v_req.created_at < clock_timestamp() - interval '6 hours' then
    return jsonb_build_object('status', 'forbidden');
  end if;
  update public.portal_requests set auth_user_id = v_uid, updated_at = clock_timestamp()
  where id = v_req.id;
  return jsonb_build_object('status', 'ok', 'gym_id', v_req.gym_id);
end;
$$;

revoke all on function public.member_portal_attach_request(uuid) from public, anon;
grant execute on function public.member_portal_attach_request(uuid) to authenticated;

create or replace function public.member_portal_me(p_gym uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_gym public.gyms;
  v_acc public.member_accounts;
  v_req public.portal_requests;
  v_has_req boolean := false;
  v_member public.members;
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

    -- Activation automatique : la demande en ligne a été validée par le gym.
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
          'id', pay.id, 'paid_at', pay.paid_at, 'amount', pay.amount, 'currency', pay.currency,
          'method', pay.method, 'reason', pay.payment_reason,
          'registration_fee', coalesce(pay.registration_fee, 0),
          'paid_currency', pay.paid_currency, 'paid_amount', pay.paid_amount,
          'receipt_path', (select o.name from storage.objects o
                           where o.bucket_id = 'receipts'
                             and o.name = pay.gym_id::text || '/receipts/' || pay.id::text || '.pdf' limit 1)) as j
        from public.payments pay
        where pay.member_id = v_member.id and pay.gym_id = p_gym
          and pay.deleted_at is null and pay.voided_at is null
        order by pay.paid_at desc limit 30) x), '[]'::jsonb),
    'attendance', jsonb_build_object(
      'total', (select count(*) from public.attendance a
                where a.member_id = v_member.id and a.gym_id = p_gym and a.result = 'granted'),
      'this_month', (select count(*) from public.attendance a
                     where a.member_id = v_member.id and a.gym_id = p_gym and a.result = 'granted'
                       and (a.scanned_at at time zone v_gym.timezone)::date >= date_trunc('month', v_today)::date),
      'last_30', (select count(*) from public.attendance a
                  where a.member_id = v_member.id and a.gym_id = p_gym and a.result = 'granted'
                    and (a.scanned_at at time zone v_gym.timezone)::date > v_today - 30),
      'last_visit', (select max(a.scanned_at) from public.attendance a
                     where a.member_id = v_member.id and a.gym_id = p_gym and a.result = 'granted'),
      'weeks', (
        select coalesce(jsonb_agg(jsonb_build_object('week', w.week_start, 'count', w.cnt) order by w.week_start), '[]'::jsonb)
        from (
          select gs::date as week_start,
                 (select count(distinct (a.scanned_at at time zone v_gym.timezone)::date)
                  from public.attendance a
                  where a.member_id = v_member.id and a.gym_id = p_gym and a.result = 'granted'
                    and (a.scanned_at at time zone v_gym.timezone)::date >= gs::date
                    and (a.scanned_at at time zone v_gym.timezone)::date < gs::date + 7) as cnt
          from generate_series(date_trunc('week', v_today)::date - 49, date_trunc('week', v_today)::date, interval '7 days') gs
        ) w),
      'weekdays', (
        select coalesce(jsonb_agg(jsonb_build_object('dow', d.dow, 'count', d.cnt) order by d.dow), '[]'::jsonb)
        from (
          select extract(isodow from (a.scanned_at at time zone v_gym.timezone))::int as dow, count(*) as cnt
          from public.attendance a
          where a.member_id = v_member.id and a.gym_id = p_gym and a.result = 'granted'
            and a.scanned_at > clock_timestamp() - interval '180 days'
          group by 1
        ) d)),
    'announcements', coalesce((
      select jsonb_agg(x.j order by x.pinned desc, x.created_at desc) from (
        select an.pinned, an.created_at, jsonb_build_object(
          'id', an.id, 'title', an.title, 'body', an.body, 'kind', an.kind,
          'pinned', an.pinned, 'created_at', an.created_at, 'ends_at', an.ends_at) as j
        from public.gym_announcements an
        where an.gym_id = p_gym and an.active
          and (an.starts_at is null or an.starts_at <= clock_timestamp())
          and (an.ends_at is null or an.ends_at > clock_timestamp())
        order by an.pinned desc, an.created_at desc limit 20) x), '[]'::jsonb),
    'plans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'price', p.price, 'currency', p.currency,
        'duration_days', p.duration_days, 'description', p.description) order by p.sort_order, p.price)
      from public.plans p
      where p.gym_id = p_gym and p.active and p.deleted_at is null), '[]'::jsonb),
    'pending_renewal', (
      select jsonb_build_object('id', r.id, 'status', r.status, 'created_at', r.created_at,
                                'plan_name', (select p.name from public.plans p where p.id = r.plan_id))
      from public.portal_requests r
      where r.gym_id = p_gym and r.member_id = v_member.id and r.kind = 'renewal'
        and r.status in ('pending', 'approved')
      order by r.created_at desc limit 1)
  );
  return v_result;
end;
$$;

revoke all on function public.member_portal_me(uuid) from public, anon;
grant execute on function public.member_portal_me(uuid) to authenticated;

create or replace function public.member_portal_request_renewal(p_gym uuid, p_plan_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_acc public.member_accounts;
  v_member public.members;
  v_req public.portal_requests;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
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
          coalesce(v_member.email, v_acc.email), 'renewal', 'Demande envoyée depuis l''espace membre',
          v_member.id, v_uid)
  returning * into v_req;
  return jsonb_build_object('status', 'ok', 'request_id', v_req.id);
end;
$$;

revoke all on function public.member_portal_request_renewal(uuid, uuid) from public, anon;
grant execute on function public.member_portal_request_renewal(uuid, uuid) to authenticated;

-- Connexion membre « sans choisir de gym » : gyms liés au compte (ou inscription en cours).
create or replace function public.member_portal_my_gyms()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', g.id, 'name', g.name, 'logo_url', g.logo_url, 'address', g.address,
    'accent_color', g.accent_color, 'state', x.state) order by lower(g.name)), '[]'::jsonb)
  from (
    select ma.gym_id, 'member'::text as state from public.member_accounts ma where ma.user_id = auth.uid()
    union
    select r.gym_id, 'pending'::text from public.portal_requests r
    where r.auth_user_id = auth.uid() and r.status <> 'rejected'
      and not exists (select 1 from public.member_accounts ma
                      where ma.user_id = auth.uid() and ma.gym_id = r.gym_id)
  ) x
  join public.gyms g on g.id = x.gym_id
  where auth.uid() is not null and g.deleted_at is null and g.status in ('active', 'trial', 'grace')
$$;

revoke all on function public.member_portal_my_gyms() from public, anon;
grant execute on function public.member_portal_my_gyms() to authenticated;

-- 5. Messagerie membre ↔ gym ------------------------------------------------
-- Le personnel lit/répond dans « Espace membre » ; le membre lit sa propre
-- conversation (policy) et écrit via member_portal_send_message (quota).
create table if not exists public.member_messages (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  account_id uuid references public.member_accounts(id) on delete set null,
  sender text not null check (sender in ('member', 'gym')),
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default clock_timestamp(),
  read_by_gym_at timestamptz,
  read_by_member_at timestamptz
);

create index if not exists idx_member_messages_conv on public.member_messages(gym_id, member_id, created_at);
create index if not exists idx_member_messages_unread on public.member_messages(gym_id, created_at desc)
  where sender = 'member' and read_by_gym_at is null;

alter table public.member_messages enable row level security;

drop policy if exists member_messages_staff_select on public.member_messages;
create policy member_messages_staff_select on public.member_messages
  for select to authenticated
  using (gym_id = public.current_gym_id());

drop policy if exists member_messages_staff_insert on public.member_messages;
create policy member_messages_staff_insert on public.member_messages
  for insert to authenticated
  with check (
    gym_id = public.current_gym_id()
    and sender = 'gym'
    and exists (select 1 from public.members m
                where m.id = member_id and m.gym_id = member_messages.gym_id)
  );

drop policy if exists member_messages_staff_update on public.member_messages;
create policy member_messages_staff_update on public.member_messages
  for update to authenticated
  using (gym_id = public.current_gym_id())
  with check (gym_id = public.current_gym_id());

-- Le membre lit (et suit en temps réel) uniquement SA conversation.
-- Le contôle passe par une fonction security definer car le membre n'a pas
-- accès en lecture à member_accounts.
create or replace function public.mp_is_portal_member(p_gym uuid, p_member uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.member_accounts ma
    where ma.user_id = auth.uid() and ma.gym_id = p_gym and ma.member_id = p_member)
$$;

revoke all on function public.mp_is_portal_member(uuid, uuid) from public;
grant execute on function public.mp_is_portal_member(uuid, uuid) to authenticated;

drop policy if exists member_messages_member_select on public.member_messages;
create policy member_messages_member_select on public.member_messages
  for select to authenticated
  using (public.mp_is_portal_member(gym_id, member_id));

grant select, insert, update on public.member_messages to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'member_messages') then
    alter publication supabase_realtime add table public.member_messages;
  end if;
end;
$$;

-- Le membre écrit au gym (40 messages / 24 h par compte).
create or replace function public.member_portal_send_message(p_gym uuid, p_body text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_acc public.member_accounts;
  v_body text := trim(coalesce(p_body, ''));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select * into v_acc from public.member_accounts ma where ma.user_id = v_uid and ma.gym_id = p_gym;
  if not found then
    return jsonb_build_object('status', 'forbidden');
  end if;
  if v_body = '' then
    return jsonb_build_object('status', 'invalid');
  end if;
  if (select count(*) from public.member_messages mm
      where mm.account_id = v_acc.id and mm.sender = 'member'
        and mm.created_at > clock_timestamp() - interval '1 day') >= 40 then
    return jsonb_build_object('status', 'rate_limited');
  end if;
  insert into public.member_messages(gym_id, member_id, account_id, sender, body, read_by_member_at)
  values (p_gym, v_acc.member_id, v_acc.id, 'member', v_body, clock_timestamp());
  return jsonb_build_object('status', 'ok');
end;
$$;

revoke all on function public.member_portal_send_message(uuid, text) from public, anon;
grant execute on function public.member_portal_send_message(uuid, text) to authenticated;

-- Conversation du membre + marque « lu » les messages venant du gym.
create or replace function public.member_portal_messages(p_gym uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_acc public.member_accounts;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select * into v_acc from public.member_accounts ma where ma.user_id = v_uid and ma.gym_id = p_gym;
  if not found then
    return '[]'::jsonb;
  end if;
  update public.member_messages
  set read_by_member_at = clock_timestamp()
  where gym_id = p_gym and member_id = v_acc.member_id
    and sender = 'gym' and read_by_member_at is null;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', x.id, 'sender', x.sender, 'body', x.body, 'created_at', x.created_at,
      'read_by_gym_at', x.read_by_gym_at, 'read_by_member_at', x.read_by_member_at
    ) order by x.created_at)
    from (
      select mm.* from public.member_messages mm
      where mm.gym_id = p_gym and mm.member_id = v_acc.member_id
      order by mm.created_at desc limit 100
    ) x), '[]'::jsonb);
end;
$$;

revoke all on function public.member_portal_messages(uuid) from public, anon;
grant execute on function public.member_portal_messages(uuid) to authenticated;

-- 6. Profil du membre (mise à jour par le membre lui-même) --------------------
-- Champs en liste blanche uniquement ; photo_url doit être un objet du membre.
create or replace function public.member_portal_update_profile(p_gym uuid, p_patch jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_acc public.member_accounts;
  v_member public.members;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_birth date := null;
  v_photo text := null;
  v_key text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select * into v_acc from public.member_accounts ma where ma.user_id = v_uid and ma.gym_id = p_gym;
  if not found then
    return jsonb_build_object('status', 'forbidden');
  end if;
  select * into v_member from public.members m
  where m.id = v_acc.member_id and m.gym_id = p_gym and m.deleted_at is null;
  if not found then
    return jsonb_build_object('status', 'forbidden');
  end if;

  if v_patch ? 'sex'
     and coalesce(v_patch->>'sex', '') not in ('', 'male', 'female', 'other') then
    return jsonb_build_object('status', 'invalid', 'field', 'sex');
  end if;
  if v_patch ? 'birth_date' and coalesce(v_patch->>'birth_date', '') <> '' then
    begin
      v_birth := (v_patch->>'birth_date')::date;
    exception when others then
      return jsonb_build_object('status', 'invalid', 'field', 'birth_date');
    end;
    if v_birth < '1900-01-01' or v_birth > current_date then
      return jsonb_build_object('status', 'invalid', 'field', 'birth_date');
    end if;
  end if;
  if v_patch ? 'email' and coalesce(v_patch->>'email', '') <> ''
     and v_patch->>'email' !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then
    return jsonb_build_object('status', 'invalid', 'field', 'email');
  end if;
  if v_patch ? 'photo_url' and coalesce(v_patch->>'photo_url', '') <> '' then
    v_photo := v_patch->>'photo_url';
    if v_photo !~ ('^' || p_gym::text || '/' || v_member.id::text || '/[0-9a-zA-Z_-]{4,80}\.(jpg|jpeg|png)$') then
      return jsonb_build_object('status', 'invalid', 'field', 'photo_url');
    end if;
  end if;
  for v_key in select key from jsonb_object_keys(v_patch) k(key) loop
    if v_key not in ('first_name', 'last_name', 'phone', 'whatsapp', 'email', 'birth_date',
                     'sex', 'address', 'nif', 'cin', 'emergency_contact_name',
                     'emergency_contact_phone', 'guardian_name', 'photo_url') then
      return jsonb_build_object('status', 'invalid', 'field', v_key);
    end if;
  end loop;

  update public.members set
    first_name = case when v_patch ? 'first_name' and trim(coalesce(v_patch->>'first_name', '')) <> ''
                      then left(trim(v_patch->>'first_name'), 60) else first_name end,
    last_name = case when v_patch ? 'last_name' and trim(coalesce(v_patch->>'last_name', '')) <> ''
                     then left(trim(v_patch->>'last_name'), 60) else last_name end,
    phone = case when v_patch ? 'phone' then nullif(left(trim(coalesce(v_patch->>'phone', '')), 32) , '') else phone end,
    whatsapp = case when v_patch ? 'whatsapp' then nullif(left(trim(coalesce(v_patch->>'whatsapp', '')), 32), '') else whatsapp end,
    email = case when v_patch ? 'email' then nullif(lower(trim(coalesce(v_patch->>'email', ''))), '') else email end,
    birth_date = case when v_patch ? 'birth_date' then v_birth else birth_date end,
    sex = case when v_patch ? 'sex' then nullif(v_patch->>'sex', '') else sex end,
    address = case when v_patch ? 'address' then nullif(left(trim(coalesce(v_patch->>'address', '')), 300), '') else address end,
    nif = case when v_patch ? 'nif' then nullif(regexp_replace(coalesce(v_patch->>'nif', ''), '[^0-9]', '', 'g'), '') else nif end,
    cin = case when v_patch ? 'cin' then nullif(left(trim(coalesce(v_patch->>'cin', '')), 32), '') else cin end,
    emergency_contact_name = case when v_patch ? 'emergency_contact_name' then nullif(left(trim(coalesce(v_patch->>'emergency_contact_name', '')), 120), '') else emergency_contact_name end,
    emergency_contact_phone = case when v_patch ? 'emergency_contact_phone' then nullif(left(trim(coalesce(v_patch->>'emergency_contact_phone', '')), 32), '') else emergency_contact_phone end,
    guardian_name = case when v_patch ? 'guardian_name' then nullif(left(trim(coalesce(v_patch->>'guardian_name', '')), 120), '') else guardian_name end,
    photo_url = case when v_patch ? 'photo_url' then v_photo else photo_url end,
    updated_at = clock_timestamp()
  where id = v_member.id;

  return jsonb_build_object('status', 'ok', 'member_id', v_member.id);
end;
$$;

revoke all on function public.member_portal_update_profile(uuid, jsonb) from public, anon;
grant execute on function public.member_portal_update_profile(uuid, jsonb) to authenticated;

-- Le membre peut téléverser UNIQUEMENT ses propres photos :
-- member-photos/<gym_id>/<member_id>/<fichier>.(jpg|jpeg|png)
create or replace function public.mp_can_write_photo(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from public.member_accounts ma
    where ma.user_id = auth.uid()
      and ma.gym_id::text = (storage.foldername(p_name))[1]
      and ma.member_id::text = (storage.foldername(p_name))[2])
$$;

revoke all on function public.mp_can_write_photo(text) from public;
grant execute on function public.mp_can_write_photo(text) to authenticated;

drop policy if exists member_portal_photo_insert on storage.objects;
create policy member_portal_photo_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'member-photos' and public.mp_can_write_photo(name));

drop policy if exists member_portal_photo_update on storage.objects;
create policy member_portal_photo_update on storage.objects
  for update to authenticated
  using (bucket_id = 'member-photos' and public.mp_can_write_photo(name))
  with check (bucket_id = 'member-photos' and public.mp_can_write_photo(name));

notify pgrst, 'reload schema';

commit;
