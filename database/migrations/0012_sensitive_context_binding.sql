alter table public.oppa_step_up_challenges
  add column if not exists context_hash text;

create index if not exists oppa_step_up_context_hash_idx
  on public.oppa_step_up_challenges(context_hash)
  where consumed_at is null;
