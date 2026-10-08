-- =============================================================
-- 03_rls.sql — GymDesk
-- Row Level Security : l'isolation inter-salles est garantie
-- ICI, pas dans l'interface.
--
-- Modèle :
--  * super_admin : tables gyms + staff uniquement (aucune donnée
--    personnelle de membre).
--  * staff d'une salle : gym_id = current_gym_id().
--  * reception : pas de DELETE ; paiements limités à ses propres
--    encaissements sauf si la salle l'autorise
--    (settings.reception_see_all_payments).
--  * attendance : INSERT + SELECT, jamais UPDATE/DELETE (trigger
--    de 02_functions.sql en plus des politiques absentes).
-- =============================================================

alter table public.gyms            enable row level security;
alter table public.staff           enable row level security;
alter table public.gym_counters    enable row level security;
alter table public.members         enable row level security;
alter table public.plans           enable row level security;
alter table public.subscriptions   enable row level security;
alter table public.payments        enable row level security;
alter table public.attendance      enable row level security;
alter table public.badge_templates enable row level security;
alter table public.audit_log       enable row level security;

-- -------------------------------------------------------------
-- gyms
-- -------------------------------------------------------------
create policy gyms_select on public.gyms
for select to authenticated
using ( is_super_admin() or id = public.current_gym_id() );

create policy gyms_insert on public.gyms
for insert to authenticated
with check ( is_super_admin() );

-- super_admin : tout ; owner : branding/paramètres de SA salle
create policy gyms_update on public.gyms
for update to authenticated
using     ( is_super_admin() or (id = public.current_gym_id() and public.current_role() = 'owner') )
with check( is_super_admin() or (id = public.current_gym_id() and public.current_role() = 'owner') );

create policy gyms_delete on public.gyms
for delete to authenticated
using ( is_super_admin() );

-- -------------------------------------------------------------
-- staff
-- -------------------------------------------------------------
create policy staff_select on public.staff
for select to authenticated
using ( is_super_admin() or gym_id = public.current_gym_id() );

-- Le super_admin crée les comptes owner ; l'owner crée le
-- personnel de sa salle (jamais de super_admin, jamais
-- pour une autre salle).
create policy staff_insert on public.staff
for insert to authenticated
with check (
       is_super_admin()
    or ( gym_id = public.current_gym_id()
         and public.current_role() = 'owner'
         and role in ('manager','reception') )
);

create policy staff_update on public.staff
for update to authenticated
using (
       is_super_admin()
    or ( gym_id = public.current_gym_id() and public.current_role() = 'owner' )
    or ( id = public.current_staff_id() )                    -- chacun édite son profil
)
with check (
       is_super_admin()
    or ( gym_id = public.current_gym_id()
         and public.current_role() = 'owner'
         and role <> 'super_admin' )
    or ( id = public.current_staff_id() and role = public.current_role() )
);

create policy staff_delete on public.staff
for delete to authenticated
using ( is_super_admin()
     or ( gym_id = public.current_gym_id() and public.current_role() = 'owner' ) );

-- -------------------------------------------------------------
-- gym_counters : accès direct interdit — uniquement via les
-- fonctions security definer (next_member_number,
-- reserve_member_numbers). Aucune politique = tout refusé.
-- -------------------------------------------------------------

-- -------------------------------------------------------------
-- members
-- -------------------------------------------------------------
create policy members_select on public.members
for select to authenticated
using ( gym_id = public.current_gym_id() );

create policy members_insert on public.members
for insert to authenticated
with check ( gym_id = public.current_gym_id()
         and public.current_role() in ('owner','manager','reception') );

create policy members_update on public.members
for update to authenticated
using     ( gym_id = public.current_gym_id()
        and public.current_role() in ('owner','manager','reception') )
with check( gym_id = public.current_gym_id()
        and public.current_role() in ('owner','manager','reception') );

-- suppression définitive : owner uniquement (l'app utilise
-- deleted_at ; cette politique couvre le hard delete)
create policy members_delete on public.members
for delete to authenticated
using ( gym_id = public.current_gym_id() and public.current_role() = 'owner' );

