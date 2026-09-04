-- Per-member delivery/read state so clients can show delivery/read receipts
-- and compute unread counts across direct and group conversations.

create table if not exists public.oppa_message_receipts (
  message_id uuid not null references public.oppa_messages(id) on delete cascade,
  user_id uuid not null references public.oppa_users(id) on delete cascade,
  conversation_id uuid not null references public.oppa_conversations(id) on delete cascade,
  delivered_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create index if not exists oppa_message_receipts_user_unread_idx
  on public.oppa_message_receipts(conversation_id, user_id)
  where read_at is null;

alter table public.oppa_message_receipts enable row level security;
