-- Student clearance workflow for AXIOMBYTE SMS.
-- Run after production security hardening.

create table if not exists public.clearance_requirements (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  title text not null,
  position_title text not null,
  staff_user_id uuid references public.staff_users(id) on delete set null,
  is_required boolean not null default true,
  sort_order integer not null default 1,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (school_id, title)
);

create table if not exists public.student_clearances (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  requirement_id uuid not null references public.clearance_requirements(id) on delete cascade,
  assigned_staff_user_id uuid references public.staff_users(id) on delete set null,
  position_title text not null,
  status text not null default 'Pending' check (status in ('Pending', 'Cleared', 'Declined')),
  reason text,
  reviewed_by uuid references public.staff_users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, requirement_id)
);

create index if not exists idx_clearance_requirements_school on public.clearance_requirements(school_id, active, sort_order);
create index if not exists idx_student_clearances_student on public.student_clearances(school_id, student_id, status);
create index if not exists idx_student_clearances_staff on public.student_clearances(school_id, assigned_staff_user_id, status);

create or replace function public.staff_has_position(p_staff_id uuid, p_position text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.staff_users staff
    where staff.id = p_staff_id
      and staff.status = 'Active'
      and lower(replace(coalesce(staff.position_responsibility, ''), '_', ' ')) like '%' || lower(replace(coalesce(p_position, ''), '_', ' ')) || '%'
  );
$$;

create or replace function public.current_staff_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
  from public.staff_users
  where auth_user_id = auth.uid()
    and status = 'Active'
  limit 1;
$$;

create or replace function public.initialize_student_clearance(p_student_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  student_record public.students%rowtype;
  inserted_count integer := 0;
begin
  select * into student_record
  from public.students
  where id = p_student_id;

  if not found then
    raise exception 'Student was not found.';
  end if;

  insert into public.student_clearances (
    school_id, student_id, requirement_id, assigned_staff_user_id, position_title
  )
  select
    requirement.school_id,
    student_record.id,
    requirement.id,
    requirement.staff_user_id,
    requirement.position_title
  from public.clearance_requirements requirement
  where requirement.school_id = student_record.school_id
    and requirement.active = true
  on conflict (student_id, requirement_id) do nothing;

  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

create or replace function public.trg_initialize_student_clearance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.status, '') = 'Completed'
     or coalesce(to_jsonb(new)->>'student_level', '') = 'Completed' then
    perform public.initialize_student_clearance(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists students_clearance_after_completion on public.students;
create trigger students_clearance_after_completion
after insert or update on public.students
for each row
execute function public.trg_initialize_student_clearance();

create or replace function public.review_student_clearance(
  p_clearance_id uuid,
  p_status text,
  p_reason text default null
)
returns public.student_clearances
language plpgsql
security definer
set search_path = public
as $$
declare
  clearance public.student_clearances%rowtype;
  staff_id uuid;
  saved public.student_clearances;
begin
  if p_status not in ('Cleared', 'Declined', 'Pending') then
    raise exception 'Invalid clearance status.';
  end if;
  if p_status = 'Declined' and nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'Decline reason is required.';
  end if;

  select * into clearance
  from public.student_clearances
  where id = p_clearance_id;

  if not found then
    raise exception 'Clearance record was not found.';
  end if;

  staff_id := public.current_staff_id();

  if not public.can_manage_school(clearance.school_id)
     and not (staff_id is not null and clearance.assigned_staff_user_id = staff_id)
     and not public.staff_has_position(staff_id, clearance.position_title) then
    raise exception 'Access denied: this clearance item is not assigned to you.';
  end if;

  update public.student_clearances
  set status = p_status,
      reason = case when p_status = 'Declined' then btrim(coalesce(p_reason, '')) else null end,
      reviewed_by = staff_id,
      reviewed_at = now(),
      updated_at = now()
  where id = p_clearance_id
  returning * into saved;

  return saved;
end;
$$;

alter table public.clearance_requirements enable row level security;
alter table public.student_clearances enable row level security;

drop policy if exists "clearance requirements read" on public.clearance_requirements;
drop policy if exists "clearance requirements manage" on public.clearance_requirements;
drop policy if exists "student clearances read" on public.student_clearances;
drop policy if exists "student clearances manage" on public.student_clearances;

create policy "clearance requirements read" on public.clearance_requirements for select to authenticated
using (public.can_manage_school(school_id) or school_id = public.current_school_id());

create policy "clearance requirements manage" on public.clearance_requirements for all to authenticated
using (public.can_manage_school(school_id))
with check (public.can_manage_school(school_id));

create policy "student clearances read" on public.student_clearances for select to authenticated
using (
  public.can_manage_school(school_id)
  or assigned_staff_user_id = public.current_staff_id()
  or public.staff_has_position(public.current_staff_id(), position_title)
  or exists (select 1 from public.students s where s.id = student_id and s.auth_user_id = auth.uid())
);

create policy "student clearances manage" on public.student_clearances for all to authenticated
using (
  public.can_manage_school(school_id)
  or assigned_staff_user_id = public.current_staff_id()
  or public.staff_has_position(public.current_staff_id(), position_title)
)
with check (
  public.can_manage_school(school_id)
  or assigned_staff_user_id = public.current_staff_id()
  or public.staff_has_position(public.current_staff_id(), position_title)
);

grant select, insert, update, delete on public.clearance_requirements to authenticated, service_role;
grant select, insert, update, delete on public.student_clearances to authenticated, service_role;
grant execute on function public.initialize_student_clearance(uuid) to authenticated, service_role;
grant execute on function public.review_student_clearance(uuid, text, text) to authenticated, service_role;
grant execute on function public.current_staff_id() to authenticated, service_role;
grant execute on function public.staff_has_position(uuid, text) to authenticated, service_role;

