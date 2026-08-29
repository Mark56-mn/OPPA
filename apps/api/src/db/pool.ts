import { Pool } from "pg";

const connectionString = process.env.DATABASE_URL;

export const db = connectionString
  ? new Pool({
      connectionString,
      max: Number(process.env.DB_POOL_MAX ?? 10),
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 5_000,
      ssl: process.env.DB_SSL === "false" ? false : { rejectUnauthorized: false }
    })
  : null;
