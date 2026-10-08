-- =============================================================
-- 08_v2_migration.sql — GymDesk V2 Migration
-- Idempotent migration for V2 SaaS upgrade, pre-printed badges,
-- 7-day trial, member PINs, kiosk scanner, supervisor role.
-- =============================================================

begin;

-- -------------------------------------------------------------
-- 1. Salles & Essai V2
-- -------------------------------------------------------------
alter table public.gyms
  add column if not exists trial_started_at timestamptz,
  add column if not exists trial_ends_at timestamptz,
  add column if not exists onboarding_done boolean default false,
  add column if not exists suspension_reason text,
  add column if not exists source text default 'admin';

-- Mise à jour de la contrainte de statut de gym pour accepter trial et grace
alter table public.gyms drop constraint if exists gyms_status_check;
alter table public.gyms add constraint gyms_status_check
  check (status in ('trial', 'active', 'grace', 'suspended'));

-- Plateforme / Offres / Paramètres
create table if not exists public.platform_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb
);

insert into public.platform_settings (key, value)
values
  ('payment_instructions', jsonb_build_object(
    'moncash', '+509 37 00 0000 (Cvisual Corp)',
    'natcash', '+509 40 00 0000 (Cvisual Corp)',
    'bank', 'Sogebank HTG #123456789 / Unibank USD #987654321',
    'contact_phone', '+509 37 00 0000',
    'whatsapp', '+509 37 00 0000',
    'email', 'billing@cvisual.net'
  )),
  ('trial_duration_days', '7'::jsonb)
on conflict (key) do nothing;

create table if not exists public.platform_offers (
  id text primary key,
  name text not null,
  description text,
  billing_period text not null check (billing_period in ('monthly', 'annual')),
  price numeric(12,2) not null check (price >= 0),
  currency text not null default 'USD',
  config jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp()
);

insert into public.platform_offers (id, name, description, billing_period, price, currency, config)
values
  ('per_member', 'Par Membre Actif', 'Idéal pour démarrer sans risque', 'monthly', 1.00, 'USD',
   jsonb_build_object('badge_quota', 50, 'min_monthly', 20.00, 'setup_fee', 50.00)),
  ('tiered', 'Paliers Fixes', 'Prix fixe mensuel prévisible', 'monthly', 45.00, 'USD',
   jsonb_build_object('badge_quota', 60, 'tiers', jsonb_build_array(
     jsonb_build_object('max_members', 60, 'price', 45, 'badge_quota', 30),
     jsonb_build_object('max_members', 120, 'price', 80, 'badge_quota', 60),
     jsonb_build_object('max_members', 250, 'price', 140, 'badge_quota', 100),
     jsonb_build_object('max_members', 500, 'price', 220, 'badge_quota', 100)
   ))),
  ('unlimited_annual', 'Illimité Annuel', 'Pour les grandes salles et chaînes', 'annual', 1500.00, 'USD',
   jsonb_build_object('badge_quota', 100, 'hardware_included', true))
on conflict (id) do nothing;

