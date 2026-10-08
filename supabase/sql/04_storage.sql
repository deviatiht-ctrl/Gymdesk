-- =============================================================
-- 04_storage.sql — GymDesk
-- Buckets PRIVÉS + politiques Storage.
-- Convention de chemin : <gym_id>/<fichier>
--   member-photos/<gym_id>/<member_id>.jpg
--   gym-assets/<gym_id>/<logo|badge|...>
--   exports/<gym_id>/<rapport>.pdf
-- Le premier segment du chemin doit être current_gym_id().
-- Les photos sont servies par URL SIGNÉE (jamais publiques).
-- =============================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
    ('member-photos', 'member-photos', false,  5242880,                  -- 5 Mo
        array['image/jpeg','image/png','image/webp']),
    ('gym-assets',    'gym-assets',    false,  5242880,
        array['image/jpeg','image/png','image/webp','image/svg+xml']),
    ('exports',       'exports',       false, 52428800,                  -- 50 Mo
        array['application/pdf','text/csv'])
on conflict (id) do nothing;

-- -------------------------------------------------------------
-- member-photos : tout le personnel de la salle lit/écrit dans
-- son dossier <gym_id>/ ; aucun accès inter-salles.
-- -------------------------------------------------------------
create policy member_photos_select on storage.objects
for select to authenticated
using ( bucket_id = 'member-photos'
    and (storage.foldername(name))[1] = public.current_gym_id()::text );

create policy member_photos_insert on storage.objects
for insert to authenticated
with check ( bucket_id = 'member-photos'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() in ('owner','manager','reception') );

create policy member_photos_update on storage.objects
for update to authenticated
using     ( bucket_id = 'member-photos'
        and (storage.foldername(name))[1] = public.current_gym_id()::text
        and public.current_role() in ('owner','manager','reception') )
with check ( bucket_id = 'member-photos'
        and (storage.foldername(name))[1] = public.current_gym_id()::text );

create policy member_photos_delete on storage.objects
for delete to authenticated
using ( bucket_id = 'member-photos'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() in ('owner','manager') );

-- -------------------------------------------------------------
-- gym-assets : logo, éléments de branding.
-- Lecture : personnel de la salle. Écriture : owner/manager.
-- -------------------------------------------------------------
create policy gym_assets_select on storage.objects
for select to authenticated
using ( bucket_id = 'gym-assets'
    and (storage.foldername(name))[1] = public.current_gym_id()::text );

create policy gym_assets_insert on storage.objects
for insert to authenticated
with check ( bucket_id = 'gym-assets'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() in ('owner','manager') );

create policy gym_assets_update on storage.objects
for update to authenticated
using     ( bucket_id = 'gym-assets'
        and (storage.foldername(name))[1] = public.current_gym_id()::text
        and public.current_role() in ('owner','manager') )
with check ( bucket_id = 'gym-assets'
        and (storage.foldername(name))[1] = public.current_gym_id()::text );

create policy gym_assets_delete on storage.objects
for delete to authenticated
using ( bucket_id = 'gym-assets'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() in ('owner','manager') );

-- -------------------------------------------------------------
-- exports : rapports PDF/CSV archivés côté serveur.
-- Lecture/écriture : owner/manager (données financières possibles).
-- -------------------------------------------------------------
create policy exports_select on storage.objects
for select to authenticated
using ( bucket_id = 'exports'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() in ('owner','manager') );

create policy exports_insert on storage.objects
for insert to authenticated
with check ( bucket_id = 'exports'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() in ('owner','manager') );

create policy exports_delete on storage.objects
for delete to authenticated
using ( bucket_id = 'exports'
    and (storage.foldername(name))[1] = public.current_gym_id()::text
    and public.current_role() = 'owner' );
