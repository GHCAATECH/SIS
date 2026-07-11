-- Staff login accounts for AXIOMBYTE SMS.
-- Run this in Supabase SQL Editor before creating staff login accounts.

alter table staff_users
add column if not exists account_password text,
add column if not exists must_change_password boolean not null default true,
add column if not exists last_login_at timestamptz;

grant select, insert, update, delete on staff_users to anon, authenticated, service_role;
