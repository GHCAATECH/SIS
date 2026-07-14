-- Capture Assessment staff-session support.
-- Run this after production security hardening if staff login uses account_password fallback.

create extension if not exists pgcrypto;

create table if not exists public.staff_login_sessions (
  session_token text primary key default encode(gen_random_bytes(32), 'hex'),
  staff_user_id uuid not null references public.staff_users(id) on delete cascade,
  school_id uuid not null references public.schools(id) on delete cascade,
  expires_at timestamptz not null default now() + interval '12 hours',
  created_at timestamptz not null default now(),
  last_seen_at timestamptz
);

create index if not exists idx_staff_login_sessions_staff
  on public.staff_login_sessions(staff_user_id, expires_at);

alter table public.staff_login_sessions enable row level security;

drop policy if exists "staff login sessions hidden" on public.staff_login_sessions;
create policy "staff login sessions hidden"
  on public.staff_login_sessions for all
  using (false)
  with check (false);

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

create or replace function public.staff_from_login_session(p_session_token text)
returns public.staff_users
language sql
stable
security definer
set search_path = public
as $$
  select staff.*
  from public.staff_login_sessions login
  join public.staff_users staff on staff.id = login.staff_user_id
  where login.session_token = p_session_token
    and login.expires_at > now()
    and staff.status = 'Active'
  limit 1;
$$;

