create table if not exists public.qualitative_assessments (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  class_name text not null,
  student_ref text not null,
  student_name text not null,
  term text not null,
  ratings jsonb not null default '{}'::jsonb,
  teacher_remark text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (school_id, student_ref, term)
);

alter table public.qualitative_assessments enable row level security;

drop policy if exists "Allow anon read qualitative assessments" on public.qualitative_assessments;
drop policy if exists "Allow anon insert qualitative assessments" on public.qualitative_assessments;
drop policy if exists "Allow anon update qualitative assessments" on public.qualitative_assessments;
drop policy if exists "Allow anon delete qualitative assessments" on public.qualitative_assessments;

create policy "Allow anon read qualitative assessments"
  on public.qualitative_assessments for select
  to anon
  using (true);

create policy "Allow anon insert qualitative assessments"
  on public.qualitative_assessments for insert
  to anon
  with check (true);

create policy "Allow anon update qualitative assessments"
  on public.qualitative_assessments for update
  to anon
  using (true)
  with check (true);

create policy "Allow anon delete qualitative assessments"
  on public.qualitative_assessments for delete
  to anon
  using (true);
