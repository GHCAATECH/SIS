-- Allows Super Admin to reset a linked School Admin Supabase Auth password.
-- Run this in Supabase SQL Editor before using the Reset button in the Super Admin portal.

create extension if not exists pgcrypto;

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

  if target_staff.auth_user_id is null then
    raise exception 'This school admin has no linked Supabase Auth account.';
  end if;

  update auth.users
  set encrypted_password = crypt(p_new_password, gen_salt('bf')),
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
