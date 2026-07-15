-- Restore Scheme of Work storage bucket and policies.
-- Run this if document links show: {"statusCode":"404","error":"Bucket not found"}.

insert into storage.buckets (id, name, public)
values ('scheme-of-work', 'scheme-of-work', false)
on conflict (id) do update
set name = excluded.name,
    public = false;

drop policy if exists "scheme of work file read" on storage.objects;
create policy "scheme of work file read"
on storage.objects for select to authenticated
using (
  bucket_id = 'scheme-of-work'
  and exists (
    select 1
    from public.schools school
    where school.code = (storage.foldername(name))[1]
      and (
        public.can_manage_school(school.id)
        or school.id = public.current_school_id()
        or public.is_teaching_staff_for_school(school.id)
      )
  )
);

drop policy if exists "scheme of work file insert" on storage.objects;
create policy "scheme of work file insert"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'scheme-of-work'
  and exists (
    select 1
    from public.schools school
    where school.code = (storage.foldername(name))[1]
      and (
        public.can_manage_school(school.id)
        or school.id = public.current_school_id()
        or public.is_teaching_staff_for_school(school.id)
      )
  )
);

drop policy if exists "scheme of work file update" on storage.objects;
create policy "scheme of work file update"
on storage.objects for update to authenticated
using (
  bucket_id = 'scheme-of-work'
  and exists (
    select 1
    from public.schools school
    where school.code = (storage.foldername(name))[1]
      and public.can_manage_school(school.id)
  )
)
with check (
  bucket_id = 'scheme-of-work'
  and exists (
    select 1
    from public.schools school
    where school.code = (storage.foldername(name))[1]
      and public.can_manage_school(school.id)
  )
);

drop policy if exists "scheme of work file delete" on storage.objects;
create policy "scheme of work file delete"
on storage.objects for delete to authenticated
using (
  bucket_id = 'scheme-of-work'
  and exists (
    select 1
    from public.schools school
    where school.code = (storage.foldername(name))[1]
      and public.can_manage_school(school.id)
  )
);
