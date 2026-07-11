-- Department setup linked to programmes, classes, and Teaching Staff.

create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  name text not null,
  code text,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint departments_school_name_key unique (school_id, name)
);

alter table public.programmes
  add column if not exists department_id uuid
  references public.departments(id) on delete restrict;

alter table public.classes
  add column if not exists department_id uuid
  references public.departments(id) on delete restrict;

insert into public.departments (school_id, name)
select distinct on (source.school_id, lower(source.name))
  source.school_id, source.name
from (
  select school_id, btrim(department) as name
  from public.programmes
  where nullif(btrim(coalesce(department, '')), '') is not null
    and lower(btrim(department)) not in (
      'science department', 'arts department', 'business department',
      'visual arts department', 'home economics department', 'agriculture department'
    )
  union
  select school_id, btrim(department) as name
  from public.staff_users
  where nullif(btrim(coalesce(department, '')), '') is not null
    and lower(btrim(department)) not in (
      'science department', 'arts department', 'business department',
      'visual arts department', 'home economics department', 'agriculture department'
    )
) source
where not exists (
  select 1
  from public.departments existing
  where existing.school_id = source.school_id
    and lower(existing.name) = lower(source.name)
)
order by source.school_id, lower(source.name), source.name;

update public.programmes programme
set department_id = department.id,
    department = department.name
from public.departments department
where programme.school_id = department.school_id
  and lower(btrim(coalesce(programme.department, ''))) = lower(department.name)
  and programme.department_id is null;

update public.classes class_row
set department_id = programme.department_id
from public.programmes programme
where class_row.programme_id = programme.id
  and class_row.department_id is null;

create or replace function public.sync_programme_department()
returns trigger
language plpgsql
as $$
declare
  department_record public.departments%rowtype;
begin
  if new.department_id is not null then
    select * into department_record
    from public.departments
    where id = new.department_id
      and school_id = new.school_id;
  elsif nullif(btrim(coalesce(new.department, '')), '') is not null then
    select * into department_record
    from public.departments
    where school_id = new.school_id
      and lower(name) = lower(btrim(new.department))
    limit 1;
  end if;

  if not found then
    raise exception 'Select a valid department for the programme.';
  end if;

  new.department_id := department_record.id;
  new.department := department_record.name;
  return new;
end;
$$;

create or replace function public.sync_class_department_from_programme()
returns trigger
language plpgsql
as $$
declare
  programme_record public.programmes%rowtype;
begin
  select * into programme_record
  from public.programmes
  where id = new.programme_id
    and school_id = new.school_id;

  if not found then
    raise exception 'Select a valid programme for the class.';
  end if;

  if programme_record.department_id is null then
    raise exception 'The selected programme is not linked to a department.';
  end if;

  new.department_id := programme_record.department_id;
  return new;
end;
$$;

drop trigger if exists sync_programme_department on public.programmes;
create trigger sync_programme_department
before insert or update
on public.programmes
for each row execute function public.sync_programme_department();

drop trigger if exists sync_class_department_from_programme on public.classes;
create trigger sync_class_department_from_programme
before insert or update
on public.classes
for each row execute function public.sync_class_department_from_programme();

create or replace function public.touch_department_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists touch_department_updated_at on public.departments;
create trigger touch_department_updated_at
before update on public.departments
for each row execute function public.touch_department_updated_at();

create index if not exists programmes_department_idx
  on public.programmes (school_id, department_id);
create index if not exists classes_department_idx
  on public.classes (school_id, department_id);
create unique index if not exists departments_school_name_lower_key
  on public.departments (school_id, lower(name));

alter table public.departments enable row level security;

drop policy if exists "Development access to departments" on public.departments;
create policy "Development access to departments"
on public.departments for all to anon, authenticated
using (true) with check (true);

grant select, insert, update, delete
on public.departments to anon, authenticated, service_role;
