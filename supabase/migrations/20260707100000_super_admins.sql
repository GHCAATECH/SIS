-- Super Admin support for multi-school AXIOMBYTE SMS.
-- Run this in Supabase SQL Editor before using superadmin-login.html.

create extension if not exists pgcrypto;

create table if not exists public.super_admins (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  username text not null unique,
  email text unique,
  account_password text not null,
  status text not null default 'Active' check (status in ('Active', 'Suspended')),
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.super_admins enable row level security;

drop policy if exists "dev access super_admins" on public.super_admins;
create policy "dev access super_admins"
  on public.super_admins for all
  using (true)
  with check (true);

grant select, insert, update, delete on public.super_admins to anon, authenticated, service_role;

insert into public.super_admins (full_name, username, email, account_password, status)
values ('Super Administrator', 'superadmin', 'superadmin@axiombyte.local', 'Admin@12345', 'Active')
on conflict (username) do update set
  full_name = excluded.full_name,
  email = excluded.email,
  account_password = excluded.account_password,
  status = excluded.status,
  updated_at = now();
