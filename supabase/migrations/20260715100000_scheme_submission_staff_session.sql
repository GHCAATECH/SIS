-- Scheme of Work staff-session submission support.
-- Run this after the production security hardening and staff session migrations.

create or replace function public.secure_submit_scheme_of_work_with_session(
  p_session_token text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  staff_record public.staff_users;
  school_record public.schools;
  inserted_scheme public.scheme_of_work;
  clean_file_name text := nullif(btrim(coalesce(p_payload->>'fileName', '')), '');
  clean_file_path text := nullif(btrim(coalesce(p_payload->>'filePath', '')), '');
  teacher_position text;
  teacher_is_hod boolean;
begin
  select * into staff_record
  from public.staff_from_login_session(p_session_token);

  if staff_record.id is null then
    raise exception 'Staff login session expired. Please login again.';
  end if;

  if staff_record.status <> 'Active' then
    raise exception 'This staff account is not active.';
  end if;

  if lower(btrim(coalesce(staff_record.category, ''))) <> 'teaching staff' then
    raise exception 'Only Teaching Staff can submit a scheme of work.';
  end if;

  if nullif(btrim(coalesce(staff_record.department, '')), '') is null then
    raise exception 'The Teaching Staff department must be assigned before submission.';
  end if;

  select * into school_record
  from public.schools
  where id = staff_record.school_id
  limit 1;

  if school_record.id is null then
    raise exception 'School was not found for this staff account.';
  end if;

  if clean_file_name is null then
    raise exception 'Scheme document file name is required.';
  end if;

  if clean_file_path is null then
    clean_file_path := school_record.code || '/' || staff_record.id || '/' || extract(epoch from now())::bigint || '-' || clean_file_name;
  end if;

  teacher_position := replace(lower(coalesce(staff_record.position_responsibility, '')), '_', ' ');
  teacher_is_hod := teacher_position
    ~ '(^|[;,])[[:space:]]*(hod|head of department([[:space:]]*\(hod\))?)';

  insert into public.scheme_of_work (
    school_id,
    teacher_id,
    department,
    academic_year,
    term,
    class_name,
    subject_name,
    title,
    file_title,
    file_name,
    file_path,
    file_url,
    status
  )
  values (
    staff_record.school_id,
    staff_record.id,
    staff_record.department,
    nullif(btrim(coalesce(p_payload->>'academic_year', p_payload->>'academicYear', '')), ''),
    nullif(btrim(coalesce(p_payload->>'term', '')), ''),
    nullif(btrim(coalesce(p_payload->>'class_name', p_payload->>'className', '')), ''),
    nullif(btrim(coalesce(p_payload->>'subject_name', p_payload->>'subjectName', '')), ''),
    nullif(btrim(coalesce(p_payload->>'title', '')), ''),
    nullif(btrim(coalesce(p_payload->>'file_title', p_payload->>'fileTitle', '')), ''),
    clean_file_name,
    clean_file_path,
    nullif(coalesce(p_payload->>'fileUrl', p_payload->>'file_url', ''), ''),
    case when teacher_is_hod then 'Pending Head Academic' else 'Pending HOD' end
  )
  returning * into inserted_scheme;

  insert into public.scheme_of_work_history (
    school_id,
    scheme_id,
    actor_id,
    action
  )
  values (
    staff_record.school_id,
    inserted_scheme.id,
    staff_record.id,
    case
      when teacher_is_hod then 'HOD submitted directly to Head Academic'
      else 'Teaching Staff submitted to HOD'
    end
  );

  update public.staff_login_sessions
  set last_seen_at = now()
  where session_token = p_session_token;

  return to_jsonb(inserted_scheme);
end;
$$;

grant execute on function public.secure_submit_scheme_of_work_with_session(text, jsonb)
  to anon, authenticated, service_role;
