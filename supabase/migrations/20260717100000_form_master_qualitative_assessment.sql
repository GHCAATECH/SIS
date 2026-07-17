-- Assign qualitative assessment capture to Form Master/Form Mistress by class.
-- Run after 20260717090000_staff_form_master_class.sql.

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

alter table public.staff_users
  add column if not exists form_master_class text;

alter table public.qualitative_assessments
  add column if not exists captured_by_staff_id uuid references public.staff_users(id) on delete set null,
  add column if not exists captured_by_name text;

create or replace function public.resolve_staff_password_login(
  p_identifier text,
  p_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_identifier text := lower(trim(coalesce(p_identifier, '')));
  clean_password text := coalesce(p_password, '');
  staff_record public.staff_users;
  school_record public.schools;
  privilege_keys jsonb := '[]'::jsonb;
  login_token text;
begin
  if clean_identifier = '' or clean_password = '' then
    return null;
  end if;

  select *
    into staff_record
  from public.staff_users
  where status = 'Active'
    and coalesce(account_password, '') = clean_password
    and (
      lower(coalesce(staff_id, '')) = clean_identifier
      or lower(coalesce(username, '')) = clean_identifier
      or lower(coalesce(email, '')) = clean_identifier
    )
  limit 1;

  if staff_record.id is null then
    return null;
  end if;

  select *
    into school_record
  from public.schools
  where id = staff_record.school_id
  limit 1;

  if school_record.id is null then
    return null;
  end if;

  if coalesce(school_record.subscription_status, 'Active') = 'Suspended' then
    return null;
  end if;

  if coalesce(school_record.subscription_status, 'Active') = 'Trial'
     and school_record.trial_expires_at is not null
     and school_record.trial_expires_at < now() then
    return null;
  end if;

  select coalesce(jsonb_agg(page_key order by page_key), '[]'::jsonb)
    into privilege_keys
  from public.user_privileges
  where staff_user_id = staff_record.id;

  delete from public.staff_login_sessions
  where staff_user_id = staff_record.id
    and expires_at < now();

  insert into public.staff_login_sessions (staff_user_id, school_id)
  values (staff_record.id, staff_record.school_id)
  returning session_token into login_token;

  update public.staff_users
  set last_login_at = now()
  where id = staff_record.id;

  return jsonb_build_object(
    'id', staff_record.id,
    'auth_user_id', staff_record.auth_user_id,
    'session_token', login_token,
    'full_name', staff_record.full_name,
    'staff_id', staff_record.staff_id,
    'username', staff_record.username,
    'email', staff_record.email,
    'role', staff_record.role,
    'category', staff_record.category,
    'position_responsibility', staff_record.position_responsibility,
    'position', staff_record.position_responsibility,
    'form_master_class', staff_record.form_master_class,
    'department', staff_record.department,
    'rank', staff_record.rank,
    'school_id', staff_record.school_id,
    'school_code', school_record.code,
    'school_name', school_record.name,
    'isAdmin', staff_record.category = 'School Administrator',
    'privileges', privilege_keys
  );
end;
$$;

create or replace function public.secure_qualitative_assessment_setup(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  staff_record public.staff_users;
  role_text text;
  is_admin boolean;
  is_form_master boolean;
  assigned_class text;
begin
  select staff.*
    into staff_record
  from public.staff_login_sessions login
  join public.staff_users staff on staff.id = login.staff_user_id
  where login.session_token = p_session_token
    and login.expires_at > now()
    and staff.status = 'Active'
  limit 1;

  if staff_record.id is null then
    raise exception 'Staff login session expired. Please logout and login again.';
  end if;

  update public.staff_login_sessions
  set last_seen_at = now()
  where session_token = p_session_token;

  role_text := lower(replace(coalesce(staff_record.position_responsibility, ''), '_', ' '));
  is_admin := staff_record.category = 'School Administrator';
  is_form_master := role_text ~ 'form[[:space:]]+master|form[[:space:]]+mistress';
  assigned_class := nullif(trim(coalesce(staff_record.form_master_class, '')), '');

  if not is_admin and not is_form_master then
    raise exception 'Qualitative Assessment is assigned to Form Master/Form Mistress only.';
  end if;

  if not is_admin and assigned_class is null then
    return jsonb_build_object(
      'classes', '[]'::jsonb,
      'students', '[]'::jsonb,
      'message', 'No class has been assigned to this Form Master/Form Mistress.'
    );
  end if;

  return jsonb_build_object(
    'classes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cls.id,
        'name', cls.name,
        'programme', prog.name,
        'year_level', cls.year_level
      ) order by cls.name)
      from public.classes cls
      left join public.programmes prog on prog.id = cls.programme_id
      where cls.school_id = staff_record.school_id
        and (is_admin or lower(cls.name) = lower(assigned_class))
    ), '[]'::jsonb),
    'students', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', student.id,
        'ass_ref_id', student.ass_ref_id,
        'surname', student.surname,
        'first_name', student.first_name,
        'other_names', student.other_names,
        'gender', student.gender,
        'disability_status', student.disability_status,
        'passport_url', student.passport_url,
        'student_level', student.student_level,
        'year_admitted', student.year_admitted,
        'classes', jsonb_build_object(
          'name', cls.name,
          'year_level', cls.year_level,
          'programmes', jsonb_build_object('name', prog.name)
        )
      ) order by student.surname, student.first_name)
      from public.students student
      join public.classes cls on cls.id = student.class_id
      left join public.programmes prog on prog.id = cls.programme_id
      where student.school_id = staff_record.school_id
        and coalesce(student.status, 'Active') not in ('Deleted', 'Transferred', 'Dropped')
        and (is_admin or lower(cls.name) = lower(assigned_class))
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.secure_save_qualitative_assessment_with_session(
  p_session_token text,
  p_payload jsonb
)
returns public.qualitative_assessments
language plpgsql
security definer
set search_path = public
as $$
declare
  staff_record public.staff_users;
  role_text text;
  is_admin boolean;
  is_form_master boolean;
  assigned_class text;
  v_class_name text;
  v_student_ref text;
  v_term text;
  v_student public.students;
  saved public.qualitative_assessments;
