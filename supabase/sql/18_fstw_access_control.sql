-- =============================================================
-- 18_fstw_access_control.sql — GymDesk FSTW F30 Door Access,
-- Offline Resilience Queue, and Updated Platform Plans
-- =============================================================

begin;

-- -------------------------------------------------------------
-- 1. Ajoute kolòn pou PIN tanporè (pass 1 jou) nan tab 'members'
-- -------------------------------------------------------------
alter table public.members
  add column if not exists temporary_pin text,
  add column if not exists pin_expires_at timestamptz;

create index if not exists idx_members_pin_expires_at
  on public.members(gym_id, pin_expires_at)
  where pin_expires_at is not null;

-- -------------------------------------------------------------
-- 2. Kreye tab fstw_sync_queue pou file d'attente rezilyans
--    lè tèminal FSTW F30 la offline oswa rezo a gen mikwo-koupi
-- -------------------------------------------------------------
create table if not exists public.fstw_sync_queue (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  member_id uuid references public.members(id) on delete set null,
  action text not null check (action in ('sync_user', 'delete_user', 'set_pin')),
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending', 'processing', 'completed', 'failed')),
  attempts int not null default 0,
  last_error text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

-- Alias view pou konpatibilite 'sync_queue'
create or replace view public.sync_queue as
  select * from public.fstw_sync_queue;

create index if not exists idx_fstw_sync_queue_gym_status
  on public.fstw_sync_queue(gym_id, status, created_at asc);

alter table public.fstw_sync_queue enable row level security;

drop policy if exists fstw_sync_queue_read on public.fstw_sync_queue;
create policy fstw_sync_queue_read on public.fstw_sync_queue for select to authenticated
  using (gym_id = public.current_gym_id() or public.is_super_admin());

drop policy if exists fstw_sync_queue_write on public.fstw_sync_queue;
create policy fstw_sync_queue_write on public.fstw_sync_queue for all to authenticated
  using (gym_id = public.current_gym_id() or public.is_super_admin())
  with check (gym_id = public.current_gym_id() or public.is_super_admin());

grant select, insert, update, delete on public.fstw_sync_queue to authenticated;

-- Pèmèt Supabase Realtime difize evenman sou fstw_sync_queue
alter publication supabase_realtime add table public.fstw_sync_queue;

-- -------------------------------------------------------------
-- 3. Mete ajou katalòg 4 plan ofisyèl yo (platform_offers) :
--    - BASIC (Starter) : 150 manb, $950 USD/an. Byometri pòt enkli.
--      Kit materyèl & enstalasyon teknik enkli. Peman an 3 fwa ($550 / $200 / $200).
--    - MEDIUM (Growth) : 500 manb, $1,450 USD/an. Peman an 3 fwa ($850 / $300 / $300).
--    - PRO (Expansion) : 1 000 manb, $2,200 USD/an. 1 Tablèt Android gratis.
--      Peman an 3 fwa ($1,300 / $450 / $450).
--    - ENTERPRISE (Unlimited) : Manb Illimités, $3,200 USD/an. 1 Tablèt Android gratis.
--      Peman an 3 fwa ($1,800 / $700 / $700).
-- -------------------------------------------------------------
insert into public.platform_offers (id, name, description, billing_period, price, currency, config, active)
values
  (
    'plan_basic',
    'PLAN 1 : BASIC (Starter & Pòt Byometrik)',
    'Solisyon konplè pou ti sal jiska 150 manm avèk kontwòl aksè pòt byometrik.',
    'annual',
    950.00,
    'USD',
    jsonb_build_object(
      'max_members', 150,
      'overage_member_fee', 2.0,
      'badge_quota', 0,
      'includes_tablet', false,
      'tablet_count', 0,
      'tablet_optional_price', 180.0,
      'biometric_supported', true,
      'includes_door_access', true,
      'door_hardware_kit', 'Tèminal FSTW F30 TCP/IP + Lektè USB DigitalPersona 4500 + Ventouse 280kg + Bra LZ + Bouton sòti + Alimantasyon sekirize',
      'installation_included', true,
      'installments_allowed', true,
      'installment_1_amount', 550.0,
      'installment_2_amount', 200.0,
      'installment_3_amount', 200.0,
      'features', jsonb_build_array(
        'Jiska 150 manb aktif',
        'Depasman : +2.00 USD / manb extra',
        '✅ Sistèm Pòt Byometrik FSTW F30 Enkli',
        '✅ Lektè anprent USB DigitalPersona 4500 Enkli',
        '✅ Kit Materyèl pòt (Ventouse 280kg, Bra LZ, Bouton sòti, Alim) Enkli',
        '🛠️ Enstalasyon konplè sou plas pa yon ekip teknik',
        '💳 Posibilite Peman an 3 fwa : $550 akonpt + $200 (mwa 2) + $200 (mwa 3)',
        'Kòd PIN tanporè pou pas 1 jou',
        'Badj fizik opsyonèl (manb ka antre ak anprent sèlman)',
        'Sipò teknik & mizajou enkli'
      )
    ),
    true
  ),
  (
    'plan_medium',
    'PLAN 2 : MEDIUM (Growth & Pòt Byometrik)',
    'Pou sal an kwasans jiska 500 manm avèk jesyon pòt ak rapò finansye konplè.',
    'annual',
    1450.00,
    'USD',
    jsonb_build_object(
      'max_members', 500,
      'overage_member_fee', 2.5,
      'badge_quota', 0,
      'includes_tablet', false,
      'tablet_count', 0,
      'tablet_optional_price', 150.0,
      'biometric_supported', true,
      'includes_door_access', true,
      'door_hardware_kit', 'Tèminal FSTW F30 TCP/IP + Lektè USB DigitalPersona 4500 + Ventouse 280kg + Bra LZ + Bouton sòti + Alimantasyon sekirize',
      'installation_included', true,
      'installments_allowed', true,
      'installment_1_amount', 850.0,
      'installment_2_amount', 300.0,
      'installment_3_amount', 300.0,
      'features', jsonb_build_array(
        'Jiska 500 manb aktif',
        'Depasman : +2.50 USD / manb extra',
        '✅ Sistèm Pòt Byometrik FSTW F30 Enkli',
        '✅ Lektè anprent USB DigitalPersona 4500 Enkli',
        '✅ Kit Materyèl pòt konplè & Enstalasyon pa ekip teknik',
        '💳 Posibilite Peman an 3 fwa : $850 akonpt + $300 + $300',
        'Kòd PIN tanporè pou pas 1 jou',
        'Jesyon peman, rapò finansye avanse & resi',
        'Sipò priyoritè'
      )
    ),
    true
  ),
  (
    'plan_pro',
    'PLAN 3 : PRO (Expansion & Tablèt Gratis)',
    'Solisyon avanse avèk 1 tablèt Android gratis, 1000 manm, ak aksè pòt entegre.',
    'annual',
    2200.00,
    'USD',
    jsonb_build_object(
      'max_members', 1000,
      'overage_member_fee', 2.0,
      'badge_quota', 200,
      'includes_tablet', true,
      'tablet_count', 1,
      'biometric_supported', true,
      'includes_door_access', true,
      'door_hardware_kit', 'Tèminal FSTW F30 TCP/IP + Lektè USB DigitalPersona 4500 + Ventouse 280kg + Bra LZ + Bouton sòti + Alimantasyon sekirize',
      'installation_included', true,
      'installments_allowed', true,
      'installment_1_amount', 1300.0,
      'installment_2_amount', 450.0,
      'installment_3_amount', 450.0,
      'is_hot', true,
      'features', jsonb_build_array(
        'Jiska 1 000 manb aktif',
        'Depasman : +2.00 USD / manb extra',
        '📱 1 Tablèt Android GRATIS enkli pou akèy la',
        '✅ Sistèm Pòt Byometrik FSTW F30 Enkli',
        '✅ Lektè anprent USB DigitalPersona 4500 Enkli',
        '✅ Kit Materyèl pòt konplè & Enstalasyon pa ekip teknik',
        '💳 Posibilite Peman an 3 fwa : $1,300 akonpt + $450 + $450',
        '200 Badj fizik QR gratis (opsyonèl)',
        'Sipò priyoritè 24/7'
      )
    ),
    true
  ),
  (
    'plan_enterprise',
    'PLAN 4 : ENTERPRISE (Unlimited Performance)',
    'Akonpanyiman total san okenn limit manm, tablèt gratis, ak ekip teknik dedye.',
    'annual',
    3200.00,
    'USD',
    jsonb_build_object(
      'max_members', 0,
      'overage_member_fee', 0.0,
      'badge_quota', 500,
      'includes_tablet', true,
      'tablet_count', 1,
      'biometric_supported', true,
      'includes_door_access', true,
      'door_hardware_kit', 'Tèminal FSTW F30 TCP/IP + Lektè USB DigitalPersona 4500 + Ventouse 280kg + Bra LZ + Bouton sòti + Alimantasyon sekirize',
      'installation_included', true,
      'installments_allowed', true,
      'installment_1_amount', 1800.0,
      'installment_2_amount', 700.0,
      'installment_3_amount', 700.0,
      'features', jsonb_build_array(
        'MEMBRES ILLIMITÉS (San limit) 🚀',
        'Depasman manb : 0 USD (Tout enkli)',
        '📱 1 Tablèt Android GRATIS enkli',
        '✅ Sistèm Pòt Byometrik FSTW F30 Enkli',
        '✅ Lektè anprent USB DigitalPersona 4500 Enkli',
        '✅ Kit Materyèl pòt konplè & Enstalasyon pa ekip teknik',
        '💳 Posibilite Peman an 3 fwa : $1,800 akonpt + $700 + $700',
        '500 Badj fizik QR gratis (opsyonèl)',
        'Aksè API, rapò avanse & backup nwaj',
        'Responsab kont dedye'
      )
    ),
    true
  )
on conflict (id) do update set
  name = excluded.name,
  description = excluded.description,
  billing_period = excluded.billing_period,
  price = excluded.price,
  currency = excluded.currency,
  config = excluded.config,
  active = true;

-- -------------------------------------------------------------
-- 4. Mete ajou sync_branding pou aksepte nouvo paramèt pòt la
-- -------------------------------------------------------------
create or replace function public.sync_branding(
  p_operation uuid,
  p_entity text,
  p_payload jsonb,
  p_changed_at timestamptz,
  p_base_version timestamptz default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    g public.gyms; r public.sync_receipts; outcome text := 'accepted';
    v_logo text := nullif(p_payload->>'logo_url', '');
    v_settings jsonb := coalesce(p_payload->'settings', '{}'::jsonb);
begin
    if public.current_role() is distinct from 'owner' or public.current_gym_id() is null
      or p_entity is distinct from 'gyms' or (p_payload->>'id')::uuid is distinct from public.current_gym_id() then
        raise exception 'access_denied' using errcode = '42501';
    end if;
    if p_changed_at is null or p_changed_at > clock_timestamp() + interval '10 minutes' then
        raise exception 'invalid_clock' using errcode = '22023';
    end if;
    select * into strict g from public.gyms where id = public.current_gym_id() for update;
    select * into r from public.sync_receipts where id = p_operation;
    if found then
        if r.user_id <> auth.uid() or r.gym_id <> g.id or r.entity <> 'gyms' or r.entity_id <> g.id then
            raise exception 'access_denied' using errcode = '42501';
        end if;
        return jsonb_build_object('outcome', r.outcome, 'row', to_jsonb(g));
    end if;
    if p_base_version is distinct from g.updated_at then
        outcome := 'conflict';
    else
        if jsonb_typeof(v_settings) is distinct from 'object' then
            raise exception 'invalid_record' using errcode = '22023';
        end if;

        -- Whitelist elaji ki gen ladan paramèt pòt FSTW F30 ak byometri
        if exists(select 1 from jsonb_object_keys(v_settings) k where k not in (
            'doc_footer','offline_lease_hours','auto_logout_minutes','pin_lock_minutes',
            'allow_access_pending','grace_days','reception_see_all_payments','scan_sound',
            'scan_vibrate','entry_duplicate_seconds','qr_defaults',
            'badge_theme','badge_qr_style','badge_positions',
            'biometric_mode','biometric_enabled',
            'door_terminal_ip','door_terminal_port','door_terminal_enabled',
            'temporary_pin_duration_hours')) then
            raise exception 'invalid_record' using errcode = '22023';
        end if;

        if char_length(trim(coalesce(p_payload->>'name', ''))) not between 2 and 120
          or coalesce(p_payload->>'accent_color', '') !~ '^#[0-9A-Fa-f]{6}$'
          or coalesce(p_payload->>'currency', '') not in ('HTG','USD')
          or not exists(select 1 from pg_timezone_names where name = p_payload->>'timezone')
          or char_length(coalesce(p_payload->>'address', '')) > 500
          or char_length(coalesce(p_payload->>'phone', '')) > 32
          or char_length(coalesce(p_payload->>'email', '')) > 254
          or (coalesce(p_payload->>'email', '') <> '' and p_payload->>'email' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        if v_logo is not null and v_logo !~ '^https?://' and v_logo !~ '^gym-assets/[0-9a-fA-F-]{36}/' then
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        update public.gyms set
            name = trim(p_payload->>'name'),
            accent_color = p_payload->>'accent_color',
            currency = p_payload->>'currency',
            timezone = p_payload->>'timezone',
            address = nullif(trim(p_payload->>'address'), ''),
            phone = nullif(trim(p_payload->>'phone'), ''),
            email = nullif(trim(p_payload->>'email'), ''),
            logo_url = v_logo,
            settings = v_settings,
            updated_at = clock_timestamp()
        where id = g.id
        returning * into g;
    end if;
    insert into public.sync_receipts(id, gym_id, user_id, entity, entity_id, outcome)
    values (p_operation, g.id, auth.uid(), 'gyms', g.id, outcome);
    perform public.audit('branding_updated', 'gyms', g.id, jsonb_build_object('settings', v_settings));
    return jsonb_build_object('outcome', outcome, 'row', to_jsonb(g));
end;
$$;

revoke all on function public.sync_branding(uuid, text, jsonb, timestamptz, timestamptz) from public, anon;
grant execute on function public.sync_branding(uuid, text, jsonb, timestamptz, timestamptz) to authenticated;

-- -------------------------------------------------------------
-- 5. Fonksyon pou Job Minwi : process_daily_expirations
--    Idantifye manb ki ekspire oswa pas 1 jou ki fini,
--    epi anrejistre kòmand 'delete_user' nan fstw_sync_queue
-- -------------------------------------------------------------
create or replace function public.process_daily_expirations()
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_count int := 0;
  r record;
begin
  -- 1. Manb ki gen pas 1 jou ki ekspire (pin_expires_at <= now())
  for r in (
    select m.id as member_id, m.gym_id, m.first_name || ' ' || m.last_name as full_name
    from public.members m
    where m.deleted_at is null
      and m.pin_expires_at is not null
      and m.pin_expires_at <= clock_timestamp()
      and m.status = 'active'
  ) loop
    update public.members
    set status = 'expired',
        temporary_pin = null,
        updated_at = clock_timestamp()
    where id = r.member_id;

    insert into public.fstw_sync_queue (gym_id, member_id, action, payload, status)
    values (
      r.gym_id,
      r.member_id,
      'delete_user',
      jsonb_build_object('user_id', r.member_id, 'reason', 'temporary_pin_expired'),
      'pending'
    );
    v_count := v_count + 1;
  end loop;

  -- 2. Manb ki gen tout abònman yo ekspire (end_date < now()::date)
  for r in (
    select distinct m.id as member_id, m.gym_id, m.first_name || ' ' || m.last_name as full_name
    from public.members m
    where m.deleted_at is null
      and m.status = 'active'
      and not exists (
        select 1 from public.subscriptions s
        where s.member_id = m.id
          and s.gym_id = m.gym_id
          and s.deleted_at is null
          and s.status = 'active'
          and s.end_date >= current_date
      )
  ) loop
    update public.members
    set status = 'expired',
        updated_at = clock_timestamp()
    where id = r.member_id;

    insert into public.fstw_sync_queue (gym_id, member_id, action, payload, status)
    values (
      r.gym_id,
      r.member_id,
      'delete_user',
      jsonb_build_object('user_id', r.member_id, 'reason', 'subscription_expired'),
      'pending'
    );
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('success', true, 'expired_members_queued', v_count);
end;
$$;

grant execute on function public.process_daily_expirations() to authenticated;

commit;
