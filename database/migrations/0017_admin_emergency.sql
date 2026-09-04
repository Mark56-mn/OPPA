-- Admin / Control Center completion: emergency controls with strong
-- authorization, explicit reason capture, and append-only audit. Every staff
-- action is written to public.oppa_audit_events.

create table if not exists public.oppa_emergency_actions (
  id uuid primary key default gen_random_uuid(),
  action_type text not null check (action_type in
    ('freeze_user','unfreeze_user','revoke_all_sessions','suspend_business','restore_business')),
  target_user_id uuid not null references public.oppa_users(id) on delete restrict,
  reason text not null check (length(reason) between 5 and 500),
  created_by uuid not null references public.oppa_users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists oppa_emergency_actions_target_idx
  on public.oppa_emergency_actions(target_user_id, created_at desc);

alter table public.oppa_emergency_actions enable row level security;

-- Missing V1 permissions for the Control Center surfaces.
insert into public.oppa_permissions(code,description) values
 ('devices.revoke','Revoke devices and sessions for a user'),
 ('notifications.read','View notification delivery records'),
 ('emergency.execute','Execute emergency controls')
on conflict(code) do nothing;

-- Grant the new permissions to the roles that need them.
insert into public.oppa_role_permissions(role_id, permission_id)
select r.id, p.id
from public.oppa_roles r
cross join public.oppa_permissions p
where r.name = 'super_admin'
  and p.code in ('devices.revoke','notifications.read','emergency.execute',
                 'users.manage','audit.read','payments.read','wallet.read',
                 'support.manage','staff.manage')
on conflict do nothing;

insert into public.oppa_role_permissions(role_id, permission_id)
select r.id, p.id
from public.oppa_roles r
cross join public.oppa_permissions p
where r.name = 'admin'
  and p.code in ('devices.revoke','notifications.read','users.manage',
                 'audit.read','payments.read','wallet.read')
on conflict do nothing;
