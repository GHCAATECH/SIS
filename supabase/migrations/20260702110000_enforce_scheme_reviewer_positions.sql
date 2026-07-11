-- Enforce Scheme of Work reviewer positions and department routing in PostgreSQL.

create or replace function public.validate_scheme_of_work_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status = 'Pending HOD'
     and new.status in ('Pending Head Academic', 'Declined by HOD') then
    if new.hod_reviewer_id is null or new.hod_decision_at is null then
      raise exception 'An HOD reviewer and decision date are required.';
    end if;

    if not exists (
      select 1
      from public.staff_users reviewer
      where reviewer.id = new.hod_reviewer_id
        and reviewer.school_id = new.school_id
        and lower(btrim(coalesce(reviewer.category, ''))) = 'teaching staff'
        and lower(btrim(coalesce(reviewer.department, ''))) = lower(btrim(new.department))
        and replace(lower(coalesce(reviewer.position_responsibility, '')), '_', ' ')
          ~ '(^|[;,])[[:space:]]*(hod|head of department([[:space:]]*\(hod\))?)'
    ) then
      raise exception 'Only the Teaching Staff HOD for this department can review this scheme.';
    end if;

    return new;
  end if;

  if old.status = 'Pending Head Academic'
     and new.status in ('Final Approved', 'Declined by Head Academic') then
    if new.head_academic_reviewer_id is null or new.head_academic_decision_at is null then
      raise exception 'A Head Academic reviewer and decision date are required.';
    end if;

    if not exists (
      select 1
      from public.staff_users reviewer
      where reviewer.id = new.head_academic_reviewer_id
        and reviewer.school_id = new.school_id
        and lower(btrim(coalesce(reviewer.category, ''))) = 'teaching staff'
        and replace(lower(coalesce(reviewer.position_responsibility, '')), '_', ' ')
          ~ '(assistant headmaster[[:space:]]*\(academics\)|head[[:space:]]+(of[[:space:]]+)?academics?|academic head)'
    ) then
      raise exception 'Only a Teaching Staff Head Academic can complete final review.';
    end if;

    return new;
  end if;

  raise exception 'Invalid scheme of work status transition from % to %.', old.status, new.status;
end;
$$;
