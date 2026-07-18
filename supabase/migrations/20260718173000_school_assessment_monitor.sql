-- School-scoped assessment monitoring for school administrators.
-- Returns assignment-level capture totals without exposing cross-school data.

create or replace function public.secure_school_assessment_monitor(
  p_session_token text default null,
  p_school_id uuid default null,
  p_academic_year text default null,
  p_year_level text default null,
  p_semester text default null,
  p_mode_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  staff_record public.staff_users;
  v_school_id uuid;
  result jsonb;
begin
  if nullif(btrim(coalesce(p_session_token, '')), '') is not null then
    select * into staff_record
    from public.staff_from_login_session(p_session_token);

    if staff_record.id is null then
      raise exception 'Staff login session expired. Please login again.';
    end if;

    if staff_record.category <> 'School Administrator' then
      raise exception 'Only a school administrator can view the school assessment monitor.';
    end if;

    v_school_id := staff_record.school_id;

    update public.staff_login_sessions
    set last_seen_at = now()
    where session_token = p_session_token;
  else
    v_school_id := coalesce(p_school_id, public.current_school_id());
    if v_school_id is null or not public.can_manage_school(v_school_id) then
      raise exception 'You do not have permission to view this school assessment monitor.';
    end if;
  end if;

  with assignment_stats as (
    select
      assign.staff_user_id,
      coalesce(nullif(staff.full_name, ''), nullif(staff.staff_name, ''), staff.staff_id, 'Unnamed Staff') as teacher_name,
      coalesce(staff.phone, '') as phone_number,
      coalesce(staff.email, '') as email,
      assign.class_id,
      cls.name as class_name,
      assign.subject_id,
      subject.name as subject_name,
      subject.code as subject_code,
      (
        select count(*)::integer
        from public.students student
        where student.school_id = v_school_id
          and student.class_id = assign.class_id
          and coalesce(lower(student.status), 'active') not in ('deleted', 'transferred', 'dropped', 'completed')
      ) as total_assigned,
      (
        select count(distinct score.student_id)::integer
        from public.assessments assessment
        join public.assessment_modes mode on mode.id = assessment.assessment_mode_id
        join public.assessment_scores score on score.assessment_id = assessment.id
        join public.students student on student.id = score.student_id
        where assessment.school_id = v_school_id
          and assessment.class_id = assign.class_id
          and assessment.subject_id = assign.subject_id
          and assessment.status = 'Submitted'
          and score.score is not null
          and coalesce(lower(student.status), 'active') not in ('deleted', 'transferred', 'dropped', 'completed')
          and (nullif(p_academic_year, '') is null or assessment.academic_year = p_academic_year)
          and (nullif(p_year_level, '') is null or lower(assessment.year_level) = lower(p_year_level))
          and (nullif(p_semester, '') is null or lower(assessment.semester) = lower(p_semester))
          and (nullif(p_mode_name, '') is null or lower(mode.name) = lower(p_mode_name))
      ) as captured
    from public.staff_subject_classes assign
    join public.staff_users staff on staff.id = assign.staff_user_id
    join public.classes cls on cls.id = assign.class_id
    join public.subjects subject on subject.id = assign.subject_id
    where assign.school_id = v_school_id
      and coalesce(staff.status, 'Active') = 'Active'
      and (nullif(p_year_level, '') is null or lower(cls.year_level) = lower(p_year_level))
  ),
  capture_summary as (
    select
      coalesce(sum(total_assigned), 0)::integer as expected_total,
      coalesce(sum(captured), 0)::integer as captured_total,
      count(distinct staff_user_id)::integer as teacher_total
    from assignment_stats
  ),
  score_summary as (
    select coalesce(round(avg(
      case
        when assessment.overall_score > 0 then (score.score / assessment.overall_score) * 100
        else null
      end
    )::numeric, 2), 0) as mean_mark
    from public.assessments assessment
    join public.assessment_modes mode on mode.id = assessment.assessment_mode_id
    join public.assessment_scores score on score.assessment_id = assessment.id
    join public.students student on student.id = score.student_id
    where assessment.school_id = v_school_id
      and assessment.status = 'Submitted'
      and score.score is not null
      and coalesce(lower(student.status), 'active') not in ('deleted', 'transferred', 'dropped', 'completed')
      and (nullif(p_academic_year, '') is null or assessment.academic_year = p_academic_year)
      and (nullif(p_year_level, '') is null or lower(assessment.year_level) = lower(p_year_level))
      and (nullif(p_semester, '') is null or lower(assessment.semester) = lower(p_semester))
      and (nullif(p_mode_name, '') is null or lower(mode.name) = lower(p_mode_name))
  )
  select jsonb_build_object(
    'school_id', school.id,
    'school_code', school.code,
    'school_name', school.name,
    'total_students', (
      select count(*)::integer
      from public.students student
      where student.school_id = v_school_id
        and coalesce(lower(student.status), 'active') not in ('deleted', 'transferred', 'dropped', 'completed')
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
      from assignment_stats stat
    ), '[]'::jsonb)
  into result
  from public.schools school
  cross join capture_summary summary
  cross join score_summary scores
  where school.id = v_school_id;

  return coalesce(result, '{}'::jsonb);
end;
$$;

revoke all on function public.secure_school_assessment_monitor(text, uuid, text, text, text, text) from public;
grant execute on function public.secure_school_assessment_monitor(text, uuid, text, text, text, text)
to anon, authenticated, service_role;
