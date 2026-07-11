create table if not exists public.staff_subject_classes (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  staff_user_id uuid not null references public.staff_users(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (staff_user_id, class_id, subject_id)
);

alter table public.staff_subject_classes enable row level security;

drop policy if exists "dev access staff_subject_classes" on public.staff_subject_classes;

create policy "dev access staff_subject_classes"
  on public.staff_subject_classes for all
  to anon
  using (true)
  with check (true);
