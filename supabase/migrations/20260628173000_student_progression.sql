alter table public.students
add column if not exists student_level text;

alter table public.students
drop constraint if exists students_student_level_check;

alter table public.students
add constraint students_student_level_check
check (student_level in ('Year 1', 'Year 2', 'Year 3', 'Completed'));

alter table public.students
drop constraint if exists students_status_check;

alter table public.students
add constraint students_status_check
check (status in ('Active', 'Transferred', 'Dropped', 'Repeated', 'Completed'));

update public.students
set student_level = case
  when extract(year from current_date)::integer - year_admitted <= 0 then 'Year 1'
  when extract(year from current_date)::integer - year_admitted = 1 then 'Year 2'
  when extract(year from current_date)::integer - year_admitted = 2 then 'Year 3'
  else 'Completed'
end
where student_level is null
  and year_admitted is not null;

create or replace function public.progress_students(
  p_school_id uuid,
  p_ass_ref_ids text[]
)
returns setof public.students
language plpgsql
security invoker
set search_path = public
as $$
begin
  return query
  with levels as (
    select
      s.id,
      case coalesce(
        s.student_level,
        case
          when extract(year from current_date)::integer - s.year_admitted <= 0 then 'Year 1'
          when extract(year from current_date)::integer - s.year_admitted = 1 then 'Year 2'
          when extract(year from current_date)::integer - s.year_admitted = 2 then 'Year 3'
          else 'Completed'
        end
      )
        when 'Year 1' then 'Year 2'
        when 'Year 2' then 'Year 3'
        when 'Year 3' then 'Completed'
        else 'Completed'
      end as next_level
    from public.students s
    where s.school_id = p_school_id
      and s.ass_ref_id = any(p_ass_ref_ids)
      and coalesce(s.status, 'Active') not in ('Transferred', 'Dropped')
  ), updated as (
    update public.students s
    set
      student_level = levels.next_level,
      status = case when levels.next_level = 'Completed' then 'Completed' else 'Active' end,
      updated_at = now()
    from levels
    where s.id = levels.id
    returning s.*
  )
  select * from updated;
end;
$$;

grant execute on function public.progress_students(uuid, text[]) to anon, authenticated;

notify pgrst, 'reload schema';
