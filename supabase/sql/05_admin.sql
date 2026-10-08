-- =============================================================
-- 05_admin.sql — GymDesk
-- Création du compte SUPER ADMIN.
--
-- AVANT D'EXÉCUTER :
--   1. ÉDITER v_email ci-dessous avec l'email réel du super admin.
--   2. Créer le compte d'abord dans Supabase :
--        Authentication → Users → Add user
--      (ou par invitation / sign-up depuis l'app), sinon le script
--      échoue — auth.users n'est pas modifiable proprement en SQL
--      simple et nécessite la service_role.
-- =============================================================

do $$
declare
    -- ╔═══════════════════════════════════════════════════════╗
    -- ║  >>>>>>  ÉDITER CET EMAIL AVANT EXÉCUTION  <<<<<<     ║
    -- ╚═══════════════════════════════════════════════════════╝
    v_email text := 'laurorejeanclarens0@gmail.com';
    v_user  uuid;
begin
    if v_email like '%A_MODIFIER%' then
        raise exception 'Éditez v_email dans 05_admin.sql avant exécution.';
    end if;

    select u.id into v_user
      from auth.users u
     where lower(u.email) = lower(v_email)
     limit 1;

    if v_user is null then
        raise exception
            'Aucun utilisateur % dans auth.users. Créez le compte via '
            'Authentication → Users → Add user, puis réexécutez ce script.',
            v_email;
    end if;

    insert into public.staff (id, user_id, gym_id, role, full_name, active)
    values (gen_random_uuid(), v_user, null, 'super_admin', 'Super Admin', true)
    on conflict (user_id) do update
        set role       = 'super_admin',
            gym_id     = null,
            active     = true,
            deleted_at = null;

    raise notice 'Super admin configuré pour % (user_id=%)', v_email, v_user;
end $$;
