-- ============================================================================
-- 24 — Reçus de paiement PDF + balance (crédit) membre (idempotent).
-- Apply after 23_employees_access.sql.
--  * members.credit_balance : reste d'un paiement conservé comme crédit
--  * payments.received_amount / credit_amount : montant remis vs appliqué
--  * payments.method 'credit' : une échéance réglée avec la balance
--  * bucket privé 'receipts' : reçus PDF (<gym_id>/<payment_id>.pdf)
--  * enqueue_payment_receipt() : met le reçu dans la file email avec le lien
-- ============================================================================
begin;

alter table public.members
  add column if not exists credit_balance numeric(12,2) not null default 0
  check (credit_balance >= 0);

alter table public.payments
  add column if not exists received_amount numeric(12,2)
    check (received_amount is null or received_amount >= 0),
  add column if not exists credit_amount numeric(12,2) not null default 0
    check (credit_amount >= 0),
  add column if not exists credit_used numeric(12,2) not null default 0
    check (credit_used >= 0);

alter table public.payments drop constraint if exists payments_method_check;
alter table public.payments add constraint payments_method_check
  check (method in ('cash','moncash','natcash','bank','card','cheque','other','credit'));

-- ----------------------------------------------------------------------------
-- Bucket privé 'receipts' : le personnel de la salle écrit/lit son dossier
-- <gym_id>/ ; le worker email signe le lien ; jamais public.
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 5242880, array['application/pdf'])
on conflict (id) do nothing;

drop policy if exists receipts_select on storage.objects;
create policy receipts_select on storage.objects
for select to authenticated
using ( bucket_id = 'receipts'
    and (storage.foldername(name))[1] = public.current_gym_id()::text );

drop policy if exists receipts_insert on storage.objects;
create policy receipts_insert on storage.objects
for insert to authenticated
with check ( bucket_id = 'receipts'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() in ('owner','supervisor','reception','manager') );

drop policy if exists receipts_update on storage.objects;
create policy receipts_update on storage.objects
for update to authenticated
using ( bucket_id = 'receipts'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() in ('owner','supervisor','reception','manager') )
with check ( bucket_id = 'receipts'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() in ('owner','supervisor','reception','manager') );

drop policy if exists receipts_delete on storage.objects;
create policy receipts_delete on storage.objects
for delete to authenticated
using ( bucket_id = 'receipts'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() in ('owner','supervisor') );

-- ----------------------------------------------------------------------------
-- enqueue_payment_receipt : appelé par l'app après l'upload du PDF.
-- Idempotent par payment (event_key). Renvoie 'queued', 'no_email' ou lève
-- access_denied / invalid_record.
-- ----------------------------------------------------------------------------
create or replace function public.enqueue_payment_receipt(
  p_payment uuid,
  p_receipt_path text
) returns text language plpgsql security definer set search_path = '' as $$
declare
  v_gym uuid := public.current_gym_id();
  v_pay public.payments; v_member public.members; v_sub public.subscriptions;
  v_plan public.plans; v_rows int; v_lang text;
begin
  if v_gym is null
     or coalesce(public.current_role(), '') not in ('owner','supervisor','reception','manager') then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  select * into strict v_pay from public.payments
    where id = p_payment and gym_id = v_gym;
  if v_pay.deleted_at is not null or v_pay.voided_at is not null
     or p_receipt_path is null
     or p_receipt_path !~ ('^' || v_gym::text || '/receipts/[0-9a-fA-F-]{36}\.pdf$') then
    raise exception 'invalid_record' using errcode = '22023';
  end if;
  if not exists (select 1 from storage.objects
      where bucket_id = 'receipts' and name = p_receipt_path) then
    raise exception 'invalid_receipt' using errcode = '22023';
  end if;
  select * into strict v_member from public.members
    where id = v_pay.member_id and gym_id = v_gym and deleted_at is null;
  if coalesce(v_member.email, '') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return 'no_email';
  end if;
  if v_pay.subscription_id is not null then
    select * into v_sub from public.subscriptions where id = v_pay.subscription_id;
    select * into v_plan from public.plans where id = v_sub.plan_id and gym_id = v_gym;
  end if;
  select coalesce(nullif(settings->>'member_language', ''), 'fr')
    into v_lang from public.gyms where id = v_gym;
  insert into public.email_outbox(gym_id, event_key, kind, recipient, payload)
  values (v_gym, 'payment_receipt:' || v_pay.id, 'payment_receipt', lower(trim(v_member.email)),
    public.gym_email_branding(v_gym) || jsonb_build_object(
      'name', trim(v_member.first_name || ' ' || v_member.last_name),
      'member_number', v_member.member_number,
      'receipt_no', upper(substr(replace(v_pay.id::text, '-', ''), 1, 8)),
      'receipt_path', p_receipt_path,
      'amount', v_pay.amount, 'currency', v_pay.currency,
      'received_amount', coalesce(v_pay.received_amount, v_pay.amount),
      'credit_amount', v_pay.credit_amount, 'credit_used', v_pay.credit_used,
      'credit_balance', v_member.credit_balance,
      'method', v_pay.method, 'paid_at', to_char(v_pay.paid_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI"Z"'),
      'plan_name', coalesce(v_plan.name, 'Abonnement'),
      'start_date', v_sub.start_date, 'end_date', v_sub.end_date,
      'language', case when v_lang in ('ht','en','fr') then v_lang else 'fr' end))
  on conflict (event_key) do nothing;
  get diagnostics v_rows = row_count;
  return case when v_rows > 0 then 'queued' else 'already_queued' end;
end $$;
revoke all on function public.enqueue_payment_receipt(uuid, text) from public, anon;
grant execute on function public.enqueue_payment_receipt(uuid, text) to authenticated;

commit;
