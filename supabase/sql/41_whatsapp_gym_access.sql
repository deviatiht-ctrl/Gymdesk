-- ============================================================================
-- 41_whatsapp_gym_access.sql
-- Jesyon Aksè Abònman WhatsApp pou Gym yo pa Super Admin
-- Sipò Peryòd (Dat Debi, Dat Fen, Sispann, Renouvle, Nimewo Sekou)
-- ============================================================================
begin;

-- 1. Tablo aksè WhatsApp pou chak gym
create table if not exists public.gym_whatsapp_access (
  gym_id uuid primary key references public.gyms(id) on delete cascade,
  is_enabled boolean not null default false,
  status text not null default 'inactive' check (status in ('active', 'suspended', 'expired', 'inactive')),
  start_date timestamptz not null default clock_timestamp(),
  end_date timestamptz not null default (clock_timestamp() + interval '30 days'),
  backup_phone text,
  notes text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid
);

alter table public.gym_whatsapp_access enable row level security;
revoke all on public.gym_whatsapp_access from public, anon;
grant select on public.gym_whatsapp_access to authenticated;
grant all on public.gym_whatsapp_access to service_role;

-- 2. Fonksyon pou lis tout gym ak aksè WhatsApp yo (Pou Super Admin)
create or replace function public.platform_whatsapp_gym_access_list()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_caller uuid := auth.uid();
  v_is_super boolean := false;
  v_result jsonb;
begin
  -- Tcheke si apèl la fèt pa yon Super Admin
  select exists (
    select 1 from public.staff
    where user_id = v_caller
      and role = 'super_admin'
      and active is true
      and deleted_at is null
  ) into v_is_super;

  -- Si se pa super admin e pa service_role, refize aksè
  if not v_is_super and current_setting('role', true) <> 'service_role' then
    raise exception 'access_denied: Sèlman Super Admin SecurGYM ka jere aksè WhatsApp gym yo.';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'gym_id', g.id,
      'gym_name', g.name,
      'gym_code', g.code,
      'gym_phone', g.phone,
      'is_enabled', coalesce(a.is_enabled, false),
      'status', case
        when a.gym_id is null or a.is_enabled is not true then 'inactive'
        when a.status = 'suspended' then 'suspended'
        when a.end_date < clock_timestamp() then 'expired'
        else 'active'
      end,
      'start_date', coalesce(a.start_date, clock_timestamp()),
      'end_date', coalesce(a.end_date, clock_timestamp() + interval '30 days'),
      'backup_phone', coalesce(a.backup_phone, ''),
      'notes', coalesce(a.notes, ''),
      'days_remaining', case
        when a.end_date is not null and a.end_date > clock_timestamp() and a.status = 'active' and a.is_enabled is true
        then greatest(0, ceil(extract(epoch from (a.end_date - clock_timestamp())) / 86400)::int)
        else 0
      end,
      'is_valid', (
        coalesce(a.is_enabled, false) = true
        and coalesce(a.status, '') = 'active'
        and a.end_date > clock_timestamp()
      )
    ) order by g.name
  ), '[]'::jsonb) into v_result
  from public.gyms g
  left join public.gym_whatsapp_access a on a.gym_id = g.id
  where g.deleted_at is null;

  return v_result;
end $$;

revoke all on function public.platform_whatsapp_gym_access_list() from public, anon;
grant execute on function public.platform_whatsapp_gym_access_list() to authenticated;

