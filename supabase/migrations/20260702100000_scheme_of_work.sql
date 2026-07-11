-- Scheme of Work: teacher -> department HOD -> Head Academic.

create table if not exists public.scheme_of_work (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  teacher_id uuid not null references public.staff_users(id) on delete cascade,
  department text not null,
  academic_year text not null,
  term text not null,
  class_name text not null,
  subject_name text not null,
  title text not null,
  file_title text not null,
  file_name text not null,
  file_path text not null,
  file_url text,
  status text not null default 'Pending HOD',
  hod_reviewer_id uuid references public.staff_users(id) on delete set null,
  hod_decision_at timestamptz,
  hod_reason text,
  head_academic_reviewer_id uuid references public.staff_users(id) on delete set null,
  head_academic_decision_at timestamptz,
  head_academic_reason text,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scheme_of_work_status_check check (
    status in (
      'Pending HOD',
      'Declined by HOD',
      'Pending Head Academic',
      'Declined by Head Academic',
      'Final Approved'
    )
  ),
  constraint scheme_of_work_hod_reason_check check (
    status <> 'Declined by HOD' or nullif(btrim(hod_reason), '') is not null
  ),
  constraint scheme_of_work_head_reason_check check (
    status <> 'Declined by Head Academic' or nullif(btrim(head_academic_reason), '') is not null
  )
);

create table if not exists public.scheme_of_work_history (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  scheme_id uuid not null references public.scheme_of_work(id) on delete cascade,
  actor_id uuid references public.staff_users(id) on delete set null,
  action text not null,
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists scheme_of_work_teacher_idx
  on public.scheme_of_work (school_id, teacher_id, submitted_at desc);
create index if not exists scheme_of_work_review_idx
  on public.scheme_of_work (school_id, department, status, submitted_at);
create index if not exists scheme_of_work_history_scheme_idx
  on public.scheme_of_work_history (scheme_id, created_at);

create or replace function public.touch_scheme_of_work_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.validate_scheme_of_work_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status = 'Pending HOD'
     and new.status in ('Pending Head Academic', 'Declined by HOD') then
    if new.hod_reviewer_id is null or new.hod_decision_at is null then
      raise exception 'An HOD reviewer and decision date are required.';
    end if;
    return new;
  end if;

  if old.status = 'Pending Head Academic'
     and new.status in ('Final Approved', 'Declined by Head Academic') then
    if new.head_academic_reviewer_id is null or new.head_academic_decision_at is null then
      raise exception 'A Head Academic reviewer and decision date are required.';
    end if;
    return new;
  end if;

  raise exception 'Invalid scheme of work status transition from % to %.', old.status, new.status;
end;
$$;

drop trigger if exists touch_scheme_of_work_updated_at on public.scheme_of_work;
create trigger touch_scheme_of_work_updated_at
before update on public.scheme_of_work
for each row execute function public.touch_scheme_of_work_updated_at();

drop trigger if exists validate_scheme_of_work_transition on public.scheme_of_work;
create trigger validate_scheme_of_work_transition
before update on public.scheme_of_work
for each row execute function public.validate_scheme_of_work_transition();

alter table public.scheme_of_work enable row level security;
alter table public.scheme_of_work_history enable row level security;

drop policy if exists "Development access to scheme of work" on public.scheme_of_work;
create policy "Development access to scheme of work"
on public.scheme_of_work for all to anon, authenticated
using (true) with check (true);

drop policy if exists "Development access to scheme history" on public.scheme_of_work_history;
create policy "Development access to scheme history"
on public.scheme_of_work_history for all to anon, authenticated
using (true) with check (true);

grant select, insert, update, delete on public.scheme_of_work to anon, authenticated, service_role;
grant select, insert, update, delete on public.scheme_of_work_history to anon, authenticated, service_role;

insert into storage.buckets (id, name, public)
values ('scheme-of-work', 'scheme-of-work', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "Read scheme of work files" on storage.objects;
create policy "Read scheme of work files"
on storage.objects for select to anon, authenticated
using (bucket_id = 'scheme-of-work');

drop policy if exists "Upload scheme of work files" on storage.objects;
create policy "Upload scheme of work files"
on storage.objects for insert to anon, authenticated
with check (bucket_id = 'scheme-of-work');

drop policy if exists "Update scheme of work files" on storage.objects;
create policy "Update scheme of work files"
on storage.objects for update to anon, authenticated
using (bucket_id = 'scheme-of-work')
with check (bucket_id = 'scheme-of-work');

drop policy if exists "Delete scheme of work files" on storage.objects;
create policy "Delete scheme of work files"
on storage.objects for delete to anon, authenticated
using (bucket_id = 'scheme-of-work');
