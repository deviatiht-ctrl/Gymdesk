begin;

-- Detailed audit actions produced by the authoritative sync functions. The
-- function is deliberately whitelisted so clients cannot write arbitrary audit
-- text, and actor/gym are always derived from the authenticated staff session.
create or replace function public.audit(p_action text, p_entity text, p_entity_id uuid, p_details jsonb default '{}'::jsonb, p_gym uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid := gen_random_uuid(); v_gym uuid := public.current_gym_id();
begin
    if v_gym is null or public.current_staff_id() is null or (p_gym is not null and p_gym <> v_gym) then
        raise exception 'access_denied' using errcode = '42501';
    end if;
    if jsonb_typeof(coalesce(p_details, '{}'::jsonb)) is distinct from 'object' or char_length(p_details::text) > 4096 then
        raise exception 'invalid_audit_event' using errcode = '22023';
    end if;
    if p_entity not in ('members','plans','subscriptions','payments','attendance','badge_templates','gyms','staff')
       or p_action not in (
         'create','update','delete','sync_conflict',
         'member_create','member_update','member_archive','qr_regenerate',
         'plan_save','plan_archive',
         'subscription_create','subscription_update','subscription_renew','subscription_cancel','subscription_archive',
         'payment_create','payment_update','payment_archive',
         'attendance_scan','badge_template_save','badge_template_archive','export'
       ) then
        raise exception 'invalid_audit_event' using errcode = '22023';
    end if;
    insert into public.audit_log(id, gym_id, actor_id, action, entity, entity_id, details)
    values(v_id, v_gym, public.current_staff_id(), p_action, p_entity, p_entity_id, coalesce(p_details, '{}'::jsonb));
    return v_id;
end $$;

revoke execute on function public.audit(text,text,uuid,jsonb,uuid) from public, anon;
grant execute on function public.audit(text,text,uuid,jsonb,uuid) to authenticated;

commit;
