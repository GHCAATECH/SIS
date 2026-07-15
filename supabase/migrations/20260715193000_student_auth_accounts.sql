-- Create and repair Supabase Auth accounts for student portal login.
-- Students login with STD_ID plus their DOB password.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.link_student_auth_account_internal(
  p_student_id uuid,
  p_password text
)
returns public.students
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  target_student public.students;
  target_email text;
  target_auth_user_id uuid;
  clean_password text := btrim(coalesce(p_password, ''));
begin
  if p_student_id is null then
    raise exception 'Student id is required.';
  end if;

  if length(clean_password) < 6 then
    raise exception 'Student password must be at least 6 characters.';
  end if;

  select *
    into target_student
  from public.students
  where id = p_student_id
  for update;

  if target_student.id is null then
    raise exception 'Student account was not found.';
  end if;

  target_email := lower(regexp_replace(coalesce(target_student.ass_ref_id, target_student.id::text), '[^a-zA-Z0-9]+', '', 'g')) || '@students.local';
  target_auth_user_id := target_student.auth_user_id;

  if target_auth_user_id is null then
    select id
      into target_auth_user_id
    from auth.users
    where lower(email) = target_email
    limit 1;
  end if;

  if target_auth_user_id is null then
    target_auth_user_id := gen_random_uuid();

    insert into auth.users (
      id,
      instance_id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at,
      confirmation_token,
      recovery_token,
      email_change_token_new,
      email_change
    ) values (
      target_auth_user_id,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      target_email,
      extensions.crypt(clean_password, extensions.gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('account_type', 'student', 'student_id', target_student.id, 'school_id', target_student.school_id),
      now(),
      now(),
      '',
      '',
      '',
      ''
    );
  else
    update auth.users
    set email = coalesce(email, target_email),
        encrypted_password = extensions.crypt(clean_password, extensions.gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"provider":"email","providers":["email"]}'::jsonb,
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('account_type', 'student', 'student_id', target_student.id, 'school_id', target_student.school_id),
        updated_at = now()
    where id = target_auth_user_id;
  end if;

  insert into auth.identities (
    id,
    user_id,
    provider_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) values (
    target_auth_user_id,
    target_auth_user_id,
    target_email,
    jsonb_build_object('sub', target_auth_user_id::text, 'email', target_email, 'email_verified', true),
    'email',
    now(),
    now(),
    now()
  )
  on conflict do nothing;

  update public.students
  set auth_user_id = target_auth_user_id,
      updated_at = now()
  where id = target_student.id
  returning * into target_student;

  return target_student;
end;
$$;

revoke all on function public.link_student_auth_account_internal(uuid, text) from public, anon, authenticated;

create or replace function public.ensure_student_auth_account(
  p_school_id uuid,
  p_ass_ref_id text,
  p_password text default null
)
returns public.students
language plpgsql
security definer
set search_path = public
as $$
declare
  target_student public.students;
  clean_password text;
begin
  if not public.can_manage_school(p_school_id) then
    raise exception 'Access denied: school administrator privileges required.';
  end if;

  select *
    into target_student
  from public.students
  where school_id = p_school_id
    and lower(ass_ref_id) = lower(btrim(coalesce(p_ass_ref_id, '')))
  limit 1;

  if target_student.id is null then
    raise exception 'Student account was not found.';
  end if;

  clean_password := nullif(btrim(coalesce(p_password, '')), '');
  if clean_password is null then
    clean_password := to_char(target_student.date_of_birth, 'MMDDYYYY');
  end if;

  return public.link_student_auth_account_internal(target_student.id, clean_password);
end;
$$;

grant execute on function public.ensure_student_auth_account(uuid, text, text) to authenticated, service_role;

create or replace function public.resolve_student_auth_login(
  p_ass_ref_id text,
  p_password text
)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  clean_ass_ref text := lower(btrim(coalesce(p_ass_ref_id, '')));
  clean_password text := btrim(coalesce(p_password, ''));
  target_student public.students;
  linked_student public.students;
  resolved_email text;
begin
  if clean_ass_ref = '' or clean_password = '' then
    return null;
  end if;

  select *
    into target_student
  from public.students
  where lower(coalesce(ass_ref_id, '')) = clean_ass_ref
    and coalesce(status, 'Active') = 'Active'
  limit 1;

  if target_student.id is null then
    return null;
  end if;

  if clean_password not in (
    to_char(target_student.date_of_birth, 'MMDDYYYY'),
    to_char(target_student.date_of_birth, 'DDMMYYYY')
  ) then
    return null;
  end if;

  linked_student := public.link_student_auth_account_internal(target_student.id, clean_password);

  select email
    into resolved_email
  from auth.users
  where id = linked_student.auth_user_id
  limit 1;

  return resolved_email;
end;
$$;

grant execute on function public.resolve_student_auth_login(text, text) to anon, authenticated, service_role;
