-- ========================================================================
-- GymDesk V3 — Migration 09_biometrics.sql (Idempotent)
-- Module Biométrique Multi-Fabricants (Suprema, etc.) et Contrôle de Porte
-- ========================================================================

-- 1. Périphériques Biométriques (Lecteurs USB et Terminaux)
create table if not exists biometric_devices (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references gyms(id) on delete cascade,
  label text,
  role text check (role in ('enrollment', 'access', 'both')),
  vendor text,
  model text,
  vid text,
  pid text,
  serial text,
  host_device_id text,
  sdk_version text,
  firmware text,
  status text default 'active',
  last_seen timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);

create index if not exists idx_biometric_devices_gym on biometric_devices(gym_id) where deleted_at is null;

-- 2. Gabarits d'Empreintes des Membres (Chiffrés, Multi-Doigts)
create table if not exists member_fingerprints (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references gyms(id) on delete cascade,
  member_id uuid not null references members(id) on delete cascade,
  finger_index smallint check (finger_index between 0 and 9),
  vendor text not null,
  sdk_version text,
  template_format text not null,
  template_enc bytea not null,
  iso_template_enc bytea null,
  quality int check (quality between 0 and 100),
  enrolled_by uuid,
  enrolled_at timestamptz default now(),
  revoked_at timestamptz null,
  unique (member_id, finger_index, vendor)
);

create index if not exists idx_member_fingerprints_lookup on member_fingerprints(gym_id, member_id) where revoked_at is null;

-- 3. Consentements Biométriques
create table if not exists biometric_consents (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references gyms(id) on delete cascade,
  member_id uuid not null references members(id) on delete cascade,
  consent_text_version text not null default 'v3.0',
  accepted_at timestamptz,
  witness_staff_id uuid,
  refused bool default false,
  created_at timestamptz default now(),
  unique(gym_id, member_id, consent_text_version)
);

-- 4. Colonnes additionnelles sur gyms et attendance
alter table gyms add column if not exists biometric_enabled bool default true;
alter table gyms add column if not exists biometric_config jsonb default '{
  "mode": "finger_only",
  "min_quality": 60,
  "captures_per_finger": 3,
  "default_fingers": [1, 6],
  "door_open_seconds": 3,
  "door_relay_type": "none"
}'::jsonb;

alter table attendance add column if not exists method text;
alter table attendance add column if not exists reader_id uuid;

-- 5. Sécurité RLS (Row Level Security)
alter table biometric_devices enable row level security;
alter table member_fingerprints enable row level security;
alter table biometric_consents enable row level security;

-- Politiques biometric_devices
drop policy if exists biometric_devices_isolation on biometric_devices;
create policy biometric_devices_isolation on biometric_devices
  for all using (
    gym_id = (current_setting('request.jwt.claims', true)::json->>'gym_id')::uuid
    or current_setting('role') = 'service_role'
  );

-- Politiques member_fingerprints
drop policy if exists member_fingerprints_isolation on member_fingerprints;
create policy member_fingerprints_isolation on member_fingerprints
  for all using (
    gym_id = (current_setting('request.jwt.claims', true)::json->>'gym_id')::uuid
    or current_setting('role') = 'service_role'
  );

-- Politiques biometric_consents
drop policy if exists biometric_consents_isolation on biometric_consents;
create policy biometric_consents_isolation on biometric_consents
  for all using (
    gym_id = (current_setting('request.jwt.claims', true)::json->>'gym_id')::uuid
    or current_setting('role') = 'service_role'
  );

-- 6. Publication temps réel pour la surveillance de porte
alter publication supabase_realtime add table biometric_devices;
