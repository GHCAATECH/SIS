-- Filter-first clearance loading for admin clearance page.

create index if not exists idx_students_school_status_level_updated
  on public.students (school_id, status, student_level, updated_at desc);

create index if not exists idx_students_school_class_status
  on public.students (school_id, class_id, status, student_level);

create index if not exists idx_student_clearances_school_status_updated
  on public.student_clearances (school_id, status, updated_at desc);

create index if not exists idx_student_clearances_school_student_status
  on public.student_clearances (school_id, student_id, status);

create index if not exists idx_classes_school_name
  on public.classes (school_id, name);

create or replace function public.secure_list_student_clearances(
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
  v_limit integer := least(greatest(coalesce(nullif(p_filters->>'limit', '')::integer, 500), 1), 1000);
  v_page integer := greatest(coalesce(nullif(p_filters->>'page', '')::integer, 1), 1);
  v_offset integer := 0;
  v_status text := nullif(btrim(coalesce(p_filters->>'status', '')), '');
  v_completed_year text := nullif(btrim(coalesce(p_filters->>'completedYear', '')), '');
  v_class_name text := nullif(btrim(coalesce(p_filters->>'className', '')), '');
  v_search text := nullif(btrim(coalesce(p_filters->>'search', '')), '');
  v_student_id uuid := nullif(p_filters->>'studentId', '')::uuid;
  v_student_ref text := nullif(btrim(coalesce(p_filters->>'studentAssRef', '')), '');
begin
  if p_school_id is null then
    raise exception 'School context is required.';
  end if;

  v_offset := (v_page - 1) * v_limit;

  select coalesce(jsonb_agg(row_payload order by row_updated_at desc), '[]'::jsonb)
    into rows
  from (
    select
      sc.updated_at as row_updated_at,
      jsonb_build_object(
        'id', sc.id,
        'school_id', sc.school_id,
        'student_id', sc.student_id,
        'requirement_id', sc.requirement_id,
        'assigned_staff_user_id', sc.assigned_staff_user_id,
        'position_title', sc.position_title,
        'status', sc.status,
        'reason', sc.reason,
        'reviewed_by', sc.reviewed_by,
        'reviewed_at', sc.reviewed_at,
        'created_at', sc.created_at,
        'updated_at', sc.updated_at,
        'students', jsonb_build_object(
          'id', student.id,
          'ass_ref_id', student.ass_ref_id,
          'std_id', student.ass_ref_id,
          'first_name', student.first_name,
          'surname', student.surname,
          'other_names', student.other_names,
          'status', student.status,
          'student_level', student.student_level,
          'passport_url', student.passport_url,
          'created_at', student.created_at,
          'updated_at', student.updated_at,
          'classes', jsonb_build_object(
            'id', class_row.id,
            'name', class_row.name,
            'programmes', jsonb_build_object('name', programme.name)
          )
        ),
        'clearance_requirements', jsonb_build_object(
          'title', requirement.title,
          'is_required', requirement.is_required
        ),
        'assigned_staff', case
          when assigned.id is null then null
          else jsonb_build_object('id', assigned.id, 'full_name', assigned.full_name, 'staff_id', assigned.staff_id)
        end,
        'reviewer', case
          when reviewer.id is null then null
          else jsonb_build_object('id', reviewer.id, 'full_name', reviewer.full_name, 'staff_id', reviewer.staff_id)
        end
      ) as row_payload
    from public.student_clearances sc
    join public.students student on student.id = sc.student_id
    left join public.classes class_row on class_row.id = student.class_id
    left join public.programmes programme on programme.id = class_row.programme_id
    left join public.clearance_requirements requirement on requirement.id = sc.requirement_id
    left join public.staff_users assigned on assigned.id = sc.assigned_staff_user_id
    left join public.staff_users reviewer on reviewer.id = sc.reviewed_by
    where sc.school_id = p_school_id
      and student.school_id = p_school_id
      and (lower(coalesce(student.status, '')) = 'completed' or lower(coalesce(student.student_level, '')) = 'completed')
      and (v_student_id is null or student.id = v_student_id)
      and (v_student_ref is null or lower(student.ass_ref_id) = lower(v_student_ref))
      and (v_status is null or sc.status = v_status)
      and (v_class_name is null or class_row.name = v_class_name)
      and (
        v_completed_year is null
        or extract(year from coalesce(student.updated_at, sc.updated_at, sc.created_at))::text = v_completed_year
      )
      and (
        v_search is null
        or student.ass_ref_id ilike '%' || v_search || '%'
        or concat_ws(' ', student.first_name, student.surname, student.other_names) ilike '%' || v_search || '%'
        or class_row.name ilike '%' || v_search || '%'
        or requirement.title ilike '%' || v_search || '%'
        or assigned.full_name ilike '%' || v_search || '%'
      )
    order by sc.updated_at desc
    offset v_offset
    limit v_limit
  ) filtered;

  return rows;
end;
$$;

grant execute on function public.secure_list_student_clearances(uuid, jsonb)
  to anon, authenticated, service_role;