-- =============================================================================
-- Migration 31 : Correction Fonction Overloading & Suivi d'Adhésion en Direct
-- =============================================================================

begin;

-- 1. Supprimer l'ancienne fonction à 8 paramètres pour éviter l'erreur PGRST203 (Could not choose best candidate)
drop function if exists public.portal_submit(text, uuid, text, text, text, text, text, text);

-- 2. Recréer la fonction unique portal_submit avec 9 paramètres
create or replace function public.portal_submit(
  p_gym_code text,
  p_plan_id uuid,
  p_first_name text,
  p_last_name text,
  p_phone text,
  p_email text default null,
  p_kind text default 'new_membership',
  p_notes text default null,
  p_member_id uuid default null
)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_gym public.gyms;
  v_plan public.plans;
  v_req public.portal_requests;
  v_recent_count int;
begin
  if p_gym_code is null or trim(p_gym_code) = '' then
    raise exception 'invalid_gym' using errcode = '22023';
  end if;

  select * into v_gym from public.gyms
  where (id::text = lower(trim(p_gym_code)) or lower(name) = lower(trim(p_gym_code)))
    and status in ('active', 'trial')
  limit 1;

  if not found then
    raise exception 'gym_not_found' using errcode = '22023';
  end if;

  if p_first_name is null or length(trim(p_first_name)) < 2
     or p_last_name is null or length(trim(p_last_name)) < 2
     or p_phone is null or length(regexp_replace(p_phone, '\D', '', 'g')) < 8 then
    raise exception 'invalid_fields' using errcode = '22023';
  end if;

  if p_plan_id is not null then
    select * into v_plan from public.plans where id = p_plan_id and gym_id = v_gym.id and active = true and deleted_at is null;
    if not found then
      raise exception 'invalid_plan' using errcode = '22023';
    end if;
  end if;

  insert into public.portal_requests(
    gym_id, plan_id, first_name, last_name, phone, email, kind, notes, member_id
  )
  values(
    v_gym.id,
    p_plan_id,
    trim(p_first_name),
    trim(p_last_name),
    trim(p_phone),
    nullif(trim(p_email), ''),
    case when p_kind in ('new_membership', 'renewal') then p_kind else 'new_membership' end,
    nullif(trim(p_notes), ''),
    p_member_id
  )
  returning * into v_req;

  return jsonb_build_object(
    'success', true,
    'request_id', v_req.id,
    'status', v_req.status,
    'gym_name', v_gym.name,
    'created_at', v_req.created_at
  );
end;
$$;

revoke all on function public.portal_submit(text, uuid, text, text, text, text, text, text, uuid) from public, anon, authenticated;
grant execute on function public.portal_submit(text, uuid, text, text, text, text, text, text, uuid) to anon, authenticated;

-- 3. Fonction pour suivre la demande en temps réel depuis le téléphone du client
-- et récupérer le reçu officiel dès que l'inscription est validée
create or replace function public.portal_get_request_status(p_request_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_req record;
  v_member record;
  v_payment record;
  v_sub record;
  v_has_biometric boolean := false;
begin
  if p_request_id is null then
    return jsonb_build_object('found', false);
  end if;

  select r.*,
         g.name as gym_name,
         g.logo_url as gym_logo_url,
         g.currency as gym_currency,
         p.name as plan_name,
         p.price as plan_price,
         coalesce(p.registration_fee, 0) as plan_registration_fee,
         p.duration_days
  into v_req
  from public.portal_requests r
  join public.gyms g on g.id = r.gym_id
  left join public.plans p on p.id = r.plan_id
  where r.id = p_request_id;

  if not found then
    return jsonb_build_object('found', false);
  end if;

  -- Si un member_id a été rattaché
  if v_req.member_id is not null then
    select * into v_member from public.members where id = v_req.member_id;

    -- Vérifier si l'empreinte digitale est enrôlée
    select exists (
      select 1 from public.member_biometrics
      where member_id = v_req.member_id and deleted_at is null
    ) into v_has_biometric;

    -- Trouver le reçu / paiement associé
    select * into v_payment from public.payments
    where member_id = v_req.member_id
    order by payment_date desc, created_at desc
    limit 1;

    -- Trouver le dernier abonnement
    select s.*, pl.name as sub_plan_name
    from public.subscriptions s
    left join public.plans pl on pl.id = s.plan_id
    where s.member_id = v_req.member_id
    order by s.end_date desc
    limit 1;
  end if;

  return jsonb_build_object(
    'found', true,
    'id', v_req.id,
    'status', v_req.status,
    'kind', v_req.kind,
    'first_name', v_req.first_name,
    'last_name', v_req.last_name,
    'phone', v_req.phone,
    'email', v_req.email,
    'created_at', v_req.created_at,
    'updated_at', v_req.updated_at,
    'gym_name', v_req.gym_name,
    'gym_logo_url', v_req.gym_logo_url,
    'gym_currency', v_req.gym_currency,
    'plan_name', v_req.plan_name,
    'plan_price', v_req.plan_price,
    'registration_fee', v_req.plan_registration_fee,
    'duration_days', v_req.duration_days,
    'has_biometric', (v_has_biometric or v_req.status in ('approved', 'completed')),
    'member_id', v_req.member_id,
    'member_number', case when v_member.member_number is not null then v_member.member_number else null end,
    'receipt', case when v_payment.id is not null then jsonb_build_object(
      'receipt_number', coalesce(v_payment.receipt_number, substring(v_payment.id::text, 1, 8)),
      'amount', v_payment.amount,
      'registration_fee', coalesce(v_payment.registration_fee, 0),
      'plan_fee', coalesce(v_payment.plan_fee, v_payment.amount),
      'payment_reason', v_payment.payment_reason,
      'payment_method', v_payment.payment_method,
      'payment_date', coalesce(v_payment.payment_date::text, v_payment.created_at::text),
      'sub_start_date', case when v_sub.start_date is not null then v_sub.start_date::text else null end,
      'sub_end_date', case when v_sub.end_date is not null then v_sub.end_date::text else null end,
      'plan_name', coalesce(v_sub.sub_plan_name, v_req.plan_name)
    ) else null end
  );
end;
$$;

revoke all on function public.portal_get_request_status(uuid) from public, anon, authenticated;
grant execute on function public.portal_get_request_status(uuid) to anon, authenticated;

notify pgrst, 'reload schema';

commit;
