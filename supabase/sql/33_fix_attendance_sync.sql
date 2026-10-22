-- =============================================================
-- 33_fix_attendance_sync.sql — Fix Présences · Création (attendance sync)
-- 1. Ajoute la surcharge 3-arguments public.member_validity(p_gym, p_member, p_at)
--    appelée par sync_push lors de l'insertion de présences (attendance).
-- 2. Autorise les salles en statut 'trial' et 'grace' dans member_validity.
-- 3. Élargit la politique RLS attendance_insert au rôle 'supervisor'.
-- 4. Ajoute fingerprint_backup_template sur public.members si absent.
-- Idempotent : peut être ré-exécuté sans risque.
-- =============================================================

begin;

-- 1. Colonne pour le second doigt biométrique
alter table public.members
  add column if not exists fingerprint_backup_template text;

-- 2. Mise à jour de member_validity(uuid, timestamptz) pour accepter 'active', 'trial', 'grace'
create or replace function public.member_validity(
    p_member uuid,
    p_at     timestamptz default now()
)
returns table(
    valid           boolean,
    reason          text,
    subscription_id uuid,
    end_date        date,
    days_left       int
)
language plpgsql stable security definer
set search_path = ''
as $$
declare
    v_member  public.members;
    v_gym     public.gyms;
    v_sub     public.subscriptions;
    v_date    date;
    v_grace   int;
    v_pending boolean;
begin
    select * into v_member from public.members m where m.id = p_member and m.deleted_at is null;
    if not found then
        return query select false, 'unknown'::text, null::uuid, null::date, null::int;
        return;
    end if;

    select * into strict v_gym from public.gyms g where g.id = v_member.gym_id;
    if v_gym.status not in ('active', 'trial', 'grace') then
        return query select false, 'gym_suspended'::text, null::uuid, null::date, null::int;
        return;
    end if;

    if v_member.status <> 'active' then
        return query select false, v_member.status, null::uuid, null::date, null::int;
        return;
    end if;

    v_date := (p_at at time zone v_gym.timezone)::date;
    v_grace := greatest(0, least(365, coalesce((v_gym.settings->>'grace_days')::int, 0)));
    v_pending := coalesce((v_gym.settings->>'allow_access_pending')::boolean, false);

    select * into v_sub from public.subscriptions s
    where s.member_id = p_member
      and s.gym_id = v_member.gym_id
      and s.deleted_at is null
      and (s.status = 'active' or (v_pending and s.status = 'pending'))
      and v_date between s.start_date and (s.end_date + v_grace)
    order by s.end_date desc
    limit 1;

    if found then
        return query select true, 'ok'::text, v_sub.id, v_sub.end_date, (v_sub.end_date - v_date)::int;
        return;
    end if;

    select * into v_sub from public.subscriptions s
    where s.member_id = p_member
      and s.gym_id = v_member.gym_id
      and s.deleted_at is null
      and s.status <> 'cancelled'
    order by s.end_date desc
    limit 1;

    if not found then
        return query select false, 'no_subscription'::text, null::uuid, null::date, null::int;
    elsif v_sub.status = 'pending' and not v_pending then
        return query select false, 'pending_payment'::text, v_sub.id, v_sub.end_date, (v_sub.end_date - v_date)::int;
    else
        return query select false, 'expired'::text, v_sub.id, v_sub.end_date, (v_sub.end_date - v_date)::int;
    end if;
end;
$$;

-- 3. Surcharge 3-arguments public.member_validity(p_gym, p_member, p_at) appelée par sync_push
create or replace function public.member_validity(
    p_gym    uuid,
    p_member uuid,
    p_at     timestamptz default now()
)
returns table(
    valid           boolean,
    reason          text,
    subscription_id uuid,
    end_date        date,
    days_left       int
)
language sql stable security definer
set search_path = ''
as $$
    select mv.valid, mv.reason, mv.subscription_id, mv.end_date, mv.days_left
    from public.member_validity(p_member, p_at) mv;
$$;

grant execute on function public.member_validity(uuid, timestamptz) to authenticated;
grant execute on function public.member_validity(uuid, uuid, timestamptz) to authenticated;

-- 4. Politique RLS attendance_insert incluant 'supervisor'
drop policy if exists attendance_insert on public.attendance;
create policy attendance_insert on public.attendance
for insert to authenticated
with check (
    gym_id = public.current_gym_id()
    and public.current_role() in ('owner', 'manager', 'supervisor', 'reception')
);

commit;
