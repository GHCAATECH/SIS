-- Scope staff clearance review to assigned subject/class or assigned house.
-- This prevents a staff reviewer from seeing every completed Year 3 student.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.staff_login_sessions (
  session_token text primary key default encode(extensions.gen_random_bytes(32), 'hex'),
  staff_user_id uuid not null references public.staff_users(id) on delete cascade,
  school_id uuid not null references public.schools(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '12 hours')
);

create index if not exists idx_staff_login_sessions_staff
  on public.staff_login_sessions(staff_user_id, expires_at);

create or replace function public.current_staff_id_or_session(p_session_token text default null)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select staff.id
      from public.staff_users staff
      where staff.auth_user_id = auth.uid()
        and staff.status = 'Active'
      limit 1
    ),
    (
      select login.staff_user_id
      from public.staff_login_sessions login
      join public.staff_users staff on staff.id = login.staff_user_id
      where login.session_token = p_session_token
        and login.expires_at > now()
        and staff.status = 'Active'
      limit 1
    )
  );
$$;

create or replace function public.staff_is_house_staff_for_student(
  p_staff_id uuid,
  p_student_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.staff_users staff
    join public.students student on student.id = p_student_id
    left join public.houses house on house.id = student.house_id
    where staff.id = p_staff_id
      and staff.status = 'Active'
      and (
        lower(coalesce(staff.role, '')) = 'house staff'
        or lower(replace(coalesce(staff.position_responsibility, ''), '_', ' ')) like '%house staff%'
        or lower(replace(coalesce(staff.position_responsibility, ''), '_', ' ')) like '%housemaster%'
        or lower(replace(coalesce(staff.position_responsibility, ''), '_', ' ')) like '%housemistress%'
      )
      and nullif(btrim(coalesce(staff.house_assigned, '')), '') is not null
      and (
        lower(btrim(staff.house_assigned)) = lower(btrim(coalesce(house.name, '')))
        or lower(btrim(staff.house_assigned)) = lower(student.house_id::text)
      )
  );
$$;

create or replace function public.staff_has_clearance_scope_for_student(
  p_staff_id uuid,
  p_student_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.staff_users staff
    join public.students student on student.school_id = staff.school_id and student.id = p_student_id
    where staff.id = p_staff_id
      and staff.status = 'Active'
      and (
        exists (
          select 1
          from public.staff_subject_classes assign
          where assign.school_id = staff.school_id
            and assign.staff_user_id = staff.id
            and assign.class_id = student.class_id
        )
        or public.staff_is_house_staff_for_student(staff.id, student.id)
      )
  );
$$;

create or replace function public.secure_list_staff_clearances(
  p_session_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  staff_id uuid;
  staff_record public.staff_users%rowtype;
  rows jsonb;
begin
  staff_id := public.current_staff_id_or_session(p_session_token);

  if staff_id is null then
    raise exception 'Staff login session expired. Please login again.';
  end if;

  select *
    into staff_record
  from public.staff_users
  where id = staff_id
  limit 1;

  if p_session_token is not null then
    update public.staff_login_sessions
    set last_seen_at = now()
    where session_token = p_session_token
      and staff_user_id = staff_id;
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
      or public.staff_has_clearance_scope_for_student(staff_id, sc.student_id)
    );

  return rows;
end;
$$;

drop function if exists public.review_student_clearance(uuid, text, text);

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
  staff_id uuid;
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
  from public.student_clearances
  where id = p_clearance_id;

  if not found then
    raise exception 'Clearance record was not found.';
  end if;

  staff_id := public.current_staff_id_or_session(p_session_token);

  if not public.can_manage_school(clearance.school_id)
     and not public.staff_has_clearance_scope_for_student(staff_id, clearance.student_id) then
    raise exception 'Access denied: this clearance student is not in your assigned class/subject or assigned house.';
  end if;

  update public.student_clearances
  set status = p_status,
      reason = case when p_status = 'Declined' then btrim(coalesce(p_reason, '')) else null end,
      reviewed_by = staff_id,
      reviewed_at = now(),
      updated_at = now()
  where id = p_clearance_id
  returning * into saved;

  return saved;
end;
$$;

drop policy if exists "student clearances read" on public.student_clearances;
drop policy if exists "student clearances manage" on public.student_clearances;

create policy "student clearances read" on public.student_clearances for select to authenticated
using (
  public.can_manage_school(school_id)
  or exists (select 1 from public.students s where s.id = student_id and s.auth_user_id = auth.uid())
  or public.staff_has_clearance_scope_for_student(public.current_staff_id_or_session(null), student_id)
);

create policy "student clearances manage" on public.student_clearances for all to authenticated
using (
  public.can_manage_school(school_id)
  or public.staff_has_clearance_scope_for_student(public.current_staff_id_or_session(null), student_id)
)
with check (
  public.can_manage_school(school_id)
  or public.staff_has_clearance_scope_for_student(public.current_staff_id_or_session(null), student_id)
);

grant execute on function public.current_staff_id_or_session(text) to authenticated, anon, service_role;
grant execute on function public.staff_is_house_staff_for_student(uuid, uuid) to authenticated, anon, service_role;
grant execute on function public.staff_has_clearance_scope_for_student(uuid, uuid) to authenticated, anon, service_role;
grant execute on function public.secure_list_staff_clearances(text) to authenticated, anon, service_role;
grant execute on function public.review_student_clearance(uuid, text, text, text) to authenticated, anon, service_role;
