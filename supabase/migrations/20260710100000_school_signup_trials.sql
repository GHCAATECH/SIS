-- Public school signup and 30-day trial approval flow.
-- Run after production security hardening and super admin setup.

alter table public.schools
  add column if not exists subscription_status text not null default 'Permanent'
    check (subscription_status in ('Trial', 'Permanent', 'Suspended')),
  add column if not exists trial_started_at timestamptz,
  add column if not exists trial_expires_at timestamptz,
  add column if not exists approved_at timestamptz,
  add column if not exists approved_by uuid references public.super_admins(id) on delete set null;

create table if not exists public.school_signup_requests (
  id uuid primary key default gen_random_uuid(),
  school_code text not null,
  school_name text not null,
  contact_name text not null,
  contact_email text not null,
  contact_phone text,
  requested_username text,
  requested_staff_id text,
  status text not null default 'Trial' check (status in ('Trial', 'Approved', 'Declined', 'Expired')),
  school_id uuid references public.schools(id) on delete set null,
  trial_started_at timestamptz not null default now(),
  trial_expires_at timestamptz not null default (now() + interval '30 days'),
  approved_at timestamptz,
  approved_by uuid references public.super_admins(id) on delete set null,
  decline_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (school_code)
);

create index if not exists idx_school_signup_requests_status on public.school_signup_requests(status, trial_expires_at);

create or replace function public.submit_school_signup(p_payload jsonb)
returns public.school_signup_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_code text := upper(btrim(coalesce(p_payload->>'school_code', '')));
  saved public.school_signup_requests;
  linked_school public.schools;
begin
  if clean_code = '' then raise exception 'School code is required.'; end if;
  if btrim(coalesce(p_payload->>'school_name', '')) = '' then raise exception 'School name is required.'; end if;
  if btrim(coalesce(p_payload->>'contact_name', '')) = '' then raise exception 'Contact name is required.'; end if;
  if btrim(coalesce(p_payload->>'contact_email', '')) = '' then raise exception 'Contact email is required.'; end if;

  insert into public.schools (code, name, subscription_status, trial_started_at, trial_expires_at)
  values (clean_code, btrim(p_payload->>'school_name'), 'Trial', now(), now() + interval '30 days')
  on conflict (code) do update set
    name = excluded.name,
    subscription_status = case
      when public.schools.subscription_status = 'Permanent' then 'Permanent'
      when coalesce(public.schools.trial_expires_at, excluded.trial_expires_at) < now() then 'Suspended'
      else 'Trial'
    end,
    trial_started_at = coalesce(public.schools.trial_started_at, excluded.trial_started_at),
    trial_expires_at = coalesce(public.schools.trial_expires_at, excluded.trial_expires_at)
  returning * into linked_school;

  insert into public.school_signup_requests (
    school_code, school_name, contact_name, contact_email, contact_phone,
    requested_username, requested_staff_id, status, school_id, trial_started_at, trial_expires_at
  ) values (
    clean_code,
    btrim(p_payload->>'school_name'),
    btrim(p_payload->>'contact_name'),
    lower(btrim(p_payload->>'contact_email')),
    nullif(btrim(coalesce(p_payload->>'contact_phone', '')), ''),
    nullif(btrim(coalesce(p_payload->>'requested_username', '')), ''),
    nullif(btrim(coalesce(p_payload->>'requested_staff_id', '')), ''),
    case when linked_school.subscription_status = 'Permanent' then 'Approved' else 'Trial' end,
    linked_school.id,
    coalesce(linked_school.trial_started_at, now()),
    coalesce(linked_school.trial_expires_at, now() + interval '30 days')
  )
  on conflict (school_code) do update set
    school_name = excluded.school_name,
    contact_name = excluded.contact_name,
    contact_email = excluded.contact_email,
    contact_phone = excluded.contact_phone,
    requested_username = excluded.requested_username,
    requested_staff_id = excluded.requested_staff_id,
    school_id = excluded.school_id,
    status = case
      when public.school_signup_requests.status = 'Approved' then 'Approved'
      when coalesce(public.school_signup_requests.trial_expires_at, excluded.trial_expires_at) < now() then 'Expired'
      else public.school_signup_requests.status
    end,
    trial_expires_at = coalesce(public.school_signup_requests.trial_expires_at, excluded.trial_expires_at),
    updated_at = now()
  returning * into saved;

  return saved;
end;
$$;

create or replace function public.approve_school_signup(p_request_id uuid, p_permanent boolean default true, p_decline_reason text default null)
returns public.school_signup_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  super_id uuid;
  request_row public.school_signup_requests%rowtype;
  saved public.school_signup_requests;
begin
  select id into super_id from public.super_admins where auth_user_id = auth.uid() and status = 'Active' limit 1;
  if super_id is null then raise exception 'Only Super Admin can approve signup requests.'; end if;

  select * into request_row from public.school_signup_requests where id = p_request_id;
  if not found then raise exception 'Signup request was not found.'; end if;

  if p_permanent then
    update public.schools
    set subscription_status = 'Permanent', approved_at = now(), approved_by = super_id
    where id = request_row.school_id;

    update public.school_signup_requests
    set status = 'Approved', approved_at = now(), approved_by = super_id, decline_reason = null, updated_at = now()
    where id = p_request_id
    returning * into saved;
  else
    update public.schools
    set subscription_status = 'Suspended'
    where id = request_row.school_id;

    update public.school_signup_requests
    set status = 'Declined', decline_reason = nullif(btrim(coalesce(p_decline_reason, '')), ''), updated_at = now()
    where id = p_request_id
    returning * into saved;
  end if;

  return saved;
end;
$$;

alter table public.school_signup_requests enable row level security;

drop policy if exists "signup request super admin read" on public.school_signup_requests;
drop policy if exists "signup request super admin manage" on public.school_signup_requests;

create policy "signup request super admin read" on public.school_signup_requests for select to authenticated
using (public.is_super_admin());

create policy "signup request super admin manage" on public.school_signup_requests for all to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

grant execute on function public.submit_school_signup(jsonb) to anon, authenticated, service_role;
grant execute on function public.approve_school_signup(uuid, boolean, text) to authenticated, service_role;
grant select, update on public.school_signup_requests to authenticated, service_role;
