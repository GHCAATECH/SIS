-- User privilege assignments for AXIOMBYTE SMS.
-- Run this in Supabase SQL Editor to enable AssignPrivilege saving.

create table if not exists user_privileges (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  staff_user_id uuid not null references staff_users(id) on delete cascade,
  page_key text not null,
  created_at timestamptz not null default now(),
  unique (school_id, staff_user_id, page_key)
);

create index if not exists idx_user_privileges_staff on user_privileges(staff_user_id);

alter table user_privileges enable row level security;

drop policy if exists "dev access user_privileges" on user_privileges;
create policy "dev access user_privileges"
on user_privileges for all
using (true)
with check (true);

grant select, insert, update, delete on user_privileges to anon, authenticated, service_role;