-- -------------------------------------------------------------
-- plans
-- -------------------------------------------------------------
create policy plans_select on public.plans
for select to authenticated
using ( gym_id = public.current_gym_id() );

create policy plans_insert on public.plans
for insert to authenticated
with check ( gym_id = public.current_gym_id()
         and public.current_role() in ('owner','manager') );

create policy plans_update on public.plans
for update to authenticated
using     ( gym_id = public.current_gym_id()
        and public.current_role() in ('owner','manager') )
with check( gym_id = public.current_gym_id()
        and public.current_role() in ('owner','manager') );

create policy plans_delete on public.plans
for delete to authenticated
using ( gym_id = public.current_gym_id() and public.current_role() = 'owner' );

-- -------------------------------------------------------------
-- subscriptions
-- -------------------------------------------------------------
create policy subs_select on public.subscriptions
for select to authenticated
using ( gym_id = public.current_gym_id() );

-- reception peut créer (renouvellement / inscription) mais pas
-- annuler : l'annulation passe par un UPDATE → owner/manager.
create policy subs_insert on public.subscriptions
for insert to authenticated
with check ( gym_id = public.current_gym_id()
         and public.current_role() in ('owner','manager','reception') );

create policy subs_update on public.subscriptions
for update to authenticated
using     ( gym_id = public.current_gym_id()
        and public.current_role() in ('owner','manager') )
with check( gym_id = public.current_gym_id()
        and public.current_role() in ('owner','manager') );

create policy subs_delete on public.subscriptions
for delete to authenticated
using ( gym_id = public.current_gym_id() and public.current_role() = 'owner' );

-- -------------------------------------------------------------
-- payments
-- -------------------------------------------------------------
-- reception ne voit que SES encaissements, sauf si la salle
-- active settings.reception_see_all_payments.
create policy payments_select on public.payments
for select to authenticated
using ( gym_id = public.current_gym_id()
    and ( public.current_role() in ('owner','manager')
          or received_by = public.current_staff_id()
          or public.gym_setting_bool(gym_id, 'reception_see_all_payments') ) );

create policy payments_insert on public.payments
for insert to authenticated
with check ( gym_id = public.current_gym_id()
         and public.current_role() in ('owner','manager','reception') );

create policy payments_update on public.payments
for update to authenticated
using     ( gym_id = public.current_gym_id()
        and public.current_role() in ('owner','manager') )
with check( gym_id = public.current_gym_id()
        and public.current_role() in ('owner','manager') );

create policy payments_delete on public.payments
for delete to authenticated
using ( gym_id = public.current_gym_id() and public.current_role() = 'owner' );

-- -------------------------------------------------------------
-- attendance : INSERT + SELECT uniquement.
-- Aucune politique UPDATE/DELETE → refusé par défaut, en plus du
-- trigger attendance_immutable (défense en profondeur).
-- -------------------------------------------------------------
create policy attendance_select on public.attendance
for select to authenticated
using ( gym_id = public.current_gym_id() );

create policy attendance_insert on public.attendance
for insert to authenticated
with check ( gym_id = public.current_gym_id()
         and public.current_role() in ('owner','manager','reception') );

-- -------------------------------------------------------------
-- badge_templates
-- -------------------------------------------------------------
create policy badge_select on public.badge_templates
for select to authenticated
using ( gym_id = public.current_gym_id() );

create policy badge_insert on public.badge_templates
for insert to authenticated
with check ( gym_id = public.current_gym_id()
         and public.current_role() in ('owner','manager') );

create policy badge_update on public.badge_templates
for update to authenticated
using     ( gym_id = public.current_gym_id()
        and public.current_role() in ('owner','manager') )
with check( gym_id = public.current_gym_id()
        and public.current_role() in ('owner','manager') );

create policy badge_delete on public.badge_templates
for delete to authenticated
using ( gym_id = public.current_gym_id() and public.current_role() = 'owner' );

-- -------------------------------------------------------------
-- audit_log : consultation owner uniquement ; insertion via la
-- fonction audit() (security definer) — insert direct refusé.
-- -------------------------------------------------------------
create policy audit_select on public.audit_log
for select to authenticated
using ( gym_id = public.current_gym_id()
    and public.current_role() in ('owner','manager') );
