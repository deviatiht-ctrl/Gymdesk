import { PGlite } from 'npm:@electric-sql/pglite@0.3.14';

Deno.test('migration 24: receipt columns, receipts bucket, enqueue_payment_receipt idempotent + tenant safe', async () => {
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon;
      create role authenticated;
      create role service_role bypassrls;
      create schema auth;
      create table auth.users(id uuid primary key, email text, aud text, role text);
      create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
      create schema storage;
      create table storage.buckets(id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
      create table storage.objects(id uuid primary key default gen_random_uuid(), bucket_id text, name text);
      create function storage.foldername(name text) returns text[] language sql immutable as $$
        select (string_to_array(name, '/'))[:array_length(string_to_array(name, '/'), 1) - 1]
      $$;
      create publication supabase_realtime;
      grant usage on schema public, auth, storage to anon, authenticated, service_role;
      alter default privileges in schema public grant select, insert, update, delete on tables to authenticated, service_role;
      grant select, insert, update, delete on storage.buckets, storage.objects to authenticated, service_role;
    `);
    const files = ['01_schema', '02_functions', '03_rls', '07_sync', '08_platform', '09_settings_staff', '10_attendance', '11_audit',
      '08_v2_migration', '12_v2_functions', '13_v2_sync', '14_email_enrollment', '15_admin_offers', '16_biometrics_and_fixes',
      '17_update_platform_offers', '18_fstw_access_control', '19_one_time_payment_offers', '20_v3_fingerprint_only', '21_messaging',
      '22_email_delivery_fix', '23_employees_access', '24_payment_receipts', '24_payment_receipts'];
    for (const name of files) {
      const sql = await Deno.readTextFile(new URL(`../sql/${name}.sql`, import.meta.url));
      try {
        await db.exec(sql.replace(/^\uFEFF/, '').replace('create extension if not exists pgcrypto;', ''));
      } catch (error) {
        throw new Error(`Migration ${name}: ${error instanceof Error ? error.message : 'failed'}`);
      }
    }
    await db.exec(await Deno.readTextFile(new URL('./payment_receipts_tests.sql', import.meta.url)));
  } finally {
    await db.close();
  }
});
