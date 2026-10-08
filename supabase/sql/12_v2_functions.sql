-- =============================================================
-- 12_v2_functions.sql — GymDesk V2 Server Functions & Cron
-- RPCs for trial access state, badge batches, activation,
-- lifecycle, member PIN reset, and pg_cron trial jobs.
-- =============================================================

begin;

-- -------------------------------------------------------------
-- 1. État d'accès de la salle (gym_access_state)
-- -------------------------------------------------------------
create or replace function public.gym_access_state(p_gym uuid)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_gym public.gyms;
  v_now timestamptz := clock_timestamp();
  v_days_left int := 0;
  v_is_trial boolean := false;
  v_effective_status text;
  v_suspension_reason text;
begin
  select * into v_gym from public.gyms where id = p_gym and deleted_at is null;
  if not found then
    return jsonb_build_object('error', 'gym_not_found', 'accessible', false);
  end if;

  v_suspension_reason := v_gym.suspension_reason;
  v_effective_status := v_gym.status;

  -- Vérification d'expiration d'essai
  if v_gym.status = 'trial' or (v_gym.trial_ends_at is not null and v_gym.trial_ends_at > v_now) then
    if v_gym.trial_ends_at is not null and v_now > v_gym.trial_ends_at then
      v_effective_status := 'suspended';
      v_suspension_reason := 'trial_expired';
    else
      v_is_trial := true;
      v_effective_status := 'trial';
      v_days_left := greatest(0, ceil(extract(epoch from (v_gym.trial_ends_at - v_now)) / 86400)::int);
    end if;
  end if;

  return jsonb_build_object(
    'gym_id', v_gym.id,
    'status', v_effective_status,
    'is_trial', v_is_trial,
    'days_left', v_days_left,
    'trial_ends_at', v_gym.trial_ends_at,
    'accessible', (v_effective_status in ('active', 'trial', 'grace')),
    'suspension_reason', v_suspension_reason,
    'server_time', v_now
  );
end;
$$;

