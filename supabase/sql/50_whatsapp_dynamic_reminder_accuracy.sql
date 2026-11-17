-- ============================================================================
-- 49_whatsapp_dynamic_reminder_accuracy.sql
-- 1. Nettoyage et purge automatique des rappels d'expiration obsolètes dans l'outbox :
--    - Annule tout rappel J-7 en attente dès que le membre atteint J-2 ou moins.
--    - Annule tout rappel en attente pour les membres ayant déjà renouvelé leur formule.
--    - Annule tout rappel dont l'échéance est déjà dépassée (J-0 ou expiré).
-- 2. Mise à jour de cron_check_whatsapp_expiration_reminders avec purge automatique
--    et remplacement dynamique du jalon J-7 par J-2 sans doublon.
-- ============================================================================
begin;

-- 1. Fonksyon pou netwaye tout vye rapèl ki te rete nan outbox k ap tann
create or replace function public.platform_whatsapp_purge_stale_reminders()
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_cancelled_renewed int := 0;
  v_cancelled_superseded int := 0;
  v_cancelled_expired int := 0;
begin
  -- A. Anile nenpòt rapèl ki nan outbox k ap tann si manm nan te deja renouvle pou pi lwen
  with renewed as (
    update public.whatsapp_messages_outbox o
    set status = 'cancelled',
        error_message = 'Manm lan deja renouvle abònman li'
    where o.status = 'pending'
      and o.kind in ('reminder_7d', 'reminder_2d')
      and exists (
        select 1 from public.subscriptions s
        join public.members m on m.id = s.member_id
        where (
          o.to_phone = ('509' || regexp_replace(coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')), '\D', '', 'g'))
          or o.to_phone = regexp_replace(coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')), '\D', '', 'g')
        )
        and s.deleted_at is null
        and s.status in ('active', 'pending')
        and s.end_date::date > (clock_timestamp()::date + 7)
      )
    returning o.id
  )
  select count(*) into v_cancelled_renewed from renewed;

  -- B. Anile nenpòt rapèl J-7 ki nan outbox k ap tann si manm nan rive nan J-2 oswa mwens jodi a
  with superseded as (
    update public.whatsapp_messages_outbox o
    set status = 'cancelled',
        error_message = 'Ranplase pa rapèl J-2 pi fre'
    where o.status = 'pending'
      and o.kind = 'reminder_7d'
      and exists (
        select 1 from public.subscriptions s
        join public.members m on m.id = s.member_id
        join public.gyms g on g.id = s.gym_id
        where (
          o.to_phone = ('509' || regexp_replace(coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')), '\D', '', 'g'))
          or o.to_phone = regexp_replace(coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')), '\D', '', 'g')
        )
        and s.deleted_at is null
        and s.status in ('active', 'pending')
        and (s.end_date::date - (clock_timestamp() at time zone coalesce(g.timezone, 'America/Port-au-Prince'))::date) <= 2
      )
    returning o.id
  )
  select count(*) into v_cancelled_superseded from superseded;

  -- C. Anile nenpòt rapèl ki nan outbox k ap tann si abònman an fini oswa ekspire deja
  with expired as (
    update public.whatsapp_messages_outbox o
    set status = 'cancelled',
        error_message = 'Abònman an ekspire deja'
    where o.status = 'pending'
      and o.kind in ('reminder_7d', 'reminder_2d')
      and exists (
        select 1 from public.subscriptions s
        join public.members m on m.id = s.member_id
        join public.gyms g on g.id = s.gym_id
        where (
          o.to_phone = ('509' || regexp_replace(coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')), '\D', '', 'g'))
          or o.to_phone = regexp_replace(coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')), '\D', '', 'g')
        )
        and s.deleted_at is null
        and s.end_date::date <= (clock_timestamp() at time zone coalesce(g.timezone, 'America/Port-au-Prince'))::date
      )
    returning o.id
  )
  select count(*) into v_cancelled_expired from expired;

  return jsonb_build_object(
    'ok', true,
    'cancelled_renewed', v_cancelled_renewed,
    'cancelled_superseded', v_cancelled_superseded,
    'cancelled_expired', v_cancelled_expired,
    'total_cleaned', (v_cancelled_renewed + v_cancelled_superseded + v_cancelled_expired),
    'timestamp', clock_timestamp()
  );
end $$;

-- 2. Mete ajou cron_check_whatsapp_expiration_reminders
create or replace function public.cron_check_whatsapp_expiration_reminders(
  p_target_gym_id uuid default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_gym record;
  v_sub record;
  v_milestone text;
  v_diff int;
  v_today date;
  v_portal_url text;
  v_clean_phone text;
  v_formatted_date text;
  v_queued_count int := 0;
  v_already_exists boolean;
  v_msg text;
  v_seed int;
  v_greeting text;
  v_intro text;
  v_detail text;
  v_action text;
  v_footer text;
  v_ref_hash text;
begin
  -- 1. Premyèman, purge tout vye rapèl ki pa valid ankò
  perform public.platform_whatsapp_purge_stale_reminders();

  -- Boucle sou tout gym ki gen aksè WhatsApp aktif
  for v_gym in
    select 
      g.id as gym_id,
      g.name as gym_name,
      coalesce(g.phone, '') as gym_phone,
      coalesce(g.timezone, 'America/Port-au-Prince') as timezone,
      coalesce(a.backup_phone, '') as backup_phone
    from public.gym_whatsapp_access a
    join public.gyms g on g.id = a.gym_id
    where a.is_enabled is true
      and a.status = 'active'
      and a.end_date > clock_timestamp()
      and g.deleted_at is null
      and (p_target_gym_id is null or g.id = p_target_gym_id)
  loop
    v_today := (clock_timestamp() at time zone v_gym.timezone)::date;
    v_portal_url := 'https://securgym.com/m/' || v_gym.gym_id::text;

    for v_sub in
      select 
        s.id as sub_id,
        s.member_id,
        s.end_date::date as end_date,
        coalesce(p.name, 'Abonnement Gym') as plan_name,
        m.first_name,
        m.last_name,
        coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')) as raw_phone,
        (s.end_date::date - v_today) as days_diff
      from public.subscriptions s
      join public.members m on m.id = s.member_id
      left join public.plans p on p.id = s.plan_id
      where s.gym_id = v_gym.gym_id
        and s.deleted_at is null
        and s.status in ('active', 'pending')
        and m.deleted_at is null
        and (s.end_date::date - v_today) in (7, 2)
        -- Sote manm ki deja gen yon lòt abònman pi lwen (deja renouvle)
        and not exists (
          select 1 from public.subscriptions n
          where n.member_id = s.member_id
            and n.gym_id = s.gym_id
            and n.id <> s.id
            and n.deleted_at is null
            and n.status in ('active', 'pending')
            and n.end_date > s.end_date
        )
      order by s.end_date asc
    loop
      v_diff := v_sub.days_diff;
      if v_sub.raw_phone is null or length(regexp_replace(v_sub.raw_phone, '\D', '', 'g')) < 8 then
        continue;
      end if;

      v_clean_phone := regexp_replace(v_sub.raw_phone, '\D', '', 'g');
      if length(v_clean_phone) = 8 then
        v_clean_phone := '509' || v_clean_phone;
      end if;

      if v_diff = 7 then
        v_milestone := 'reminder_7d';
      elsif v_diff = 2 then
        v_milestone := 'reminder_2d';
      else
        continue;
      end if;

      -- Si se rapèl J-2, anile nenpòt vye rapèl J-7 ki te nan outbox k ap tann
      if v_diff = 2 then
        update public.whatsapp_messages_outbox
        set status = 'cancelled',
            error_message = 'Ranplase pa rapèl J-2 pi fre'
        where (gym_id = v_gym.gym_id or gym_id is null)
          and to_phone = v_clean_phone
          and kind = 'reminder_7d'
          and status = 'pending';
      end if;

      -- Anti-Doublon 1 : verifye logs (pa janm voye menm jalon an 2 fwa)
      select exists (
        select 1 from public.whatsapp_notification_logs l
        where l.gym_id = v_gym.gym_id
          and l.kind = v_milestone
          and (l.member_id = v_sub.member_id or l.recipient_phone = v_clean_phone)
          and (
            l.metadata->>'subscription_id' = v_sub.sub_id::text
            or l.created_at >= (clock_timestamp() - interval '6 days')
          )
      ) into v_already_exists;

      if v_already_exists then
        continue;
      end if;

      -- Anti-Doublon 2 : verifye outbox (pending, processing, sent)
      select exists (
        select 1 from public.whatsapp_messages_outbox o
        where (o.gym_id = v_gym.gym_id or o.gym_id is null)
          and o.kind = v_milestone
          and (o.to_phone = v_clean_phone or o.to_phone = v_sub.raw_phone)
          and o.status in ('pending', 'processing', 'sent')
          and o.created_at >= (clock_timestamp() - interval '6 days')
      ) into v_already_exists;

      if v_already_exists then
        continue;
      end if;

      v_formatted_date := to_char(v_sub.end_date, 'DD/MM/YYYY');
      v_seed := floor(random() * 4)::integer;
      v_ref_hash := substr(md5(random()::text || clock_timestamp()::text), 1, 6);

      if v_seed = 0 then
        v_greeting := 'Bonjour ' || v_sub.first_name || ' ! 👋';
      elsif v_seed = 1 then
        v_greeting := 'Bonjour cher(e) ' || v_sub.first_name || ' ' || v_sub.last_name || ' ! 🏋️';
      elsif v_seed = 2 then
        v_greeting := 'Salutations ' || v_sub.first_name || ' ! ✨';
      else
        v_greeting := 'Cher(e) membre ' || v_sub.first_name || ', bonjour ! 🏃';
      end if;

      if v_seed in (0, 2) then
        v_intro := 'Votre salle *' || v_gym.gym_name || '* vous informe :';
      else
        v_intro := 'L''équipe *' || v_gym.gym_name || '* vous transmet ce rappel :';
      end if;

      if v_diff = 7 then
        v_detail := 'Votre abonnement (*' || v_sub.plan_name || '*) arrive à son terme dans *7 jours*, le *' || v_formatted_date || '*.';
      else
        v_detail := '⚠️ Votre abonnement (*' || v_sub.plan_name || '*) arrive à échéance dans *2 jours*, le *' || v_formatted_date || '*.';
      end if;

      if v_seed in (0, 3) then
        v_action := 'Pour conserver votre accès sans coupure, merci de passer à la réception pour renouveler votre forfait.';
      else
        v_action := 'Afin d''éviter tout blocage au contrôle d''accès, rapprochez-vous de l''accueil de votre salle pour votre réabonnement.';
      end if;

      -- Footer ak enfòmasyon sekirite (Pou JL FITNESS sèlman: pa mete lyen espas manm nan footer)
      if v_gym.gym_name ilike '%JL FITNESS%' or v_gym.gym_id = '6ed6093d-557d-4bb9-b3ba-f55fedcf65b3' then
        v_footer := '📱 *Enregistrez ce contact SecurGYM* pour être notifié de vos reçus et échéances.' || E'\n' ||
                    'ℹ️ _Pour toute question, contactez directement votre salle' ||
                    case when v_gym.gym_phone <> '' then ' au ' || v_gym.gym_phone else '' end || '._' || E'\n' ||
                    '🏷️ _Réf: SG-' || v_ref_hash || '_';
      else
        v_footer := '📱 *Enregistrez ce contact SecurGYM* pour être notifié de vos reçus et échéances.' || E'\n' ||
                    'ℹ️ _Pour toute question, contactez directement votre salle' ||
                    case when v_gym.gym_phone <> '' then ' au ' || v_gym.gym_phone else '' end || '._' || E'\n' ||
                    '🌐 Votre espace : ' || v_portal_url || E'\n' ||
                    '🏷️ _Réf: SG-' || v_ref_hash || '_';
      end if;

      v_msg := v_greeting || E'\n\n' ||
               v_intro || E'\n' ||
               v_detail || E'\n\n' ||
               v_action || E'\n\n' ||
               v_footer;

      insert into public.whatsapp_messages_outbox (
        gym_id, to_phone, message, kind, status, template_seed
      ) values (
        v_gym.gym_id, v_clean_phone, v_msg, v_milestone, 'pending', v_seed
      );

      insert into public.whatsapp_notification_logs (
        gym_id, member_id, kind, recipient_phone, recipient_name, status, metadata
      ) values (
        v_gym.gym_id,
        v_sub.member_id,
        v_milestone,
        v_clean_phone,
        trim(coalesce(v_sub.first_name, '') || ' ' || coalesce(v_sub.last_name, '')),
        'queued',
        jsonb_build_object(
          'subscription_id', v_sub.sub_id,
          'days_remaining', v_diff,
          'end_date', v_sub.end_date,
          'auto', true
        )
      );

      v_queued_count := v_queued_count + 1;
    end loop;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'queued_count', v_queued_count,
    'timestamp', clock_timestamp()
  );
end $$;

grant execute on function public.platform_whatsapp_purge_stale_reminders() to authenticated, anon, service_role;
grant execute on function public.cron_check_whatsapp_expiration_reminders(uuid) to authenticated, anon, service_role;

commit;
