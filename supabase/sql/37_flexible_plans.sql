-- 37 — Plans modifiables (idempotent, appliquer après 36).
-- Un plan « flexible » n'impose ni durée ni montant : à l'inscription ou au
-- renouvellement, l'accueil choisit la date de début, la date de fin et le
-- montant. duration_days/price restent des valeurs proposées par défaut.
alter table public.plans
  add column if not exists flexible boolean not null default false;
