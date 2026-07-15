-- Repair the student clearance feed by ensuring the student's clearance rows exist
-- before returning records to the student portal.

create or replace function public.secure_list_my_student_clearances(
  p_ass_ref_id text default null,
  p_session_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  target_student public.students%rowtype;
  rows jsonb;
begin
  v_student_id := public.current_student_id_or_session(p_session_token);

  if v_student_id is null then
    return '[]'::jsonb;
  end if;

  select *
    into target_student
  from public.students student
  where student.id = v_student_id
    and (
      nullif(btrim(coalesce(p_ass_ref_id, '')), '') is null
      or lower(student.ass_ref_id) = lower(btrim(p_ass_ref_id))
    )
  limit 1;

  if target_student.id is null then
    return '[]'::jsonb;
  end if;

  -- Make the student's clearance rows exist even if the admin did not generate them first.
  perform public.initialize_student_clearance(target_student.id);

  if p_session_token is not null then
    update public.student_login_sessions login
    set last_seen_at = now()
    where login.session_token = p_session_token
      and login.student_id = target_student.id;
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
    order by req.sort_order nulls last, sc.created_at desc
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

create or replace function public.repair_student_clearance_by_ass_ref(
  p_ass_ref_id text
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
  from public.students student
  where lower(student.ass_ref_id) = lower(btrim(coalesce(p_ass_ref_id, '')))
  limit 1;

  if target_student.id is null then
    raise exception 'Student % was not found.', p_ass_ref_id;
  end if;

  perform public.initialize_student_clearance(target_student.id);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'clearance_id', sc.id,
      'ass_ref_id', s.ass_ref_id,
      'student_name', upper(btrim(concat_ws(' ', s.first_name, s.surname, s.other_names))),
      'clearance', req.title,
      'position', sc.position_title,
      'status', sc.status,
      'reviewed_at', sc.reviewed_at,
      'reviewed_by', reviewer.full_name
    )
    order by req.sort_order nulls last, sc.created_at desc
  ), '[]'::jsonb)
    into rows
  from public.student_clearances sc
  join public.students s on s.id = sc.student_id
  left join public.clearance_requirements req on req.id = sc.requirement_id
  left join public.staff_users reviewer on reviewer.id = sc.reviewed_by
  where sc.student_id = target_student.id;

  return rows;
end;
$$;

grant execute on function public.secure_list_my_student_clearances(text, text) to anon, authenticated, service_role;
grant execute on function public.repair_student_clearance_by_ass_ref(text) to authenticated, service_role;
