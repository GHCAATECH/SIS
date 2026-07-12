-- Allows Super Admin to reset a School Admin Supabase Auth password.
-- If the School Admin has no linked Auth account yet, this creates and links one.
-- Run this in Supabase SQL Editor before using the Reset button in the Super Admin portal.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.super_admin_reset_school_admin_password(
  p_staff_user_id uuid,
  p_new_password text
)
returns public.staff_users
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  target_staff public.staff_users;
  target_email text;
  target_auth_user_id uuid;
begin
  if not public.is_super_admin() then
    raise exception 'Access denied: Super Admin privileges required.';
  end if;

  if p_staff_user_id is null then
    raise exception 'School admin id is required.';
  end if;

  if length(coalesce(p_new_password, '')) < 6 then
    raise exception 'Password must be at least 6 characters.';
  end if;

  select *
    into target_staff
  from public.staff_users
  where id = p_staff_user_id
    and category = 'School Administrator'
  limit 1;

  if target_staff.id is null then
    raise exception 'School admin account was not found.';
  end if;

  target_email := lower(nullif(trim(coalesce(target_staff.email, '')), ''));
  if target_email is null then
    target_email := lower(regexp_replace(coalesce(target_staff.staff_id, target_staff.id::text), '[^a-zA-Z0-9]+', '', 'g')) || '@schooladmin.local';
  end if;

  if target_staff.auth_user_id is null then
    select id
      into target_auth_user_id
    from auth.users
    where lower(email) = target_email
    limit 1;

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
        extensions.crypt(p_new_password, extensions.gen_salt('bf')),
        now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('account_type', 'staff', 'staff_user_id', target_staff.id, 'school_id', target_staff.school_id),
        now(),
        now(),
        '',
        '',
        '',
        ''
      );

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
        target_auth_user_id::text,
        target_auth_user_id,
        target_email,
        jsonb_build_object('sub', target_auth_user_id::text, 'email', target_email, 'email_verified', true),
        'email',
        now(),
        now(),
        now()
      )
      on conflict do nothing;
    end if;

    update public.staff_users
    set auth_user_id = target_auth_user_id,
        email = target_email,
        updated_at = now()
    where id = target_staff.id
    returning * into target_staff;
  end if;

  update auth.users
  set encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
      email_confirmed_at = coalesce(email_confirmed_at, now()),
      updated_at = now()
  where id = target_staff.auth_user_id;

  update public.staff_users
  set account_password = p_new_password,
      must_change_password = true,
      updated_at = now()
  where id = target_staff.id
  returning * into target_staff;

  return target_staff;
end;
$$;

grant execute on function public.super_admin_reset_school_admin_password(uuid, text) to authenticated, service_role;
