import { PGlite } from 'npm:@electric-sql/pglite@0.3.14';

const FILES = ['01_schema', '02_functions', '03_rls', '07_sync', '08_platform', '09_settings_staff', '10_attendance', '11_audit', '08_v2_migration', '12_v2_functions', '13_v2_sync', '14_email_enrollment', '15_admin_offers'];

const ADMIN = 'a0000000-0000-4000-8000-0000000000aa';
const GYM = 'a0000000-0000-4000-8000-00000000bb01';

async function setup(): Promise<PGlite> {
  const db = new PGlite();
  await db.exec(`
    create role anon;
    create role authenticated;
    create role service_role bypassrls;
    create schema auth;
    create table auth.users(id uuid primary key, email text, aud text, role text);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create schema storage;
    create table storage.objects(id uuid primary key default gen_random_uuid(), bucket_id text, name text);
    grant usage on schema public, auth, storage to anon, authenticated, service_role;
    alter default privileges in schema public grant select, insert, update, delete on tables to authenticated, service_role;
  `);
  for (const name of FILES) {
    const sql = await Deno.readTextFile(new URL(`../sql/${name}.sql`, import.meta.url));
    try {
      await db.exec(sql.replace(/^﻿/, '').replace('create extension if not exists pgcrypto;', ''));
    } catch (error) {
      throw new Error(`Migration ${name}: ${error instanceof Error ? error.message : 'failed'}`);
    }
  }
  await db.exec(`
    insert into auth.users(id, email) values ('${ADMIN}', 'admin@gymdesk.test');
    insert into public.staff(user_id, gym_id, role, full_name)
      values ('${ADMIN}', null, 'super_admin', 'Admin');
    insert into public.gyms(id, code, name, timezone, currency, status)
      values ('${GYM}', 'TST', 'Test Gym', 'America/Port-au-Prince', 'HTG', 'trial');
    insert into public.members(gym_id, member_number, qr_token, first_name, last_name)
      values ('${GYM}', 'TST-000001', 'token-demo-00000000000000000001', 'Demo', 'Member');
    select set_config('request.jwt.claim.sub', '${ADMIN}', false);
  `);
  return db;
}

Deno.test('platform_register_payment creates an active contract, an approved declaration and reactivates the gym', async () => {
  const db = await setup();
  try {
    const result = await db.query<{ platform_register_payment: { contract_id: string; declaration_id: string } }>(
      `select public.platform_register_payment('${GYM}', 'per_member', 45, 'USD', 'cash', 'REC-1', 'Paiement accueil', true)`,
    );
    const { contract_id, declaration_id } = result.rows[0].platform_register_payment;
    if (!contract_id || !declaration_id) throw new Error('missing ids');

    const contract = await db.query<{ status: string; offer_id: string; expires_at: string | null }>(
      `select status, offer_id, expires_at from public.gym_contracts where id = '${contract_id}'`,
    );
    if (contract.rows[0].status !== 'active' || contract.rows[0].offer_id !== 'per_member' || contract.rows[0].expires_at === null) {
      throw new Error('contract not active');
    }
    const gym = await db.query<{ status: string }>(`select status from public.gyms where id = '${GYM}'`);
    if (gym.rows[0].status !== 'active') throw new Error('gym not reactivated');
    const decl = await db.query<{ status: string }>(`select status from public.payment_declarations where id = '${declaration_id}'`);
    if (decl.rows[0].status !== 'approved') throw new Error('declaration not approved');
  } finally {
    await db.close();
  }
});

Deno.test('platform_register_payment with p_paid=false creates a trial contract without declaration', async () => {
  const db = await setup();
  try {
    const result = await db.query<{ platform_register_payment: { contract_id: string; declaration_id: string | null } }>(
      `select public.platform_register_payment('${GYM}', 'tiered', 0, 'USD', 'cash', null, null, false)`,
    );
    const { contract_id, declaration_id } = result.rows[0].platform_register_payment;
    if (!contract_id || declaration_id !== null) throw new Error('unexpected declaration');
    const contract = await db.query<{ status: string }>(`select status from public.gym_contracts where id = '${contract_id}'`);
    if (contract.rows[0].status !== 'trial') throw new Error('contract not trial');
    const count = await db.query<{ n: number }>(`select count(*)::int n from public.payment_declarations where gym_id = '${GYM}'`);
    if (count.rows[0].n !== 0) throw new Error('declaration should not exist');
  } finally {
    await db.close();
  }
});

Deno.test('platform_gym_overview returns contract and member counts; non-admin is rejected', async () => {
  const db = await setup();
  try {
    await db.query(`select public.platform_register_payment('${GYM}', 'per_member', 45, 'USD', 'cash', null, null, true)`);
    const overview = await db.query<{ platform_gym_overview: Array<Record<string, unknown>> }>(
      'select public.platform_gym_overview()',
    );
    const row = overview.rows[0].platform_gym_overview.find((r) => r['gym_id'] === GYM);
    if (!row || row['members'] !== 1 || row['offer_name'] !== 'Par Membre Actif' || row['contract_status'] !== 'active') {
      throw new Error(`unexpected overview: ${JSON.stringify(row)}`);
    }
    let denied = false;
    try {
      await db.query(`select public.platform_register_payment('${GYM}', 'per_member', 10, 'USD', 'cash', null, null, true)`);
      // devient non admin
      await db.exec(`select set_config('request.jwt.claim.sub', '', false)`);
      await db.query(`select public.platform_register_payment('${GYM}', 'per_member', 10, 'USD', 'cash', null, null, true)`);
    } catch {
      denied = true;
    }
    if (!denied) throw new Error('access should be denied for non-admin');
  } finally {
    await db.close();
  }
});
