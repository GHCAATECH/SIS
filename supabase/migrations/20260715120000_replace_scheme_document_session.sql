-- Re-attach a missing Scheme of Work document through staff-password sessions.

create or replace function public.secure_replace_scheme_document_with_session(
  p_session_token text,
  p_scheme_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  staff_record public.staff_users;
  scheme_record public.scheme_of_work;
  clean_file_name text := nullif(btrim(coalesce(p_payload->>'fileName', '')), '');
  clean_file_path text := nullif(btrim(coalesce(p_payload->>'filePath', '')), '');
  clean_file_url text := nullif(coalesce(p_payload->>'fileUrl', p_payload->>'file_url', ''), '');
begin
  select * into staff_record
  from public.staff_from_login_session(p_session_token);

  if staff_record.id is null then
    raise exception 'Staff login session expired. Please login again.';
  end if;

  select * into scheme_record
  from public.scheme_of_work
  where id = p_scheme_id
    and school_id = staff_record.school_id
  limit 1;

  if scheme_record.id is null then
    raise exception 'Scheme of work was not found.';
  end if;

  if staff_record.category <> 'School Administrator'
     and scheme_record.teacher_id <> staff_record.id
     and coalesce(scheme_record.hod_reviewer_id, '00000000-0000-0000-0000-000000000000'::uuid) <> staff_record.id
     and coalesce(scheme_record.head_academic_reviewer_id, '00000000-0000-0000-0000-000000000000'::uuid) <> staff_record.id then
    raise exception 'You are not allowed to replace this scheme document.';
  end if;

  if clean_file_name is null or clean_file_url is null then
    raise exception 'Replacement document file name and file data are required.';
  end if;

  if clean_file_path is null then
    clean_file_path := scheme_record.file_path;
  end if;

  update public.scheme_of_work
  set file_name = clean_file_name,
      file_path = clean_file_path,
      file_url = clean_file_url,
      updated_at = now()
  where id = scheme_record.id
  returning * into scheme_record;

  insert into public.scheme_of_work_history (
    school_id,
    scheme_id,
    actor_id,
    action
  )
  values (
    staff_record.school_id,
    scheme_record.id,
    staff_record.id,
    'Scheme document re-uploaded'
  );

  update public.staff_login_sessions
  set last_seen_at = now()
  where session_token = p_session_token;

  return to_jsonb(scheme_record);
end;
$$;

grant execute on function public.secure_replace_scheme_document_with_session(text, uuid, jsonb)
  to anon, authenticated, service_role;