-- 3. Fonksyon pou defini oswa mete ajou aksè WhatsApp yon gym (Super Admin sèlman)
create or replace function public.platform_whatsapp_gym_access_set(
  p_gym_id uuid,
  p_is_enabled boolean,
  p_status text default 'active',
  p_start_date timestamptz default clock_timestamp(),
  p_end_date timestamptz default (clock_timestamp() + interval '30 days'),
  p_backup_phone text default null,
  p_notes text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_caller uuid := auth.uid();
  v_is_super boolean := false;
  v_final_status text := p_status;
begin
  select exists (
    select 1 from public.staff
    where user_id = v_caller
      and role = 'super_admin'
      and active is true
      and deleted_at is null
  ) into v_is_super;

  if not v_is_super and current_setting('role', true) <> 'service_role' then
    raise exception 'access_denied: Sèlman Super Admin SecurGYM ka modifye aksè WhatsApp.';
  end if;

  if p_end_date < clock_timestamp() and p_is_enabled then
    v_final_status := 'expired';
  elsif not p_is_enabled then
    v_final_status := 'inactive';
  end if;

  insert into public.gym_whatsapp_access (
    gym_id,
    is_enabled,
    status,
    start_date,
    end_date,
    backup_phone,
    notes,
    updated_at,
    updated_by
  ) values (
    p_gym_id,
    p_is_enabled,
    v_final_status,
    p_start_date,
    p_end_date,
    nullif(trim(p_backup_phone), ''),
    p_notes,
    clock_timestamp(),
    v_caller
  )
  on conflict (gym_id) do update set
    is_enabled = excluded.is_enabled,
    status = excluded.status,
    start_date = excluded.start_date,
    end_date = excluded.end_date,
    backup_phone = excluded.backup_phone,
    notes = coalesce(excluded.notes, gym_whatsapp_access.notes),
    updated_at = clock_timestamp(),
    updated_by = v_caller;

  return jsonb_build_object(
    'ok', true,
    'gym_id', p_gym_id,
    'status', v_final_status,
    'is_enabled', p_is_enabled,
    'end_date', p_end_date
  );
end $$;

revoke all on function public.platform_whatsapp_gym_access_set(uuid, boolean, text, timestamptz, timestamptz, text, text) from public, anon;
grant execute on function public.platform_whatsapp_gym_access_set(uuid, boolean, text, timestamptz, timestamptz, text, text) to authenticated;

-- 4. Fonksyon pou tcheke aksè WhatsApp pou yon gym (Itilize pa kliyan anvan li voye)
create or replace function public.gym_whatsapp_access_check(p_gym_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_gym_id uuid := p_gym_id;
  v_caller uuid := auth.uid();
  v_access public.gym_whatsapp_access;
  v_status text;
  v_days_left int := 0;
  v_is_valid boolean := false;
  v_msg text;
begin
  -- Si p_gym_id pa bay, jwenn gym id staff k ap fè demann lan
  if v_gym_id is null then
    select gym_id into v_gym_id
    from public.staff
    where user_id = v_caller
      and active is true
      and deleted_at is null
    limit 1;
  end if;

  if v_gym_id is null then
    return jsonb_build_object(
      'has_access', false,
      'status', 'inactive',
      'days_remaining', 0,
      'message', 'Gym pa rekonèt.'
    );
  end if;

  select * into v_access from public.gym_whatsapp_access where gym_id = v_gym_id;

  if v_access.gym_id is null or not v_access.is_enabled then
    v_status := 'inactive';
    v_is_valid := false;
    v_msg := 'Sèvis WhatsApp SecurGYM la pa aktif pou gym ou a. Tanpri kontakte SecurGYM pou aktive li.';
  elsif v_access.status = 'suspended' then
    v_status := 'suspended';
    v_is_valid := false;
    v_msg := 'Sèvis WhatsApp SecurGYM la sispann (an poz) pou gym ou a. Tanpri kontakte SecurGYM.';
  elsif v_access.end_date < clock_timestamp() then
    v_status := 'expired';
    v_is_valid := false;
    v_msg := 'Abònman WhatsApp SecurGYM ou a ekspire depi ' || to_char(v_access.end_date, 'DD/MM/YYYY') || '. Tanpri renouvle abònman an pou w ka voye mesaj.';
  else
    v_status := 'active';
    v_is_valid := true;
    v_days_left := greatest(0, ceil(extract(epoch from (v_access.end_date - clock_timestamp())) / 86400)::int);
    v_msg := 'Aksè WhatsApp SecurGYM aktif (' || v_days_left || ' jou ki rete).';
  end if;

  return jsonb_build_object(
    'has_access', v_is_valid,
    'status', v_status,
    'gym_id', v_gym_id,
    'start_date', v_access.start_date,
    'end_date', v_access.end_date,
    'days_remaining', v_days_left,
    'backup_phone', coalesce(v_access.backup_phone, ''),
    'message', v_msg
  );
end $$;

revoke all on function public.gym_whatsapp_access_check(uuid) from public, anon;
grant execute on function public.gym_whatsapp_access_check(uuid) to authenticated;

commit;
