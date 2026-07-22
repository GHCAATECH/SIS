-- Assessment Monitor v2: school-scoped, filter-first monitor payload.
-- Keeps heavy aggregation inside PostgreSQL and returns one compact JSON payload.

create index if not exists idx_students_school_level_class_status
  on public.students (school_id, student_level, class_id, status);

create index if not exists idx_staff_subject_classes_school_class_subject
  on public.staff_subject_classes (school_id, class_id, subject_id, staff_user_id);

create index if not exists idx_assessments_monitor_lookup
  on public.assessments (school_id, academic_year, year_level, semester, status, class_id, subject_id, assessment_mode_id);

create index if not exists idx_assessment_scores_assessment_student_score
  on public.assessment_scores (assessment_id, student_id, score);

drop function if exists public.secure_school_assessment_monitor(text, uuid, text, text, text, text);

create function public.secure_school_assessment_monitor(
  p_session_token text default null,
  p_school_id uuid default null,
  p_academic_year text default null,
  p_year_level text default null,
  p_semester text default null,
  p_mode_name text default null
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $function$
  with school_context as (
    select session_staff.school_id
    from public.staff_from_login_session(p_session_token) session_staff
    where nullif(btrim(coalesce(p_session_token, '')), '') is not null
      and session_staff.category = 'School Administrator'

    union all

    select coalesce(p_school_id, public.current_school_id())
    where nullif(btrim(coalesce(p_session_token, '')), '') is null
      and coalesce(p_school_id, public.current_school_id()) is not null
      and public.can_manage_school(coalesce(p_school_id, public.current_school_id()))
    limit 1
  ),
  selected_students as (
    select
      student.id,
      student.ass_ref_id,
      upper(btrim(concat_ws(' ', student.first_name, student.surname, student.other_names))) as student_name,
      student.gender,
      student.class_id,
      class_row.name as class_name,
      coalesce(nullif(student.student_level, ''), nullif(class_row.year_level, ''), '') as year_level
    from school_context context
    join public.students student on student.school_id = context.school_id
    left join public.classes class_row on class_row.id = student.class_id
    where coalesce(lower(student.status), 'active') not in ('deleted', 'transferred', 'dropped', 'completed')
      and (
        nullif(p_year_level, '') is null
        or lower(coalesce(nullif(student.student_level, ''), nullif(class_row.year_level, ''), '')) = lower(p_year_level)
      )
  ),
  active_school_students as (
    select count(*)::integer as total_students
    from school_context context
    join public.students student on student.school_id = context.school_id
    where coalesce(lower(student.status), 'active') not in ('deleted', 'transferred', 'dropped', 'completed')
  ),
  assignment_stats as (
    select
      assignment.staff_user_id,
      coalesce(nullif(staff.full_name, ''), nullif(staff.staff_name, ''), staff.staff_id, 'Unnamed Staff') as teacher_name,
      coalesce(staff.phone, '') as phone_number,
      coalesce(staff.email, '') as email,
      assignment.class_id,
      class_row.name as class_name,
      assignment.subject_id,
      subject.name as subject_name,
      subject.code as subject_code,
      count(distinct selected_student.id)::integer as total_assigned,
      count(distinct score.student_id) filter (where score.score is not null)::integer as captured
    from school_context context
    join public.staff_subject_classes assignment on assignment.school_id = context.school_id
    join public.staff_users staff on staff.id = assignment.staff_user_id
    join public.classes class_row on class_row.id = assignment.class_id
    join public.subjects subject on subject.id = assignment.subject_id
    join selected_students selected_student on selected_student.class_id = assignment.class_id
    left join public.assessment_modes mode
      on lower(mode.name) = lower(nullif(p_mode_name, ''))
    left join public.assessments assessment
      on assessment.school_id = context.school_id
     and assessment.class_id = assignment.class_id
     and assessment.subject_id = assignment.subject_id
     and assessment.status = 'Submitted'
     and (nullif(p_academic_year, '') is null or assessment.academic_year = p_academic_year)
     and (nullif(p_year_level, '') is null or lower(assessment.year_level) = lower(p_year_level))
     and (nullif(p_semester, '') is null or lower(assessment.semester) = lower(p_semester))
     and (
       nullif(p_mode_name, '') is null
       or assessment.assessment_mode_id = mode.id
     )
    left join public.assessment_scores score
      on score.assessment_id = assessment.id
     and score.student_id = selected_student.id
    where coalesce(staff.status, 'Active') = 'Active'
    group by
      assignment.staff_user_id,
      teacher_name,
      staff.phone,
      staff.email,
      assignment.class_id,
      class_row.name,
      assignment.subject_id,
      subject.name,
      subject.code
  ),
  assignment_with_students as (
    select stat.*
    from assignment_stats stat
    where stat.total_assigned > 0
  ),
  offered_subjects as (
    select
      selected_student.id as student_id,
      selected_student.ass_ref_id,
      selected_student.student_name,
      selected_student.gender,
      selected_student.year_level,
      selected_student.class_id,
      selected_student.class_name,
      coalesce(student_subject.subject_id, class_subject.subject_id) as subject_id
    from selected_students selected_student
    left join public.student_subjects student_subject
      on student_subject.student_id = selected_student.id
     and coalesce(lower(student_subject.status), 'active') <> 'dropped'
    left join public.class_subjects class_subject
      on class_subject.class_id = selected_student.class_id
     and not exists (
       select 1
       from public.student_subjects existing_subject
       where existing_subject.student_id = selected_student.id
         and coalesce(lower(existing_subject.status), 'active') <> 'dropped'
     )
    where coalesce(student_subject.subject_id, class_subject.subject_id) is not null
  ),
  unassigned_students as (
    select
      offered.student_id,
      offered.ass_ref_id,
      offered.student_name,
      offered.gender,
      offered.year_level,
      offered.class_id,
      offered.class_name,
      subject.id as subject_id,
      subject.name as subject_name,
      subject.code as subject_code
    from school_context context
    join offered_subjects offered on true
    join public.subjects subject on subject.id = offered.subject_id
    where not exists (
      select 1
      from public.staff_subject_classes assignment
      join public.staff_users staff on staff.id = assignment.staff_user_id
      where assignment.school_id = context.school_id
        and assignment.class_id = offered.class_id
        and assignment.subject_id = offered.subject_id
        and coalesce(staff.status, 'Active') = 'Active'
    )
  ),
  capture_summary as (
    select
      coalesce(sum(total_assigned), 0)::integer as expected_total,
      coalesce(sum(captured), 0)::integer as captured_total,
      count(distinct staff_user_id)::integer as teacher_total
    from assignment_with_students
  ),
  score_summary as (
    select coalesce(round(avg(
      case
        when assessment.overall_score > 0 then (score.score / assessment.overall_score) * 100
        else null
      end
    )::numeric, 2), 0) as mean_mark
    from school_context context
    join public.assessments assessment on assessment.school_id = context.school_id
    join public.assessment_modes mode on mode.id = assessment.assessment_mode_id
    join public.assessment_scores score on score.assessment_id = assessment.id
    join selected_students selected_student on selected_student.id = score.student_id
    where assessment.status = 'Submitted'
      and score.score is not null
      and (nullif(p_academic_year, '') is null or assessment.academic_year = p_academic_year)
      and (nullif(p_year_level, '') is null or lower(assessment.year_level) = lower(p_year_level))
      and (nullif(p_semester, '') is null or lower(assessment.semester) = lower(p_semester))
      and (nullif(p_mode_name, '') is null or lower(mode.name) = lower(p_mode_name))
  ),
  monitor_payload as (
    select jsonb_build_object(
      'school_id', school.id,
      'school_code', school.code,
      'school_name', school.name,
      'total_students', active_total.total_students,
      'selected_year_students', (select count(*)::integer from selected_students),
      'expected_total', summary.expected_total,
      'captured_total', summary.captured_total,
      'percentage_completed', case
        when summary.expected_total = 0 then 0
        else round((summary.captured_total::numeric / summary.expected_total::numeric) * 100, 2)
      end,
      'mean_mark', scores.mean_mark,
      'teacher_total', summary.teacher_total,
      'teachers', coalesce((
        select jsonb_agg(jsonb_build_object(
          'staff_user_id', stat.staff_user_id,
          'teacher_name', stat.teacher_name,
          'phone_number', stat.phone_number,
          'email', stat.email,
          'class_id', stat.class_id,
          'class_name', stat.class_name,
          'subject_id', stat.subject_id,
          'subject_name', stat.subject_name,
          'subject_code', stat.subject_code,
          'total_assigned', stat.total_assigned,
          'captured', stat.captured,
          'not_captured', greatest(stat.total_assigned - stat.captured, 0)
        ) order by stat.teacher_name, stat.class_name, stat.subject_name)
        from assignment_with_students stat
      ), '[]'::jsonb),
      'unassigned_students', coalesce((
        select jsonb_agg(jsonb_build_object(
          'student_id', unassigned.student_id,
          'ass_ref_id', unassigned.ass_ref_id,
          'student_name', unassigned.student_name,
          'gender', unassigned.gender,
          'year_level', unassigned.year_level,
          'class_id', unassigned.class_id,
          'class_name', unassigned.class_name,
          'subject_id', unassigned.subject_id,
          'subject_name', unassigned.subject_name,
          'subject_code', unassigned.subject_code,
          'status', 'UNASSIGNED'
        ) order by unassigned.class_name, unassigned.student_name, unassigned.subject_name)
        from unassigned_students unassigned
      ), '[]'::jsonb)
    ) as payload
    from school_context context
    join public.schools school on school.id = context.school_id
    cross join active_school_students active_total
    cross join capture_summary summary
    cross join score_summary scores
  )
  select coalesce((select payload from monitor_payload limit 1), '{}'::jsonb);
$function$;

revoke all on function public.secure_school_assessment_monitor(text, uuid, text, text, text, text) from public;
grant execute on function public.secure_school_assessment_monitor(text, uuid, text, text, text, text)
to anon, authenticated, service_role;
