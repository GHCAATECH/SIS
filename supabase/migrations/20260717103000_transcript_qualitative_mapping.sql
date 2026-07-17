-- Let transcript reports read qualitative assessments saved by Form Master/Form Mistress.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.student_login_sessions (
  session_token text primary key default encode(extensions.gen_random_bytes(32), 'hex'),
  student_id uuid not null references public.students(id) on delete cascade,
  school_id uuid not null references public.schools(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '12 hours')
);

create table if not exists public.staff_login_sessions (
  session_token text primary key default encode(extensions.gen_random_bytes(32), 'hex'),
  staff_user_id uuid not null references public.staff_users(id) on delete cascade,
  school_id uuid not null references public.schools(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '12 hours')
);

alter table public.qualitative_assessments
  add column if not exists captured_by_staff_id uuid references public.staff_users(id) on delete set null,
  add column if not exists captured_by_name text;

create or replace function public.secure_list_qualitative_assessments(
  p_school_id uuid default null,
  p_student_refs text[] default null,
  p_student_session_token text default null,
  p_staff_session_token text default null
)
returns setof public.qualitative_assessments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school_id uuid := p_school_id;
  v_student public.students;
  v_staff public.staff_users;
  v_role text;
  v_assigned_class text;
  v_refs text[] := coalesce(p_student_refs, array[]::text[]);
begin
  if p_student_session_token is not null then
    select student.*
      into v_student
    from public.student_login_sessions login
    join public.students student on student.id = login.student_id
    where login.session_token = p_student_session_token
      and login.expires_at > now()
    limit 1;

    if v_student.id is null then
      raise exception 'Student session expired. Please logout and login again.';
    end if;

    update public.student_login_sessions
    set last_seen_at = now()
    where session_token = p_student_session_token;

    return query
      select qa.*
      from public.qualitative_assessments qa
      where qa.school_id = v_student.school_id
        and (
          upper(qa.student_ref) = upper(v_student.ass_ref_id)
          or upper(qa.student_ref) = upper(v_student.id::text)
          or upper(qa.student_name) = upper(trim(coalesce(v_student.first_name, '') || ' ' || coalesce(v_student.surname, '') || ' ' || coalesce(v_student.other_names, '')))
        )
      order by qa.updated_at desc;
    return;
  end if;

  if p_staff_session_token is not null then
    select staff.*
      into v_staff
    from public.staff_login_sessions login
    join public.staff_users staff on staff.id = login.staff_user_id
    where login.session_token = p_staff_session_token
      and login.expires_at > now()
      and staff.status = 'Active'
    limit 1;

    if v_staff.id is null then
      raise exception 'Staff session expired. Please logout and login again.';
    end if;

    update public.staff_login_sessions
    set last_seen_at = now()
    where session_token = p_staff_session_token;

    v_role := lower(replace(coalesce(v_staff.position_responsibility, ''), '_', ' '));
    v_assigned_class := nullif(trim(coalesce(v_staff.form_master_class, '')), '');

    if v_staff.category = 'School Administrator' then
      return query
        select qa.*
        from public.qualitative_assessments qa
        where qa.school_id = v_staff.school_id
          and (
            coalesce(array_length(v_refs, 1), 0) = 0
            or exists (select 1 from unnest(v_refs) ref(value) where upper(qa.student_ref) = upper(ref.value))
            or exists (select 1 from unnest(v_refs) ref(value) where upper(qa.student_name) = upper(ref.value))
            or exists (select 1 from unnest(v_refs) ref(value) where upper(qa.student_name || '|' || coalesce(qa.class_name, '')) = upper(ref.value))
          )
        order by qa.updated_at desc;
      return;
    end if;

    if v_staff.category = 'Teaching Staff'
       and v_role ~ 'form[[:space:]]+master|form[[:space:]]+mistress'
       and v_assigned_class is not null then
      return query
        select qa.*
        from public.qualitative_assessments qa
        join public.students student
          on student.school_id = qa.school_id
         and upper(student.ass_ref_id) = upper(qa.student_ref)
        join public.classes cls on cls.id = student.class_id
        where qa.school_id = v_staff.school_id
          and lower(cls.name) = lower(v_assigned_class)
          and (
            coalesce(array_length(v_refs, 1), 0) = 0
            or exists (select 1 from unnest(v_refs) ref(value) where upper(qa.student_ref) = upper(ref.value))
            or exists (select 1 from unnest(v_refs) ref(value) where upper(qa.student_name) = upper(ref.value))
            or exists (select 1 from unnest(v_refs) ref(value) where upper(qa.student_name || '|' || coalesce(qa.class_name, '')) = upper(ref.value))
          )
        order by qa.updated_at desc;
      return;
    end if;

    raise exception 'You do not have access to qualitative assessments for transcript.';
  end if;

  if v_school_id is null then
    v_school_id := public.current_school_id();
  end if;

  if v_school_id is null or not public.can_manage_school(v_school_id) then
    raise exception 'Access denied: school administrator privileges required.';
  end if;

  return query
    select qa.*
    from public.qualitative_assessments qa
    where qa.school_id = v_school_id
      and (
        coalesce(array_length(v_refs, 1), 0) = 0
        or exists (select 1 from unnest(v_refs) ref(value) where upper(qa.student_ref) = upper(ref.value))
        or exists (select 1 from unnest(v_refs) ref(value) where upper(qa.student_name) = upper(ref.value))
        or exists (select 1 from unnest(v_refs) ref(value) where upper(qa.student_name || '|' || coalesce(qa.class_name, '')) = upper(ref.value))
      )
    order by qa.updated_at desc;
end;
$$;

grant execute on function public.secure_list_qualitative_assessments(uuid, text[], text, text)
  to anon, authenticated, service_role;
