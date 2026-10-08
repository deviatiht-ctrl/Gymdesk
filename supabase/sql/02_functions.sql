-- =============================================================
-- 02_functions.sql — GymDesk
-- Fonctions métier, helpers RLS (security definer), triggers.
-- Prérequis : 01_schema.sql
-- =============================================================

-- -------------------------------------------------------------
-- Helpers d'identité — SECURITY DEFINER pour lire staff sans
-- récursion RLS (staff est lui-même protégé). search_path figé.
-- -------------------------------------------------------------
create or replace function public.current_staff_id()
returns uuid
language sql stable security definer
set search_path = public
as $$
    select s.id from public.staff s
    where s.user_id = auth.uid()
      and s.active
      and s.deleted_at is null
    limit 1
$$;

create or replace function public.current_gym_id()
returns uuid
language sql stable security definer
set search_path = public
as $$
    select s.gym_id from public.staff s
    where s.user_id = auth.uid()
      and s.active
      and s.deleted_at is null
    limit 1
$$;

create or replace function public.current_role()
returns text
language sql stable security definer
set search_path = public
as $$
    select s.role from public.staff s
    where s.user_id = auth.uid()
      and s.active
      and s.deleted_at is null
    limit 1
$$;

create or replace function public.is_super_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
    select coalesce(public.current_role() = 'super_admin', false)
$$;

