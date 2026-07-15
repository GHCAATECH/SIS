-- Secure student portal clearance feed.
-- This avoids relying on client-side table joins and school cache when a student checks clearance status.

create or replace function public.secure_list_my_student_clearances(
  p_ass_ref_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_student public.students%rowtype;
  rows jsonb;
begin
  select *
    into target_student
  from public.students s
  where s.auth_user_id = auth.uid()
     or (
       nullif(btrim(coalesce(p_ass_ref_id, '')), '') is not null
       and lower(s.ass_ref_id) = lower(btrim(p_ass_ref_id))
       and s.auth_user_id = auth.uid()
     )
  limit 1;

  if target_student.id is null then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(
    to_jsonb(sc)
    || jsonb_build_object(
      'students', jsonb_build_object(
        'id', s.id,
        'ass_ref_id', s.ass_ref_id,
        'first_name', s.first_name,
        'surname', s.surname,
        'other_names', s.other_names,
        'status', s.status,
        'student_level', s.student_level,
        'classes', jsonb_build_object(
          'name', cls.name,
          'programmes', jsonb_build_object('name', prog.name)
        )
      ),
      'clearance_requirements', jsonb_build_object(
        'title', req.title,
        'is_required', req.is_required
      ),
      'assigned_staff', case
        when assigned.id is null then null
        else jsonb_build_object('id', assigned.id, 'full_name', assigned.full_name, 'staff_id', assigned.staff_id)
      end,
      'reviewer', case
        when reviewer.id is null then null
        else jsonb_build_object('id', reviewer.id, 'full_name', reviewer.full_name, 'staff_id', reviewer.staff_id)
      end
    )
    order by sc.created_at desc
  ), '[]'::jsonb)
    into rows
  from public.student_clearances sc
  join public.students s on s.id = sc.student_id
  left join public.classes cls on cls.id = s.class_id
  left join public.programmes prog on prog.id = cls.programme_id
  left join public.clearance_requirements req on req.id = sc.requirement_id
  left join public.staff_users assigned on assigned.id = sc.assigned_staff_user_id
  left join public.staff_users reviewer on reviewer.id = sc.reviewed_by
  where sc.student_id = target_student.id;

  return rows;
end;
$$;

grant execute on function public.secure_list_my_student_clearances(text) to authenticated, service_role;
