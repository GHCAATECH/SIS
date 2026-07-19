-- Link the active administrator Auth session to the verified staff login session
-- before Supabase Storage evaluates its school-folder RLS policy.

create or replace function public.secure_prepare_document_upload(
  p_session_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor public.staff_users;
  school_record public.schools;
  auth_email text := lower(trim(coalesce(auth.jwt()->>'email', '')));
begin
  if auth.uid() is null then
    raise exception 'A Supabase Auth session is required. Logout and login again.';
  end if;

  select * into actor
  from public.staff_from_login_session(p_session_token);

  if actor.id is null then
    raise exception 'Staff login session expired. Please login again.';
  end if;

  if actor.category <> 'School Administrator' then
    raise exception 'Only a school administrator can upload documents.';
  end if;

  if auth_email = '' or lower(trim(coalesce(actor.email, ''))) <> auth_email then
    raise exception 'The active Auth account does not match this administrator. Logout and login again.';
  end if;

  if exists (
    select 1
    from public.staff_users staff
    where staff.auth_user_id = auth.uid()
      and staff.id <> actor.id
  ) then
    raise exception 'The active Auth account is linked to another staff profile.';
  end if;

  if actor.auth_user_id is distinct from auth.uid() then
    update public.staff_users
    set auth_user_id = auth.uid(),
        updated_at = now()
    where id = actor.id;
  end if;

  select * into school_record
  from public.schools school
  where school.id = actor.school_id;

  if school_record.id is null then
    raise exception 'The administrator school could not be found.';
  end if;

  update public.staff_login_sessions
  set last_seen_at = now()
  where session_token = p_session_token;

  return jsonb_build_object(
    'school_id', school_record.id,
    'school_code', school_record.code
  );
end;
$$;

revoke all on function public.secure_prepare_document_upload(text)
  from public, anon;
grant execute on function public.secure_prepare_document_upload(text)
  to authenticated, service_role;

create or replace function public.can_manage_storage_school_code(
  p_school_code text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.staff_users staff
    join public.schools school on school.id = staff.school_id
    where staff.auth_user_id = auth.uid()
      and staff.status = 'Active'
      and staff.category = 'School Administrator'
      and school.code = p_school_code
  );
$$;

revoke all on function public.can_manage_storage_school_code(text)
  from public, anon;
grant execute on function public.can_manage_storage_school_code(text)
  to authenticated, service_role;

drop policy if exists "administrator document file read" on storage.objects;
create policy "administrator document file read"
on storage.objects for select to authenticated
using (
  bucket_id in ('student-documents', 'staff-documents')
  and public.can_manage_storage_school_code((storage.foldername(name))[1])
);

drop policy if exists "administrator document file insert" on storage.objects;
create policy "administrator document file insert"
on storage.objects for insert to authenticated
with check (
  bucket_id in ('student-documents', 'staff-documents')
  and public.can_manage_storage_school_code((storage.foldername(name))[1])
);

drop policy if exists "administrator document file update" on storage.objects;
create policy "administrator document file update"
on storage.objects for update to authenticated
using (
  bucket_id in ('student-documents', 'staff-documents')
  and public.can_manage_storage_school_code((storage.foldername(name))[1])
)
with check (
  bucket_id in ('student-documents', 'staff-documents')
  and public.can_manage_storage_school_code((storage.foldername(name))[1])
);

drop policy if exists "administrator document file delete" on storage.objects;
create policy "administrator document file delete"
on storage.objects for delete to authenticated
using (
  bucket_id in ('student-documents', 'staff-documents')
  and public.can_manage_storage_school_code((storage.foldername(name))[1])
);
