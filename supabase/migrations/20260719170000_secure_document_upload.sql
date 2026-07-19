-- Save document metadata through a school-scoped administrator operation.

create or replace function public.secure_upload_owner_document(
  p_owner_type text,
  p_owner_id uuid,
  p_title text,
  p_file_name text,
  p_file_type text,
  p_file_size bigint,
  p_file_url text,
  p_session_token text default null
)
returns public.documents
language plpgsql
security definer
set search_path = public
as $$
declare
  actor public.staff_users;
  saved public.documents;
begin
  if nullif(trim(coalesce(p_session_token, '')), '') is not null then
    select * into actor
    from public.staff_from_login_session(p_session_token);
  else
    select * into actor
    from public.staff_users staff
    where staff.auth_user_id = auth.uid()
      and staff.status = 'Active'
    limit 1;
  end if;

  if actor.id is null then
    raise exception 'Staff login session expired. Please login again.';
  end if;

  if actor.category <> 'School Administrator' then
    raise exception 'Only a school administrator can upload documents.';
  end if;

  if p_owner_type not in ('student', 'staff') then
    raise exception 'Select Student or Staff.';
  end if;

  if nullif(trim(coalesce(p_title, '')), '') is null then
    raise exception 'Enter a document title.';
  end if;

  if nullif(trim(coalesce(p_file_name, '')), '') is null
     or nullif(trim(coalesce(p_file_url, '')), '') is null then
    raise exception 'The uploaded file information is incomplete.';
  end if;

  if p_owner_type = 'student' then
    if not exists (
      select 1
      from public.students student
      where student.id = p_owner_id
        and student.school_id = actor.school_id
    ) then
      raise exception 'The selected student does not belong to your school.';
    end if;

    insert into public.documents (
      school_id, owner_type, student_id, title, file_name,
      file_type, file_size, file_url
    ) values (
      actor.school_id, 'student', p_owner_id, trim(p_title), trim(p_file_name),
      nullif(trim(coalesce(p_file_type, '')), ''), p_file_size, trim(p_file_url)
    )
    returning * into saved;
  else
    if not exists (
      select 1
      from public.staff_users staff
      where staff.id = p_owner_id
        and staff.school_id = actor.school_id
    ) then
      raise exception 'The selected staff member does not belong to your school.';
    end if;

    insert into public.documents (
      school_id, owner_type, staff_user_id, title, file_name,
      file_type, file_size, file_url
    ) values (
      actor.school_id, 'staff', p_owner_id, trim(p_title), trim(p_file_name),
      nullif(trim(coalesce(p_file_type, '')), ''), p_file_size, trim(p_file_url)
    )
    returning * into saved;
  end if;

  if nullif(trim(coalesce(p_session_token, '')), '') is not null then
    update public.staff_login_sessions
    set last_seen_at = now()
    where session_token = p_session_token;
  end if;

  return saved;
end;
$$;

revoke all on function public.secure_upload_owner_document(
  text, uuid, text, text, text, bigint, text, text
) from public, anon;

grant execute on function public.secure_upload_owner_document(
  text, uuid, text, text, text, bigint, text, text
) to authenticated, service_role;
