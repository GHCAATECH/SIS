-- Allow School Administrators to load and capture qualitative assessments.

create or replace function public.secure_qualitative_assessment_setup(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  staff_record public.staff_users;
  role_text text;
  is_admin boolean;
  is_form_master boolean;
  assigned_class text;
begin
  staff_record := public.qualitative_staff_from_session_or_auth(p_session_token);
  role_text := lower(replace(coalesce(staff_record.position_responsibility, ''), '_', ' '));
  is_admin := staff_record.category = 'School Administrator';
  is_form_master := role_text ~ 'form[[:space:]]+master|form[[:space:]]+mistress';
  assigned_class := nullif(trim(coalesce(staff_record.form_master_class, '')), '');

  if not is_admin and not is_form_master then
    raise exception 'Qualitative Assessment is assigned to School Administrators and Form Master/Form Mistress only.';
  end if;

  if not is_admin and assigned_class is null then
    return jsonb_build_object(
      'classes', '[]'::jsonb,
      'students', '[]'::jsonb,
      'message', 'No class has been assigned to this Form Master/Form Mistress.'
    );
  end if;

  return jsonb_build_object(
    'classes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cls.id,
        'name', cls.name,
        'programme', prog.name,
        'year_level', cls.year_level
      ) order by cls.name)
      from public.classes cls
      left join public.programmes prog on prog.id = cls.programme_id
      where cls.school_id = staff_record.school_id
        and (is_admin or lower(cls.name) = lower(assigned_class))
    ), '[]'::jsonb),
    'students', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', student.id,
        'ass_ref_id', student.ass_ref_id,
        'surname', student.surname,
        'first_name', student.first_name,
        'other_names', student.other_names,
        'gender', student.gender,
        'disability_status', student.disability_status,
        'passport_url', student.passport_url,
        'student_level', student.student_level,
        'year_admitted', student.year_admitted,
        'classes', jsonb_build_object(
          'name', cls.name,
          'year_level', cls.year_level,
          'programmes', jsonb_build_object('name', prog.name)
        )
      ) order by student.surname, student.first_name)
      from public.students student
      join public.classes cls on cls.id = student.class_id
      left join public.programmes prog on prog.id = cls.programme_id
      where student.school_id = staff_record.school_id
        and coalesce(student.status, 'Active') not in ('Deleted', 'Transferred', 'Dropped')
        and (is_admin or lower(cls.name) = lower(assigned_class))
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.secure_qualitative_assessment_setup(text)
  to anon, authenticated, service_role;