create table if not exists public.gym_contracts (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  offer_id text not null references public.platform_offers(id),
  status text not null default 'trial' check (status in ('trial', 'active', 'grace', 'expired', 'cancelled', 'suspended')),
  price_snapshot jsonb not null default '{}'::jsonb,
  starts_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create table if not exists public.payment_declarations (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  invoice_id uuid,
  method text not null check (method in ('moncash', 'natcash', 'bank', 'cash', 'other')),
  reference text,
  amount numeric(12,2) not null check (amount >= 0),
  currency text not null default 'USD',
  proof_path text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default clock_timestamp()
);

-- -------------------------------------------------------------
-- 2. Badges par lots & cycle de vie
-- -------------------------------------------------------------
create table if not exists public.badge_batches (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  label text not null,
  range_from int not null,
  range_to int not null,
  quantity int not null check (quantity > 0),
  source text not null check (source in ('trial', 'plan_allotment', 'extra_purchase')),
  invoice_id uuid,
  generated_by uuid references public.staff(id),
  created_at timestamptz not null default clock_timestamp()
);

create table if not exists public.badges (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  batch_id uuid references public.badge_batches(id) on delete set null,
  badge_number int not null,
  qr_token text not null unique,
  status text not null default 'unassigned' check (status in ('unassigned', 'bound', 'blocked', 'retired')),
  member_id uuid references public.members(id) on delete set null,
  bound_at timestamptz,
  bound_by uuid references public.staff(id),
  printed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (gym_id, badge_number)
);

create table if not exists public.badge_history (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  badge_id uuid not null references public.badges(id) on delete cascade,
  member_id uuid references public.members(id) on delete set null,
  event text not null check (event in ('generated', 'bound', 'released', 'blocked', 'replaced', 'revalidated')),
  actor_id uuid references public.staff(id),
  reason text,
  created_at timestamptz not null default clock_timestamp()
);

-- Vue dérivée : état réel d'un badge
create or replace view public.badge_state as
  select
    b.*,
    case
      when b.status <> 'bound' then b.status
      when exists (
        select 1 from public.subscriptions s
        join public.gyms g on g.id = s.gym_id
        where s.member_id = b.member_id
          and s.status in ('active')
          and s.deleted_at is null
          and (clock_timestamp() at time zone g.timezone)::date between s.start_date and s.end_date
      ) then 'valid'
      else 'lapsed'
    end as effective_state
  from public.badges b;

-- -------------------------------------------------------------
-- 3. Membres, PIN et Rôle Supervisor
-- -------------------------------------------------------------
alter table public.members
  add column if not exists badge_id uuid unique references public.badges(id) on delete set null,
  add column if not exists is_test boolean default false;

create table if not exists public.member_pins (
  member_id uuid primary key references public.members(id) on delete cascade,
  gym_id uuid not null references public.gyms(id) on delete cascade,
  pin_hash text not null,
  salt text not null,
  algo text not null default 'pbkdf2_sha256',
  iterations int not null default 210000,
  failed_count int not null default 0,
  total_failed int not null default 0,
  locked_until timestamptz,
  reset_required boolean not null default false,
  set_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

alter table public.attendance
  add column if not exists pin_verified boolean default false,
  add column if not exists badge_id uuid references public.badges(id) on delete set null;

-- Mise à jour de la contrainte result d'attendance pour la V2
alter table public.attendance drop constraint if exists attendance_result_check;
alter table public.attendance add constraint attendance_result_check check (result in (
  'granted',
  'denied_expired',
  'denied_no_subscription',
  'denied_pending_renewal',
  'denied_pending',
  'denied_suspended',
  'denied_unactivated',
  'denied_blocked_badge',
  'denied_bad_pin',
  'denied_pin_locked',
  'denied_duplicate',
  'denied_unknown'
));

-- Migration du rôle staff : 'manager' -> 'supervisor'
alter table public.staff drop constraint if exists staff_role_check;
update public.staff set role = 'supervisor' where role = 'manager';
alter table public.staff add constraint staff_role_check
  check (role in ('super_admin', 'owner', 'supervisor', 'reception'));

-- Renouvellements avec validation superviseur/owner
alter table public.subscriptions
  add column if not exists validated_by uuid references public.staff(id),
  add column if not exists validated_at timestamptz;

-- -------------------------------------------------------------
-- 4. Migration des données existantes (Idempotente)
-- -------------------------------------------------------------
do $$
declare
  r record;
  v_batch_id uuid;
  v_badge_id uuid;
  v_num int;
begin
  for r in select distinct m.gym_id from public.members m where m.badge_id is null loop
    -- Créer un lot de rattrapage rétroactif pour la salle
    v_batch_id := gen_random_uuid();
    insert into public.badge_batches (id, gym_id, label, range_from, range_to, quantity, source)
    values (v_batch_id, r.gym_id, 'Lot initial V1 (Migration)', 1, 9999,
      (select count(*) from public.members where gym_id = r.gym_id and badge_id is null), 'plan_allotment')
    on conflict do nothing;

    -- Créer les badges pour les membres existants
    for r in select * from public.members where gym_id = r.gym_id and badge_id is null order by created_at asc loop
      v_badge_id := gen_random_uuid();
      -- Extraire la valeur numérique de member_number (ex. PWR-000042 -> 42)
      v_num := coalesce(substring(r.member_number from '([0-9]+)$')::int, 1);
      -- Insérer badge bound
      insert into public.badges (id, gym_id, batch_id, badge_number, qr_token, status, member_id, bound_at)
      values (v_badge_id, r.gym_id, v_batch_id, v_num, r.qr_token, 'bound', r.id, r.created_at)
      on conflict (qr_token) do update set member_id = r.id, status = 'bound'
      returning id into v_badge_id;

      update public.members set badge_id = v_badge_id where id = r.id;

      -- Créer entrée member_pins avec reset_required = true
      insert into public.member_pins (member_id, gym_id, pin_hash, salt, algo, iterations, reset_required)
      values (r.id, r.gym_id, 'UNSET', 'UNSET', 'pbkdf2_sha256', 210000, true)
      on conflict (member_id) do nothing;

      insert into public.badge_history (id, gym_id, badge_id, member_id, event, reason)
      values (gen_random_uuid(), r.gym_id, v_badge_id, r.id, 'bound', 'Migration V1 vers V2')
      on conflict do nothing;
    end loop;
  end loop;
end $$;

-- -------------------------------------------------------------
-- 5. Index V2
-- -------------------------------------------------------------
create index if not exists idx_badges_gym_status on public.badges(gym_id, status);
create index if not exists idx_badges_qr on public.badges(qr_token);
create index if not exists idx_badges_member on public.badges(member_id);
create index if not exists idx_member_pins_gym on public.member_pins(gym_id);
create index if not exists idx_payment_declarations_status on public.payment_declarations(status);
create index if not exists idx_payment_declarations_gym on public.payment_declarations(gym_id);
create index if not exists idx_badge_batches_gym on public.badge_batches(gym_id);
create index if not exists idx_badge_history_badge on public.badge_history(badge_id);

-- -------------------------------------------------------------
-- 6. RLS sur les nouvelles tables
-- -------------------------------------------------------------
alter table public.platform_settings enable row level security;
create policy platform_settings_read on public.platform_settings for select to authenticated using (true);
create policy platform_settings_admin on public.platform_settings for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

alter table public.platform_offers enable row level security;
create policy platform_offers_read on public.platform_offers for select to authenticated using (true);
create policy platform_offers_admin on public.platform_offers for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

alter table public.gym_contracts enable row level security;
create policy gym_contracts_read on public.gym_contracts for select to authenticated
  using (public.is_super_admin() or gym_id = public.current_gym_id());
create policy gym_contracts_admin on public.gym_contracts for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

alter table public.payment_declarations enable row level security;
create policy declarations_read on public.payment_declarations for select to authenticated
  using (public.is_super_admin() or (gym_id = public.current_gym_id() and public.current_role() = 'owner'));
create policy declarations_insert on public.payment_declarations for insert to authenticated
  with check (gym_id = public.current_gym_id() and public.current_role() = 'owner');
create policy declarations_update on public.payment_declarations for update to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

alter table public.badge_batches enable row level security;
create policy badge_batches_read on public.badge_batches for select to authenticated
  using (public.is_super_admin() or gym_id = public.current_gym_id());
create policy badge_batches_manage on public.badge_batches for insert to authenticated
  with check (public.is_super_admin() or (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor')));

alter table public.badges enable row level security;
create policy badges_read on public.badges for select to authenticated
  using (public.is_super_admin() or gym_id = public.current_gym_id());
create policy badges_manage on public.badges for all to authenticated
  using (public.is_super_admin() or (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor')))
  with check (public.is_super_admin() or (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor')));

alter table public.badge_history enable row level security;
create policy badge_history_read on public.badge_history for select to authenticated
  using (public.is_super_admin() or gym_id = public.current_gym_id());
create policy badge_history_insert on public.badge_history for insert to authenticated
  with check (public.is_super_admin() or (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor', 'reception')));

alter table public.member_pins enable row level security;
create policy member_pins_read on public.member_pins for select to authenticated
  using (public.is_super_admin() or gym_id = public.current_gym_id());
create policy member_pins_manage on public.member_pins for all to authenticated
  using (public.is_super_admin() or (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor')))
  with check (public.is_super_admin() or (gym_id = public.current_gym_id() and public.current_role() in ('owner', 'supervisor')));

-- Publication Realtime Supabase
do $$ declare t text; begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['gyms', 'payment_declarations', 'badge_batches', 'badges', 'member_pins', 'subscriptions'] loop
      if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

commit;

-- -------------------------------------------------------------
-- 7. Mise à jour de sync_pull et sync_push pour les entités V2
-- -------------------------------------------------------------
create or replace function public.sync_pull(
  p_entity text,
  p_since timestamptz,
  p_until timestamptz,
  p_after_time timestamptz default null,
  p_after_id uuid default null,
  p_limit int default 250
)
returns setof jsonb
language plpgsql stable security invoker
set search_path = ''
as $$
declare
  v_column text;
begin
  if public.current_gym_id() is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  if p_entity not in (
    'staff', 'members', 'plans', 'subscriptions', 'payments', 'attendance',
    'badge_templates', 'audit_log', 'badge_batches', 'badges', 'badge_history',
    'member_pins', 'payment_declarations'
  ) or p_limit not between 1 and 500 then
    raise exception 'invalid_request' using errcode = '22023';
  end if;

  v_column := case
    when p_entity = 'attendance' then 'server_received_at'
    when p_entity in ('audit_log', 'badge_history', 'badge_batches', 'payment_declarations') then 'created_at'
    else 'updated_at'
  end;

  return query execute format(
    'select to_jsonb(t) from public.%1$I t where gym_id = $1 and %2$I >= $2 and %2$I <= $3 and ($4 is null or (%2$I, id) > ($4, $5)) order by %2$I, id limit $6',
    p_entity, v_column
  ) using public.current_gym_id(), p_since, p_until, p_after_time, p_after_id, p_limit;
end;
$$;

grant execute on function public.sync_pull(text, timestamptz, timestamptz, timestamptz, uuid, int) to authenticated;
