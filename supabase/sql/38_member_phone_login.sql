-- 38_member_phone_login.sql — Espace membre : connexion avec le numéro de téléphone seul.
-- Appliquer après 37 (idempotent). Utilisé UNIQUEMENT par l'Edge Function
-- member_phone_login (clé service) : aucun accès anon/authenticated.

-- Membre d'un gym ouvert correspondant aux 8 derniers chiffres du téléphone
-- (phone ou whatsapp) OU au nom / prénom / numéro de membre.
create or replace function public.mp_phone_member(p_gym uuid, p_phone text)
returns table(member_id uuid, email text, first_name text)
language sql stable security definer set search_path = '' as $$
  select m.id, nullif(lower(trim(coalesce(m.email, ''))), ''), m.first_name
  from public.members m
  where m.gym_id = p_gym
    and public.mp_gym_open(p_gym)
    and m.deleted_at is null
    and (
      (length(public.mp_phone_key(p_phone)) = 8 and (
        public.mp_phone_key(m.phone) = public.mp_phone_key(p_phone)
        or public.mp_phone_key(m.whatsapp) = public.mp_phone_key(p_phone)
      ))
      or (
        length(trim(p_phone)) >= 2 and (
          lower(trim(m.first_name || ' ' || m.last_name)) = lower(trim(p_phone))
          or lower(trim(m.last_name || ' ' || m.first_name)) = lower(trim(p_phone))
          or lower(trim(m.first_name)) = lower(trim(p_phone))
          or lower(trim(m.last_name)) = lower(trim(p_phone))
          or upper(trim(m.member_number)) = upper(trim(p_phone))
          or lower(trim(m.first_name || ' ' || m.last_name)) like '%' || lower(trim(p_phone)) || '%'
        )
      )
    )
  order by (select max(s.end_date) from public.subscriptions s
            where s.member_id = m.id and s.deleted_at is null and s.status <> 'cancelled') desc nulls last,
           m.created_at desc
  limit 1
$$;

-- Limite : 10 tentatives / 15 min par clé. true = tentative autorisée (et comptée).
create or replace function public.mp_phone_attempt(p_key text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
begin
  delete from public.member_portal_attempts where at < clock_timestamp() - interval '1 day';
  if (select count(*) from public.member_portal_attempts a
      where a.key = p_key and a.at > clock_timestamp() - interval '15 minutes') >= 10 then
    return false;
  end if;
  insert into public.member_portal_attempts(key) values (p_key);
  return true;
end $$;

revoke all on function public.mp_phone_member(uuid, text) from public, anon, authenticated;
revoke all on function public.mp_phone_attempt(text) from public, anon, authenticated;
grant execute on function public.mp_phone_member(uuid, text) to service_role;
grant execute on function public.mp_phone_attempt(text) to service_role;
