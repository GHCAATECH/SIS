-- Shared dashboard summary for admin and user dashboards.
-- This replaces broad client-side list/count calls with one aggregate RPC.

create or replace function public.dashboard_student_summary(p_school_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  with active_students as (
    select
      lower(coalesce(s.gender, '')) as gender,
      lower(coalesce(s.residential_status, '')) as residential_status,
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
      and lower(coalesce(s.status, 'active')) not in ('deleted', 'suspended', 'transferred', 'dropped', 'completed', 'archived')
  ),
  totals as (
    select
      count(*) as total_students,
      count(*) filter (where gender in ('male', 'm')) as total_male,
      count(*) filter (where gender in ('female', 'f')) as total_female,
      count(*) filter (where level = 'Year 1') as year1,
      count(*) filter (where level = 'Year 2') as year2,
      count(*) filter (where level = 'Year 3') as year3,
      count(*) filter (where level = 'Year 1' and gender in ('male', 'm')) as year1_male,
      count(*) filter (where level = 'Year 1' and gender in ('female', 'f')) as year1_female,
      count(*) filter (where level = 'Year 2' and gender in ('male', 'm')) as year2_male,
      count(*) filter (where level = 'Year 2' and gender in ('female', 'f')) as year2_female,
      count(*) filter (where level = 'Year 3' and gender in ('male', 'm')) as year3_male,
      count(*) filter (where level = 'Year 3' and gender in ('female', 'f')) as year3_female,
      count(*) filter (where level = 'Year 1' and residential_status similar to '%(board|boarding|boarder)%' and gender in ('female', 'f')) as year1_boarders_female,
      count(*) filter (where level = 'Year 1' and residential_status similar to '%(board|boarding|boarder)%' and gender in ('male', 'm')) as year1_boarders_male,
      count(*) filter (where level = 'Year 2' and residential_status similar to '%(board|boarding|boarder)%' and gender in ('female', 'f')) as year2_boarders_female,
      count(*) filter (where level = 'Year 2' and residential_status similar to '%(board|boarding|boarder)%' and gender in ('male', 'm')) as year2_boarders_male,
      count(*) filter (where level = 'Year 3' and residential_status similar to '%(board|boarding|boarder)%' and gender in ('female', 'f')) as year3_boarders_female,
      count(*) filter (where level = 'Year 3' and residential_status similar to '%(board|boarding|boarder)%' and gender in ('male', 'm')) as year3_boarders_male,
      count(*) filter (where level = 'Year 1' and residential_status like '%day%' and gender in ('female', 'f')) as year1_day_female,
      count(*) filter (where level = 'Year 1' and residential_status like '%day%' and gender in ('male', 'm')) as year1_day_male,
      count(*) filter (where level = 'Year 2' and residential_status like '%day%' and gender in ('female', 'f')) as year2_day_female,
      count(*) filter (where level = 'Year 2' and residential_status like '%day%' and gender in ('male', 'm')) as year2_day_male,
      count(*) filter (where level = 'Year 3' and residential_status like '%day%' and gender in ('female', 'f')) as year3_day_female,
      count(*) filter (where level = 'Year 3' and residential_status like '%day%' and gender in ('male', 'm')) as year3_day_male
    from active_students
  )
  select jsonb_build_object(
    'TotalStudents', total_students,
    'TotalMale', total_male,
    'TotalFemale', total_female,
    'Year1', year1,
    'Year2', year2,
    'Year3', year3,
    'Year1Male', year1_male,
    'Year1Female', year1_female,
    'Year2Male', year2_male,
    'Year2Female', year2_female,
    'Year3Male', year3_male,
    'Year3Female', year3_female,
    'MalePercent', case when total_students = 0 then 0 else (total_male::numeric / total_students::numeric) * 100 end,
    'FemalePercent', case when total_students = 0 then 0 else (total_female::numeric / total_students::numeric) * 100 end,
    'Year1BoardersFemale', year1_boarders_female,
    'Year1BoardersMale', year1_boarders_male,
    'Year2BoardersFemale', year2_boarders_female,
    'Year2BoardersMale', year2_boarders_male,
    'Year3BoardersFemale', year3_boarders_female,
    'Year3BoardersMale', year3_boarders_male,
    'Year1DayFemale', year1_day_female,
    'Year1DayMale', year1_day_male,
    'Year2DayFemale', year2_day_female,
    'Year2DayMale', year2_day_male,
    'Year3DayFemale', year3_day_female,
    'Year3DayMale', year3_day_male,
    'TotalSubjects', (
      select count(*)
      from public.subjects
      where school_id = p_school_id
    ),
    'TeachingStaff', (
      select count(*)
      from public.staff_users
      where school_id = p_school_id
        and lower(coalesce(category, '')) = 'teaching staff'
        and lower(coalesce(status, 'active')) not in ('deleted', 'suspended')
    ),
    'TotalStaff', (
      select count(*)
      from public.staff_users
      where school_id = p_school_id
        and lower(coalesce(status, 'active')) not in ('deleted', 'suspended')
    ),
    'TotalClasses', (
      select count(*)
      from public.classes
      where school_id = p_school_id
    )
  )
  from totals;
$$;

grant execute on function public.dashboard_student_summary(uuid) to authenticated, anon, service_role;
