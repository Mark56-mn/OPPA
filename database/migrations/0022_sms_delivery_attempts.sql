-- SMS delivery attempt ledger (V1 third-party provider integration).
-- One row per provider send attempt for an OTP challenge (accepted, failed,
-- or unknown). Purposes:
--   * auditable failover across BulkSMS/Termii (attempt 1 = primary, etc.);
--   * durable per-challenge rate budget (SMS_MAX_ATTEMPTS_PER_MINUTE) that
--     survives restarts and prevents duplicate SMS spam from retries;
--   * delivery-state persistence for callbacks/reconciliation support.
-- No OTP material is ever stored here: no codes, no hashes — only provider
-- metadata. Secrets and OTPs never enter this table.

create table if not exists public.oppa_sms_delivery_attempts (
  id                   bigserial primary key,
  challenge_id         uuid        not null,
  provider             text        not null,
  outcome              text        not null check (outcome in ('accepted', 'failed', 'unknown')),
  provider_message_id  text,
  provider_request_ref text,
  error_kind           text,
  attempted_at         timestamptz not null default now()
);

-- Budget queries: count attempts per challenge inside the last minute.
create index if not exists oppa_sms_attempts_challenge_time_idx
  on public.oppa_sms_delivery_attempts (challenge_id, attempted_at);

-- Support/reconciliation: find every attempt for one provider message id.
create index if not exists oppa_sms_attempts_message_id_idx
  on public.oppa_sms_delivery_attempts (provider_message_id)
  where provider_message_id is not null;

alter table public.oppa_sms_delivery_attempts enable row level security;

-- No policies: the table is service-only (migrations role), deny-all to
-- client roles — same convention as the rest of the schema (see 0019/0020).

grant select, insert on public.oppa_sms_delivery_attempts to service_role;
