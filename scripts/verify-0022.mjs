import pg from "pg";

// Read-only verification of migration 0022 on the live DB.
// Never prints connection material or secret values.
const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
await client.connect();
try {
  const m = await client.query("select name from public.schema_migrations order by name");
  console.log("applied migrations:", m.rows.map((r) => r.name).join(", "));
  const t = await client.query("select to_regclass('public.oppa_sms_delivery_attempts') as tbl");
  console.log("table:", t.rows[0].tbl);
  const cols = await client.query(
    "select column_name from information_schema.columns where table_schema='public' and table_name='oppa_sms_delivery_attempts' order by ordinal_position"
  );
  console.log("columns:", cols.rows.map((r) => r.column_name).join(", "));
  const idx = await client.query(
    "select indexname from pg_indexes where tablename='oppa_sms_delivery_attempts' order by indexname"
  );
  console.log("indexes:", idx.rows.map((r) => r.indexname).join(", "));
  const rls = await client.query("select relrowsecurity from pg_class where relname='oppa_sms_delivery_attempts'");
  console.log("rls_enabled:", rls.rows[0]?.relrowsecurity);
  const policies = await client.query("select count(*)::int as n from pg_policies where tablename='oppa_sms_delivery_attempts'");
  console.log("rls_policies:", policies.rows[0].n);
  const grants = await client.query(
    "select grantee, string_agg(privilege_type, ',' order by privilege_type) as privs from information_schema.role_table_grants where table_schema='public' and table_name='oppa_sms_delivery_attempts' group by grantee"
  );
  console.log("grants:", grants.rows.map((r) => `${r.grantee}:${r.privs}`).join(" | ") || "(none)");
  // OTP challenge provider_message_id column (DLR attribution path)
  const om = await client.query(
    "select column_name from information_schema.columns where table_schema='public' and table_name='otp_challenges' and column_name='provider_message_id'"
  );
  console.log("otp_challenges.provider_message_id present:", om.rows.length === 1);
} finally {
  await client.end();
}
