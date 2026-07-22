-- Filter-first Capture Assessment loading.
-- This RPC returns only students for the selected class/year/subject and enforces staff assignment.

create or replace function public.secure_list_capture_assessment_students(
  p_session_token text,
  p_filters jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  staff_record public.staff_users;
  is_admin boolean := false;
  v_class_id uuid;
  v_subject_id uuid;
  v_class_name text := nullif(btrim(coalesce(p_filters->>'className', p_filters->>'class_name', '')), '');
  v_subject_name text := nullif(btrim(coalesce(p_filters->>'subjectName', p_filters->>'subject_name', '')), '');
  v_year_level text := nullif(btrim(coalesce(p_filters->>'yearLevel', p_filters->>'year_level', '')), '');
  v_search text := nullif(btrim(coalesce(p_filters->>'search', '')), '');
  v_limit integer := least(greatest(coalesce(nullif(p_filters->>'limit', '')::integer, 1000), 1), 2000);
  v_page integer := greatest(coalesce(nullif(p_filters->>'page', '')::integer, 1), 1);
  v_offset integer;
begin
  select * into staff_record
  from public.staff_from_login_session(p_session_token);

  if staff_record.id is null then
    raise exception 'Staff login session expired. Please login again.';
  end if;

  update public.staff_login_sessions
  set last_seen_at = now()
  where session_token = p_session_token;

  is_admin := staff_record.category = 'School Administrator';
  v_offset := (v_page - 1) * v_limit;

  if nullif(p_filters->>'classId', '') is not null then
    v_class_id := (p_filters->>'classId')::uuid;
  elsif v_class_name is not null then
    select cls.id into v_class_id
    from public.classes cls
    where cls.school_id = staff_record.school_id
      and lower(cls.name) = lower(v_class_name)
    limit 1;
  end if;

  if nullif(p_filters->>'subjectId', '') is not null then
    v_subject_id := (p_filters->>'subjectId')::uuid;
  elsif v_subject_name is not null then
    select subj.id into v_subject_id
    from public.subjects subj
    where subj.school_id = staff_record.school_id
      and lower(subj.name) = lower(v_subject_name)
    limit 1;
  end if;

  if v_class_id is null then
    raise exception 'Select a valid class before loading students.';
  end if;

  if v_subject_id is null then
    raise exception 'Select a valid subject before loading students.';
  end if;

  if not is_admin and not exists (
    select 1
    from public.staff_subject_classes assign
    where assign.school_id = staff_record.school_id
      and assign.staff_user_id = staff_record.id
      and assign.class_id = v_class_id
      and assign.subject_id = v_subject_id
  ) then
    raise exception 'You are not assigned to capture scores for this class and subject.';
  end if;

  return coalesce((
    select jsonb_agg(row_payload order by sort_name, ass_ref_id)
    from (
      select
        s.ass_ref_id,
        lower(coalesce(s.surname, '') || ' ' || coalesce(s.first_name, '') || ' ' || coalesce(s.other_names, '')) as sort_name,
        jsonb_build_object(
          'id', s.id,
          'ass_ref_id', s.ass_ref_id,
          'surname', s.surname,
          'first_name', s.first_name,
          'other_names', s.other_names,
          'student_level', coalesce(nullif(s.student_level, ''), nullif(cls.year_level, '')),
          'year_admitted', s.year_admitted,
          'classes', jsonb_build_object(
            'id', cls.id,
            'name', cls.name,
            'year_level', cls.year_level
          )
        ) as row_payload
      from public.students s
      join public.classes cls on cls.id = s.class_id
      where s.school_id = staff_record.school_id
        and s.class_id = v_class_id
        and lower(coalesce(s.status, 'active')) not in ('deleted', 'transferred', 'dropped', 'completed')
        and (
          v_year_level is null
          or lower(coalesce(nullif(s.student_level, ''), nullif(cls.year_level, ''))) = lower(v_year_level)
        )
        and (
          v_search is null
          or s.ass_ref_id ilike '%' || v_search || '%'
          or s.first_name ilike '%' || v_search || '%'
          or s.surname ilike '%' || v_search || '%'
          or s.other_names ilike '%' || v_search || '%'
        )
      order by sort_name, s.ass_ref_id
      offset v_offset
      limit v_limit
    ) rows
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.secure_list_capture_assessment_students(text, jsonb)
  to anon, authenticated, service_role;
