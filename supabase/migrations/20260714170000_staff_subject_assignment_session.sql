-- Secure class/subject assignment saving for school admins using staff-password login.
-- Run after 20260714160000_capture_assessment_staff_session.sql.

create or replace function public.secure_save_staff_subject_classes_with_session(
  p_session_token text,
  p_staff_user_id uuid,
  p_assignments jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_record public.staff_users;
  target_record public.staff_users;
  assignment jsonb;
  v_class_id uuid;
  v_subject_id uuid;
begin
  select * into admin_record
  from public.staff_from_login_session(p_session_token);

  if admin_record.id is null then
    raise exception 'School administrator session expired. Please login again.';
  end if;

  if admin_record.category <> 'School Administrator' then
    raise exception 'Access denied: only school administrators can assign classes.';
  end if;

  select * into target_record
  from public.staff_users
  where id = p_staff_user_id
    and school_id = admin_record.school_id
    and status = 'Active'
  limit 1;

  if target_record.id is null then
    raise exception 'Staff user was not found in this school.';
  end if;

  delete from public.staff_subject_classes
  where school_id = admin_record.school_id
    and staff_user_id = target_record.id;

  for assignment in select * from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) loop
    v_class_id := null;
    v_subject_id := null;

    if coalesce(assignment->>'classId', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      v_class_id := (assignment->>'classId')::uuid;
    else
      select id into v_class_id
      from public.classes
      where school_id = admin_record.school_id
        and lower(name) = lower(coalesce(assignment->>'className', assignment->>'classId', ''))
      limit 1;
    end if;

    if coalesce(assignment->>'subjectId', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      v_subject_id := (assignment->>'subjectId')::uuid;
    else
      select id into v_subject_id
      from public.subjects
      where school_id = admin_record.school_id
        and lower(name) = lower(coalesce(assignment->>'subjectName', assignment->>'subjectId', ''))
      limit 1;
    end if;

    if v_class_id is null or v_subject_id is null then
      continue;
    end if;

    if not exists (
      select 1
      from public.classes cls
      join public.class_subjects class_sub on class_sub.class_id = cls.id
      where cls.school_id = admin_record.school_id
        and cls.id = v_class_id
        and class_sub.subject_id = v_subject_id
    ) then
      raise exception 'Class and subject do not match this school setup.';
    end if;

    insert into public.staff_subject_classes (
      school_id,
      staff_user_id,
      class_id,
      subject_id
    ) values (
      admin_record.school_id,
      target_record.id,
      v_class_id,
      v_subject_id
    )
    on conflict (school_id, staff_user_id, class_id, subject_id)
    do nothing;
  end loop;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'classId', assign.class_id,
      'className', cls.name,
      'subjectId', assign.subject_id,
      'subjectName', subj.name
    ) order by cls.name, subj.name)
    from public.staff_subject_classes assign
    join public.classes cls on cls.id = assign.class_id
    join public.subjects subj on subj.id = assign.subject_id
    where assign.school_id = admin_record.school_id
      and assign.staff_user_id = target_record.id
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.secure_save_staff_subject_classes_with_session(text, uuid, jsonb)
to anon, authenticated, service_role;