begin
  select staff.*
    into staff_record
  from public.staff_login_sessions login
  join public.staff_users staff on staff.id = login.staff_user_id
  where login.session_token = p_session_token
    and login.expires_at > now()
    and staff.status = 'Active'
  limit 1;

  if staff_record.id is null then
    raise exception 'Staff login session expired. Please logout and login again.';
  end if;

  role_text := lower(replace(coalesce(staff_record.position_responsibility, ''), '_', ' '));
  is_admin := staff_record.category = 'School Administrator';
  is_form_master := role_text ~ 'form[[:space:]]+master|form[[:space:]]+mistress';
  assigned_class := nullif(trim(coalesce(staff_record.form_master_class, '')), '');
  v_class_name := nullif(trim(coalesce(p_payload->>'class_name', '')), '');
  v_student_ref := nullif(trim(coalesce(p_payload->>'student_ref', '')), '');
  v_term := nullif(trim(coalesce(p_payload->>'term', '')), '');

  if v_class_name is null or v_student_ref is null or v_term is null then
    raise exception 'Class, student, and year are required.';
  end if;

  if not is_admin then
    if not is_form_master then
      raise exception 'Qualitative Assessment is assigned to Form Master/Form Mistress only.';
    end if;
    if assigned_class is null or lower(assigned_class) <> lower(v_class_name) then
      raise exception 'You can only capture qualitative assessment for your assigned form class.';
    end if;
  end if;

  select student.*
    into v_student
  from public.students student
  join public.classes cls on cls.id = student.class_id
  where student.school_id = staff_record.school_id
    and student.ass_ref_id = v_student_ref
    and lower(cls.name) = lower(v_class_name)
    and coalesce(student.status, 'Active') not in ('Deleted', 'Transferred', 'Dropped')
  limit 1;

  if v_student.id is null then
    raise exception 'Student was not found in the assigned class.';
  end if;

  insert into public.qualitative_assessments (
    school_id, class_name, student_ref, student_name, term, ratings,
    teacher_remark, captured_by_staff_id, captured_by_name, updated_at
  ) values (
    staff_record.school_id,
    v_class_name,
    v_student_ref,
    coalesce(nullif(p_payload->>'student_name', ''), trim(coalesce(v_student.first_name, '') || ' ' || coalesce(v_student.surname, '') || ' ' || coalesce(v_student.other_names, ''))),
    v_term,
    coalesce(p_payload->'ratings', '{}'::jsonb),
    nullif(p_payload->>'teacher_remark', ''),
    staff_record.id,
    coalesce(nullif(p_payload->>'captured_by', ''), staff_record.full_name, staff_record.staff_id),
    now()
  )
  on conflict (school_id, student_ref, term)
  do update set
    class_name = excluded.class_name,
    student_name = excluded.student_name,
    ratings = excluded.ratings,
    teacher_remark = excluded.teacher_remark,
    captured_by_staff_id = excluded.captured_by_staff_id,
    captured_by_name = excluded.captured_by_name,
    updated_at = now()
  returning * into saved;

  return saved;
end;
$$;

grant execute on function public.resolve_staff_password_login(text, text) to anon, authenticated, service_role;
grant execute on function public.secure_qualitative_assessment_setup(text) to anon, authenticated, service_role;
grant execute on function public.secure_save_qualitative_assessment_with_session(text, jsonb) to anon, authenticated, service_role;
