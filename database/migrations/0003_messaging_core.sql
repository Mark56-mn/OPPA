create table if not exists public.oppa_profiles (
  user_id uuid primary key references public.oppa_users(id) on delete cascade,
  display_name text,
  avatar_url text,
  about text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.oppa_contacts (
  user_id uuid not null references public.oppa_users(id) on delete cascade,
  contact_user_id uuid not null references public.oppa_users(id) on delete cascade,
  nickname text,
  blocked_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (user_id, contact_user_id),
  check (user_id <> contact_user_id)
);

create index if not exists oppa_contacts_contact_idx on public.oppa_contacts(contact_user_id);

create table if not exists public.oppa_conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'direct' check (kind in ('direct','group')),
  title text,
  created_by uuid not null references public.oppa_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.oppa_conversation_members (
  conversation_id uuid not null references public.oppa_conversations(id) on delete cascade,
  user_id uuid not null references public.oppa_users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','member')),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  primary key (conversation_id, user_id)
);

create index if not exists oppa_conversation_members_user_idx
  on public.oppa_conversation_members(user_id, conversation_id);

create table if not exists public.oppa_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.oppa_conversations(id) on delete cascade,
  sender_user_id uuid not null references public.oppa_users(id) on delete restrict,
  client_message_id text,
  message_type text not null default 'text'
    check (message_type in ('text','image','video','audio','file','system')),
  body text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz,
  unique (sender_user_id, client_message_id)
);

create index if not exists oppa_messages_conversation_idx
  on public.oppa_messages(conversation_id, created_at desc);

alter table public.oppa_profiles enable row level security;
alter table public.oppa_contacts enable row level security;
alter table public.oppa_conversations enable row level security;
alter table public.oppa_conversation_members enable row level security;
alter table public.oppa_messages enable row level security;
