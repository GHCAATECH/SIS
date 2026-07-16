-- Return clearance privilege to students only after they are completed / archived.

create or replace function public.resolve_student_password_login(
  p_ass_ref_id text,
  p_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_ass_ref text := lower(btrim(coalesce(p_ass_ref_id, '')));
  clean_password text := btrim(coalesce(p_password, ''));
  student_record public.students%rowtype;
  school_record public.schools%rowtype;
  class_record public.classes%rowtype;
  programme_record public.programmes%rowtype;
  login_token text;
  is_completed boolean := false;
begin
  if clean_ass_ref = '' or clean_password = '' then
    return null;
  end if;

  select *
    into student_record
  from public.students student
  where lower(coalesce(student.ass_ref_id, '')) = clean_ass_ref
    and coalesce(student.status, 'Active') <> 'Deleted'
  limit 1;

  if student_record.id is null then
    return null;
  end if;

  if clean_password not in (
    to_char(student_record.date_of_birth, 'MMDDYYYY'),
    to_char(student_record.date_of_birth, 'DDMMYYYY')
  ) then
    return null;
  end if;

  is_completed := lower(coalesce(student_record.status, '')) = 'completed'
    or lower(coalesce(student_record.student_level, '')) = 'completed';

  select *
    into school_record
  from public.schools school
  where school.id = student_record.school_id
  limit 1;

  select *
    into class_record
  from public.classes class_row
  where class_row.id = student_record.class_id
  limit 1;

  if class_record.programme_id is not null then
    select *
      into programme_record
    from public.programmes programme
    where programme.id = class_record.programme_id
    limit 1;
  end if;

  insert into public.student_login_sessions (student_id, school_id)
  values (student_record.id, student_record.school_id)
  returning session_token into login_token;

  return jsonb_build_object(
    'id', student_record.id,
    'auth_user_id', student_record.auth_user_id,
    'session_token', login_token,
    'type', 'student',
    'ass_ref_id', student_record.ass_ref_id,
    'full_name', upper(btrim(concat_ws(' ', student_record.first_name, student_record.surname, student_record.other_names))),
    'class_name', coalesce(class_record.name, ''),
    'programme', coalesce(programme_record.name, ''),
    'status', coalesce(student_record.status, ''),
    'student_level', coalesce(student_record.student_level, ''),
    'school_id', student_record.school_id,
    'school_code', coalesce(school_record.code, ''),
    'school_name', coalesce(school_record.name, ''),
    'category', 'Student',
    'role', 'Student',
    'privileges', case
      when is_completed then jsonb_build_array('dashboard', 'mydocuments', 'transcript', 'clearance')
      else jsonb_build_array('dashboard', 'mydocuments', 'transcript')
    end
  );
end;
$$;

grant execute on function public.resolve_student_password_login(text, text) to anon, authenticated, service_role;
