-- Fix ambiguous staff_id references in clearance staff portal RPCs.
-- Run this after 20260715202000_scope_clearance_by_assignment.sql.

create or replace function public.secure_list_staff_clearances(
  p_session_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff_id uuid;
  staff_record public.staff_users%rowtype;
  rows jsonb;
begin
  v_staff_id := public.current_staff_id_or_session(p_session_token);

  if v_staff_id is null then
    raise exception 'Staff login session expired. Please login again.';
  end if;

  select *
    into staff_record
  from public.staff_users staff
  where staff.id = v_staff_id
  limit 1;

  if p_session_token is not null then
    update public.staff_login_sessions login
    set last_seen_at = now()
    where login.session_token = p_session_token
      and login.staff_user_id = v_staff_id;
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
  where sc.school_id = staff_record.school_id
    and (
      public.can_manage_school(sc.school_id)
      or public.staff_has_clearance_scope_for_student(v_staff_id, sc.student_id)
    );

  return rows;
end;
$$;

create or replace function public.review_student_clearance(
  p_clearance_id uuid,
  p_status text,
  p_reason text default null,
  p_session_token text default null
)
returns public.student_clearances
language plpgsql
security definer
set search_path = public
as $$
declare
  clearance public.student_clearances%rowtype;
  v_staff_id uuid;
  saved public.student_clearances;
begin
  if p_status not in ('Cleared', 'Declined', 'Pending') then
    raise exception 'Invalid clearance status.';
  end if;
  if p_status = 'Declined' and nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'Decline reason is required.';
  end if;

  select *
    into clearance
  from public.student_clearances sc
  where sc.id = p_clearance_id;

  if not found then
    raise exception 'Clearance record was not found.';
  end if;

  v_staff_id := public.current_staff_id_or_session(p_session_token);

  if not public.can_manage_school(clearance.school_id)
     and not public.staff_has_clearance_scope_for_student(v_staff_id, clearance.student_id) then
    raise exception 'Access denied: this clearance student is not in your assigned class/subject or assigned house.';
  end if;

  update public.student_clearances sc
  set status = p_status,
      reason = case when p_status = 'Declined' then btrim(coalesce(p_reason, '')) else null end,
      reviewed_by = v_staff_id,
      reviewed_at = now(),
      updated_at = now()
  where sc.id = p_clearance_id
  returning * into saved;

  return saved;
end;
$$;

grant execute on function public.secure_list_staff_clearances(text) to authenticated, anon, service_role;
grant execute on function public.review_student_clearance(uuid, text, text, text) to authenticated, anon, service_role;
