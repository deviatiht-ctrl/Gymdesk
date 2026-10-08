-- =============================================================
-- rls_tests.sql — GymDesk
-- Vérification de l'isolation inter-salles par RLS.
--
-- Mode d'emploi (SQL Editor Supabase) :
--   1. Exécuter 01..05 (+ 06 pour la salle PWR de démo).
--   2. Créer DEUX salles supplémentaires ou utiliser PWR + une
--      autre, et DEUX comptes auth de test (Authentication →
--      Add user) rattachés à chacune via public.staff.
--   3. Remplacer les UUID ci-dessous, exécuter bloc par bloc.
--
-- Principe : `set local request.jwt.claim.sub` simule un JWT,
-- `set role authenticated` applique les politiques RLS.
-- =============================================================

-- ---------- À ÉDITER : UUID de test ----------
-- user_id auth du staff de la salle A et de la salle B,
-- et id des deux salles.
-- \set n'est pas supporté : éditez directement les valeurs.

begin;
set local role authenticated;

-- ============ TEST 1 : staff salle A ==========================
-- Remplacer par l'user_id auth du staff A :
set local request.jwt.claim.sub = 'USER_ID_STAFF_A';

-- 1a. Doit retourner uniquement les membres de la salle A
select count(*) as membres_visibles_salle_a from public.members;

-- 1b. Doit échouer : lecture des membres de la salle B
--     (la requête retourne 0 ligne, pas d'erreur — RLS filtre)
select count(*) as doit_etre_zero
  from public.members
 where gym_id = 'ID_SALLE_B';

-- 1c. Doit échouer : insertion dans la salle B
--     → ERROR : new row violates row-level security policy
insert into public.members
    (id, gym_id, member_number, qr_token, first_name, last_name)
values
    (gen_random_uuid(), 'ID_SALLE_B', 'XXB-000001', 'tok-test-rls-32-caracteres-xxxxxx',
     'Test', 'Intrusion');

-- 1d. Doit échouer : lecture directe des compteurs
select * from public.gym_counters;   -- attendu : 0 ligne

-- 1e. Doit échouer : UPDATE sur attendance (append-only)
--     → trigger attendance_immutable, et aucune politique update
update public.attendance set result = 'granted' where false;

-- ============ TEST 2 : reception vs owner =====================
-- staff A = reception :
--   select payments → uniquement ses propres lignes
--   delete payments → interdit
-- staff A = owner :
--   insert staff role='super_admin' → interdit (with check)
select count(*) as paiements_visibles from public.payments;

rollback;

-- ============ TEST 3 : super_admin ============================
begin;
set local role authenticated;
set local request.jwt.claim.sub = 'USER_ID_SUPER_ADMIN';

-- 3a. Voit toutes les salles
select count(*) as toutes_les_salles from public.gyms;

-- 3b. NE DOIT PAS voir les données personnelles des membres
select count(*) as doit_etre_zero from public.members;

-- 3c. Peut suspendre une salle
update public.gyms set status = 'suspended' where id = 'ID_SALLE_B';

-- 3d. Vérif : is_gym_active passe à false
select public.is_gym_active('ID_SALLE_B');   -- attendu : f

rollback;

-- ============ TEST 4 : salle suspendue ========================
-- Après suspension de la salle B :
--   reserve_member_numbers(B, 10) doit lever une exception.
begin;
set local role authenticated;
set local request.jwt.claim.sub = 'USER_ID_STAFF_B';

-- attendu : ERROR « gym suspendu »
select * from public.reserve_member_numbers('ID_SALLE_B', 10);

rollback;

-- ============ TEST 5 : validité (membre de démo seed) =========
-- PWR-000001 a un abonnement actif ; PWR-000002 expiré hier ;
-- PWR-000003 aucun abonnement.
select * from public.member_validity(
    'c0000000-0000-4000-8000-000000000001', now());   -- valid=t, 'ok'
select * from public.member_validity(
    'c0000000-0000-4000-8000-000000000002', now());   -- valid=f, 'expired'
select * from public.member_validity(
    'c0000000-0000-4000-8000-000000000003', now());   -- valid=f, 'no_subscription'

-- Règle « jour J inclus » : valide le jour de end_date,
-- refusé le lendemain (recalculé côté app à chaque scan,
-- même hors ligne).
