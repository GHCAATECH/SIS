-- Route ordinary Teaching Staff through HOD review.
-- Route an HOD's own submission directly to Head Academic.

create or replace function public.route_scheme_of_work_submission()
returns trigger
language plpgsql
as $$
declare
  teacher_record public.staff_users%rowtype;
  teacher_position text;
  teacher_is_hod boolean;
begin
  select *
  into teacher_record
  from public.staff_users
  where id = new.teacher_id
    and school_id = new.school_id;

  if not found then
    raise exception 'The Teaching Staff account was not found.';
  end if;

  if lower(btrim(coalesce(teacher_record.category, ''))) <> 'teaching staff' then
    raise exception 'Only Teaching Staff can submit a scheme of work.';
  end if;

  if nullif(btrim(coalesce(teacher_record.department, '')), '') is null then
    raise exception 'The Teaching Staff department must be assigned before submission.';
  end if;

  teacher_position := replace(
    lower(coalesce(teacher_record.position_responsibility, '')),
    '_',
    ' '
  );

  teacher_is_hod := teacher_position
    ~ '(^|[;,])[[:space:]]*(hod|head of department([[:space:]]*\(hod\))?)';

  new.department := teacher_record.department;
  new.status := case
    when teacher_is_hod then 'Pending Head Academic'
    else 'Pending HOD'
  end;

  new.hod_reviewer_id := null;
  new.hod_decision_at := null;
  new.hod_reason := null;
  new.head_academic_reviewer_id := null;
  new.head_academic_decision_at := null;
  new.head_academic_reason := null;

  return new;
end;
$$;

drop trigger if exists route_scheme_of_work_submission
on public.scheme_of_work;

create trigger route_scheme_of_work_submission
before insert on public.scheme_of_work
for each row
execute function public.route_scheme_of_work_submission();
