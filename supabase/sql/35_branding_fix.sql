-- ============================================================================
-- 35 — Correctif sync_branding (idempotent). Apply after 34.
--  * Whitelist + 'biometric_config' : biometric_settings_page écrit la config
--    d'accès dans gyms.settings ; sans cette clé toute sauvegarde branding
--    d'une salle qui l'a était rejetée (invalid_record).
--  * phone : limite 32 → 64 (les fiches réelles tiennent plusieurs numéros).
--  * logo_url : accepte le vrai format des objets gym-assets
--    '<gym_id>/logos/<uuid>.<ext>' en plus de 'gym-assets/<uuid>/...' et des
--    URL http(s). Le chemin brut doit rester dans le dossier de la salle.
-- ============================================================================
begin;

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
        if exists(select 1 from jsonb_object_keys(v_settings) k where k not in (
            'doc_footer','offline_lease_hours','auto_logout_minutes','pin_lock_minutes',
            'allow_access_pending','grace_days','reception_see_all_payments','scan_sound',
            'scan_vibrate','entry_duplicate_seconds','qr_defaults',
            'badge_theme','badge_qr_style','badge_positions',
            'biometric_mode','biometric_enabled','biometric_config',
            'door_terminal_ip','door_terminal_port','door_terminal_enabled',
            'temporary_pin_duration_hours','member_language','exchange_rate_htg')) then
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        if v_settings ? 'biometric_config' and (
             jsonb_typeof(v_settings->'biometric_config') is distinct from 'object'
             or char_length((v_settings->'biometric_config')::text) > 16384) then
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        if v_settings ? 'exchange_rate_htg' and (
             jsonb_typeof(v_settings->'exchange_rate_htg') is distinct from 'number'
             or (v_settings->>'exchange_rate_htg')::numeric not between 0 and 100000) then
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        if char_length(trim(coalesce(p_payload->>'name', ''))) not between 2 and 120
          or coalesce(p_payload->>'accent_color', '') !~ '^#[0-9A-Fa-f]{6}$'
          or coalesce(p_payload->>'currency', '') not in ('HTG','USD')
          or not exists(select 1 from pg_timezone_names where name = p_payload->>'timezone')
          or char_length(coalesce(p_payload->>'address', '')) > 500
          or char_length(coalesce(p_payload->>'phone', '')) > 64
          or char_length(coalesce(p_payload->>'email', '')) > 254
          or (coalesce(p_payload->>'email', '') <> '' and p_payload->>'email' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then
            raise exception 'invalid_record' using errcode = '22023';
        end if;
        if v_logo is not null
          and v_logo !~ '^https?://'
          and v_logo !~ '^gym-assets/[0-9a-fA-F-]{36}/'
          and v_logo not like (g.id::text || '/logos/%') then
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

commit;
