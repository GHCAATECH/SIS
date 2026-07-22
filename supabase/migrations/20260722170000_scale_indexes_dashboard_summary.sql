-- Scale pass: index high-traffic filters and expose dashboard counts without loading every student.

create extension if not exists pg_trgm;

create index if not exists idx_students_school_status_level
  on public.students (school_id, status, student_level);

create index if not exists idx_students_school_class_status
  on public.students (school_id, class_id, status);

create index if not exists idx_students_school_ass_ref
  on public.students (school_id, ass_ref_id);

create index if not exists idx_students_ass_ref_trgm
  on public.students using gin (ass_ref_id gin_trgm_ops);

create index if not exists idx_students_first_name_trgm
  on public.students using gin (first_name gin_trgm_ops);

create index if not exists idx_students_surname_trgm
  on public.students using gin (surname gin_trgm_ops);

create index if not exists idx_students_other_names_trgm
  on public.students using gin (other_names gin_trgm_ops);

create index if not exists idx_students_phone_number_trgm
  on public.students using gin (phone_number gin_trgm_ops);

create index if not exists idx_staff_users_school_category_status
  on public.staff_users (school_id, category, status);

create index if not exists idx_staff_users_school_staff_id
  on public.staff_users (school_id, staff_id);

create index if not exists idx_assessments_school_filters
  on public.assessments (school_id, academic_year, year_level, semester, class_id, subject_id, assessment_mode_id, status);

create index if not exists idx_assessment_scores_assessment_student
  on public.assessment_scores (assessment_id, student_id);

create index if not exists idx_assessment_scores_student_updated
  on public.assessment_scores (student_id, updated_at desc);

create index if not exists idx_staff_subject_classes_staff_class_subject
  on public.staff_subject_classes (staff_user_id, class_id, subject_id);

create index if not exists idx_student_clearances_school_student_status
  on public.student_clearances (school_id, student_id, status);

create index if not exists idx_documents_school_owner_type_student
  on public.documents (school_id, owner_type, student_id, uploaded_at desc);

create or replace function public.dashboard_student_summary(p_school_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  with active_students as (
    select
      lower(coalesce(s.gender, '')) as gender,
      coalesce(
        nullif(s.student_level, ''),
        nullif(c.year_level, ''),
        case
          when s.year_admitted is null then 'Year 1'
          when extract(year from current_date)::integer - s.year_admitted <= 0 then 'Year 1'
          when extract(year from current_date)::integer - s.year_admitted = 1 then 'Year 2'
          when extract(year from current_date)::integer - s.year_admitted = 2 then 'Year 3'
          else 'Completed'
        end
      ) as level
    from public.students s
    left join public.classes c on c.id = s.class_id
    where s.school_id = p_school_id
      and lower(coalesce(s.status, 'active')) not in ('deleted', 'suspended')
  )
  select jsonb_build_object(
    'TotalStudents', count(*),
    'TotalMale', count(*) filter (where gender in ('male', 'm')),
    'TotalFemale', count(*) filter (where gender in ('female', 'f')),
    'Year1', count(*) filter (where level = 'Year 1'),
    'Year2', count(*) filter (where level = 'Year 2'),
    'Year3', count(*) filter (where level = 'Year 3'),
    'Year1Male', count(*) filter (where level = 'Year 1' and gender in ('male', 'm')),
    'Year1Female', count(*) filter (where level = 'Year 1' and gender in ('female', 'f')),
    'Year2Male', count(*) filter (where level = 'Year 2' and gender in ('male', 'm')),
    'Year2Female', count(*) filter (where level = 'Year 2' and gender in ('female', 'f')),
    'Year3Male', count(*) filter (where level = 'Year 3' and gender in ('male', 'm')),
    'Year3Female', count(*) filter (where level = 'Year 3' and gender in ('female', 'f')),
    'MalePercent', case when count(*) = 0 then 0 else (count(*) filter (where gender in ('male', 'm'))::numeric / count(*)::numeric) * 100 end,
    'FemalePercent', case when count(*) = 0 then 0 else (count(*) filter (where gender in ('female', 'f'))::numeric / count(*)::numeric) * 100 end,
    'TotalSubjects', (select count(*) from public.subjects where school_id = p_school_id),
    'TeachingStaff', (
      select count(*)
      from public.staff_users
      where school_id = p_school_id
        and lower(coalesce(category, '')) = 'teaching staff'
        and lower(coalesce(status, 'active')) <> 'suspended'
    )
  )
  from active_students;
$$;

grant execute on function public.dashboard_student_summary(uuid) to authenticated, anon, service_role;

create index if not exists idx_documents_school_owner_type_staff
  on public.documents (school_id, owner_type, staff_user_id, uploaded_at desc);