-- -------------------------------------------------------------
-- 2. Génération de lot de badges avec contrôle de quota
-- -------------------------------------------------------------
create or replace function public.generate_badge_batch(
  p_gym uuid,
  p_quantity int,
  p_source text default 'plan_allotment'
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym public.gyms;
  v_contract public.gym_contracts;
  v_offer public.platform_offers;
  v_total_badges int;
  v_max_quota int := 10;
  v_last_number int;
  v_batch_id uuid := gen_random_uuid();
  v_i int;
  v_token text;
  v_label text;
begin
  if p_gym is distinct from public.current_gym_id() and not public.is_super_admin() then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  if public.current_role() not in ('owner', 'supervisor') and not public.is_super_admin() then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity <= 0 or p_quantity > 500 then
    raise exception 'invalid_quantity' using errcode = '22023';
  end if;

  select * into strict v_gym from public.gyms where id = p_gym for update;

  -- Déterminer le quota selon contrat / offre
  select * into v_contract from public.gym_contracts
  where gym_id = p_gym and status in ('active', 'trial', 'grace')
  order by created_at desc limit 1;

  if v_contract.offer_id is not null then
    select * into v_offer from public.platform_offers where id = v_contract.offer_id;
    if v_contract.status = 'trial' then
      v_max_quota := 10;
    else
      v_max_quota := coalesce((v_offer.config->>'badge_quota')::int, 50);
    end if;
  elsif v_gym.status = 'trial' then
    v_max_quota := 10;
  end if;

  select count(*) into v_total_badges from public.badges where gym_id = p_gym;

  if (v_total_badges + p_quantity) > v_max_quota and p_source <> 'extra_purchase' and not public.is_super_admin() then
    raise exception 'badge_quota_exceeded' using errcode = 'P0001';
  end if;

  select coalesce(max(badge_number), 0) into v_last_number from public.badges where gym_id = p_gym;

  v_label := 'Lot #' || (coalesce((select count(*) from public.badge_batches where gym_id = p_gym), 0) + 1);

  insert into public.badge_batches (id, gym_id, label, range_from, range_to, quantity, source, generated_by)
  values (v_batch_id, p_gym, v_label, v_last_number + 1, v_last_number + p_quantity, p_quantity, p_source, public.current_staff_id());

  for v_i in 1..p_quantity loop
    -- Jeton sécurisé 32 caractères
    v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    insert into public.badges (id, gym_id, batch_id, badge_number, qr_token, status)
    values (gen_random_uuid(), p_gym, v_batch_id, v_last_number + v_i, v_token, 'unassigned');
  end loop;

  insert into public.badge_history (id, gym_id, badge_id, event, actor_id, reason)
  select gen_random_uuid(), p_gym, b.id, 'generated', public.current_staff_id(), 'Génération de lot ' || v_label
  from public.badges b where b.batch_id = v_batch_id;

  return jsonb_build_object(
    'batch_id', v_batch_id,
    'range_from', v_last_number + 1,
    'range_to', v_last_number + p_quantity,
    'quantity', p_quantity,
    'quota_used', v_total_badges + p_quantity,
    'quota_max', v_max_quota
  );
end;
$$;

-- -------------------------------------------------------------
-- 3. Libération, Blocage et Remplacement de Badge
-- -------------------------------------------------------------
create or replace function public.release_badge(p_badge uuid, p_reason text default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_badge public.badges;
  v_effective_state text;
begin
  if public.current_role() <> 'owner' and not public.is_super_admin() then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  select * into strict v_badge from public.badges where id = p_badge and gym_id = public.current_gym_id() for update;
  select effective_state into v_effective_state from public.badge_state where id = p_badge;

  if v_badge.status <> 'bound' or v_effective_state = 'valid' then
    raise exception 'badge_cannot_be_released' using errcode = 'P0001';
  end if;

  -- Supprimer PIN et lien membre
  delete from public.member_pins where member_id = v_badge.member_id;
  update public.members set badge_id = null, status = 'archived' where id = v_badge.member_id;

  update public.badges
  set status = 'unassigned', member_id = null, bound_at = null, bound_by = null, updated_at = clock_timestamp()
  where id = p_badge returning * into v_badge;

  insert into public.badge_history (id, gym_id, badge_id, member_id, event, actor_id, reason)
  values (gen_random_uuid(), v_badge.gym_id, p_badge, v_badge.member_id, 'released', public.current_staff_id(), coalesce(p_reason, 'Libération du badge'));

  return to_jsonb(v_badge);
end;
$$;

create or replace function public.block_badge(p_badge uuid, p_reason text default 'Perte ou vol')
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_badge public.badges;
begin
  if public.current_role() not in ('owner', 'supervisor') and not public.is_super_admin() then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  select * into strict v_badge from public.badges where id = p_badge and gym_id = public.current_gym_id() for update;

  update public.badges
  set status = 'blocked', updated_at = clock_timestamp()
  where id = p_badge returning * into v_badge;

  insert into public.badge_history (id, gym_id, badge_id, member_id, event, actor_id, reason)
  values (gen_random_uuid(), v_badge.gym_id, p_badge, v_badge.member_id, 'blocked', public.current_staff_id(), p_reason);

  return to_jsonb(v_badge);
end;
$$;

create or replace function public.replace_badge(p_old_badge uuid, p_new_badge uuid, p_reason text default 'Remplacement')
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_old public.badges;
  v_new public.badges;
  v_member_id uuid;
begin
  if public.current_role() not in ('owner', 'supervisor') and not public.is_super_admin() then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  select * into strict v_old from public.badges where id = p_old_badge and gym_id = public.current_gym_id() for update;
  select * into strict v_new from public.badges where id = p_new_badge and gym_id = public.current_gym_id() for update;

  if v_new.status <> 'unassigned' then
    raise exception 'new_badge_not_available' using errcode = 'P0001';
  end if;

  v_member_id := v_old.member_id;

  -- Bloquer l'ancien
  update public.badges set status = 'blocked', updated_at = clock_timestamp() where id = p_old_badge;
  insert into public.badge_history (id, gym_id, badge_id, member_id, event, actor_id, reason)
  values (gen_random_uuid(), v_old.gym_id, p_old_badge, v_member_id, 'blocked', public.current_staff_id(), 'Remplacé par badge #' || v_new.badge_number);

  -- Attribuer le nouveau au même membre
  update public.badges
  set status = 'bound', member_id = v_member_id, bound_at = clock_timestamp(), bound_by = public.current_staff_id(), updated_at = clock_timestamp()
  where id = p_new_badge;

  update public.members set badge_id = p_new_badge, updated_at = clock_timestamp() where id = v_member_id;

  -- Forcer redéfinition du PIN
  update public.member_pins set reset_required = true, updated_at = clock_timestamp() where member_id = v_member_id;

  insert into public.badge_history (id, gym_id, badge_id, member_id, event, actor_id, reason)
  values (gen_random_uuid(), v_new.gym_id, p_new_badge, v_member_id, 'replaced', public.current_staff_id(), p_reason);

  return jsonb_build_object('success', true, 'member_id', v_member_id, 'badge_id', p_new_badge);
end;
$$;

-- -------------------------------------------------------------
-- 4. Droits d'exécution RPC
-- -------------------------------------------------------------
grant execute on function public.gym_access_state(uuid) to authenticated;
grant execute on function public.generate_badge_batch(uuid, int, text) to authenticated;
grant execute on function public.release_badge(uuid, text) to authenticated;
grant execute on function public.block_badge(uuid, text) to authenticated;
grant execute on function public.replace_badge(uuid, uuid, text) to authenticated;

-- -------------------------------------------------------------
-- 5. pg_cron : suspension automatique des essais expirés
-- -------------------------------------------------------------
create or replace function public.cron_suspend_expired_trials()
returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  update public.gyms
  set status = 'suspended',
      suspension_reason = 'trial_expired',
      updated_at = clock_timestamp()
  where status = 'trial'
    and trial_ends_at < clock_timestamp()
    and not exists (
      select 1 from public.gym_contracts c
      where c.gym_id = gyms.id and c.status = 'active'
    );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'gymdesk-suspend-trials',
      '* * * * *',
      'select public.cron_suspend_expired_trials()'
    );
  end if;
end $$;

commit;
