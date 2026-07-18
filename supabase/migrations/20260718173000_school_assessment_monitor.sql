-- School-scoped assessment monitoring for school administrators.
-- Returns assignment-level capture totals without exposing cross-school data.

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
      (
        select count(*)::integer
        from public.students student
        where student.school_id = context.school_id
          and student.class_id = assignment.class_id
          and coalesce(lower(student.status), 'active') not in ('deleted', 'transferred', 'dropped', 'completed')
          and (
            nullif(p_year_level, '') is null
            or lower(coalesce(nullif(student.student_level, ''), nullif(class_row.year_level, ''), '')) = lower(p_year_level)
          )
      ) as total_assigned,
      (
        select count(distinct score.student_id)::integer
        from public.assessments assessment
        join public.assessment_modes mode on mode.id = assessment.assessment_mode_id
        join public.assessment_scores score on score.assessment_id = assessment.id
        join public.students student on student.id = score.student_id
        where assessment.school_id = context.school_id
          and assessment.class_id = assignment.class_id
          and assessment.subject_id = assignment.subject_id
          and assessment.status = 'Submitted'
          and score.score is not null
          and coalesce(lower(student.status), 'active') not in ('deleted', 'transferred', 'dropped', 'completed')
          and (nullif(p_academic_year, '') is null or assessment.academic_year = p_academic_year)
          and (nullif(p_year_level, '') is null or lower(assessment.year_level) = lower(p_year_level))
          and (nullif(p_semester, '') is null or lower(assessment.semester) = lower(p_semester))
          and (nullif(p_mode_name, '') is null or lower(mode.name) = lower(p_mode_name))
      ) as captured
    from school_context context
    join public.staff_subject_classes assignment on assignment.school_id = context.school_id
    join public.staff_users staff on staff.id = assignment.staff_user_id
    join public.classes class_row on class_row.id = assignment.class_id
    join public.subjects subject on subject.id = assignment.subject_id
    where coalesce(staff.status, 'Active') = 'Active'
      and (
        nullif(p_year_level, '') is null
        or lower(coalesce(class_row.year_level, '')) = lower(p_year_level)
        or exists (
          select 1
          from public.students assigned_student
          where assigned_student.school_id = context.school_id
            and assigned_student.class_id = assignment.class_id
            and lower(coalesce(assigned_student.student_level, '')) = lower(p_year_level)
            and coalesce(lower(assigned_student.status), 'active') not in ('deleted', 'transferred', 'dropped', 'completed')
        )
        or exists (
          select 1
          from public.assessments assigned_assessment
          where assigned_assessment.school_id = context.school_id
            and assigned_assessment.class_id = assignment.class_id
            and lower(coalesce(assigned_assessment.year_level, '')) = lower(p_year_level)
            and (nullif(p_academic_year, '') is null or assigned_assessment.academic_year = p_academic_year)
        )
      )
  ),
  assignment_with_students as (
    select stat.*
    from assignment_stats stat
    where stat.total_assigned > 0
  ),
  unassigned_students as (
    select
      student.id as student_id,
      student.ass_ref_id,
      upper(btrim(concat_ws(' ', student.first_name, student.surname, student.other_names))) as student_name,
      student.gender,
      coalesce(nullif(student.student_level, ''), nullif(class_row.year_level, ''), '') as year_level,
      class_row.id as class_id,
      class_row.name as class_name,
      subject.id as subject_id,
      subject.name as subject_name,
      subject.code as subject_code
    from school_context context
    join public.students student on student.school_id = context.school_id
    join public.classes class_row on class_row.id = student.class_id
    cross join lateral (
      select student_subject.subject_id
      from public.student_subjects student_subject
      where student_subject.student_id = student.id
        and coalesce(lower(student_subject.status), 'active') <> 'dropped'

      union

      select class_subject.subject_id
      from public.class_subjects class_subject
      where class_subject.class_id = student.class_id
        and not exists (
          select 1
          from public.student_subjects existing_subject
          where existing_subject.student_id = student.id
            and coalesce(lower(existing_subject.status), 'active') <> 'dropped'
        )
    ) offered_subject
    join public.subjects subject on subject.id = offered_subject.subject_id
    where coalesce(lower(student.status), 'active') not in ('deleted', 'transferred', 'dropped', 'completed')
      and (
        nullif(p_year_level, '') is null
        or lower(coalesce(nullif(student.student_level, ''), nullif(class_row.year_level, ''), '')) = lower(p_year_level)
      )
      and not exists (
        select 1
        from public.staff_subject_classes staff_assignment
        join public.staff_users assigned_staff on assigned_staff.id = staff_assignment.staff_user_id
        where staff_assignment.school_id = context.school_id
          and staff_assignment.class_id = class_row.id
          and staff_assignment.subject_id = subject.id
          and coalesce(assigned_staff.status, 'Active') = 'Active'
      )
  ),
  capture_summary as (
    select
      coalesce(sum(stat.total_assigned), 0)::integer as expected_total,
      coalesce(sum(stat.captured), 0)::integer as captured_total,
      count(distinct stat.staff_user_id)::integer as teacher_total
    from assignment_with_students stat
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
    join public.students student on student.id = score.student_id
    where assessment.status = 'Submitted'
      and score.score is not null
      and coalesce(lower(student.status), 'active') not in ('deleted', 'transferred', 'dropped', 'completed')
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
      'total_students', (
        select count(*)::integer
        from public.students student
        where student.school_id = context.school_id
          and coalesce(lower(student.status), 'active') not in ('deleted', 'transferred', 'dropped', 'completed')
      ),
      'selected_year_students', (
        select count(*)::integer
        from public.students selected_student
        left join public.classes selected_class on selected_class.id = selected_student.class_id
        where selected_student.school_id = context.school_id
          and coalesce(lower(selected_student.status), 'active') not in ('deleted', 'transferred', 'dropped', 'completed')
          and (
            nullif(p_year_level, '') is null
            or lower(coalesce(nullif(selected_student.student_level, ''), nullif(selected_class.year_level, ''), '')) = lower(p_year_level)
          )
      ),
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
    cross join capture_summary summary
    cross join score_summary scores
  )
  select coalesce((select monitor_payload.payload from monitor_payload limit 1), '{}'::jsonb);
$function$;

revoke all on function public.secure_school_assessment_monitor(text, uuid, text, text, text, text) from public;
grant execute on function public.secure_school_assessment_monitor(text, uuid, text, text, text, text)
to anon, authenticated, service_role;
