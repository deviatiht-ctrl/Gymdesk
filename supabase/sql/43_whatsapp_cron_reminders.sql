-- ============================================================================
-- 43_whatsapp_cron_reminders.sql
-- Fonksyon Entèlijan Otomatik pou tcheke ak voye tout rapèl abònman
-- (7 Jou, 2 Jou, Jou Fini ak fenk ekspire) pou tout Gym ki gen aksè aktif
-- ============================================================================
begin;

create or replace function public.cron_check_whatsapp_expiration_reminders(
  p_target_gym_id uuid default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_gym record;
  v_sub record;
  v_milestone text;
  v_diff int;
  v_headline text;
  v_body text;
  v_msg text;
  v_phone text;
  v_portal_url text;
  v_clean_phone text;
  v_formatted_date text;
  v_queued_count int := 0;
  v_already_logged boolean;
begin
  -- Boucle sou tout gym ki gen aksè WhatsApp aktif
  for v_gym in
    select 
      g.id as gym_id,
      g.name as gym_name,
      coalesce(g.phone, '') as gym_phone,
      coalesce(a.backup_phone, '') as backup_phone
    from public.gym_whatsapp_access a
    join public.gyms g on g.id = a.gym_id
    where a.is_enabled is true
      and a.status = 'active'
      and a.end_date > clock_timestamp()
      and g.deleted_at is null
      and (p_target_gym_id is null or g.id = p_target_gym_id)
  loop
    v_portal_url := 'https://securgym.com/m/' || v_gym.gym_id::text;

    -- Jwenn tout abònman aktif ak dènye abònman ki fenk fini
    for v_sub in
      select 
        s.id as sub_id,
        s.member_id,
        s.end_date::date as end_date,
        coalesce(p.name, 'Abonnement Gym') as plan_name,
        m.first_name,
        m.last_name,
        coalesce(nullif(trim(m.whatsapp), ''), nullif(trim(m.phone), '')) as raw_phone,
        (s.end_date::date - CURRENT_DATE) as days_diff
      from public.subscriptions s
      join public.members m on m.id = s.member_id
      left join public.plans p on p.id = s.plan_id
      where s.gym_id = v_gym.gym_id
        and s.deleted_at is null
        and m.deleted_at is null
        and (s.end_date::date - CURRENT_DATE) in (7, 2, 0, -1)
      order by s.end_date asc
    loop
      v_diff := v_sub.days_diff;
      if v_sub.raw_phone is null or length(regexp_replace(v_sub.raw_phone, '\D', '', 'g')) < 8 then
        continue;
      end if;

      -- Detèmine kalite rapèl la
      if v_diff = 7 then
        v_milestone := 'reminder_7d';
      elsif v_diff = 2 then
        v_milestone := 'reminder_2d';
      elsif v_diff = 0 then
        v_milestone := 'reminder_0d';
      elsif v_diff = -1 then
        v_milestone := 'reminder_expired';
      else
        continue;
      end if;

      -- Verifye si nou pa t deja voye rapèl sa a nan 3 dènye jou yo (Anti-Doublon)
      select exists (
        select 1 from public.whatsapp_notification_logs
        where gym_id = v_gym.gym_id
          and member_id = v_sub.member_id
          and kind = v_milestone
          and created_at >= (clock_timestamp() - interval '3 days')
      ) into v_already_logged;

      if v_already_logged then
        continue;
      end if;

      -- Verifye tou si mesaj la pa deja nan outbox k ap tann voye
      select exists (
        select 1 from public.whatsapp_messages_outbox
        where gym_id = v_gym.gym_id
          and to_phone = regexp_replace(v_sub.raw_phone, '\D', '', 'g')
          and kind = v_milestone
          and status in ('pending', 'processing')
      ) into v_already_logged;

      if v_already_logged then
        continue;
      end if;

      -- Netwaye nimewo telefòn
      v_clean_phone := regexp_replace(v_sub.raw_phone, '\D', '', 'g');
      if length(v_clean_phone) = 8 then
        v_clean_phone := '509' || v_clean_phone;
      end if;

      v_formatted_date := to_char(v_sub.end_date, 'DD/MM/YYYY');

      -- Bati mesaj la an Fransè (lang ofisyèl)
      if v_diff = 7 then
        v_headline := '⏳ *Rappel Fin d''Abonnement (7 jours) - ' || v_gym.gym_name || '*';
        v_body := 'Votre formule (*' || v_sub.plan_name || '*) arrive à expiration dans 7 jours (*' || v_formatted_date || '*).';
      elsif v_diff = 2 then
        v_headline := '⚠️ *Rappel Urgent : Fin d''Abonnement dans 2 Jours - ' || v_gym.gym_name || '*';
        v_body := 'Votre formule (*' || v_sub.plan_name || '*) expire dans seulement 2 jours (*' || v_formatted_date || '*).';
      elsif v_diff = 0 then
        v_headline := '🚨 *Dernier Jour d''Abonnement - ' || v_gym.gym_name || '*';
        v_body := 'Votre formule (*' || v_sub.plan_name || '*) expire aujourd''hui même (*' || v_formatted_date || '*).';
      else
        v_headline := '🔒 *Abonnement Expiré - ' || v_gym.gym_name || '*';
        v_body := 'Votre formule (*' || v_sub.plan_name || '*) a expiré le *' || v_formatted_date || '*. Votre accès biométrique est suspendu.';
      end if;

      v_msg := v_headline || E'\n' ||
        '_Système SecurGYM • https://securgym.com_' || E'\n\n' ||
        'Bonjour *' || coalesce(v_sub.first_name, '') || ' ' || coalesce(v_sub.last_name, '') || '*' || E',\n' ||
        v_body || E'\n\n' ||
        'Pour conserver votre accès empreinte aux portes sans interruption :' || E'\n' ||
        '1. Passez à l''accueil de *' || v_gym.gym_name || '* pour renouveler votre formule.' || E'\n' ||
        '2. Ou faites votre demande de renouvellement en ligne :' || E'\n' ||
        '👉 ' || v_portal_url || E'\n' ||
        '_Connectez-vous avec votre numéro :_ *' || v_clean_phone || '*' || E'\n\n' ||
        '────────────────────────' || E'\n' ||
        '⚠️ *IMPORTANT :*' || E'\n' ||
        '1. Veuillez enregistrer ce numéro sous le nom *SecurGYM* dans vos contacts.' || E'\n' ||
        '2. *Ne répondez pas à ce numéro*. Contactez la salle directement au : *' || coalesce(nullif(trim(v_gym.gym_phone), ''), 'gym') || '*.';

      -- Enskri mesaj la nan Outbox pou sèvis WhatsApp la voye l
      insert into public.whatsapp_messages_outbox (
        gym_id,
        to_phone,
        message,
        kind,
        status
      ) values (
        v_gym.gym_id,
        v_clean_phone,
        v_msg,
        v_milestone,
        'pending'
      );

      -- Enskri nan journal logs pou anpeche doublon
      insert into public.whatsapp_notification_logs (
        gym_id,
        member_id,
        kind,
        recipient_phone,
        recipient_name,
        status,
        metadata
      ) values (
        v_gym.gym_id,
        v_sub.member_id,
        v_milestone,
        v_clean_phone,
        trim(coalesce(v_sub.first_name, '') || ' ' || coalesce(v_sub.last_name, '')),
        'queued',
        jsonb_build_object(
          'days_remaining', v_diff,
          'plan_name', v_sub.plan_name,
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

revoke all on function public.cron_check_whatsapp_expiration_reminders(uuid) from public, anon;
grant execute on function public.cron_check_whatsapp_expiration_reminders(uuid) to authenticated, anon, service_role;

commit;