-- Salle active ? (utilisé pour bloquer le sync d'une salle suspendue)
create or replace function public.is_gym_active(p_gym uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
    select coalesce(
        (select g.status = 'active' from public.gyms g where g.id = p_gym),
        false)
$$;

-- Lecture d'un réglage de salle sans passer par le RLS de gyms
-- (utilisé dans les politiques, ex. reception_see_all_payments)
create or replace function public.gym_setting(p_gym uuid, p_key text)
returns jsonb
language sql stable security definer
set search_path = public
as $$
    select g.settings -> p_key from public.gyms g where g.id = p_gym
$$;

create or replace function public.gym_setting_bool(p_gym uuid, p_key text)
returns boolean
language sql stable security definer
set search_path = public
as $$
    select coalesce((g.settings ->> p_key)::boolean, false)
    from public.gyms g where g.id = p_gym
$$;

-- -------------------------------------------------------------
-- Numérotation des membres
-- -------------------------------------------------------------

-- Incrémente gym_counters de façon atomique et retourne le
-- prochain numéro formaté « CODE-000124 ».
create or replace function public.next_member_number(p_gym uuid)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
    v_code text;
    v_seq  bigint;
begin
    if not public.is_gym_active(p_gym) then
        raise exception 'gym % introuvable ou suspendu', p_gym;
    end if;

    select g.code into v_code from public.gyms g where g.id = p_gym;

    insert into public.gym_counters (gym_id, member_seq)
    values (p_gym, 1)
    on conflict (gym_id) do update
        set member_seq = gym_counters.member_seq + 1
    returning member_seq into v_seq;

    return v_code || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

-- Réserve un BLOC de numéros pour un appareil qui travaille hors
-- ligne. Retourne la plage [seq_first, seq_last] et le préfixe.
-- L'appareil compose localement « CODE-000124 » pour chaque valeur.
create or replace function public.reserve_member_numbers(
    p_gym   uuid,
    p_count int
)
returns table (prefix text, seq_first bigint, seq_last bigint)
language plpgsql security definer
set search_path = public
as $$
declare
    v_code  text;
    v_first bigint;
    v_last  bigint;
begin
    if p_count is null or p_count < 1 or p_count > 500 then
        raise exception 'p_count doit être entre 1 et 500';
    end if;

    if not public.is_gym_active(p_gym) then
        raise exception 'gym % introuvable ou suspendu', p_gym;
    end if;

    -- seul le personnel de cette salle (ou super_admin) réserve des blocs
    if not (public.is_super_admin() or p_gym = public.current_gym_id()) then
        raise exception 'accès refusé';
    end if;

    select g.code into v_code from public.gyms g where g.id = p_gym;

    insert into public.gym_counters (gym_id, member_seq)
    values (p_gym, p_count)
    on conflict (gym_id) do update
        set member_seq = gym_counters.member_seq + p_count
    returning member_seq - p_count + 1, member_seq
    into v_first, v_last;

    prefix    := v_code || '-';
    seq_first := v_first;
    seq_last  := v_last;
    return next;
end;
$$;

-- Jeton QR cryptographiquement sûr (64 caractères hexadécimaux).
-- Généré normalement côté client ; fourni pour créations serveur.
-- gen_random_uuid() est intégré (PG13+) : aucune extension requise.
create or replace function public.gen_qr_token()
returns text
language sql volatile
set search_path = public
as $$
    select replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
$$;

-- -------------------------------------------------------------
-- Règle de validité — LA fonction de référence.
-- Un membre est valide à T ssi :
--   statut membre = 'active'
--   ET ∃ abonnement non annulé avec start_date <= date_locale(T) <= end_date
--   (date_locale dans le fuseau de la salle, bornes incluses)
--   (+ réglages salle : grace_days, allow_access_pending)
-- L'app reproduit EXACTEMENT cette logique en local pour le
-- scan hors ligne ; les tests unitaires Dart couvrent les deux.
-- -------------------------------------------------------------
create or replace function public.member_validity(
    p_member uuid,
    p_at     timestamptz default now()
)
returns table (
    valid           boolean,
    reason          text,
    subscription_id uuid,
    end_date        date,
    days_left       int
)
language plpgsql stable security definer
set search_path = public
as $$
declare
    m        record;
    g        record;
    s        record;
    v_today  date;
    v_grace  int;
begin
    select mem.status, mem.gym_id
      into m
      from public.members mem
     where mem.id = p_member
       and mem.deleted_at is null;

    if not found then
        valid := false; reason := 'unknown'; return next; return;
    end if;

    select g.timezone,
           coalesce((g.settings->>'grace_days')::int, 0) as grace_days,
           coalesce((g.settings->>'allow_access_pending')::boolean, false)
               as allow_pending,
           g.status as gym_status
      into g
      from public.gyms g where g.id = m.gym_id;

    if g.gym_status <> 'active' then
        valid := false; reason := 'gym_suspended'; return next; return;
    end if;

    v_today := (p_at at time zone g.timezone)::date;
    v_grace := g.grace_days;

    if m.status = 'suspended' then
        valid := false; reason := 'suspended'; return next; return;
    elsif m.status <> 'active' then
        valid := false; reason := 'archived'; return next; return;
    end if;

    -- abonnement couvrant la date locale (le plus récent d'abord)
    select s2.id, s2.end_date, s2.status
      into s
      from public.subscriptions s2
     where s2.member_id = p_member
       and s2.deleted_at is null
       and s2.status <> 'cancelled'
       and s2.start_date <= v_today
       and s2.end_date   + v_grace >= v_today
     order by s2.end_date desc
     limit 1;

    if found then
        subscription_id := s.id;
        end_date        := s.end_date;
        days_left       := s.end_date - v_today;
        if days_left < 0 then days_left := 0; end if;  -- en période de grâce
        if s.status = 'pending' and not g.allow_pending then
            valid := false; reason := 'pending_payment';
        else
            valid := true; reason := 'ok';
        end if;
        return next; return;
    end if;

    -- aucun abonnement valide : expiré ou jamais abonné ?
    select s2.end_date into s
      from public.subscriptions s2
     where s2.member_id = p_member
       and s2.deleted_at is null
       and s2.status <> 'cancelled'
     order by s2.end_date desc
     limit 1;

    if found then
        valid := false; reason := 'expired'; end_date := s.end_date;
        days_left := 0;
    else
        valid := false; reason := 'no_subscription';
    end if;
    return next;
end;
$$;

-- -------------------------------------------------------------
-- Expiration automatique : passe en 'expired' les abonnements
-- dont end_date est dépassé dans le fuseau de LEUR salle.
-- Appelée par pg_cron quotidiennement ET à la lecture côté app.
-- -------------------------------------------------------------
create or replace function public.compute_subscription_status()
returns int
language plpgsql security definer
set search_path = public
as $$
declare
    v_count int;
begin
    update public.subscriptions s
       set status     = 'expired',
           updated_at = now()
      from public.gyms g
     where s.gym_id = g.id
       and s.status in ('active','pending')
       and s.end_date < (now() at time zone g.timezone)::date
       and s.deleted_at is null;

    get diagnostics v_count = row_count;
    return v_count;
end;
$$;

-- Planification quotidienne si pg_cron est disponible
do $$
begin
    if exists (select 1 from pg_extension where extname = 'pg_cron') then
        perform cron.schedule(
            'gymdesk-expire-subscriptions',
            '5 0 * * *',
            'select public.compute_subscription_status()');
    end if;
end $$;

-- -------------------------------------------------------------
-- Audit : insertion tracée par l'app (ou les triggers) via cette
-- fonction ; actor_id/gym_id déduits de la session courante.
-- -------------------------------------------------------------
create or replace function public.audit(
    p_action    text,
    p_entity    text,
    p_entity_id uuid,
    p_details   jsonb default '{}'::jsonb,
    p_gym       uuid default null
)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
    v_id uuid;
begin
    insert into public.audit_log (gym_id, actor_id, action, entity, entity_id, details)
    values (coalesce(p_gym, public.current_gym_id()),
            public.current_staff_id(),
            p_action, p_entity, p_entity_id, p_details)
    returning id into v_id;
    return v_id;
end;
$$;

-- -------------------------------------------------------------
-- Trigger updated_at générique
-- -------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

do $$
declare
    t text;
begin
    foreach t in array array[
        'gyms','staff','gym_counters','members','plans',
        'subscriptions','payments','badge_templates']
    loop
        execute format(
            'create or replace trigger trg_%1$s_updated
             before update on public.%1$I
             for each row execute function public.set_updated_at()', t);
    end loop;
end $$;

-- -------------------------------------------------------------
-- attendance append-only : UPDATE/DELETE interdits, même pour
-- le propriétaire. Les erreurs de scan se corrigent par un
-- nouvel enregistrement, jamais par modification.
-- -------------------------------------------------------------
create or replace function public.attendance_immutable()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    raise exception 'attendance est append-only : % interdit', tg_op;
end;
$$;

create or replace trigger trg_attendance_no_update
    before update on public.attendance
    for each row execute function public.attendance_immutable();

create or replace trigger trg_attendance_no_delete
    before delete on public.attendance
    for each row execute function public.attendance_immutable();

-- -------------------------------------------------------------
-- Création automatique du compteur dès qu'une salle est créée
-- -------------------------------------------------------------
create or replace function public.init_gym_counter()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
    insert into public.gym_counters (gym_id) values (new.id)
    on conflict (gym_id) do nothing;
    return new;
end;
$$;

create or replace trigger trg_gyms_init_counter
    after insert on public.gyms
    for each row execute function public.init_gym_counter();

-- -------------------------------------------------------------
-- Droits d'exécution pour les clients authentifiés
-- -------------------------------------------------------------
grant execute on function public.reserve_member_numbers(uuid, int) to authenticated;
grant execute on function public.next_member_number(uuid)          to authenticated;
grant execute on function public.member_validity(uuid, timestamptz) to authenticated;
grant execute on function public.compute_subscription_status()      to authenticated;
grant execute on function public.audit(text, text, uuid, jsonb, uuid) to authenticated;
grant execute on function public.gen_qr_token()                     to authenticated;
grant execute on function public.is_gym_active(uuid)                to authenticated;
