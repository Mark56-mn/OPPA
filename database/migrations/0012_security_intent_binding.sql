-- Bind sensitive authorizations to the exact operation intent (recipient,
-- amount, currency, reference) by storing a hash of the canonical intent with
-- the step-up challenge. The device signature then covers challenge + intent.
alter table public.oppa_step_up_challenges
  add column if not exists intent_hash text;

-- Atomically enforce a single active challenge per user + purpose. Combined
-- with the consume-before-create flow in the repository, this prevents a stale
-- challenge from remaining usable when a newer one is issued concurrently.
create unique index if not exists oppa_step_up_one_active_per_purpose_uidx
  on public.oppa_step_up_challenges(user_id, purpose)
  where consumed_at is null;