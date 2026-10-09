-- =============================================================
-- 01_schema.sql — GymDesk
-- Tables, contraintes et index.
-- Exécuter dans le SQL Editor Supabase AVANT 02..06.
--
-- Conventions :
--  * Clés primaires uuid générées CÔTÉ CLIENT (offline). Un défaut
--    gen_random_uuid() est conservé pour les inserts serveur.
--  * Toutes les tables modifiables : created_at, updated_at
--    (trigger, voir 02), deleted_at (suppression logique),
--    gym_id sauf gyms.
--  * attendance est append-only : pas d'updated_at/deleted_at.
-- =============================================================

create extension if not exists pgcrypto;  -- optionnel : gen_random_uuid() est déjà intégré (PG13+)

-- -------------------------------------------------------------
-- Salles (tenants)
-- -------------------------------------------------------------
-- settings (jsonb) — clés reconnues par l'app :
--   grace_days                  int     délai de grâce après end_date (défaut 0)
--   allow_access_pending        bool    entrée autorisée si abonnement 'pending'
--   reception_see_all_payments  bool    réception voit tout le journal des paiements
--   scan_sound / scan_vibrate   bool    feedback du scanner
--   qr_defaults                 jsonb   style QR par défaut de la salle
--   doc_footer                  text    pied de page des documents PDF
--   offline_lease_hours         int     1–72 h d'autorisation hors ligne
--   auto_logout_minutes         int     0–1440, déconnexion automatique
--   pin_lock_minutes            int     1–60, verrouillage local par PIN
--   entry_duplicate_seconds     int     anti-double lecture du scanner
create table public.gyms (
    id           uuid primary key default gen_random_uuid(),
    code         text not null unique check (code ~ '^[A-Z0-9]{2,6}$'),
    name         text not null,
    logo_url     text,
    accent_color text not null default '#1F6F4A',
    address      text,
    phone        text,
    email        text,
    timezone     text not null default 'America/Port-au-Prince',
    currency     text not null default 'HTG',
    status       text not null default 'active'
                 check (status in ('active','suspended')),
    settings     jsonb not null default '{}'::jsonb,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

-- -------------------------------------------------------------
-- Personnel (lié à auth.users)
-- gym_id null  <=>  super_admin (portée plateforme)
-- -------------------------------------------------------------
create table public.staff (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null unique references auth.users(id) on delete cascade,
    gym_id     uuid references public.gyms(id) on delete cascade,
    role       text not null
               check (role in ('super_admin','owner','manager','reception')),
    full_name  text not null,
    phone      text,
    active     boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    check ( (role = 'super_admin') = (gym_id is null) )
);

create index idx_staff_gym      on public.staff(gym_id);
create index idx_staff_user     on public.staff(user_id);

-- -------------------------------------------------------------
-- Compteur de numéros de membres par salle (séquence atomique,
-- manipulée uniquement via les fonctions security definer de 02)
-- -------------------------------------------------------------
create table public.gym_counters (
    gym_id     uuid primary key references public.gyms(id) on delete cascade,
    member_seq bigint not null default 0,
    updated_at timestamptz not null default now()
);

-- -------------------------------------------------------------
-- Membres
-- -------------------------------------------------------------
create table public.members (
    id                       uuid primary key default gen_random_uuid(),
    gym_id                   uuid not null references public.gyms(id),
    member_number            text not null,           -- ex. PWR-000124 (TMP-xxxx hors ligne)
    qr_token                 text not null,           -- 32+ car. crypto, jamais le numéro seul
    first_name               text not null,
    last_name                text not null,
    sex                      text check (sex in ('male','female','other')),
    birth_date               date,
    phone                    text,
    whatsapp                 text,
    email                    text,
    address                  text,
    nif                      text,                    -- 10 chiffres, unique par salle
    cin                      text,
    emergency_contact_name   text,
    emergency_contact_phone  text,
    guardian_name            text,                    -- obligatoire si < 18 ans (validé côté app)
    photo_url                text,
    notes                    text,
    status                   text not null default 'active'
                             check (status in ('active','suspended','archived')),
    qr_style                 jsonb,                   -- surcharge du style QR salle
    fingerprint_template     text,
    fingerprint_registered   boolean not null default false,
    created_by               uuid references public.staff(id),
    created_at               timestamptz not null default now(),
    updated_at               timestamptz not null default now(),
    deleted_at               timestamptz,
    unique (gym_id, member_number),
    unique (gym_id, qr_token)
);

-- NIF unique par salle quand renseigné
create unique index uq_members_nif on public.members(gym_id, nif)
    where nif is not null;

create index idx_members_name        on public.members(gym_id, last_name);
create index idx_members_qr          on public.members(gym_id, qr_token);
create index idx_members_status      on public.members(gym_id, status);
create index idx_members_fingerprint on public.members(gym_id, fingerprint_registered)
    where fingerprint_registered = true;
create index idx_members_updated     on public.members(gym_id, updated_at);

-- -------------------------------------------------------------
-- Types d'abonnement
-- -------------------------------------------------------------
create table public.plans (
    id            uuid primary key default gen_random_uuid(),
    gym_id        uuid not null references public.gyms(id),
    name          text not null,
    duration_days int  not null check (duration_days > 0),
    price         numeric(12,2) not null check (price >= 0),
    currency      text not null default 'HTG',
    description   text,
    active        boolean not null default true,
    sort_order    int not null default 0,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    deleted_at    timestamptz
);

create index idx_plans_gym on public.plans(gym_id, active, sort_order);

-- -------------------------------------------------------------
-- Abonnements
-- status : active | pending (paiement partiel) | expired | cancelled
-- -------------------------------------------------------------
create table public.subscriptions (
    id            uuid primary key default gen_random_uuid(),
    gym_id        uuid not null references public.gyms(id),
    member_id     uuid not null references public.members(id),
    plan_id       uuid references public.plans(id),
    start_date    date not null,
    end_date      date not null check (end_date >= start_date),
    price         numeric(12,2) not null check (price >= 0),
    status        text not null default 'active'
                  check (status in ('active','expired','cancelled','pending')),
    renewed_from  uuid references public.subscriptions(id),
    created_by    uuid references public.staff(id),
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    deleted_at    timestamptz
);

create index idx_subs_member_end on public.subscriptions(member_id, end_date);
create index idx_subs_gym_end    on public.subscriptions(gym_id, end_date);
create index idx_subs_status     on public.subscriptions(gym_id, status);
create index idx_subs_updated    on public.subscriptions(gym_id, updated_at);

-- -------------------------------------------------------------
-- Paiements
-- -------------------------------------------------------------
create table public.payments (
    id              uuid primary key default gen_random_uuid(),
    gym_id          uuid not null references public.gyms(id),
    member_id       uuid not null references public.members(id),
    subscription_id uuid references public.subscriptions(id),
    amount          numeric(12,2) not null check (amount >= 0),
    currency        text not null default 'HTG',
    method          text not null
                    check (method in ('cash','moncash','natcash','bank','other')),
    reference       text,
    paid_at         timestamptz not null default now(),
    received_by     uuid references public.staff(id),
    notes           text,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    deleted_at      timestamptz
);

create index idx_payments_gym_date   on public.payments(gym_id, paid_at desc);
create index idx_payments_member     on public.payments(member_id, paid_at desc);
create index idx_payments_received   on public.payments(gym_id, received_by, paid_at desc);
create index idx_payments_updated    on public.payments(gym_id, updated_at);

-- -------------------------------------------------------------
-- Présences — APPEND ONLY (update/delete interdits, voir 02)
-- scanned_at          : heure de l'appareil (peut être hors ligne)
-- server_received_at  : heure serveur à la synchronisation
-- entry_number_today  : 1re, 2e… entrée du jour (fuseau de la salle)
-- suspect_clock       : horloge appareil en dérive > 10 min
-- -------------------------------------------------------------
create table public.attendance (
    id                  uuid primary key default gen_random_uuid(),
    gym_id              uuid not null references public.gyms(id),
    member_id           uuid references public.members(id),
    subscription_id     uuid references public.subscriptions(id),
    scanned_at          timestamptz not null,
    server_received_at  timestamptz not null default now(),
    result              text not null check (result in (
                            'granted','denied_expired','denied_no_subscription',
                            'denied_suspended','denied_bad_fingerprint','denied_unknown')),
    denial_reason       text,
    entry_number_today  int,
    device_id           text,
    scanned_by          uuid references public.staff(id),
    was_offline         boolean not null default false,
    suspect_clock       boolean not null default false,
    fingerprint_verified boolean not null default false,
    created_at          timestamptz not null default now()
);

create index idx_att_gym_time    on public.attendance(gym_id, scanned_at desc);
create index idx_att_member_time on public.attendance(member_id, scanned_at desc);
create index idx_att_result      on public.attendance(gym_id, result, scanned_at desc);

-- -------------------------------------------------------------
-- Modèles de badge / carte
-- layout (jsonb) : disposition, champs affichés, couleurs, polices,
-- orientation CR80 paysage ou portrait
-- -------------------------------------------------------------
create table public.badge_templates (
    id         uuid primary key default gen_random_uuid(),
    gym_id     uuid not null references public.gyms(id),
    name       text not null,
    layout     jsonb not null default '{}'::jsonb,
    is_default boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz
);

-- un seul modèle par défaut par salle
create unique index uq_badge_default on public.badge_templates(gym_id)
    where is_default and deleted_at is null;

-- -------------------------------------------------------------
-- Journal d'audit — qui a fait quoi, quand
-- action : create | update | cancel | suspend | reactivate |
--          qr_regenerate | delete | login | export | ...
-- -------------------------------------------------------------
create table public.audit_log (
    id         uuid primary key default gen_random_uuid(),
    gym_id     uuid references public.gyms(id),
    actor_id   uuid references public.staff(id),
    action     text not null,
    entity     text not null,
    entity_id  uuid,
    details    jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index idx_audit_gym_time   on public.audit_log(gym_id, created_at desc);
create index idx_audit_entity     on public.audit_log(gym_id, entity, entity_id);
