-- Let the student portal clearance feed use the student's real login session.
-- This fixes cases where Auth linking exists only partially, so clearance rows do not show for the student portal.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.student_login_sessions (
  session_token text primary key default encode(extensions.gen_random_bytes(32), 'hex'),
  student_id uuid not null references public.students(id) on delete cascade,
  school_id uuid not null references public.schools(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '12 hours')
);

create index if not exists idx_student_login_sessions_student
  on public.student_login_sessions(student_id, expires_at);

create or replace function public.current_student_id_or_session(
  p_session_token text default null
)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select student.id
      from public.students student
      where student.auth_user_id = auth.uid()
        and coalesce(student.status, 'Active') <> 'Deleted'
      limit 1
    ),
    (
      select login.student_id
      from public.student_login_sessions login
      join public.students student on student.id = login.student_id
      where login.session_token = p_session_token
        and login.expires_at > now()
        and coalesce(student.status, 'Active') <> 'Deleted'
      limit 1
    )
  );
$$;

create or replace function public.resolve_student_password_login(
  p_ass_ref_id text,
  p_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_ass_ref text := lower(btrim(coalesce(p_ass_ref_id, '')));
  clean_password text := btrim(coalesce(p_password, ''));
  student_record public.students%rowtype;
  school_record public.schools%rowtype;
  class_record public.classes%rowtype;
  programme_record public.programmes%rowtype;
  login_token text;
begin
  if clean_ass_ref = '' or clean_password = '' then
    return null;
  end if;

  select *
    into student_record
  from public.students student
  where lower(coalesce(student.ass_ref_id, '')) = clean_ass_ref
    and coalesce(student.status, 'Active') <> 'Deleted'
  limit 1;

  if student_record.id is null then
    return null;
  end if;

  if clean_password not in (
    to_char(student_record.date_of_birth, 'MMDDYYYY'),
    to_char(student_record.date_of_birth, 'DDMMYYYY')
  ) then
    return null;
  end if;

  select *
    into school_record
  from public.schools school
  where school.id = student_record.school_id
  limit 1;

  select *
    into class_record
  from public.classes class_row
  where class_row.id = student_record.class_id
  limit 1;

  if class_record.programme_id is not null then
    select *
      into programme_record
    from public.programmes programme
    where programme.id = class_record.programme_id
    limit 1;
  end if;

  insert into public.student_login_sessions (student_id, school_id)
  values (student_record.id, student_record.school_id)
  returning session_token into login_token;

  return jsonb_build_object(
    'id', student_record.id,
    'auth_user_id', student_record.auth_user_id,
    'session_token', login_token,
    'type', 'student',
    'ass_ref_id', student_record.ass_ref_id,
    'full_name', upper(btrim(concat_ws(' ', student_record.first_name, student_record.surname, student_record.other_names))),
    'class_name', coalesce(class_record.name, ''),
    'programme', coalesce(programme_record.name, ''),
    'school_id', student_record.school_id,
    'school_code', coalesce(school_record.code, ''),
    'school_name', coalesce(school_record.name, ''),
    'category', 'Student',
    'role', 'Student',
    'privileges', jsonb_build_array('dashboard', 'mydocuments', 'transcript', 'clearance')
  );
end;
$$;

drop function if exists public.secure_list_my_student_clearances(text);

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

grant execute on function public.current_student_id_or_session(text) to anon, authenticated, service_role;
grant execute on function public.resolve_student_password_login(text, text) to anon, authenticated, service_role;
grant execute on function public.secure_list_my_student_clearances(text, text) to anon, authenticated, service_role;
