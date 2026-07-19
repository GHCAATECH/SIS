-- Secure student/staff directory used by the school administrator document uploader.

create or replace function public.secure_document_owner_directory(
  p_session_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor public.staff_users;
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
    raise exception 'Only a school administrator can load the document owner directory.';
  end if;

  if nullif(trim(coalesce(p_session_token, '')), '') is not null then
    update public.staff_login_sessions
    set last_seen_at = now()
    where session_token = p_session_token;
  end if;

  return jsonb_build_object(
    'classes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cls.id,
        'name', cls.name,
        'year_level', cls.year_level
      ) order by cls.name)
      from public.classes cls
      where cls.school_id = actor.school_id
    ), '[]'::jsonb),
    'students', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', student.id,
        'student_id', student.ass_ref_id,
        'name', trim(concat_ws(' ', student.first_name, student.surname, student.other_names)),
        'class_id', student.class_id,
        'class_name', cls.name,
        'status', student.status
      ) order by student.surname, student.first_name, student.other_names)
      from public.students student
      left join public.classes cls on cls.id = student.class_id
      where student.school_id = actor.school_id
        and lower(coalesce(student.status, 'active')) not in ('deleted', 'transferred', 'dropped')
    ), '[]'::jsonb),
    'staff', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', staff.id,
        'staff_id', staff.staff_id,
        'name', coalesce(nullif(staff.full_name, ''), staff.staff_name),
        'category', staff.category,
        'status', staff.status
      ) order by coalesce(nullif(staff.full_name, ''), staff.staff_name))
      from public.staff_users staff
      where staff.school_id = actor.school_id
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.secure_document_owner_directory(text)
  to anon, authenticated, service_role;
