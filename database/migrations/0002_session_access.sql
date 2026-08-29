alter table public.oppa_sessions
  add column if not exists access_token_hash text unique,
  add column if not exists access_expires_at timestamptz;

create index if not exists oppa_sessions_access_active_idx
  on public.oppa_sessions (access_token_hash, access_expires_at)
  where revoked_at is null;
