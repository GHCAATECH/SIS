-- Filter-first Assessment Records loading for admin and staff portals.

create or replace function public.secure_list_assessment_records(
  p_school_id uuid,
  p_filters jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rows jsonb;
  v_limit integer := least(greatest(coalesce(nullif(p_filters->>'limit', '')::integer, 1000), 1), 5000);
  v_page integer := greatest(coalesce(nullif(p_filters->>'page', '')::integer, 1), 1);
  v_offset integer := 0;
  v_search text := nullif(btrim(coalesce(p_filters->>'search', '')), '');
  v_class_id uuid := nullif(p_filters->>'classId', '')::uuid;
begin
  v_offset := (v_page - 1) * v_limit;

  select coalesce(jsonb_agg(record_payload order by updated_at desc), '[]'::jsonb)
    into rows
  from (
    select
      score.updated_at,
      jsonb_build_object(
        'score', score.score,
        'grade', score.grade,
        'remark', score.remark,
        'updated_at', score.updated_at,
        'students', jsonb_build_object(
          'ass_ref_id', student.ass_ref_id,
          'first_name', student.first_name,
          'surname', student.surname,
          'other_names', student.other_names,
          'ghana_card_number', student.ghana_card_number,
          'gender', student.gender,
          'disability_status', student.disability_status,
          'date_of_birth', student.date_of_birth,
          'status', student.status,
          'passport_url', student.passport_url,
          'student_level', student.student_level,
          'year_admitted', student.year_admitted,
          'classes', jsonb_build_object('year_level', student_class.year_level)
        ),
        'assessments', jsonb_build_object(
          'class_id', assessment.class_id,
          'academic_year', assessment.academic_year,
          'year_level', assessment.year_level,
          'semester', assessment.semester,
          'status', assessment.status,
          'submitted_at', assessment.submitted_at,
          'overall_score', assessment.overall_score,
          'inserted_by', assessment.inserted_by,
          'subjects', jsonb_build_object('name', subject.name, 'code', subject.code),
          'classes', jsonb_build_object(
            'name', class_row.name,
            'programme_id', class_row.programme_id,
            'programmes', jsonb_build_object('name', programme.name)
          ),
          'assessment_modes', jsonb_build_object(
            'name', mode.name,
            'display_order', mode.display_order
          )
        )
      ) as record_payload
    from public.assessment_scores score
    join public.assessments assessment on assessment.id = score.assessment_id
    join public.students student on student.id = score.student_id
    left join public.classes student_class on student_class.id = student.class_id
    left join public.classes class_row on class_row.id = assessment.class_id
    left join public.programmes programme on programme.id = class_row.programme_id
    left join public.subjects subject on subject.id = assessment.subject_id
    left join public.assessment_modes mode on mode.id = assessment.assessment_mode_id
    where assessment.school_id = p_school_id
      and assessment.status = 'Submitted'
      and (nullif(p_filters->>'academicYear', '') is null or assessment.academic_year = p_filters->>'academicYear')
      and (nullif(p_filters->>'yearLevel', '') is null or assessment.year_level = p_filters->>'yearLevel')
      and (nullif(p_filters->>'semester', '') is null or assessment.semester = p_filters->>'semester')
      and (v_class_id is null or assessment.class_id = v_class_id)
      and (nullif(p_filters->>'className', '') is null or class_row.name = p_filters->>'className')
      and (
        nullif(p_filters->>'modeName', '') is null
        or mode.name = p_filters->>'modeName'
        or (mode.display_order::text || '. ' || mode.name) = p_filters->>'modeName'
      )
      and (nullif(p_filters->>'subjectName', '') is null or subject.name = p_filters->>'subjectName')
      and (
        v_search is null
        or student.ass_ref_id ilike '%' || v_search || '%'
        or concat_ws(' ', student.first_name, student.surname, student.other_names) ilike '%' || v_search || '%'
        or subject.name ilike '%' || v_search || '%'
        or class_row.name ilike '%' || v_search || '%'
      )
    order by score.updated_at desc
    offset v_offset
    limit v_limit
  ) filtered;

  return rows;
end;
$$;

create or replace function public.secure_list_assessment_records_with_session(
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
  rows jsonb;
  is_admin boolean;
  v_limit integer := least(greatest(coalesce(nullif(p_filters->>'limit', '')::integer, 1000), 1), 5000);
  v_page integer := greatest(coalesce(nullif(p_filters->>'page', '')::integer, 1), 1);
  v_offset integer := 0;
  v_search text := nullif(btrim(coalesce(p_filters->>'search', '')), '');
  v_class_id uuid := nullif(p_filters->>'classId', '')::uuid;
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

  select coalesce(jsonb_agg(record_payload order by updated_at desc), '[]'::jsonb)
    into rows
  from (
    select
      score.updated_at,
      jsonb_build_object(
        'score', score.score,
        'grade', score.grade,
        'remark', score.remark,
        'updated_at', score.updated_at,
        'students', jsonb_build_object(
          'ass_ref_id', student.ass_ref_id,
          'first_name', student.first_name,
          'surname', student.surname,
          'other_names', student.other_names,
          'ghana_card_number', student.ghana_card_number,
          'gender', student.gender,
          'disability_status', student.disability_status,
          'date_of_birth', student.date_of_birth,
          'status', student.status,
          'passport_url', student.passport_url,
          'student_level', student.student_level,
          'year_admitted', student.year_admitted,
          'classes', jsonb_build_object('year_level', student_class.year_level)
        ),
        'assessments', jsonb_build_object(
          'class_id', assessment.class_id,
          'academic_year', assessment.academic_year,
          'year_level', assessment.year_level,
          'semester', assessment.semester,
          'status', assessment.status,
          'submitted_at', assessment.submitted_at,
          'overall_score', assessment.overall_score,
          'inserted_by', assessment.inserted_by,
          'subjects', jsonb_build_object('name', subject.name, 'code', subject.code),
          'classes', jsonb_build_object(
            'name', class_row.name,
            'programme_id', class_row.programme_id,
            'programmes', jsonb_build_object('name', programme.name)
          ),
          'assessment_modes', jsonb_build_object(
            'name', mode.name,
            'display_order', mode.display_order
          )
        )
      ) as record_payload
    from public.assessment_scores score
    join public.assessments assessment on assessment.id = score.assessment_id
    join public.students student on student.id = score.student_id
    left join public.classes student_class on student_class.id = student.class_id
    left join public.classes class_row on class_row.id = assessment.class_id
    left join public.programmes programme on programme.id = class_row.programme_id
    left join public.subjects subject on subject.id = assessment.subject_id
    left join public.assessment_modes mode on mode.id = assessment.assessment_mode_id
    where assessment.school_id = staff_record.school_id
      and assessment.status = 'Submitted'
      and (
        is_admin
        or exists (
          select 1
          from public.staff_subject_classes assign
          where assign.school_id = staff_record.school_id
            and assign.staff_user_id = staff_record.id
            and assign.class_id = assessment.class_id
            and assign.subject_id = assessment.subject_id
        )
      )
      and (nullif(p_filters->>'academicYear', '') is null or assessment.academic_year = p_filters->>'academicYear')
      and (nullif(p_filters->>'yearLevel', '') is null or assessment.year_level = p_filters->>'yearLevel')
      and (nullif(p_filters->>'semester', '') is null or assessment.semester = p_filters->>'semester')
      and (v_class_id is null or assessment.class_id = v_class_id)
      and (nullif(p_filters->>'className', '') is null or class_row.name = p_filters->>'className')
      and (
        nullif(p_filters->>'modeName', '') is null
        or mode.name = p_filters->>'modeName'
        or (mode.display_order::text || '. ' || mode.name) = p_filters->>'modeName'
      )
      and (nullif(p_filters->>'subjectName', '') is null or subject.name = p_filters->>'subjectName')
      and (
        v_search is null
        or student.ass_ref_id ilike '%' || v_search || '%'
        or concat_ws(' ', student.first_name, student.surname, student.other_names) ilike '%' || v_search || '%'
        or subject.name ilike '%' || v_search || '%'
        or class_row.name ilike '%' || v_search || '%'
      )
    order by score.updated_at desc
    offset v_offset
    limit v_limit
  ) filtered;

  return rows;
end;
$$;

grant execute on function public.secure_list_assessment_records(uuid, jsonb)
  to anon, authenticated, service_role;

grant execute on function public.secure_list_assessment_records_with_session(text, jsonb)
  to anon, authenticated, service_role;
