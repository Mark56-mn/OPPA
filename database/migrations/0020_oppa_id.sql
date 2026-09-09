-- OPPA ID (V1 identity completion): a unique, human-chosen handle per user.
-- Rules (server-enforced, not client-trusted):
--   * 3–32 chars, lowercase letters/digits/underscores, starts with a letter;
--   * unique across all users (case-insensitive via citext);
--   * reserved names (product/system terms) can never be claimed;
--   * nullable: existing users keep phone-only identity until they choose one;
--   * changes allowed but rate-limited server-side (audit on every change).
--
-- citext needs the extension; on Supabase it is available in the public
-- schema. Idempotent: safe to re-run.
create extension if not exists citext;

alter table public.oppa_profiles
  add column if not exists oppa_id citext;

-- Uniqueness across all users, case-insensitive. Partial index keeps the
-- common phone-only state (null oppa_id) out of the index entirely.
create unique index if not exists oppa_profiles_oppa_id_uidx
  on public.oppa_profiles(oppa_id)
  where oppa_id is not null;

-- Search/discovery by OPPA ID (the Connect flow looks users up by handle).
create index if not exists oppa_profiles_oppa_id_idx
  on public.oppa_profiles(oppa_id)
  where oppa_id is not null;

alter table public.oppa_profiles enable row level security;

-- Audit: identity claims/changes are security-relevant (impersonation
-- vector), so every mutation is recorded by the API layer into
-- oppa_audit_events as event_type 'profile.oppa_id_set'.