create or replace function public.secure_capture_assessment_setup(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  staff_record public.staff_users;
  is_admin boolean;
begin
  select * into staff_record
  from public.staff_from_login_session(p_session_token);

  if staff_record.id is null then
    raise exception 'Staff login session expired. Please login again.';
  end if;

  update public.staff_login_sessions
  set last_seen_at = now()
  where session_token = p_session_token;

  is_admin := staff_record.category = 'School Administrator';

  return jsonb_build_object(
    'assignments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'classId', assign.class_id,
        'className', cls.name,
        'subjectId', assign.subject_id,
        'subjectName', subj.name
      ) order by cls.name, subj.name)
      from public.staff_subject_classes assign
      join public.classes cls on cls.id = assign.class_id
      join public.subjects subj on subj.id = assign.subject_id
      where assign.school_id = staff_record.school_id
        and assign.staff_user_id = staff_record.id
    ), '[]'::jsonb),
    'assessment_modes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', mode.id,
        'display_order', mode.display_order,
        'name', mode.name
      ) order by mode.display_order)
      from public.assessment_modes mode
    ), '[]'::jsonb),
    'classes', coalesce((
      select jsonb_agg(class_row.payload order by class_row.name)
      from (
        select
          cls.name,
          jsonb_build_object(
            'id', cls.id,
            'name', cls.name,
            'programme_id', cls.programme_id,
            'programme', prog.name,
            'department_id', cls.department_id,
            'department', dept.name,
            'year_level', cls.year_level,
            'class_teacher', cls.class_teacher,
            'subjects', coalesce(jsonb_agg(subj.name order by class_sub.option_no) filter (where subj.id is not null), '[]'::jsonb),
            'subjectLinks', coalesce(jsonb_agg(jsonb_build_object('id', subj.id, 'name', subj.name, 'code', subj.code) order by class_sub.option_no) filter (where subj.id is not null), '[]'::jsonb)
          ) as payload
        from public.classes cls
        left join public.programmes prog on prog.id = cls.programme_id
        left join public.departments dept on dept.id = cls.department_id
        left join public.class_subjects class_sub on class_sub.class_id = cls.id
        left join public.subjects subj on subj.id = class_sub.subject_id
        where cls.school_id = staff_record.school_id
          and (
            is_admin
            or exists (
              select 1
              from public.staff_subject_classes assign
              where assign.school_id = staff_record.school_id
                and assign.staff_user_id = staff_record.id
                and assign.class_id = cls.id
                and assign.subject_id = class_sub.subject_id
            )
          )
        group by cls.id, prog.name, dept.name
      ) class_row
    ), '[]'::jsonb),
    'students', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', student.id,
        'ass_ref_id', student.ass_ref_id,
        'surname', student.surname,
        'first_name', student.first_name,
        'other_names', student.other_names,
        'student_level', student.student_level,
        'year_admitted', student.year_admitted,
        'classes', jsonb_build_object('name', cls.name)
      ) order by student.surname, student.first_name)
      from public.students student
      join public.classes cls on cls.id = student.class_id
      where student.school_id = staff_record.school_id
        and coalesce(student.status, 'Active') not in ('Deleted', 'Transferred', 'Dropped')
        and (
          is_admin
          or exists (
            select 1
            from public.staff_subject_classes assign
            where assign.school_id = staff_record.school_id
              and assign.staff_user_id = staff_record.id
              and assign.class_id = student.class_id
          )
        )
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.secure_save_assessment_scores_with_session(
  p_session_token text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  staff_record public.staff_users;
  v_school_id uuid;
  v_class_id uuid;
  v_subject_id uuid;
  v_mode_id uuid;
  v_assessment public.assessments;
  v_score jsonb;
  v_student_id uuid;
  v_score_count integer := 0;
begin
  select * into staff_record
  from public.staff_from_login_session(p_session_token);

  if staff_record.id is null then
    raise exception 'Staff login session expired. Please login again.';
  end if;

  v_school_id := staff_record.school_id;

  select id into v_class_id
  from public.classes
  where school_id = v_school_id
    and name = p_payload->>'className'
  limit 1;

  select id into v_subject_id
  from public.subjects
  where school_id = v_school_id
    and name = p_payload->>'subjectName'
  limit 1;

  select id into v_mode_id
  from public.assessment_modes
  where display_order = case
      when split_part(coalesce(p_payload->>'modeName', ''), '.', 1) ~ '^[0-9]+$'
      then split_part(coalesce(p_payload->>'modeName', ''), '.', 1)::int
      else null
    end
     or name = p_payload->>'modeName'
  order by display_order
  limit 1;

  if v_class_id is null or v_subject_id is null or v_mode_id is null then
    raise exception 'Class, subject, or assessment mode was not found.';
  end if;

  if staff_record.category <> 'School Administrator' and not exists (
    select 1
    from public.staff_subject_classes assign
    where assign.school_id = v_school_id
      and assign.staff_user_id = staff_record.id
      and assign.class_id = v_class_id
      and assign.subject_id = v_subject_id
  ) then
    raise exception 'You are not assigned to capture scores for this class and subject.';
  end if;

  insert into public.assessments (
    school_id, academic_year, class_id, subject_id, assessment_mode_id,
    year_level, semester, overall_score, inserted_by, status, submitted_at
  ) values (
    v_school_id,
    p_payload->>'academicYear',
    v_class_id,
    v_subject_id,
    v_mode_id,
    p_payload->>'yearLevel',
    p_payload->>'semester',
    (p_payload->>'overallScore')::numeric,
    coalesce(p_payload->>'capturedBy', staff_record.full_name, staff_record.staff_id, 'System'),
    coalesce(p_payload->>'status', 'Draft'),
    case when p_payload->>'status' = 'Submitted' then now() else null end
  )
  on conflict (school_id, academic_year, semester, year_level, class_id, subject_id, assessment_mode_id)
  do update set
    overall_score = excluded.overall_score,
    inserted_by = excluded.inserted_by,
    status = excluded.status,
    submitted_at = excluded.submitted_at
  returning * into v_assessment;

  for v_score in select * from jsonb_array_elements(coalesce(p_payload->'scores', '[]'::jsonb)) loop
    select id into v_student_id
    from public.students
    where school_id = v_school_id
      and ass_ref_id = v_score->>'assRef'
      and class_id = v_class_id
    limit 1;

    if v_student_id is not null then
      if nullif(v_score->>'score', '')::numeric > v_assessment.overall_score then
        raise exception 'Score is greater than overall score for STD_ID %.', v_score->>'assRef';
      end if;

      insert into public.assessment_scores (assessment_id, student_id, score, grade, remark)
      values (
        v_assessment.id,
        v_student_id,
        nullif(v_score->>'score', '')::numeric,
        nullif(v_score->>'grade', ''),
        nullif(v_score->>'remark', '')
      )
      on conflict (assessment_id, student_id)
      do update set
        score = excluded.score,
        grade = excluded.grade,
        remark = excluded.remark,
        updated_at = now();

      v_score_count := v_score_count + 1;
    end if;
  end loop;

  return jsonb_build_object('assessment_id', v_assessment.id, 'score_count', v_score_count);
end;
$$;

grant execute on function public.resolve_staff_password_login(text, text) to anon, authenticated, service_role;
grant execute on function public.staff_from_login_session(text) to anon, authenticated, service_role;
grant execute on function public.secure_capture_assessment_setup(text) to anon, authenticated, service_role;
grant execute on function public.secure_save_assessment_scores_with_session(text, jsonb) to anon, authenticated, service_role;
