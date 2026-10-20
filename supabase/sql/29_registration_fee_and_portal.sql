-- =============================================================================
-- Migration 29 : Frais d'inscription, Motifs de paiement & Portail Membre
-- =============================================================================

begin;

-- 1. Colonnes de frais d'inscription et motifs sur public.payments
alter table public.payments
  add column if not exists registration_fee numeric(12,2) not null default 0,
  add column if not exists plan_fee numeric(12,2),
  add column if not exists payment_reason text;

-- 2. Colonne frais d'inscription sur public.plans
alter table public.plans
  add column if not exists registration_fee numeric(12,2) not null default 0;

-- 3. Table des demandes d'adhésion en ligne (Portail web membre)
create table if not exists public.portal_requests (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  plan_id uuid references public.plans(id) on delete set null,
  first_name text not null,
  last_name text not null,
  phone text not null,
  email text,
  kind text not null default 'new_membership' check (kind in ('new_membership', 'renewal')),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'completed')),
  member_id uuid references public.members(id) on delete set null,
  notes text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create index if not exists idx_portal_requests_gym_status on public.portal_requests(gym_id, status, created_at desc);

-- 4. Sécurité RLS pour portal_requests
alter table public.portal_requests enable row level security;

drop policy if exists portal_requests_select on public.portal_requests;
create policy portal_requests_select on public.portal_requests
  for select to authenticated
  using (is_super_admin() or gym_id = public.current_gym_id());

drop policy if exists portal_requests_update on public.portal_requests;
create policy portal_requests_update on public.portal_requests
  for update to authenticated
  using (is_super_admin() or (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'reception', 'manager')));

-- 5. RPC anonyme pour soumettre une demande depuis le portail web
create or replace function public.portal_submit(
  p_gym_code text,
  p_plan_id uuid,
  p_first_name text,
  p_last_name text,
  p_phone text,
  p_email text default null,
  p_kind text default 'new_membership',
  p_notes text default null
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
  -- 1. Valider la salle (par id ou slug/code)
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

  -- 2. Validation des champs obligatoires
  if p_first_name is null or length(trim(p_first_name)) < 2
     or p_last_name is null or length(trim(p_last_name)) < 2
     or p_phone is null or length(regexp_replace(p_phone, '\D', '', 'g')) < 8 then
    raise exception 'invalid_fields' using errcode = '22023';
  end if;

  if p_email is not null and trim(p_email) <> '' and p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'invalid_email' using errcode = '22023';
  end if;

  -- 3. Valider le plan si fourni
  if p_plan_id is not null then
    select * into v_plan from public.plans where id = p_plan_id and gym_id = v_gym.id and active = true and deleted_at is null;
    if not found then
      raise exception 'invalid_plan' using errcode = '22023';
    end if;
  end if;

  -- 4. Rate-limiting par téléphone (max 5 demandes pendantes par téléphone pour ce gym)
  select count(*) into v_recent_count
  from public.portal_requests
  where gym_id = v_gym.id
    and phone = trim(p_phone)
    and status = 'pending'
    and created_at > clock_timestamp() - interval '24 hours';

  if v_recent_count >= 5 then
    raise exception 'rate_limit_exceeded' using errcode = '22023';
  end if;

  -- 5. Insertion de la demande
  insert into public.portal_requests(
    gym_id, plan_id, first_name, last_name, phone, email, kind, notes
  )
  values(
    v_gym.id,
    p_plan_id,
    trim(p_first_name),
    trim(p_last_name),
    trim(p_phone),
    nullif(trim(p_email), ''),
    case when p_kind in ('new_membership', 'renewal') then p_kind else 'new_membership' end,
    nullif(trim(p_notes), '')
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

revoke all on function public.portal_submit(text, uuid, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.portal_submit(text, uuid, text, text, text, text, text, text) to anon, authenticated;

-- 6. RPC anonyme pour récupérer les infos publiques du gym et ses formules
create or replace function public.portal_get_gym(p_gym_code text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym public.gyms;
  v_plans jsonb;
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

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'name', p.name,
    'duration_days', p.duration_days,
    'price', p.price,
    'registration_fee', coalesce(p.registration_fee, 0),
    'currency', p.currency,
    'description', p.description
  ) order by p.price asc), '[]'::jsonb)
  into v_plans
  from public.plans p
  where p.gym_id = v_gym.id
    and p.active = true
    and p.deleted_at is null;

  return jsonb_build_object(
    'gym', jsonb_build_object(
      'id', v_gym.id,
      'name', v_gym.name,
      'currency', v_gym.currency,
      'logo_url', v_gym.logo_url
    ),
    'plans', v_plans
  );
end;
$$;

revoke all on function public.portal_get_gym(text) from public, anon, authenticated;
grant execute on function public.portal_get_gym(text) to anon, authenticated;

-- Activer le realtime si disponible
do $$
begin
  alter publication supabase_realtime add table public.portal_requests;
exception when others then
  null;
end $$;

commit;
